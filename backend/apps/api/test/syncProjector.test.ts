/**
 * Sync projector — drains pending_operations into domain tables.
 *
 * Exercises the worker's projector directly against the test database (no
 * Redis): seed a user, insert raw pending_operations for a never-provisioned
 * Circle, and prove the projector auto-provisions the Circle and lands each
 * op in its target table. A second pass with fresh client_op_ids but the same
 * entity ids proves idempotency — no duplicate domain rows.
 */
import './helpers/env.js';
import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import { randomUUID } from 'node:crypto';
import pg from 'pg';
import { createLogger, decryptColumn, unwrapDek } from '@carecircle/shared';
import { runSyncProjector } from '@carecircle/worker/projector';
import { loadConfig } from '@carecircle/worker/config';
import { makePool, resetDb, insertUser, type SeededUser } from './helpers/db.js';

type PendingSeed = {
  type: string;
  payload: Record<string, unknown>;
  offsetMs: number;
};

describe('Sync projector', () => {
  let pool: pg.Pool;
  let user: SeededUser;
  let circleId: string;
  const config = loadConfig();
  const logger = createLogger({ level: 'silent', name: 'cc-test' });

  // Stable entity ids reused across both projector passes so the second pass
  // collides on the primary key and must no-op.
  const medicationId = randomUUID();
  const activityId = randomUUID();
  const vitalId = randomUUID();
  const doseId = randomUUID();

  async function seedPending(seed: PendingSeed): Promise<void> {
    await pool.query(
      `INSERT INTO pending_operations
         (client_op_id, user_id, circle_id, operation_type, payload, received_at)
       VALUES ($1, $2, $3, $4, $5, NOW() + ($6 || ' milliseconds')::interval)`,
      [randomUUID(), user.id, circleId, seed.type, seed.payload, String(seed.offsetMs)],
    );
  }

  function domainOps(now: string): PendingSeed[] {
    return [
      {
        type: 'create_medication',
        offsetMs: 0,
        payload: {
          medicationId,
          name: 'Metformin',
          dosage: '500 mg',
          form: 'tablet',
          status: 'asNeeded',
          startDate: now,
        },
      },
      {
        type: 'create_activity',
        offsetMs: 100,
        payload: {
          activityId,
          type: 'visit',
          body: 'Home visit completed',
          createdAt: now,
          authorAppleUserID: user.appleId,
        },
      },
      {
        type: 'create_vital',
        offsetMs: 200,
        payload: {
          vitalId,
          kind: 'heart_rate',
          recordedAt: now,
          valueNumeric: 72,
          unit: 'bpm',
          source: 'manual',
          recordedByAppleUserID: user.appleId,
        },
      },
      {
        type: 'mark_dose_taken',
        offsetMs: 300,
        payload: {
          doseId,
          medicationId,
          takenAt: now,
          markedByAppleUserID: user.appleId,
        },
      },
    ];
  }

  beforeAll(() => {
    pool = makePool();
  });
  afterAll(async () => {
    await pool.end();
  });
  beforeEach(async () => {
    await resetDb(pool);
    user = await insertUser(pool, { appleId: 'mock|projector-user' });
    circleId = randomUUID();
  });

  it('auto-provisions the Circle and projects every op type', async () => {
    const now = new Date().toISOString();
    for (const seed of domainOps(now)) {
      await seedPending(seed);
    }

    const result = await runSyncProjector({ userId: user.id }, { pool, config, logger });
    expect(result).toEqual({ applied: 4, failed: 0, deferred: 0 });

    // Circle, DEK, and owner membership were materialised on first touch.
    const circle = await pool.query<{ owner_user_id: string }>(
      `SELECT owner_user_id FROM circles WHERE id = $1`,
      [circleId],
    );
    expect(circle.rows[0]?.owner_user_id).toBe(user.id);
    const keys = await pool.query(`SELECT 1 FROM circle_keys WHERE circle_id = $1`, [circleId]);
    expect(keys.rowCount).toBe(1);
    const owner = await pool.query<{ role: string }>(
      `SELECT role FROM circle_members WHERE circle_id = $1 AND user_id = $2`,
      [circleId, user.id],
    );
    expect(owner.rows[0]?.role).toBe('owner');

    // Medication: camelCase status normalised, PHI columns encrypted with the DEK.
    const med = await pool.query<{ status: string; name_enc: Buffer; dosage_enc: Buffer }>(
      `SELECT status, name_enc, dosage_enc FROM medications WHERE id = $1 AND circle_id = $2`,
      [medicationId, circleId],
    );
    expect(med.rows[0]?.status).toBe('as_needed');
    const dek = await unwrapCircleDek(pool, circleId, config.APP_MASTER_KEY);
    expect(decryptColumn(med.rows[0]!.name_enc, dek)).toBe('Metformin');
    expect(decryptColumn(med.rows[0]!.dosage_enc, dek)).toBe('500 mg');

    // Activity: iOS 'visit' collapses onto the appointment_logged bucket; author resolved.
    const act = await pool.query<{ activity_type: string; author_user_id: string }>(
      `SELECT activity_type, author_user_id FROM activities WHERE id = $1`,
      [activityId],
    );
    expect(act.rows[0]?.activity_type).toBe('appointment_logged');
    expect(act.rows[0]?.author_user_id).toBe(user.id);

    const vital = await pool.query<{ kind: string; value_numeric: string }>(
      `SELECT kind, value_numeric FROM vitals WHERE id = $1`,
      [vitalId],
    );
    expect(vital.rows[0]?.kind).toBe('heart_rate');
    expect(Number(vital.rows[0]?.value_numeric)).toBe(72);

    const dose = await pool.query<{ status: string; medication_id: string }>(
      `SELECT status, medication_id FROM dose_events WHERE id = $1`,
      [doseId],
    );
    expect(dose.rows[0]?.status).toBe('taken');
    expect(dose.rows[0]?.medication_id).toBe(medicationId);

    // Every op is marked processed with no error.
    const unprocessed = await pool.query<{ n: string }>(
      `SELECT COUNT(*)::text AS n FROM pending_operations
       WHERE user_id = $1 AND (processed_at IS NULL OR error IS NOT NULL)`,
      [user.id],
    );
    expect(unprocessed.rows[0]?.n).toBe('0');
  });

  it('is idempotent under replay with fresh client_op_ids', async () => {
    const now = new Date().toISOString();
    for (const seed of domainOps(now)) {
      await seedPending(seed);
    }
    await runSyncProjector({ userId: user.id }, { pool, config, logger });

    // Replay: same entity ids, new client_op_ids, later received_at.
    for (const seed of domainOps(now)) {
      await seedPending({ ...seed, offsetMs: seed.offsetMs + 1_000 });
    }
    const replay = await runSyncProjector({ userId: user.id }, { pool, config, logger });
    expect(replay.failed).toBe(0);
    expect(replay.deferred).toBe(0);
    expect(replay.applied).toBe(4);

    // No duplicate domain rows despite eight ops total.
    for (const [table, id] of [
      ['medications', medicationId],
      ['activities', activityId],
      ['vitals', vitalId],
      ['dose_events', doseId],
    ] as const) {
      const count = await pool.query<{ n: string }>(
        `SELECT COUNT(*)::text AS n FROM ${table} WHERE id = $1`,
        [id],
      );
      expect(count.rows[0]?.n).toBe('1');
    }
  });
});

async function unwrapCircleDek(
  pool: pg.Pool,
  circleId: string,
  masterKey: string,
): Promise<Buffer> {
  const res = await pool.query<{ encrypted_dek: Buffer }>(
    `SELECT encrypted_dek FROM circle_keys WHERE circle_id = $1`,
    [circleId],
  );
  const row = res.rows[0];
  if (!row) {
    throw new Error('circle_keys row missing');
  }
  return unwrapDek(row.encrypted_dek, masterKey);
}
