/**
 * Sync batch endpoint — accepts offline operations and dedups replays.
 * Projection into domain tables is exercised separately in
 * syncProjector.test.ts; here we only assert the queue/ack contract.
 */
import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import pg from 'pg';
import { closeTestApp, getTestApp } from './helpers/app.js';
import {
  makePool,
  resetDb,
  insertUser,
  insertCircle,
  type SeededCircle,
  type SeededUser,
} from './helpers/db.js';
import { bearer, loginAs } from './helpers/auth.js';

describe('Sync batch', () => {
  let app: FastifyInstance;
  let pool: pg.Pool;
  let user: SeededUser;
  let circle: SeededCircle;
  let token: string;

  beforeAll(async () => {
    app = await getTestApp();
    pool = makePool();
  });
  afterAll(async () => {
    await closeTestApp();
    await pool.end();
  });
  beforeEach(async () => {
    await resetDb(pool);
    user = await insertUser(pool, { appleId: 'mock|sync-user' });
    circle = await insertCircle(pool, { ownerId: user.id, name: 'Sync Circle' });
    token = (await loginAs(app, user.appleId)).accessToken;
  });

  function batchPayload(op1: string, op2: string) {
    return {
      operations: [
        {
          clientOpId: op1,
          operationType: 'mark_dose_taken',
          circleId: circle.id,
          payload: { medicationId: randomUUID(), takenAt: new Date().toISOString() },
        },
        {
          clientOpId: op2,
          operationType: 'create_activity',
          circleId: circle.id,
          payload: { type: 'text_note', content: 'queued' },
        },
      ],
    };
  }

  it('accepts new operations as pending and dedups replays', async () => {
    const op1 = randomUUID();
    const op2 = randomUUID();
    const res1 = await app.inject({
      method: 'POST',
      url: '/v1/sync/batch',
      headers: bearer(token),
      payload: batchPayload(op1, op2),
    });
    expect(res1.statusCode).toBe(200);
    const body1 = JSON.parse(res1.body) as { acks: Array<{ clientOpId: string; status: string }> };
    expect(body1.acks).toHaveLength(2);
    expect(body1.acks.every((a) => a.status === 'pending')).toBe(true);

    // Replay the same batch — still pending, and no duplicate rows persist.
    const res2 = await app.inject({
      method: 'POST',
      url: '/v1/sync/batch',
      headers: bearer(token),
      payload: batchPayload(op1, op2),
    });
    expect(res2.statusCode).toBe(200);
    const body2 = JSON.parse(res2.body) as { acks: Array<{ clientOpId: string; status: string }> };
    expect(body2.acks.every((a) => a.status === 'pending')).toBe(true);

    const count = await pool.query<{ count: string }>(
      `SELECT COUNT(*)::text AS count FROM pending_operations WHERE user_id = $1`,
      [user.id],
    );
    expect(count.rows[0]?.count).toBe('2');
  });

  it('reports applied and failed states via the status endpoint', async () => {
    const op = randomUUID();
    await app.inject({
      method: 'POST',
      url: '/v1/sync/batch',
      headers: bearer(token),
      payload: {
        operations: [
          {
            clientOpId: op,
            operationType: 'create_activity',
            circleId: circle.id,
            payload: { type: 'text_note', content: 'hi' },
          },
        ],
      },
    });

    // Simulate the projector marking this op applied.
    await pool.query(
      `UPDATE pending_operations SET processed_at = NOW(), result = '{}'::jsonb WHERE user_id = $1 AND client_op_id = $2`,
      [user.id, op],
    );

    const unknown = randomUUID();
    const res = await app.inject({
      method: 'POST',
      url: '/v1/sync/status',
      headers: bearer(token),
      payload: { clientOpIds: [op, unknown] },
    });
    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body) as {
      statuses: Array<{ clientOpId: string; status: string }>;
    };
    const byId = new Map(body.statuses.map((s) => [s.clientOpId, s.status]));
    expect(byId.get(op)).toBe('applied');
    expect(byId.get(unknown)).toBe('unknown');
  });
});
