/**
 * Shifts: aide clock-in/out, owner schedules, lists.
 */
import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import pg from 'pg';
import { closeTestApp, getTestApp } from './helpers/app.js';
import {
  makePool,
  resetDb,
  insertUser,
  insertCircle,
  addMember,
  type SeededCircle,
  type SeededUser,
} from './helpers/db.js';
import { bearer, loginAs } from './helpers/auth.js';

describe('Care shifts', () => {
  let app: FastifyInstance;
  let pool: pg.Pool;
  let owner: SeededUser;
  let aide: SeededUser;
  let circle: SeededCircle;
  let ownerToken: string;
  let aideToken: string;

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
    owner = await insertUser(pool, { appleId: 'mock|shift-owner' });
    aide = await insertUser(pool, { appleId: 'mock|shift-aide', displayName: 'Aide' });
    circle = await insertCircle(pool, { ownerId: owner.id, name: 'Shift Circle' });
    await addMember(pool, { circleId: circle.id, userId: aide.id, role: 'paid_aide' });
    ownerToken = (await loginAs(app, owner.appleId)).accessToken;
    aideToken = (await loginAs(app, aide.appleId)).accessToken;
  });

  it('owner schedules a shift; aide can list and clock in/out', async () => {
    const startsAt = new Date(Date.now() + 60_000).toISOString();
    const endsAt = new Date(Date.now() + 4 * 3_600_000).toISOString();
    const create = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/shifts`,
      headers: bearer(ownerToken),
      payload: {
        aideUserId: aide.id,
        startsAt,
        endsAt,
        services: ['T1019', 'S5125'],
        notes: 'Light housekeeping + meal prep',
      },
    });
    expect(create.statusCode).toBe(201);
    const { id } = JSON.parse(create.body) as { id: string };

    const list = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}/shifts`,
      headers: bearer(aideToken),
    });
    expect(list.statusCode).toBe(200);
    const body = JSON.parse(list.body) as {
      shifts: Array<{ aideUserId: string; services: string[]; actualStart: string | null }>;
    };
    expect(body.shifts).toHaveLength(1);
    expect(body.shifts[0]!.aideUserId).toBe(aide.id);
    expect(body.shifts[0]!.services).toEqual(['T1019', 'S5125']);
    expect(body.shifts[0]!.actualStart).toBeNull();

    const clockIn = await app.inject({
      method: 'POST',
      url: `/v1/shifts/${id}/clock-in`,
      headers: bearer(aideToken),
    });
    expect(clockIn.statusCode).toBe(204);

    const clockOut = await app.inject({
      method: 'POST',
      url: `/v1/shifts/${id}/clock-out`,
      headers: bearer(aideToken),
    });
    expect(clockOut.statusCode).toBe(204);

    const list2 = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}/shifts`,
      headers: bearer(aideToken),
    });
    const after = JSON.parse(list2.body).shifts[0] as {
      actualStart: string | null;
      actualEnd: string | null;
    };
    expect(after.actualStart).not.toBeNull();
    expect(after.actualEnd).not.toBeNull();
  });

  it('clock-in is restricted to the assigned aide (other members get 404)', async () => {
    const startsAt = new Date(Date.now() + 60_000).toISOString();
    const endsAt = new Date(Date.now() + 4 * 3_600_000).toISOString();
    const create = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/shifts`,
      headers: bearer(ownerToken),
      payload: { aideUserId: aide.id, startsAt, endsAt },
    });
    const id = JSON.parse(create.body).id as string;

    // Owner cannot clock in for the aide.
    const ownerClockIn = await app.inject({
      method: 'POST',
      url: `/v1/shifts/${id}/clock-in`,
      headers: bearer(ownerToken),
    });
    expect(ownerClockIn.statusCode).toBe(404);
  });
});
