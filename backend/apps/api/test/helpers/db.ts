/**
 * Direct DB access for test setup. Bypasses RLS (superuser connection)
 * so we can seed cross-tenant data and then prove the API cannot leak it.
 */
import './env.js';
import { randomUUID } from 'node:crypto';
import pg from 'pg';
import { encryptColumn, newDek, wrapDek } from '@carecircle/shared';

const TABLES = [
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

export function makePool(): pg.Pool {
  return new pg.Pool({
    connectionString: process.env.DATABASE_URL,
    application_name: 'cc-test',
  });
}

export async function resetDb(pool: pg.Pool): Promise<void> {
  await pool.query(`TRUNCATE TABLE ${TABLES.join(', ')} RESTART IDENTITY CASCADE`);
}

export type SeededUser = {
  id: string;
  appleId: string;
  email: string;
  displayName: string;
};

export async function insertUser(
  pool: pg.Pool,
  args: { appleId?: string; email?: string; displayName?: string } = {},
): Promise<SeededUser> {
  const id = randomUUID();
  const appleId = args.appleId ?? `mock|${id}`;
  const email = args.email ?? `${id.slice(0, 8)}@test.example`;
  const displayName = args.displayName ?? `User-${id.slice(0, 4)}`;
  await pool.query(
    `INSERT INTO users (id, apple_user_id, email, display_name)
     VALUES ($1, $2, $3, $4)`,
    [id, appleId, email, displayName],
  );
  return { id, appleId, email, displayName };
}

export type SeededCircle = {
  id: string;
  name: string;
  ownerId: string;
  dek: Buffer;
};

export async function insertCircle(
  pool: pg.Pool,
  args: { ownerId: string; name?: string; tier?: 'free' | 'family' | 'pro' },
): Promise<SeededCircle> {
  const id = randomUUID();
  const name = args.name ?? `Circle-${id.slice(0, 4)}`;
  const tier = args.tier ?? 'family';
  await pool.query(
    `INSERT INTO circles (id, name, owner_user_id, subscription_tier, subscription_status)
     VALUES ($1, $2, $3, $4::subscription_tier, 'active')`,
    [id, name, args.ownerId, tier],
  );
  const dek = newDek();
  const masterKey = process.env.APP_MASTER_KEY;
  if (!masterKey) {
    throw new Error('APP_MASTER_KEY required for tests');
  }
  const wrapped = wrapDek(dek, masterKey);
  await pool.query(
    `INSERT INTO circle_keys (circle_id, encrypted_dek, key_version) VALUES ($1, $2, 1)`,
    [id, wrapped],
  );
  await pool.query(
    `INSERT INTO circle_members (circle_id, user_id, role, status, display_name, joined_at)
     VALUES ($1, $2, 'owner', 'active', 'Owner', NOW())`,
    [id, args.ownerId],
  );
  return { id, name, ownerId: args.ownerId, dek };
}

export async function addMember(
  pool: pg.Pool,
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
    displayName?: string;
  },
): Promise<string> {
  const id = randomUUID();
  await pool.query(
    `INSERT INTO circle_members (id, circle_id, user_id, role, status, display_name, joined_at)
     VALUES ($1, $2, $3, $4::member_role, 'active', $5, NOW())`,
    [id, args.circleId, args.userId, args.role, args.displayName ?? 'Member'],
  );
  return id;
}

export async function insertActivityRaw(
  pool: pg.Pool,
  args: {
    circleId: string;
    authorId: string;
    dek: Buffer;
    type?: string;
    headline?: string;
    content?: string;
  },
): Promise<string> {
  const id = randomUUID();
  await pool.query(
    `INSERT INTO activities (id, circle_id, author_user_id, activity_type, headline, content_enc)
     VALUES ($1, $2, $3, $4::activity_type, $5, $6)`,
    [
      id,
      args.circleId,
      args.authorId,
      args.type ?? 'text_note',
      args.headline ?? null,
      args.content ? encryptColumn(args.content, args.dek) : null,
    ],
  );
  return id;
}

export async function insertMedicationRaw(
  pool: pg.Pool,
  args: {
    circleId: string;
    dek: Buffer;
    name: string;
    dosage: string;
  },
): Promise<string> {
  const id = randomUUID();
  await pool.query(
    `INSERT INTO medications (id, circle_id, name_enc, dosage_enc, status, schedule)
     VALUES ($1, $2, $3, $4, 'active', '{}'::jsonb)`,
    [id, args.circleId, encryptColumn(args.name, args.dek), encryptColumn(args.dosage, args.dek)],
  );
  return id;
}

export async function countAuditLog(
  pool: pg.Pool,
  circleId: string,
): Promise<number> {
  const result = await pool.query<{ n: string }>(
    `SELECT COUNT(*)::TEXT AS n FROM audit_log WHERE circle_id = $1`,
    [circleId],
  );
  return Number(result.rows[0]?.n ?? '0');
}
