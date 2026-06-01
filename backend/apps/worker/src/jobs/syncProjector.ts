import { z } from 'zod';
import type pg from 'pg';
import { withRls } from '@carecircle/db';
import { FieldCipher, type Logger } from '@carecircle/shared';
import type { Config } from '../config.js';
import type { SyncJobData } from '../queues.js';
import { ensureCircleProvisioned } from '../lib/circleProvision.js';

// ---------------------------------------------------------------------------
// Projects the durable `pending_operations` queue into domain tables.
//
// The iOS SyncEngine appends one row per local mutation and POSTs them to
// `/v1/sync/batch`, which persists them and enqueues this job. Here we drain
// each unprocessed op into its target table using the client-supplied entity
// UUID as the primary key, so replays are idempotent. PHI columns are
// envelope-encrypted with the per-circle DEK before insert.
//
// Each op is projected in its own transaction. A permanent failure (bad
// payload, constraint violation) is recorded on the op and skipped; a
// transient failure (lost connection, deadlock) defers the op and fails the
// job so BullMQ retries. Duplicates are treated as a successful no-op.
// ---------------------------------------------------------------------------

const MAX_OPS_PER_RUN = 5_000;

class PermanentProjectionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PermanentProjectionError';
  }
}

type Disposition = 'permanent' | 'transient' | 'duplicate';

function classifyError(err: unknown): Disposition {
  if (err instanceof z.ZodError || err instanceof PermanentProjectionError) {
    return 'permanent';
  }
  const code = (err as { code?: unknown }).code;
  if (typeof code === 'string') {
    if (code === '23505') {
      return 'duplicate';
    }
    // Class 22 (data exception), 23 (integrity constraint other than unique,
    // including FK/check/not-null), 42 (syntax/undefined object) cannot be
    // resolved by retrying the same payload.
    if (code.startsWith('22') || code.startsWith('23') || code.startsWith('42')) {
      return 'permanent';
    }
  }
  return 'transient';
}

function errorMessage(err: unknown): string {
  if (err instanceof Error) {
    return err.message.slice(0, 1_000);
  }
  return String(err).slice(0, 1_000);
}

// iOS ActivityType raw values are broader than the backend `activity_type`
// enum; collapse the extras onto the closest persisted bucket.
const ACTIVITY_TYPE_MAP: Record<string, string> = {
  text_note: 'text_note',
  photo: 'photo',
  voice_note: 'voice_note',
  med_taken: 'med_taken',
  med_skipped: 'med_skipped',
  med_missed: 'med_missed',
  vital_logged: 'vital_logged',
  appointment_logged: 'appointment_logged',
  shift_started: 'shift_started',
  shift_ended: 'shift_ended',
  document_added: 'document_added',
  sos_triggered: 'sos_triggered',
  visit: 'appointment_logged',
  appointment: 'appointment_logged',
  alert: 'system',
  system: 'system',
};

// iOS MedicationStatus uses camelCase raw values for the multi-word case.
const MED_STATUS_MAP: Record<string, string> = {
  active: 'active',
  asNeeded: 'as_needed',
  as_needed: 'as_needed',
  discontinued: 'discontinued',
};

const MEMBER_ROLES = new Set([
  'owner',
  'family_member',
  'paid_aide',
  'paid_family',
  'care_recipient',
  'view_only',
]);
const MEMBER_STATUSES = new Set(['invited', 'active', 'paused', 'removed']);
const VITAL_KINDS = new Set([
  'heart_rate',
  'blood_pressure_systolic',
  'blood_pressure_diastolic',
  'body_weight',
  'blood_glucose',
  'oxygen_saturation',
  'body_temperature',
  'respiratory_rate',
  'falls',
  'walking_steadiness',
  'sleep_hours',
  'resting_heart_rate',
  'step_count',
]);

const uuid = z.string().uuid();
const isoDate = z.string().min(1);

function dateOnly(iso: string): string {
  return iso.slice(0, 10);
}

function durationMinutes(startIso: string, endIso: string): number {
  const start = Date.parse(startIso);
  const end = Date.parse(endIso);
  if (Number.isNaN(start) || Number.isNaN(end)) {
    throw new PermanentProjectionError('care minute entry has unparseable timestamps');
  }
  return Math.max(0, Math.round((end - start) / 60_000));
}

type PendingOpRow = {
  id: string;
  client_op_id: string;
  user_id: string;
  circle_id: string | null;
  operation_type: string;
  payload: Record<string, unknown>;
};

type ProjectionResult = { table: string; rowId: string; action: 'inserted' | 'updated' | 'noop' };
type SkipResult = { skipped: string };
type OpOutcome = ProjectionResult | SkipResult;

type ProjectCtx = {
  client: pg.PoolClient;
  op: PendingOpRow;
  cipher: FieldCipher;
  actorId: string;
  resolveUser: (appleUserId: string | null | undefined) => Promise<string | null>;
};

function actionFromInsert(rows: Array<{ id: string; inserted?: boolean }>, table: string): ProjectionResult {
  const row = rows[0];
  if (!row) {
    // ON CONFLICT DO NOTHING matched an existing row: already projected.
    return { table, rowId: 'duplicate', action: 'noop' };
  }
  return { table, rowId: row.id, action: row.inserted === false ? 'updated' : 'inserted' };
}

// --- per-operation projectors ----------------------------------------------

const activitySchema = z.object({
  activityId: uuid,
  type: z.string().min(1),
  body: z.string(),
  createdAt: isoDate,
  authorAppleUserID: z.string().optional(),
  extractedEntitiesJSON: z.string().nullish(),
});

async function projectActivity(ctx: ProjectCtx, circleId: string): Promise<OpOutcome> {
  const p = activitySchema.parse(ctx.op.payload);
  const author = (await ctx.resolveUser(p.authorAppleUserID)) ?? ctx.actorId;
  const activityType = ACTIVITY_TYPE_MAP[p.type] ?? 'system';
  const res = await ctx.client.query<{ id: string }>(
    `INSERT INTO activities
       (id, circle_id, author_user_id, activity_type, content_enc, entities_enc, occurred_at, client_op_id)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     ON CONFLICT (id) DO NOTHING
     RETURNING id`,
    [
      p.activityId,
      circleId,
      author,
      activityType,
      p.body.length > 0 ? ctx.cipher.encrypt(p.body) : null,
      p.extractedEntitiesJSON ? ctx.cipher.encrypt(p.extractedEntitiesJSON) : null,
      p.createdAt,
      ctx.op.client_op_id,
    ],
  );
  return actionFromInsert(res.rows, 'activities');
}

const medicationSchema = z.object({
  medicationId: uuid,
  name: z.string().min(1),
  dosage: z.string().min(1),
  form: z.string().optional(),
  status: z.string().optional(),
  scheduleJSON: z.string().nullish(),
  startDate: isoDate.nullish(),
  endDate: isoDate.nullish(),
  instructions: z.string().nullish(),
  colorHex: z.string().nullish(),
});

function parseSchedule(scheduleJSON: string | null | undefined): unknown {
  if (!scheduleJSON) {
    return {};
  }
  try {
    return JSON.parse(scheduleJSON);
  } catch {
    return {};
  }
}

async function projectMedication(ctx: ProjectCtx, circleId: string): Promise<OpOutcome> {
  const p = medicationSchema.parse(ctx.op.payload);
  const res = await ctx.client.query<{ id: string }>(
    `INSERT INTO medications
       (id, circle_id, name_enc, dosage_enc, form, color, status, schedule, notes_enc, start_date, end_date)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
     ON CONFLICT (id) DO NOTHING
     RETURNING id`,
    [
      p.medicationId,
      circleId,
      ctx.cipher.encrypt(p.name),
      ctx.cipher.encrypt(p.dosage),
      p.form ?? null,
      p.colorHex ?? null,
      MED_STATUS_MAP[p.status ?? 'active'] ?? 'active',
      parseSchedule(p.scheduleJSON),
      ctx.cipher.encryptOptional(p.instructions ?? null),
      p.startDate ? dateOnly(p.startDate) : null,
      p.endDate ? dateOnly(p.endDate) : null,
    ],
  );
  return actionFromInsert(res.rows, 'medications');
}

const doseSchema = z.object({
  doseId: uuid,
  medicationId: uuid,
  takenAt: isoDate.optional(),
  skippedAt: isoDate.optional(),
  markedByAppleUserID: z.string().nullish(),
  notes: z.string().nullish(),
});

async function projectDose(
  ctx: ProjectCtx,
  circleId: string,
  status: 'taken' | 'skipped',
): Promise<OpOutcome> {
  const p = doseSchema.parse(ctx.op.payload);
  const eventAt = status === 'taken' ? p.takenAt : p.skippedAt;
  if (!eventAt) {
    throw new PermanentProjectionError(`dose ${status} op missing timestamp`);
  }
  const markedBy = (await ctx.resolveUser(p.markedByAppleUserID)) ?? ctx.actorId;
  const res = await ctx.client.query<{ id: string; inserted: boolean }>(
    `INSERT INTO dose_events
       (id, medication_id, circle_id, scheduled_at, taken_at, marked_by, status, notes_enc)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     ON CONFLICT (id) DO UPDATE SET
       taken_at = EXCLUDED.taken_at,
       marked_by = EXCLUDED.marked_by,
       status = EXCLUDED.status,
       notes_enc = EXCLUDED.notes_enc,
       updated_at = NOW()
     RETURNING id, (xmax = 0) AS inserted`,
    [
      p.doseId,
      p.medicationId,
      circleId,
      eventAt,
      status === 'taken' ? eventAt : null,
      markedBy,
      status,
      ctx.cipher.encryptOptional(p.notes ?? null),
    ],
  );
  return actionFromInsert(res.rows, 'dose_events');
}

const appointmentSchema = z.object({
  appointmentId: uuid,
  title: z.string().min(1),
  provider: z.string().nullish(),
  location: z.string().nullish(),
  startsAt: isoDate,
  durationMinutes: z.number().int().nonnegative().default(60),
  prepNotes: z.string().nullish(),
  reminderOffsetsMinutes: z.array(z.number().int()).default([]),
  createdByAppleUserID: z.string().optional(),
});

async function projectAppointment(ctx: ProjectCtx, circleId: string): Promise<OpOutcome> {
  const p = appointmentSchema.parse(ctx.op.payload);
  const createdBy = (await ctx.resolveUser(p.createdByAppleUserID)) ?? ctx.actorId;
  const res = await ctx.client.query<{ id: string }>(
    `INSERT INTO appointments
       (id, circle_id, title_enc, provider_enc, location_enc, starts_at, duration_minutes,
        prep_notes_enc, reminder_minutes_before, created_by)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
     ON CONFLICT (id) DO NOTHING
     RETURNING id`,
    [
      p.appointmentId,
      circleId,
      ctx.cipher.encrypt(p.title),
      ctx.cipher.encryptOptional(p.provider ?? null),
      ctx.cipher.encryptOptional(p.location ?? null),
      p.startsAt,
      p.durationMinutes,
      ctx.cipher.encryptOptional(p.prepNotes ?? null),
      p.reminderOffsetsMinutes,
      createdBy,
    ],
  );
  return actionFromInsert(res.rows, 'appointments');
}

const emergencyContactSchema = z.object({
  contactId: uuid,
  name: z.string().min(1),
  relationship: z.string().nullish(),
  phoneE164: z.string().min(1),
  isPrimary: z.boolean().default(false),
  isMedical: z.boolean().default(false),
  sortOrder: z.number().int().default(100),
});

async function projectEmergencyContact(ctx: ProjectCtx, circleId: string): Promise<OpOutcome> {
  const p = emergencyContactSchema.parse(ctx.op.payload);
  const res = await ctx.client.query<{ id: string }>(
    `INSERT INTO emergency_contacts
       (id, circle_id, name_enc, relationship, phone_enc, is_primary, is_medical, sort_order)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     ON CONFLICT (id) DO NOTHING
     RETURNING id`,
    [
      p.contactId,
      circleId,
      ctx.cipher.encrypt(p.name),
      p.relationship ?? null,
      ctx.cipher.encrypt(p.phoneE164),
      p.isPrimary,
      p.isMedical,
      p.sortOrder,
    ],
  );
  return actionFromInsert(res.rows, 'emergency_contacts');
}

const careMinuteSchema = z.object({
  entryId: uuid,
  caregiverAppleUserID: z.string().optional(),
  serviceCode: z.string().min(1),
  serviceDescription: z.string().min(1),
  startedAt: isoDate,
  endedAt: isoDate,
  notes: z.string().nullish(),
  fiscalIntermediary: z.string().nullish(),
});

async function projectCareMinute(ctx: ProjectCtx, circleId: string): Promise<OpOutcome> {
  const p = careMinuteSchema.parse(ctx.op.payload);
  const caregiver = (await ctx.resolveUser(p.caregiverAppleUserID)) ?? ctx.actorId;
  const res = await ctx.client.query<{ id: string }>(
    `INSERT INTO care_minute_entries
       (id, circle_id, caregiver_user_id, service_code, service_description, started_at, ended_at,
        duration_minutes, notes_enc, fiscal_intermediary)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
     ON CONFLICT (id) DO NOTHING
     RETURNING id`,
    [
      p.entryId,
      circleId,
      caregiver,
      p.serviceCode,
      p.serviceDescription,
      p.startedAt,
      p.endedAt,
      durationMinutes(p.startedAt, p.endedAt),
      ctx.cipher.encryptOptional(p.notes ?? null),
      p.fiscalIntermediary ?? null,
    ],
  );
  return actionFromInsert(res.rows, 'care_minute_entries');
}

const sosSchema = z.object({
  eventId: uuid,
  triggeredByAppleUserID: z.string().optional(),
  triggeredAt: isoDate,
  latitude: z.number().nullish(),
  longitude: z.number().nullish(),
  locationAccuracyMeters: z.number().nullish(),
});

async function projectSos(ctx: ProjectCtx, circleId: string): Promise<OpOutcome> {
  const p = sosSchema.parse(ctx.op.payload);
  const triggeredBy = (await ctx.resolveUser(p.triggeredByAppleUserID)) ?? ctx.actorId;
  const res = await ctx.client.query<{ id: string }>(
    `INSERT INTO sos_events
       (id, circle_id, triggered_by, triggered_at, location_lat, location_lng, location_accuracy_m)
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     ON CONFLICT (id) DO NOTHING
     RETURNING id`,
    [
      p.eventId,
      circleId,
      triggeredBy,
      p.triggeredAt,
      p.latitude ?? null,
      p.longitude ?? null,
      p.locationAccuracyMeters ?? null,
    ],
  );
  return actionFromInsert(res.rows, 'sos_events');
}

const shiftDigestSchema = z.object({
  digestId: uuid,
  shiftStartAt: isoDate,
  shiftEndAt: isoDate,
  narratorAppleUserID: z.string().optional(),
  transcript: z.string().nullish(),
  summary: z.string().nullish(),
  audioDurationSeconds: z.number().nonnegative().default(0),
  extractedEntitiesJSON: z.string().nullish(),
  structuredArtifactsJSON: z.string().nullish(),
  relatedShiftID: uuid.nullish(),
});

async function projectShiftDigest(ctx: ProjectCtx, circleId: string): Promise<OpOutcome> {
  const p = shiftDigestSchema.parse(ctx.op.payload);
  const narrator = (await ctx.resolveUser(p.narratorAppleUserID)) ?? ctx.actorId;
  const res = await ctx.client.query<{ id: string }>(
    `INSERT INTO shift_digests
       (id, circle_id, narrator_user_id, shift_start_at, shift_end_at, transcript_enc, summary_enc,
        entities_enc, artifacts_enc, audio_duration_seconds, related_shift_id, client_op_id)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
     ON CONFLICT (id) DO NOTHING
     RETURNING id`,
    [
      p.digestId,
      circleId,
      narrator,
      p.shiftStartAt,
      p.shiftEndAt,
      ctx.cipher.encryptOptional(p.transcript ?? null),
      ctx.cipher.encryptOptional(p.summary ?? null),
      p.extractedEntitiesJSON ? ctx.cipher.encrypt(p.extractedEntitiesJSON) : null,
      p.structuredArtifactsJSON ? ctx.cipher.encrypt(p.structuredArtifactsJSON) : null,
      p.audioDurationSeconds,
      p.relatedShiftID ?? null,
      ctx.op.client_op_id,
    ],
  );
  return actionFromInsert(res.rows, 'shift_digests');
}

const vitalSchema = z
  .object({
    vitalId: uuid,
    kind: z.string().min(1),
    recordedAt: isoDate,
    valueNumeric: z.number().nullish(),
    valueText: z.string().nullish(),
    unit: z.string().min(1),
    source: z.string().default('manual'),
    healthkitUUID: z.string().nullish(),
    notes: z.string().nullish(),
    recordedByAppleUserID: z.string().optional(),
  })
  .refine((v) => v.valueNumeric != null || (v.valueText != null && v.valueText.length > 0), {
    message: 'vital requires valueNumeric or valueText',
  });

async function projectVital(ctx: ProjectCtx, circleId: string): Promise<OpOutcome> {
  const p = vitalSchema.parse(ctx.op.payload);
  if (!VITAL_KINDS.has(p.kind)) {
    throw new PermanentProjectionError(`unknown vital kind: ${p.kind}`);
  }
  const source = p.source === 'healthkit' ? 'healthkit' : 'manual';
  const recordedBy = (await ctx.resolveUser(p.recordedByAppleUserID)) ?? ctx.actorId;
  const res = await ctx.client.query<{ id: string }>(
    `INSERT INTO vitals
       (id, circle_id, recorded_by_user_id, kind, recorded_at, value_numeric, value_text, unit,
        source, healthkit_uuid, notes_enc, client_op_id)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
     ON CONFLICT (id) DO NOTHING
     RETURNING id`,
    [
      p.vitalId,
      circleId,
      recordedBy,
      p.kind,
      p.recordedAt,
      p.valueNumeric ?? null,
      p.valueText ?? null,
      p.unit,
      source,
      p.healthkitUUID ?? null,
      ctx.cipher.encryptOptional(p.notes ?? null),
      ctx.op.client_op_id,
    ],
  );
  return actionFromInsert(res.rows, 'vitals');
}

const memberSchema = z.object({
  appleUserID: z.string().min(1),
  displayName: z.string().min(1),
  role: z.string().optional(),
  status: z.string().optional(),
  invitedAt: isoDate.nullish(),
  joinedAt: isoDate.nullish(),
});

async function projectMember(ctx: ProjectCtx, circleId: string): Promise<OpOutcome> {
  const p = memberSchema.parse(ctx.op.payload);
  const userId = await ctx.resolveUser(p.appleUserID);
  if (!userId) {
    // The member has not signed in to the backend yet, so there is no
    // users row to link. Record the gap rather than failing — the roster
    // reconciles when that member authenticates and re-syncs.
    return { skipped: 'member_not_provisioned' };
  }
  const role = MEMBER_ROLES.has(p.role ?? '') ? p.role! : 'family_member';
  const status = MEMBER_STATUSES.has(p.status ?? '') ? p.status! : 'active';
  const res = await ctx.client.query<{ id: string; inserted: boolean }>(
    `INSERT INTO circle_members
       (circle_id, user_id, role, status, display_name, invited_at, joined_at)
     VALUES ($1, $2, $3, $4, $5, COALESCE($6, NOW()), $7)
     ON CONFLICT (circle_id, user_id) DO UPDATE SET
       role = EXCLUDED.role,
       status = EXCLUDED.status,
       display_name = EXCLUDED.display_name,
       joined_at = COALESCE(circle_members.joined_at, EXCLUDED.joined_at),
       updated_at = NOW()
     RETURNING id, (xmax = 0) AS inserted`,
    [circleId, userId, role, status, p.displayName, p.invitedAt ?? null, p.joinedAt ?? null],
  );
  return actionFromInsert(res.rows, 'circle_members');
}

async function dispatch(ctx: ProjectCtx, circleId: string): Promise<OpOutcome> {
  switch (ctx.op.operation_type) {
    case 'create_activity':
      return projectActivity(ctx, circleId);
    case 'create_medication':
      return projectMedication(ctx, circleId);
    case 'mark_dose_taken':
      return projectDose(ctx, circleId, 'taken');
    case 'mark_dose_skipped':
      return projectDose(ctx, circleId, 'skipped');
    case 'create_appointment':
      return projectAppointment(ctx, circleId);
    case 'create_emergency_contact':
      return projectEmergencyContact(ctx, circleId);
    case 'create_care_minute_entry':
      return projectCareMinute(ctx, circleId);
    case 'create_sos_event':
      return projectSos(ctx, circleId);
    case 'create_shift_digest':
      return projectShiftDigest(ctx, circleId);
    case 'create_vital':
      return projectVital(ctx, circleId);
    case 'create_member':
      return projectMember(ctx, circleId);
    default:
      throw new PermanentProjectionError(`unknown operation type: ${ctx.op.operation_type}`);
  }
}

// --- drain loop -------------------------------------------------------------

export type SyncProjectorResult = {
  applied: number;
  failed: number;
  deferred: number;
};

export async function runSyncProjector(
  data: SyncJobData,
  ctx: { pool: pg.Pool; config: Config; logger: Logger },
): Promise<SyncProjectorResult> {
  const { pool, config, logger } = ctx;
  const dekCache = new Map<string, Buffer>();
  const deferredIds: string[] = [];
  let applied = 0;
  let failed = 0;

  for (let i = 0; i < MAX_OPS_PER_RUN; i += 1) {
    let cipherCircleId: string | undefined;
    let dekForCommit: Buffer | undefined;

    const step = await withRls(pool, { role: 'app_service' }, async (client) => {
      const claim = await client.query<PendingOpRow>(
        `SELECT id, client_op_id, user_id, circle_id, operation_type, payload
         FROM pending_operations
         WHERE user_id = $1
           AND processed_at IS NULL
           AND NOT (id = ANY($2::uuid[]))
         ORDER BY received_at ASC
         LIMIT 1
         FOR UPDATE SKIP LOCKED`,
        [data.userId, deferredIds],
      );
      const op = claim.rows[0];
      if (!op) {
        return { done: true as const };
      }

      const circleId = op.circle_id;
      if (!circleId) {
        await client.query(
          `UPDATE pending_operations SET processed_at = NOW(), error = $2, result = NULL WHERE id = $1`,
          [op.id, 'operation has no circle_id'],
        );
        return { done: false as const, status: 'error' as const };
      }

      await client.query('SAVEPOINT proj');
      try {
        let dek = dekCache.get(circleId);
        if (!dek) {
          dek = await ensureCircleProvisioned(client, {
            circleId,
            ownerUserId: op.user_id,
            masterKey: config.APP_MASTER_KEY,
          });
        }
        const cipher = new FieldCipher(circleId, dek);
        const resolveUser = makeUserResolver(client);
        const outcome = await dispatch(
          { client, op, cipher, actorId: op.user_id, resolveUser },
          circleId,
        );
        await client.query(
          `UPDATE pending_operations SET processed_at = NOW(), result = $2, error = NULL WHERE id = $1`,
          [op.id, JSON.stringify(outcome)],
        );
        cipherCircleId = circleId;
        dekForCommit = dek;
        return { done: false as const, status: 'ok' as const };
      } catch (err) {
        const disposition = classifyError(err);
        if (disposition === 'duplicate') {
          await client.query('ROLLBACK TO SAVEPOINT proj');
          await client.query(
            `UPDATE pending_operations SET processed_at = NOW(), result = $2, error = NULL WHERE id = $1`,
            [op.id, JSON.stringify({ action: 'noop', reason: 'duplicate' })],
          );
          // The circle was already provisioned for the conflicting row.
          cipherCircleId = circleId;
          return { done: false as const, status: 'ok' as const };
        }
        if (disposition === 'permanent') {
          await client.query('ROLLBACK TO SAVEPOINT proj');
          await client.query(
            `UPDATE pending_operations SET processed_at = NOW(), error = $2, result = NULL WHERE id = $1`,
            [op.id, errorMessage(err)],
          );
          logger.warn(
            { opId: op.id, type: op.operation_type, err: errorMessage(err) },
            'sync op rejected',
          );
          return { done: false as const, status: 'error' as const };
        }
        // Transient: abandon this op's transaction and defer it.
        deferredIds.push(op.id);
        throw err;
      }
    }).catch((err) => {
      // withRls rolled back; the op stays unprocessed and is deferred so the
      // drain keeps making progress on the rest. The job still fails at the
      // end so BullMQ retries the deferred ops.
      logger.warn({ userId: data.userId, err: errorMessage(err) }, 'sync op deferred');
      return { done: false as const, status: 'deferred' as const };
    });

    if (cipherCircleId && dekForCommit) {
      dekCache.set(cipherCircleId, dekForCommit);
    }
    if (step.done) {
      break;
    }
    if (step.status === 'ok') {
      applied += 1;
    } else if (step.status === 'error') {
      failed += 1;
    }
  }

  const result: SyncProjectorResult = { applied, failed, deferred: deferredIds.length };
  logger.info({ userId: data.userId, ...result }, 'sync projector drained');
  if (deferredIds.length > 0) {
    throw new Error(`sync projector deferred ${deferredIds.length} op(s) for retry`);
  }
  return result;
}

function makeUserResolver(
  client: pg.PoolClient,
): (appleUserId: string | null | undefined) => Promise<string | null> {
  const cache = new Map<string, string | null>();
  return async (appleUserId) => {
    if (!appleUserId) {
      return null;
    }
    if (cache.has(appleUserId)) {
      return cache.get(appleUserId) ?? null;
    }
    const res = await client.query<{ id: string }>(
      `SELECT id FROM users WHERE apple_user_id = $1 AND deleted_at IS NULL`,
      [appleUserId],
    );
    const id = res.rows[0]?.id ?? null;
    cache.set(appleUserId, id);
    return id;
  };
}
