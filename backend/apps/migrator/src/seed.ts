/**
 * CareCircle seed. Idempotent: clears the existing app data then re-creates
 * two complete demo circles, every entity type populated, every RLS-bound
 * relationship wired. Apple IDs use the deterministic "mock|<id>" form so
 * `/v1/auth/_mock-token` can mint test tokens in non-prod environments.
 */
import { randomUUID, randomBytes } from 'node:crypto';
import pg from 'pg';
import {
  encryptColumn,
  newDek,
  wrapDek,
  HCBS_SERVICES,
} from '@carecircle/shared';

type Cipher = (plaintext: string) => Buffer;

type SeededUser = {
  id: string;
  appleId: string;
  email: string;
  displayName: string;
};

type SeededCircle = {
  id: string;
  name: string;
  ownerId: string;
  recipientId: string;
  cipher: Cipher;
  memberIds: Record<string, string>; // userId -> circleMemberId
};

const APP_MASTER_KEY = process.env.APP_MASTER_KEY;
if (!APP_MASTER_KEY || APP_MASTER_KEY.length < 32) {
  console.error('APP_MASTER_KEY is required (>= 32 chars).');
  process.exit(1);
}

const connectionString =
  process.env.DIRECT_DATABASE_URL ?? process.env.DATABASE_URL;
if (!connectionString) {
  console.error('DATABASE_URL or DIRECT_DATABASE_URL is required.');
  process.exit(1);
}

const TABLES_TO_TRUNCATE = [
  'audit_log',
  'activity_reactions',
  'activity_comments',
  'activities',
  'dose_events',
  'medications',
  'appointment_attendees',
  'appointments',
  'care_minute_entries',
  'care_shifts',
  'documents',
  'emergency_contacts',
  'sos_events',
  'pending_operations',
  'circle_invitations',
  'circle_members',
  'circle_keys',
  'care_recipients',
  'circles',
  'devices',
  'refresh_tokens',
  'users',
];

const FAMILY_USERS = {
  laura: {
    appleId: 'mock|laura.chen',
    email: 'laura@example.com',
    displayName: 'Laura',
  },
  michael: {
    appleId: 'mock|michael.chen',
    email: 'michael@example.com',
    displayName: 'Michael',
  },
  ada: {
    appleId: 'mock|ada.chen',
    email: 'ada@example.com',
    displayName: 'Ada (Mom)',
  },
  rosa: {
    appleId: 'mock|rosa.aide',
    email: 'rosa@example.com',
    displayName: 'Rosa',
  },
  uncleBen: {
    appleId: 'mock|ben.relative',
    email: 'ben@example.com',
    displayName: 'Uncle Ben',
  },

  diego: {
    appleId: 'mock|diego.alvarez',
    email: 'diego@example.com',
    displayName: 'Diego',
  },
  sofia: {
    appleId: 'mock|sofia.alvarez',
    email: 'sofia@example.com',
    displayName: 'Sofía',
  },
  martin: {
    appleId: 'mock|martin.alvarez',
    email: 'martin@example.com',
    displayName: 'Martín (Dad)',
  },
  carla: {
    appleId: 'mock|carla.aide',
    email: 'carla@example.com',
    displayName: 'Carla',
  },
} as const;

function cipherFor(dek: Buffer): Cipher {
  return (plaintext: string) => encryptColumn(plaintext, dek);
}

function asInteger(date: Date): string {
  return date.toISOString();
}

async function truncateAll(client: pg.PoolClient): Promise<void> {
  const list = TABLES_TO_TRUNCATE.join(', ');
  await client.query(`TRUNCATE TABLE ${list} RESTART IDENTITY CASCADE`);
}

async function insertUser(
  client: pg.PoolClient,
  user: { appleId: string; email: string; displayName: string },
): Promise<SeededUser> {
  const id = randomUUID();
  await client.query(
    `INSERT INTO users (id, apple_user_id, email, display_name)
     VALUES ($1, $2, $3, $4)`,
    [id, user.appleId, user.email, user.displayName],
  );
  return { id, ...user };
}

async function insertDevice(
  client: pg.PoolClient,
  userId: string,
  label: string,
): Promise<void> {
  await client.query(
    `INSERT INTO devices (user_id, apns_token, device_name, os_version, app_version, locale, timezone)
     VALUES ($1, $2, $3, '18.4', '0.13.7', 'en_US', 'America/Los_Angeles')`,
    [userId, randomBytes(32).toString('hex'), label],
  );
}

async function insertCircleKey(
  client: pg.PoolClient,
  circleId: string,
): Promise<Cipher> {
  const dek = newDek();
  const wrapped = wrapDek(dek, APP_MASTER_KEY!);
  await client.query(
    `INSERT INTO circle_keys (circle_id, encrypted_dek, key_version)
     VALUES ($1, $2, 1)`,
    [circleId, wrapped],
  );
  return cipherFor(dek);
}

async function insertCircle(
  client: pg.PoolClient,
  ownerId: string,
  name: string,
  tier: 'free' | 'family' | 'pro',
): Promise<{ id: string; cipher: Cipher }> {
  const id = randomUUID();
  await client.query(
    `INSERT INTO circles (id, name, owner_user_id, subscription_tier, subscription_status)
     VALUES ($1, $2, $3, $4, 'active')`,
    [id, name, ownerId, tier],
  );
  const cipher = await insertCircleKey(client, id);
  return { id, cipher };
}

async function insertRecipient(
  client: pg.PoolClient,
  circleId: string,
  cipher: Cipher,
  details: {
    firstName: string;
    lastName?: string;
    dob?: string;
    pronouns?: string;
    conditions?: string[];
    userId?: string | null;
  },
): Promise<string> {
  const id = randomUUID();
  await client.query(
    `INSERT INTO care_recipients (
        id, circle_id,
        first_name_enc, last_name_enc, date_of_birth_enc,
        pronouns, primary_conditions_enc, has_user_account, user_id
     ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
    [
      id,
      circleId,
      cipher(details.firstName),
      details.lastName ? cipher(details.lastName) : null,
      details.dob ? cipher(details.dob) : null,
      details.pronouns ?? null,
      details.conditions ? cipher(JSON.stringify(details.conditions)) : null,
      details.userId != null,
      details.userId ?? null,
    ],
  );
  await client.query(`UPDATE circles SET care_recipient_id = $1 WHERE id = $2`, [
    id,
    circleId,
  ]);
  return id;
}

async function insertMember(
  client: pg.PoolClient,
  args: {
    circleId: string;
    userId: string;
    role:
      | 'owner'
      | 'family_member'
      | 'paid_aide'
      | 'paid_family'
      | 'care_recipient'
      | 'view_only';
    displayName: string;
    invitedBy?: string | null;
    joinedAt?: Date | null;
  },
): Promise<string> {
  const id = randomUUID();
  await client.query(
    `INSERT INTO circle_members (
        id, circle_id, user_id, role, status, display_name,
        invited_by, joined_at, invited_at
     ) VALUES ($1, $2, $3, $4, 'active', $5, $6, COALESCE($7, NOW()), NOW())`,
    [
      id,
      args.circleId,
      args.userId,
      args.role,
      args.displayName,
      args.invitedBy ?? null,
      args.joinedAt ?? new Date(),
    ],
  );
  return id;
}

async function insertActivity(
  client: pg.PoolClient,
  args: {
    circleId: string;
    authorId: string;
    type:
      | 'voice_note'
      | 'text_note'
      | 'photo'
      | 'med_taken'
      | 'med_skipped'
      | 'med_missed'
      | 'vital_logged'
      | 'appointment_logged'
      | 'shift_started'
      | 'shift_ended'
      | 'document_added'
      | 'sos_triggered'
      | 'system';
    headline?: string;
    content?: string;
    photoKeys?: string[];
    voiceKey?: string;
    entities?: string[];
    relatedMedId?: string;
    relatedAppointmentId?: string;
    relatedShiftId?: string;
    occurredAt?: Date;
    cipher: Cipher;
  },
): Promise<string> {
  const id = randomUUID();
  await client.query(
    `INSERT INTO activities (
        id, circle_id, author_user_id, activity_type, headline,
        content_enc, voice_object_key, photo_object_keys, entities_enc,
        related_med_id, related_appointment_id, related_shift_id,
        occurred_at, client_op_id
     ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)`,
    [
      id,
      args.circleId,
      args.authorId,
      args.type,
      args.headline ?? null,
      args.content ? args.cipher(args.content) : null,
      args.voiceKey ?? null,
      args.photoKeys ?? null,
      args.entities ? args.cipher(JSON.stringify(args.entities)) : null,
      args.relatedMedId ?? null,
      args.relatedAppointmentId ?? null,
      args.relatedShiftId ?? null,
      args.occurredAt ?? new Date(),
      randomUUID(),
    ],
  );
  return id;
}

async function insertReaction(
  client: pg.PoolClient,
  args: { activityId: string; circleId: string; userId: string; emoji: string },
): Promise<void> {
  await client.query(
    `INSERT INTO activity_reactions (activity_id, circle_id, user_id, emoji)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT DO NOTHING`,
    [args.activityId, args.circleId, args.userId, args.emoji],
  );
}

async function insertComment(
  client: pg.PoolClient,
  args: {
    activityId: string;
    circleId: string;
    authorId: string;
    content: string;
    cipher: Cipher;
  },
): Promise<void> {
  await client.query(
    `INSERT INTO activity_comments (activity_id, circle_id, author_user_id, content_enc)
     VALUES ($1, $2, $3, $4)`,
    [args.activityId, args.circleId, args.authorId, args.cipher(args.content)],
  );
}

async function insertMedication(
  client: pg.PoolClient,
  args: {
    circleId: string;
    cipher: Cipher;
    name: string;
    generic?: string;
    dosage: string;
    form?: string;
    rxcui?: string;
    schedule: { times: string[]; intervalHours?: number };
    color?: string;
    prescriber?: string;
    pharmacy?: string;
    notes?: string;
    startDate?: string;
  },
): Promise<string> {
  const id = randomUUID();
  await client.query(
    `INSERT INTO medications (
        id, circle_id, name_enc, generic_name_enc, dosage_enc, form, rxcui, color, status, schedule,
        prescribing_provider_enc, pharmacy_enc, notes_enc, start_date
     ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'active', $9::jsonb,
              $10, $11, $12, $13)`,
    [
      id,
      args.circleId,
      args.cipher(args.name),
      args.generic ? args.cipher(args.generic) : null,
      args.cipher(args.dosage),
      args.form ?? null,
      args.rxcui ?? null,
      args.color ?? null,
      JSON.stringify(args.schedule),
      args.prescriber ? args.cipher(args.prescriber) : null,
      args.pharmacy ? args.cipher(args.pharmacy) : null,
      args.notes ? args.cipher(args.notes) : null,
      args.startDate ?? null,
    ],
  );
  return id;
}

async function insertDose(
  client: pg.PoolClient,
  args: {
    medicationId: string;
    circleId: string;
    scheduledAt: Date;
    status: 'scheduled' | 'taken' | 'skipped' | 'missed' | 'late';
    takenAt?: Date | null;
    markedBy?: string | null;
    notes?: string;
    cipher: Cipher;
  },
): Promise<void> {
  await client.query(
    `INSERT INTO dose_events (
        medication_id, circle_id, scheduled_at, taken_at, marked_by, status, notes_enc
     ) VALUES ($1, $2, $3, $4, $5, $6, $7)`,
    [
      args.medicationId,
      args.circleId,
      args.scheduledAt,
      args.takenAt ?? null,
      args.markedBy ?? null,
      args.status,
      args.notes ? args.cipher(args.notes) : null,
    ],
  );
}

async function insertAppointment(
  client: pg.PoolClient,
  args: {
    circleId: string;
    cipher: Cipher;
    createdBy: string;
    title: string;
    provider?: string;
    location?: string;
    startsAt: Date;
    durationMinutes: number;
    transportResponsible?: string;
    prepNotes?: string;
    attendees?: string[];
  },
): Promise<string> {
  const id = randomUUID();
  await client.query(
    `INSERT INTO appointments (
        id, circle_id, title_enc, provider_enc, location_enc, starts_at,
        duration_minutes, transport_responsible, prep_notes_enc, created_by
     ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
    [
      id,
      args.circleId,
      args.cipher(args.title),
      args.provider ? args.cipher(args.provider) : null,
      args.location ? args.cipher(args.location) : null,
      args.startsAt,
      args.durationMinutes,
      args.transportResponsible ?? null,
      args.prepNotes ? args.cipher(args.prepNotes) : null,
      args.createdBy,
    ],
  );
  for (const attendee of args.attendees ?? []) {
    await client.query(
      `INSERT INTO appointment_attendees (appointment_id, user_id, circle_id)
       VALUES ($1, $2, $3)
       ON CONFLICT DO NOTHING`,
      [id, attendee, args.circleId],
    );
  }
  return id;
}

async function insertShift(
  client: pg.PoolClient,
  args: {
    circleId: string;
    aideId: string;
    startsAt: Date;
    endsAt: Date;
    actualStart?: Date | null;
    actualEnd?: Date | null;
    services?: string[];
    notes?: string;
    cipher: Cipher;
  },
): Promise<string> {
  const id = randomUUID();
  await client.query(
    `INSERT INTO care_shifts (
        id, circle_id, aide_user_id, starts_at, ends_at,
        actual_start, actual_end, services, notes_enc
     ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
    [
      id,
      args.circleId,
      args.aideId,
      args.startsAt,
      args.endsAt,
      args.actualStart ?? null,
      args.actualEnd ?? null,
      args.services ?? [],
      args.notes ? args.cipher(args.notes) : null,
    ],
  );
  return id;
}

async function insertDocument(
  client: pg.PoolClient,
  args: {
    circleId: string;
    cipher: Cipher;
    title: string;
    documentType:
      | 'insurance_card'
      | 'advance_directive'
      | 'dnr'
      | 'med_list'
      | 'visit_summary'
      | 'eob'
      | 'lab_result'
      | 'identification'
      | 'other';
    objectKey: string;
    mimeType: string;
    sizeBytes: number;
    uploadedBy: string;
    expiresAt?: string;
  },
): Promise<string> {
  const id = randomUUID();
  await client.query(
    `INSERT INTO documents (
        id, circle_id, title_enc, document_type, object_key, mime_type,
        size_bytes, encryption_nonce, encryption_tag, expires_at, uploaded_by
     ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)`,
    [
      id,
      args.circleId,
      args.cipher(args.title),
      args.documentType,
      args.objectKey,
      args.mimeType,
      args.sizeBytes,
      randomBytes(12),
      randomBytes(16),
      args.expiresAt ?? null,
      args.uploadedBy,
    ],
  );
  return id;
}

async function insertEmergencyContact(
  client: pg.PoolClient,
  args: {
    circleId: string;
    cipher: Cipher;
    name: string;
    phone: string;
    relationship?: string;
    isPrimary?: boolean;
    isMedical?: boolean;
    sortOrder?: number;
  },
): Promise<void> {
  await client.query(
    `INSERT INTO emergency_contacts (
        circle_id, name_enc, phone_enc, relationship,
        is_primary, is_medical, sort_order
     ) VALUES ($1, $2, $3, $4, $5, $6, $7)`,
    [
      args.circleId,
      args.cipher(args.name),
      args.cipher(args.phone),
      args.relationship ?? null,
      !!args.isPrimary,
      !!args.isMedical,
      args.sortOrder ?? 100,
    ],
  );
}

async function insertCareMinute(
  client: pg.PoolClient,
  args: {
    circleId: string;
    caregiverId: string;
    serviceCode: string;
    startedAt: Date;
    endedAt: Date;
    notes?: string;
    fiscalIntermediary?: string;
    cipher: Cipher;
  },
): Promise<void> {
  const service = HCBS_SERVICES.find((s) => s.code === args.serviceCode);
  if (!service) {
    throw new Error(`unknown HCBS code ${args.serviceCode}`);
  }
  const duration = Math.round(
    (args.endedAt.getTime() - args.startedAt.getTime()) / 60_000,
  );
  await client.query(
    `INSERT INTO care_minute_entries (
        circle_id, caregiver_user_id, service_code, service_description,
        started_at, ended_at, duration_minutes, notes_enc, fiscal_intermediary
     ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
    [
      args.circleId,
      args.caregiverId,
      args.serviceCode,
      service.description,
      args.startedAt,
      args.endedAt,
      duration,
      args.notes ? args.cipher(args.notes) : null,
      args.fiscalIntermediary ?? null,
    ],
  );
}

async function insertSos(
  client: pg.PoolClient,
  args: {
    circleId: string;
    triggeredBy: string;
    triggeredAt: Date;
    canceledAt?: Date;
    canceledBy?: string;
    notifiedUserIds: string[];
  },
): Promise<void> {
  await client.query(
    `INSERT INTO sos_events (
        circle_id, triggered_by, triggered_at, canceled_at, canceled_by,
        location_lat, location_lng, location_accuracy_m, notified_user_ids
     ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::uuid[])`,
    [
      args.circleId,
      args.triggeredBy,
      args.triggeredAt,
      args.canceledAt ?? null,
      args.canceledBy ?? null,
      37.7749,
      -122.4194,
      14.0,
      args.notifiedUserIds,
    ],
  );
}

async function seedCircleA(client: pg.PoolClient): Promise<SeededCircle> {
  const laura = await insertUser(client, FAMILY_USERS.laura);
  const michael = await insertUser(client, FAMILY_USERS.michael);
  const ada = await insertUser(client, FAMILY_USERS.ada);
  const rosa = await insertUser(client, FAMILY_USERS.rosa);
  const uncleBen = await insertUser(client, FAMILY_USERS.uncleBen);
  await Promise.all([
    insertDevice(client, laura.id, 'iPhone 16 Pro Max'),
    insertDevice(client, michael.id, 'iPhone 15'),
    insertDevice(client, rosa.id, 'iPhone SE'),
  ]);

  const { id: circleId, cipher } = await insertCircle(
    client,
    laura.id,
    "Mom's Care",
    'family',
  );
  const recipientId = await insertRecipient(client, circleId, cipher, {
    firstName: 'Ada',
    lastName: 'Chen',
    dob: '1948-03-19',
    pronouns: 'she/her',
    conditions: ['Type 2 Diabetes', 'Mild Cognitive Impairment', 'Hypertension'],
    userId: ada.id,
  });

  const memberIds: Record<string, string> = {};
  memberIds[laura.id] = await insertMember(client, {
    circleId,
    userId: laura.id,
    role: 'owner',
    displayName: 'Laura',
    joinedAt: new Date('2026-01-04T15:00:00Z'),
  });
  memberIds[michael.id] = await insertMember(client, {
    circleId,
    userId: michael.id,
    role: 'family_member',
    displayName: 'Michael',
    invitedBy: laura.id,
    joinedAt: new Date('2026-01-04T16:30:00Z'),
  });
  memberIds[ada.id] = await insertMember(client, {
    circleId,
    userId: ada.id,
    role: 'care_recipient',
    displayName: 'Mom',
    invitedBy: laura.id,
    joinedAt: new Date('2026-01-04T17:00:00Z'),
  });
  memberIds[rosa.id] = await insertMember(client, {
    circleId,
    userId: rosa.id,
    role: 'paid_aide',
    displayName: 'Rosa (Aide)',
    invitedBy: laura.id,
    joinedAt: new Date('2026-01-07T19:00:00Z'),
  });
  memberIds[uncleBen.id] = await insertMember(client, {
    circleId,
    userId: uncleBen.id,
    role: 'view_only',
    displayName: 'Uncle Ben',
    invitedBy: laura.id,
    joinedAt: new Date('2026-01-12T19:00:00Z'),
  });

  // Open invitation (waiting for accept)
  await client.query(
    `INSERT INTO circle_invitations (
        circle_id, invited_by, role, code, email, expires_at
     ) VALUES ($1, $2, 'family_member', 'ABCD1234', 'cousin@example.com',
              NOW() + INTERVAL '7 days')`,
    [circleId, laura.id],
  );

  // Medications
  const metformin = await insertMedication(client, {
    circleId,
    cipher,
    name: 'Metformin',
    generic: 'metformin hydrochloride',
    dosage: '500 mg',
    form: 'tablet',
    rxcui: '860975',
    color: '#3b82f6',
    schedule: { times: ['08:00', '20:00'] },
    prescriber: 'Dr. Yang',
    pharmacy: 'CVS — 24th & Mission',
    notes: 'Take with food.',
    startDate: '2025-11-01',
  });
  const lisinopril = await insertMedication(client, {
    circleId,
    cipher,
    name: 'Lisinopril',
    generic: 'lisinopril',
    dosage: '10 mg',
    form: 'tablet',
    rxcui: '197884',
    color: '#10b981',
    schedule: { times: ['08:00'] },
    prescriber: 'Dr. Yang',
    pharmacy: 'CVS — 24th & Mission',
    startDate: '2025-09-15',
  });
  const donepezil = await insertMedication(client, {
    circleId,
    cipher,
    name: 'Donepezil',
    generic: 'donepezil hydrochloride',
    dosage: '5 mg',
    form: 'tablet',
    rxcui: '997220',
    color: '#a855f7',
    schedule: { times: ['21:00'] },
    prescriber: 'Dr. Patel',
    notes: 'Bedtime. Watch for sleep changes for first two weeks.',
    startDate: '2026-02-10',
  });

  const today = new Date();
  const startOfDayUTC = new Date(
    Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate()),
  );
  // Seven days of doses
  for (let dayOffset = -6; dayOffset <= 0; dayOffset++) {
    const day = new Date(startOfDayUTC);
    day.setUTCDate(day.getUTCDate() + dayOffset);
    const at = (h: number) => {
      const d = new Date(day);
      d.setUTCHours(h, 0, 0, 0);
      return d;
    };
    // metformin morning + evening
    await insertDose(client, {
      medicationId: metformin,
      circleId,
      scheduledAt: at(8 + 7), // 8am Pacific ~ 15 UTC
      status: dayOffset === 0 ? 'taken' : 'taken',
      takenAt: at(8 + 7 + 0.1),
      markedBy: dayOffset % 2 === 0 ? laura.id : rosa.id,
      cipher,
    });
    await insertDose(client, {
      medicationId: metformin,
      circleId,
      scheduledAt: at(20 + 7), // 8pm pacific ~ 3 UTC next day, simplified
      status: dayOffset === -3 ? 'missed' : 'taken',
      takenAt: dayOffset === -3 ? null : at(20 + 7 + 0.1),
      markedBy: dayOffset === -3 ? null : laura.id,
      cipher,
    });
    // lisinopril morning
    await insertDose(client, {
      medicationId: lisinopril,
      circleId,
      scheduledAt: at(8 + 7),
      status: dayOffset === -5 ? 'late' : 'taken',
      takenAt: at(8 + 7 + (dayOffset === -5 ? 2 : 0.2)),
      markedBy: dayOffset % 3 === 0 ? rosa.id : laura.id,
      cipher,
    });
    if (dayOffset >= -3) {
      // donepezil started recently
      await insertDose(client, {
        medicationId: donepezil,
        circleId,
        scheduledAt: at(21 + 7),
        status: dayOffset === 0 ? 'scheduled' : 'taken',
        takenAt: dayOffset === 0 ? null : at(21 + 7 + 0.2),
        markedBy: dayOffset === 0 ? null : laura.id,
        cipher,
      });
    }
  }

  // Appointments
  const cardio = await insertAppointment(client, {
    circleId,
    cipher,
    createdBy: laura.id,
    title: 'Cardiology follow-up',
    provider: 'Dr. Yang — UCSF',
    location: '350 Parnassus Ave',
    startsAt: new Date(Date.now() + 3 * 24 * 3600 * 1000 + 9 * 3600 * 1000),
    durationMinutes: 45,
    transportResponsible: laura.id,
    prepNotes: 'Bring BP log + current med list. Fasting NOT required.',
    attendees: [laura.id, ada.id],
  });
  const dental = await insertAppointment(client, {
    circleId,
    cipher,
    createdBy: michael.id,
    title: 'Dental cleaning',
    provider: 'Dr. Mendez',
    location: 'Mission Smiles Dental',
    startsAt: new Date(Date.now() + 12 * 24 * 3600 * 1000),
    durationMinutes: 60,
    transportResponsible: michael.id,
    prepNotes: 'Mom prefers afternoon slots.',
    attendees: [michael.id, ada.id],
  });

  // Shifts
  const shiftYesterday = await insertShift(client, {
    circleId,
    aideId: rosa.id,
    startsAt: new Date(Date.now() - 1 * 24 * 3600 * 1000),
    endsAt: new Date(Date.now() - 1 * 24 * 3600 * 1000 + 4 * 3600 * 1000),
    actualStart: new Date(Date.now() - 1 * 24 * 3600 * 1000 + 5 * 60 * 1000),
    actualEnd: new Date(Date.now() - 1 * 24 * 3600 * 1000 + 4 * 3600 * 1000),
    services: ['T1019', 'S5125'],
    notes: 'Helped Ada with shower + lunch. Steady on her feet today.',
    cipher,
  });
  const shiftToday = await insertShift(client, {
    circleId,
    aideId: rosa.id,
    startsAt: new Date(Date.now() + 6 * 3600 * 1000),
    endsAt: new Date(Date.now() + 10 * 3600 * 1000),
    services: ['T1019'],
    cipher,
  });

  // Care minute entries (paid aide billing)
  await insertCareMinute(client, {
    circleId,
    caregiverId: rosa.id,
    serviceCode: 'T1019',
    startedAt: new Date(Date.now() - 1 * 24 * 3600 * 1000),
    endedAt: new Date(Date.now() - 1 * 24 * 3600 * 1000 + 3 * 3600 * 1000),
    notes: 'Personal care: shower, dressing, meal prep.',
    fiscalIntermediary: 'PPL',
    cipher,
  });
  await insertCareMinute(client, {
    circleId,
    caregiverId: rosa.id,
    serviceCode: 'S5125',
    startedAt: new Date(Date.now() - 1 * 24 * 3600 * 1000 + 3 * 3600 * 1000),
    endedAt: new Date(Date.now() - 1 * 24 * 3600 * 1000 + 4 * 3600 * 1000),
    notes: 'Attendant care: companionship, medication reminders.',
    fiscalIntermediary: 'PPL',
    cipher,
  });

  // Documents
  await insertDocument(client, {
    circleId,
    cipher,
    title: 'Blue Shield member ID — Ada',
    documentType: 'insurance_card',
    objectKey: 'documents/circle-a/insurance-front.enc',
    mimeType: 'image/jpeg',
    sizeBytes: 1_245_312,
    uploadedBy: laura.id,
    expiresAt: '2027-01-01',
  });
  await insertDocument(client, {
    circleId,
    cipher,
    title: 'Advance directive (notarized)',
    documentType: 'advance_directive',
    objectKey: 'documents/circle-a/ad-2025.pdf.enc',
    mimeType: 'application/pdf',
    sizeBytes: 1_874_998,
    uploadedBy: laura.id,
  });
  await insertDocument(client, {
    circleId,
    cipher,
    title: 'Recent med list',
    documentType: 'med_list',
    objectKey: 'documents/circle-a/meds.pdf.enc',
    mimeType: 'application/pdf',
    sizeBytes: 412_044,
    uploadedBy: rosa.id,
  });

  // Emergency contacts
  await insertEmergencyContact(client, {
    circleId,
    cipher,
    name: 'Dr. Yang (Cardiology)',
    phone: '+14155551234',
    relationship: 'physician',
    isMedical: true,
    sortOrder: 10,
  });
  await insertEmergencyContact(client, {
    circleId,
    cipher,
    name: 'Laura Chen',
    phone: '+14155557788',
    relationship: 'daughter',
    isPrimary: true,
    sortOrder: 1,
  });
  await insertEmergencyContact(client, {
    circleId,
    cipher,
    name: 'Michael Chen',
    phone: '+14155551111',
    relationship: 'son',
    sortOrder: 5,
  });
  await insertEmergencyContact(client, {
    circleId,
    cipher,
    name: 'San Francisco Fire / 911',
    phone: '911',
    relationship: 'emergency',
    sortOrder: 0,
  });

  // SOS events
  await insertSos(client, {
    circleId,
    triggeredBy: ada.id,
    triggeredAt: new Date(Date.now() - 4 * 24 * 3600 * 1000),
    canceledAt: new Date(Date.now() - 4 * 24 * 3600 * 1000 + 90_000),
    canceledBy: ada.id,
    notifiedUserIds: [laura.id, michael.id, rosa.id],
  });

  // Activities
  const ts = (offsetMin: number) => new Date(Date.now() + offsetMin * 60_000);

  const voiceA1 = await insertActivity(client, {
    circleId,
    authorId: rosa.id,
    type: 'voice_note',
    headline: 'Morning visit recap',
    content:
      "Ada slept well. BP was 132/78. She's a bit tired but otherwise good. We walked to the kitchen and back twice.",
    voiceKey: 'voice/circle-a/2026-05-13/0900-handoff.m4a',
    entities: ['BP 132/78', 'walking', 'fatigue'],
    occurredAt: ts(-60 * 4),
    cipher,
  });
  await insertReaction(client, {
    activityId: voiceA1,
    circleId,
    userId: laura.id,
    emoji: '🙏',
  });
  await insertReaction(client, {
    activityId: voiceA1,
    circleId,
    userId: michael.id,
    emoji: '👍',
  });
  await insertComment(client, {
    activityId: voiceA1,
    circleId,
    authorId: laura.id,
    content: 'Thanks Rosa — I’ll mention the fatigue at the cardiology visit Thursday.',
    cipher,
  });

  const medActivity = await insertActivity(client, {
    circleId,
    authorId: laura.id,
    type: 'med_taken',
    headline: 'Metformin (morning) marked taken',
    occurredAt: ts(-60 * 2),
    relatedMedId: metformin,
    cipher,
  });
  await insertReaction(client, {
    activityId: medActivity,
    circleId,
    userId: rosa.id,
    emoji: '✅',
  });

  await insertActivity(client, {
    circleId,
    authorId: michael.id,
    type: 'photo',
    headline: 'Mom in the garden',
    content: 'She wanted to show off the tomatoes today.',
    photoKeys: ['photos/circle-a/garden-2026-05-12.jpg'],
    occurredAt: ts(-60 * 24),
    cipher,
  });

  await insertActivity(client, {
    circleId,
    authorId: rosa.id,
    type: 'shift_started',
    headline: 'Rosa clocked in',
    relatedShiftId: shiftYesterday,
    occurredAt: ts(-60 * 24 - 5),
    cipher,
  });
  await insertActivity(client, {
    circleId,
    authorId: rosa.id,
    type: 'shift_ended',
    headline: 'Rosa clocked out',
    relatedShiftId: shiftYesterday,
    occurredAt: ts(-60 * 24 + 60 * 4),
    cipher,
  });

  await insertActivity(client, {
    circleId,
    authorId: laura.id,
    type: 'appointment_logged',
    headline: 'Cardiology Thursday at 9am — Laura driving',
    occurredAt: ts(-60 * 12),
    relatedAppointmentId: cardio,
    cipher,
  });

  await insertActivity(client, {
    circleId,
    authorId: laura.id,
    type: 'text_note',
    headline: 'BP log Monday morning',
    content: 'Tracked 130/76, 134/80, 128/74. Trend stable.',
    entities: ['BP 130/76', 'BP 134/80', 'BP 128/74'],
    occurredAt: ts(-60 * 36),
    cipher,
  });

  await insertActivity(client, {
    circleId,
    authorId: ada.id,
    type: 'sos_triggered',
    headline: 'Ada triggered SOS (canceled within 90s)',
    occurredAt: new Date(Date.now() - 4 * 24 * 3600 * 1000),
    cipher,
  });

  // Pending operation example
  await client.query(
    `INSERT INTO pending_operations (client_op_id, user_id, circle_id, operation_type, payload)
     VALUES ($1, $2, $3, 'mark_dose_taken', $4::jsonb)`,
    [
      randomUUID(),
      michael.id,
      circleId,
      JSON.stringify({ medicationId: metformin, scheduledAt: ts(-60 * 30).toISOString() }),
    ],
  );

  // Mark dental as used variable to avoid 'declared but unused'
  void dental;
  void shiftToday;

  return {
    id: circleId,
    name: "Mom's Care",
    ownerId: laura.id,
    recipientId,
    cipher,
    memberIds,
  };
}

async function seedCircleB(client: pg.PoolClient): Promise<SeededCircle> {
  const diego = await insertUser(client, FAMILY_USERS.diego);
  const sofia = await insertUser(client, FAMILY_USERS.sofia);
  const martin = await insertUser(client, FAMILY_USERS.martin);
  const carla = await insertUser(client, FAMILY_USERS.carla);
  await Promise.all([
    insertDevice(client, diego.id, 'iPhone 16'),
    insertDevice(client, sofia.id, 'iPhone 14 Pro'),
  ]);

  const { id: circleId, cipher } = await insertCircle(
    client,
    diego.id,
    "Papá's Care",
    'pro',
  );
  const recipientId = await insertRecipient(client, circleId, cipher, {
    firstName: 'Martín',
    lastName: 'Álvarez',
    dob: '1944-07-02',
    pronouns: 'he/him',
    conditions: ['Parkinson’s disease (stage 2)', 'Mild dysphagia'],
    userId: martin.id,
  });

  const memberIds: Record<string, string> = {};
  memberIds[diego.id] = await insertMember(client, {
    circleId,
    userId: diego.id,
    role: 'owner',
    displayName: 'Diego',
    joinedAt: new Date('2026-02-01T12:00:00Z'),
  });
  memberIds[sofia.id] = await insertMember(client, {
    circleId,
    userId: sofia.id,
    role: 'paid_family',
    displayName: 'Sofía (paid family)',
    invitedBy: diego.id,
    joinedAt: new Date('2026-02-01T13:00:00Z'),
  });
  memberIds[martin.id] = await insertMember(client, {
    circleId,
    userId: martin.id,
    role: 'care_recipient',
    displayName: 'Papá',
    invitedBy: diego.id,
    joinedAt: new Date('2026-02-02T01:00:00Z'),
  });
  memberIds[carla.id] = await insertMember(client, {
    circleId,
    userId: carla.id,
    role: 'paid_aide',
    displayName: 'Carla',
    invitedBy: diego.id,
    joinedAt: new Date('2026-02-10T15:00:00Z'),
  });

  const carbidopa = await insertMedication(client, {
    circleId,
    cipher,
    name: 'Carbidopa/Levodopa',
    generic: 'carbidopa-levodopa',
    dosage: '25/100 mg',
    form: 'tablet',
    rxcui: '197784',
    color: '#f97316',
    schedule: { times: ['07:00', '12:00', '17:00', '22:00'] },
    prescriber: 'Dr. Ahmadi — Neurology',
    pharmacy: 'Walgreens — Cesar Chavez',
    notes: 'Avoid taking with protein-heavy meals.',
    startDate: '2024-11-12',
  });
  const trihex = await insertMedication(client, {
    circleId,
    cipher,
    name: 'Trihexyphenidyl',
    generic: 'trihexyphenidyl',
    dosage: '2 mg',
    form: 'tablet',
    schedule: { times: ['08:00', '20:00'] },
    prescriber: 'Dr. Ahmadi — Neurology',
    startDate: '2025-03-01',
  });

  const startOfDayUTC = new Date();
  startOfDayUTC.setUTCHours(0, 0, 0, 0);
  for (let dayOffset = -5; dayOffset <= 0; dayOffset++) {
    const day = new Date(startOfDayUTC);
    day.setUTCDate(day.getUTCDate() + dayOffset);
    for (const hour of [14, 19, 24, 29]) {
      // approximate Carbidopa schedule in UTC
      const scheduledAt = new Date(day);
      scheduledAt.setUTCHours(hour, 0, 0, 0);
      await insertDose(client, {
        medicationId: carbidopa,
        circleId,
        scheduledAt,
        status: dayOffset === 0 && hour === 29 ? 'scheduled' : 'taken',
        takenAt: dayOffset === 0 && hour === 29 ? null : new Date(scheduledAt.getTime() + 6 * 60 * 1000),
        markedBy: dayOffset === 0 && hour === 29 ? null : sofia.id,
        cipher,
      });
    }
    for (const hour of [15, 27]) {
      const scheduledAt = new Date(day);
      scheduledAt.setUTCHours(hour, 0, 0, 0);
      await insertDose(client, {
        medicationId: trihex,
        circleId,
        scheduledAt,
        status: dayOffset === -2 && hour === 27 ? 'skipped' : 'taken',
        takenAt:
          dayOffset === -2 && hour === 27 ? null : new Date(scheduledAt.getTime() + 4 * 60 * 1000),
        markedBy: dayOffset === -2 && hour === 27 ? null : sofia.id,
        cipher,
        notes: dayOffset === -2 && hour === 27 ? 'Papá refused. Will retry tomorrow.' : undefined,
      });
    }
  }

  const neurology = await insertAppointment(client, {
    circleId,
    cipher,
    createdBy: diego.id,
    title: 'Neurology — Parkinson’s 6-mo review',
    provider: 'Dr. Ahmadi — UCSF Neurology',
    location: '1600 Divisadero',
    startsAt: new Date(Date.now() + 9 * 24 * 3600 * 1000),
    durationMinutes: 60,
    transportResponsible: diego.id,
    prepNotes: 'Bring tremor diary + recent symptom log.',
    attendees: [diego.id, sofia.id, martin.id],
  });
  await insertAppointment(client, {
    circleId,
    cipher,
    createdBy: sofia.id,
    title: 'Physical therapy (weekly)',
    provider: 'BalanceFirst PT',
    location: '2901 Geary Blvd',
    startsAt: new Date(Date.now() + 2 * 24 * 3600 * 1000),
    durationMinutes: 45,
    transportResponsible: sofia.id,
    prepNotes: 'PT shoes + water bottle.',
    attendees: [sofia.id, martin.id],
  });

  const shift1 = await insertShift(client, {
    circleId,
    aideId: carla.id,
    startsAt: new Date(Date.now() - 2 * 24 * 3600 * 1000),
    endsAt: new Date(Date.now() - 2 * 24 * 3600 * 1000 + 6 * 3600 * 1000),
    actualStart: new Date(Date.now() - 2 * 24 * 3600 * 1000),
    actualEnd: new Date(Date.now() - 2 * 24 * 3600 * 1000 + 6 * 3600 * 1000),
    services: ['T1019', 'S5125', 'T1005'],
    notes: 'Bathing, exercises, meal. Tremor calm afternoon.',
    cipher,
  });
  const shift2 = await insertShift(client, {
    circleId,
    aideId: sofia.id,
    startsAt: new Date(Date.now() - 24 * 3600 * 1000),
    endsAt: new Date(Date.now() - 24 * 3600 * 1000 + 8 * 3600 * 1000),
    actualStart: new Date(Date.now() - 24 * 3600 * 1000),
    actualEnd: new Date(Date.now() - 24 * 3600 * 1000 + 8 * 3600 * 1000),
    services: ['T1019'],
    notes: 'Full day with Papá. Quiet, good mood.',
    cipher,
  });

  await insertCareMinute(client, {
    circleId,
    caregiverId: sofia.id,
    serviceCode: 'T1019',
    startedAt: new Date(Date.now() - 24 * 3600 * 1000),
    endedAt: new Date(Date.now() - 24 * 3600 * 1000 + 8 * 3600 * 1000),
    notes: 'Companionship + meals + medication reminders.',
    fiscalIntermediary: 'Acumen',
    cipher,
  });
  await insertCareMinute(client, {
    circleId,
    caregiverId: carla.id,
    serviceCode: 'S5125',
    startedAt: new Date(Date.now() - 2 * 24 * 3600 * 1000),
    endedAt: new Date(Date.now() - 2 * 24 * 3600 * 1000 + 6 * 3600 * 1000),
    notes: 'Attendant care + therapeutic exercise.',
    fiscalIntermediary: 'Acumen',
    cipher,
  });
  await insertCareMinute(client, {
    circleId,
    caregiverId: sofia.id,
    serviceCode: 'T1005',
    startedAt: new Date(Date.now() - 5 * 24 * 3600 * 1000),
    endedAt: new Date(Date.now() - 5 * 24 * 3600 * 1000 + 4 * 3600 * 1000),
    notes: 'Respite care so Diego could attend a work event.',
    fiscalIntermediary: 'Acumen',
    cipher,
  });

  await insertDocument(client, {
    circleId,
    cipher,
    title: 'Medi-Cal card front',
    documentType: 'insurance_card',
    objectKey: 'documents/circle-b/medical-front.enc',
    mimeType: 'image/jpeg',
    sizeBytes: 1_023_877,
    uploadedBy: diego.id,
    expiresAt: '2027-06-01',
  });
  await insertDocument(client, {
    circleId,
    cipher,
    title: 'POLST (signed)',
    documentType: 'advance_directive',
    objectKey: 'documents/circle-b/polst.pdf.enc',
    mimeType: 'application/pdf',
    sizeBytes: 932_115,
    uploadedBy: diego.id,
  });

  await insertEmergencyContact(client, {
    circleId,
    cipher,
    name: 'Diego Álvarez',
    phone: '+14155558899',
    relationship: 'son',
    isPrimary: true,
    sortOrder: 1,
  });
  await insertEmergencyContact(client, {
    circleId,
    cipher,
    name: 'Dr. Ahmadi (Neurology)',
    phone: '+14155555050',
    relationship: 'physician',
    isMedical: true,
    sortOrder: 10,
  });
  await insertEmergencyContact(client, {
    circleId,
    cipher,
    name: '911',
    phone: '911',
    relationship: 'emergency',
    sortOrder: 0,
  });

  const ts = (offsetMin: number) => new Date(Date.now() + offsetMin * 60_000);

  const photo = await insertActivity(client, {
    circleId,
    authorId: sofia.id,
    type: 'photo',
    headline: 'Walk in the park today',
    photoKeys: ['photos/circle-b/park-2026-05-12.jpg'],
    occurredAt: ts(-90),
    cipher,
  });
  await insertReaction(client, {
    activityId: photo,
    circleId,
    userId: diego.id,
    emoji: '❤️',
  });
  await insertComment(client, {
    activityId: photo,
    circleId,
    authorId: diego.id,
    content: 'Papá looks great. Tell him I’ll bring empanadas Sunday.',
    cipher,
  });

  const voiceB = await insertActivity(client, {
    circleId,
    authorId: carla.id,
    type: 'voice_note',
    headline: 'Carla handoff – Tuesday',
    content:
      'Tremor mostly steady today. He had some trouble with the cup at lunch — would help to switch to the weighted cup.',
    voiceKey: 'voice/circle-b/2026-05-12/handoff.m4a',
    entities: ['tremor steady', 'dysphagia', 'switch to weighted cup'],
    occurredAt: ts(-60 * 30),
    cipher,
  });
  await insertReaction(client, {
    activityId: voiceB,
    circleId,
    userId: sofia.id,
    emoji: '🙏',
  });

  await insertActivity(client, {
    circleId,
    authorId: diego.id,
    type: 'document_added',
    headline: 'POLST signed and added',
    occurredAt: ts(-60 * 24 * 3),
    cipher,
  });

  await insertActivity(client, {
    circleId,
    authorId: sofia.id,
    type: 'shift_started',
    relatedShiftId: shift2,
    occurredAt: ts(-60 * 24),
    cipher,
  });

  await insertActivity(client, {
    circleId,
    authorId: diego.id,
    type: 'appointment_logged',
    headline: 'Neurology booked',
    relatedAppointmentId: neurology,
    occurredAt: ts(-60 * 8),
    cipher,
  });

  void shift1;

  return {
    id: circleId,
    name: "Papá's Care",
    ownerId: diego.id,
    recipientId,
    cipher,
    memberIds,
  };
}

async function main(): Promise<void> {
  const pool = new pg.Pool({ connectionString });
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await truncateAll(client);
    const circleA = await seedCircleA(client);
    const circleB = await seedCircleB(client);
    await client.query('COMMIT');

    const summary = {
      circles: [
        { id: circleA.id, name: circleA.name, ownerId: circleA.ownerId },
        { id: circleB.id, name: circleB.name, ownerId: circleB.ownerId },
      ],
      generatedAt: asInteger(new Date()),
    };
    console.log(JSON.stringify(summary, null, 2));
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
    await pool.end();
  }
}

main().catch((err) => {
  console.error('seed failed', err);
  process.exit(1);
});
