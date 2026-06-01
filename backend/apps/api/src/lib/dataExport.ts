import type pg from 'pg';
import { withRls } from '@carecircle/db';
import { cipherFor } from './encrypt.js';
import type { CircleKeyService } from '../services/circleKeys.js';

/** One file in the export archive. */
export type ExportEntry = { name: string; content: string };

// Bounds the in-memory footprint of a single export. Realistic family data is
// far below this; if a table exceeds it we flag truncation in the manifest
// rather than silently dropping rows.
const EXPORT_ROW_CAP = 10_000;

const README = `CareCircle data export
======================

This archive contains the data associated with your CareCircle account at the
time of export.

- profile.json          Your account profile.
- circles/<id>/         One folder per circle you belong to, containing the
                        circle's care data you have access to: members, the
                        care recipient, the activity timeline, medications,
                        appointments, vitals, care-minute logs, and document
                        metadata.

Document and voice/photo file contents are not included: documents are
end-to-end encrypted with a key only your devices hold, and media lives in
object storage. The metadata (titles, types, timestamps, object keys) is
exported so you can reconcile it with your devices.

Each circle folder includes manifest.json listing row counts and whether any
table was truncated at the export cap.
`;

function toJson(value: unknown): string {
  return JSON.stringify(value, null, 2);
}

function isoOrNull(value: Date | null): string | null {
  return value ? value.toISOString() : null;
}

function dateOnlyOrNull(value: Date | null): string | null {
  return value ? value.toISOString().slice(0, 10) : null;
}

type CircleRow = {
  id: string;
  name: string;
  subscription_tier: string;
  created_at: Date;
  role: string;
  joined_at: Date | null;
};

async function query<T extends pg.QueryResultRow>(
  pool: pg.Pool,
  userId: string,
  sql: string,
  params: unknown[],
): Promise<T[]> {
  return withRls(pool, { userId, role: 'app_user' }, async (client) => {
    const result = await client.query<T>(sql, params);
    return result.rows;
  });
}

/**
 * Gather every export file for a user, decrypting circle PHI with each
 * circle's DEK. All reads happen here so a failure surfaces before any archive
 * bytes are sent to the client. Each table is fetched in its own short
 * transaction to stay well under the pool's statement/idle ceilings.
 */
export async function collectUserExportEntries(opts: {
  pool: pg.Pool;
  circleKeys: CircleKeyService;
  userId: string;
}): Promise<ExportEntry[]> {
  const { pool, circleKeys, userId } = opts;
  const entries: ExportEntry[] = [{ name: 'README.txt', content: README }];

  const profileRows = await query<{
    id: string;
    email: string | null;
    display_name: string | null;
    photo_object_key: string | null;
    is_private_email: boolean;
    has_apple: boolean;
    has_google: boolean;
    has_password: boolean;
    created_at: Date;
  }>(
    pool,
    userId,
    `SELECT id, email, display_name, photo_object_key, is_private_email,
            apple_user_id IS NOT NULL AS has_apple,
            google_user_id IS NOT NULL AS has_google,
            password_hash IS NOT NULL AS has_password,
            created_at
     FROM users WHERE id = $1 AND deleted_at IS NULL`,
    [userId],
  );
  const profile = profileRows[0];
  entries.push({
    name: 'profile.json',
    content: toJson(
      profile
        ? {
            id: profile.id,
            email: profile.email,
            displayName: profile.display_name,
            photoObjectKey: profile.photo_object_key,
            isPrivateEmail: profile.is_private_email,
            signInMethods: {
              apple: profile.has_apple,
              google: profile.has_google,
              password: profile.has_password,
            },
            createdAt: profile.created_at.toISOString(),
          }
        : null,
    ),
  });

  const circles = await query<CircleRow>(
    pool,
    userId,
    `SELECT c.id, c.name, c.subscription_tier, c.created_at, cm.role, cm.joined_at
     FROM circles c
     JOIN circle_members cm ON cm.circle_id = c.id
     WHERE cm.user_id = $1 AND cm.deleted_at IS NULL AND c.deleted_at IS NULL
     ORDER BY c.created_at ASC`,
    [userId],
  );

  for (const circle of circles) {
    const cipher = await cipherFor(circleKeys, circle.id);
    const prefix = `circles/${circle.id}`;
    const truncated: string[] = [];
    const counts: Record<string, number> = {};

    const record = (table: string, rows: unknown[]): unknown[] => {
      counts[table] = rows.length;
      if (rows.length > EXPORT_ROW_CAP) {
        truncated.push(table);
        return rows.slice(0, EXPORT_ROW_CAP);
      }
      return rows;
    };

    entries.push({
      name: `${prefix}/circle.json`,
      content: toJson({
        id: circle.id,
        name: circle.name,
        subscriptionTier: circle.subscription_tier,
        myRole: circle.role,
        myJoinedAt: isoOrNull(circle.joined_at),
        createdAt: circle.created_at.toISOString(),
      }),
    });

    const members = await query<{
      id: string;
      user_id: string;
      role: string;
      status: string;
      display_name: string;
      joined_at: Date | null;
    }>(
      pool,
      userId,
      `SELECT id, user_id, role, status, display_name, joined_at
       FROM circle_members
       WHERE circle_id = $1 AND deleted_at IS NULL
       ORDER BY role, display_name
       LIMIT $2`,
      [circle.id, EXPORT_ROW_CAP + 1],
    );
    entries.push({
      name: `${prefix}/members.json`,
      content: toJson(
        record('members', members).map((m) => {
          const row = m as (typeof members)[number];
          return {
            id: row.id,
            userId: row.user_id,
            role: row.role,
            status: row.status,
            displayName: row.display_name,
            joinedAt: isoOrNull(row.joined_at),
          };
        }),
      ),
    });

    const recipients = await query<{
      id: string;
      first_name_enc: Buffer;
      last_name_enc: Buffer | null;
      date_of_birth_enc: Buffer | null;
      pronouns: string | null;
      primary_conditions_enc: Buffer | null;
      photo_object_key: string | null;
    }>(
      pool,
      userId,
      `SELECT id, first_name_enc, last_name_enc, date_of_birth_enc, pronouns,
              primary_conditions_enc, photo_object_key
       FROM care_recipients
       WHERE circle_id = $1 AND deleted_at IS NULL
       ORDER BY created_at ASC`,
      [circle.id],
    );
    counts.recipient = recipients.length;
    entries.push({
      name: `${prefix}/recipient.json`,
      content: toJson(
        recipients.map((r) => ({
          id: r.id,
          firstName: cipher.decrypt(r.first_name_enc),
          lastName: cipher.decryptOptional(r.last_name_enc),
          dateOfBirth: cipher.decryptOptional(r.date_of_birth_enc),
          pronouns: r.pronouns,
          primaryConditions: cipher.decryptJson<string[]>(r.primary_conditions_enc) ?? [],
          photoObjectKey: r.photo_object_key,
        })),
      ),
    });

    const activities = await query<{
      id: string;
      author_user_id: string;
      activity_type: string;
      headline: string | null;
      content_enc: Buffer | null;
      voice_object_key: string | null;
      photo_object_keys: string[] | null;
      entities_enc: Buffer | null;
      occurred_at: Date;
    }>(
      pool,
      userId,
      `SELECT id, author_user_id, activity_type, headline, content_enc,
              voice_object_key, photo_object_keys, entities_enc, occurred_at
       FROM activities
       WHERE circle_id = $1 AND deleted_at IS NULL
       ORDER BY occurred_at DESC, id DESC
       LIMIT $2`,
      [circle.id, EXPORT_ROW_CAP + 1],
    );
    entries.push({
      name: `${prefix}/activities.json`,
      content: toJson(
        record('activities', activities).map((a) => {
          const row = a as (typeof activities)[number];
          return {
            id: row.id,
            authorUserId: row.author_user_id,
            type: row.activity_type,
            headline: row.headline,
            content: cipher.decryptOptional(row.content_enc),
            voiceObjectKey: row.voice_object_key,
            photoObjectKeys: row.photo_object_keys ?? [],
            entities: cipher.decryptJson<string[]>(row.entities_enc) ?? [],
            occurredAt: row.occurred_at.toISOString(),
          };
        }),
      ),
    });

    const medications = await query<{
      id: string;
      name_enc: Buffer;
      generic_name_enc: Buffer | null;
      dosage_enc: Buffer;
      form: string | null;
      rxcui: string | null;
      status: string;
      schedule: unknown;
      start_date: Date | null;
      end_date: Date | null;
    }>(
      pool,
      userId,
      `SELECT id, name_enc, generic_name_enc, dosage_enc, form, rxcui, status,
              schedule, start_date, end_date
       FROM medications
       WHERE circle_id = $1 AND deleted_at IS NULL
       ORDER BY status, start_date NULLS LAST, id
       LIMIT $2`,
      [circle.id, EXPORT_ROW_CAP + 1],
    );
    entries.push({
      name: `${prefix}/medications.json`,
      content: toJson(
        record('medications', medications).map((m) => {
          const row = m as (typeof medications)[number];
          return {
            id: row.id,
            name: cipher.decrypt(row.name_enc),
            genericName: cipher.decryptOptional(row.generic_name_enc),
            dosage: cipher.decrypt(row.dosage_enc),
            form: row.form,
            rxcui: row.rxcui,
            status: row.status,
            schedule: row.schedule,
            startDate: dateOnlyOrNull(row.start_date),
            endDate: dateOnlyOrNull(row.end_date),
          };
        }),
      ),
    });

    const appointments = await query<{
      id: string;
      title_enc: Buffer;
      provider_enc: Buffer | null;
      location_enc: Buffer | null;
      starts_at: Date;
      duration_minutes: number;
      transport_responsible: string | null;
      prep_notes_enc: Buffer | null;
    }>(
      pool,
      userId,
      `SELECT id, title_enc, provider_enc, location_enc, starts_at, duration_minutes,
              transport_responsible, prep_notes_enc
       FROM appointments
       WHERE circle_id = $1 AND deleted_at IS NULL
       ORDER BY starts_at ASC
       LIMIT $2`,
      [circle.id, EXPORT_ROW_CAP + 1],
    );
    entries.push({
      name: `${prefix}/appointments.json`,
      content: toJson(
        record('appointments', appointments).map((a) => {
          const row = a as (typeof appointments)[number];
          return {
            id: row.id,
            title: cipher.decrypt(row.title_enc),
            provider: cipher.decryptOptional(row.provider_enc),
            location: cipher.decryptOptional(row.location_enc),
            startsAt: row.starts_at.toISOString(),
            durationMinutes: row.duration_minutes,
            transportResponsible: row.transport_responsible,
            prepNotes: cipher.decryptOptional(row.prep_notes_enc),
          };
        }),
      ),
    });

    const vitals = await query<{
      id: string;
      recorded_by_user_id: string;
      kind: string;
      recorded_at: Date;
      value_numeric: string | null;
      value_text: string | null;
      unit: string | null;
      source: string;
      notes_enc: Buffer | null;
    }>(
      pool,
      userId,
      `SELECT id, recorded_by_user_id, kind, recorded_at, value_numeric::TEXT,
              value_text, unit, source, notes_enc
       FROM vitals
       WHERE circle_id = $1 AND deleted_at IS NULL
       ORDER BY recorded_at DESC, id DESC
       LIMIT $2`,
      [circle.id, EXPORT_ROW_CAP + 1],
    );
    entries.push({
      name: `${prefix}/vitals.json`,
      content: toJson(
        record('vitals', vitals).map((v) => {
          const row = v as (typeof vitals)[number];
          return {
            id: row.id,
            recordedByUserId: row.recorded_by_user_id,
            kind: row.kind,
            recordedAt: row.recorded_at.toISOString(),
            valueNumeric: row.value_numeric !== null ? Number(row.value_numeric) : null,
            valueText: row.value_text,
            unit: row.unit,
            source: row.source,
            notes: cipher.decryptOptional(row.notes_enc),
          };
        }),
      ),
    });

    const careMinutes = await query<{
      id: string;
      caregiver_user_id: string;
      service_code: string;
      service_description: string;
      started_at: Date;
      ended_at: Date;
      duration_minutes: number;
      notes_enc: Buffer | null;
      fiscal_intermediary: string | null;
    }>(
      pool,
      userId,
      `SELECT id, caregiver_user_id, service_code, service_description,
              started_at, ended_at, duration_minutes, notes_enc, fiscal_intermediary
       FROM care_minute_entries
       WHERE circle_id = $1 AND deleted_at IS NULL
       ORDER BY started_at DESC
       LIMIT $2`,
      [circle.id, EXPORT_ROW_CAP + 1],
    );
    entries.push({
      name: `${prefix}/care_minutes.json`,
      content: toJson(
        record('careMinutes', careMinutes).map((c) => {
          const row = c as (typeof careMinutes)[number];
          return {
            id: row.id,
            caregiverUserId: row.caregiver_user_id,
            serviceCode: row.service_code,
            serviceDescription: row.service_description,
            startedAt: row.started_at.toISOString(),
            endedAt: row.ended_at.toISOString(),
            durationMinutes: row.duration_minutes,
            notes: cipher.decryptOptional(row.notes_enc),
            fiscalIntermediary: row.fiscal_intermediary,
          };
        }),
      ),
    });

    const documents = await query<{
      id: string;
      title_enc: Buffer;
      document_type: string;
      object_key: string;
      mime_type: string;
      size_bytes: string;
      issued_at: Date | null;
      expires_at: Date | null;
      created_at: Date;
    }>(
      pool,
      userId,
      `SELECT id, title_enc, document_type, object_key, mime_type, size_bytes::TEXT,
              issued_at, expires_at, created_at
       FROM documents
       WHERE circle_id = $1 AND deleted_at IS NULL
       ORDER BY created_at DESC
       LIMIT $2`,
      [circle.id, EXPORT_ROW_CAP + 1],
    );
    entries.push({
      name: `${prefix}/documents.json`,
      content: toJson(
        record('documents', documents).map((d) => {
          const row = d as (typeof documents)[number];
          return {
            id: row.id,
            title: cipher.decrypt(row.title_enc),
            documentType: row.document_type,
            objectKey: row.object_key,
            mimeType: row.mime_type,
            sizeBytes: Number(row.size_bytes),
            issuedAt: dateOnlyOrNull(row.issued_at),
            expiresAt: dateOnlyOrNull(row.expires_at),
            createdAt: row.created_at.toISOString(),
          };
        }),
      ),
    });

    entries.push({
      name: `${prefix}/manifest.json`,
      content: toJson({ counts, truncated, rowCap: EXPORT_ROW_CAP }),
    });
  }

  return entries;
}
