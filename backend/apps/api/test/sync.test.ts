/**
 * Sync batch endpoint — replays offline operations idempotently.
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

  it('queues new operations and dedups replays', async () => {
    const op1 = randomUUID();
    const op2 = randomUUID();
    const res1 = await app.inject({
      method: 'POST',
      url: '/v1/sync/batch',
      headers: bearer(token),
      payload: {
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
      },
    });
    expect(res1.statusCode).toBe(200);
    const body1 = JSON.parse(res1.body) as {
      acks: Array<{ clientOpId: string; status: 'queued' | 'duplicate' }>;
    };
    expect(body1.acks).toHaveLength(2);
    expect(body1.acks.every((a) => a.status === 'queued')).toBe(true);

    // Replay the same batch — every op should be marked duplicate.
    const res2 = await app.inject({
      method: 'POST',
      url: '/v1/sync/batch',
      headers: bearer(token),
      payload: {
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
      },
    });
    expect(res2.statusCode).toBe(200);
    const body2 = JSON.parse(res2.body) as {
      acks: Array<{ clientOpId: string; status: 'queued' | 'duplicate' }>;
    };
    expect(body2.acks.every((a) => a.status === 'duplicate')).toBe(true);
  });
});
