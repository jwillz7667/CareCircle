/**
 * SOS: trigger fans out push to other members, cancel marks canceled_at,
 * GET lists events DESC.
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
  addMember,
  type SeededCircle,
  type SeededUser,
} from './helpers/db.js';
import { bearer, loginAs } from './helpers/auth.js';

describe('SOS', () => {
  let app: FastifyInstance;
  let pool: pg.Pool;
  let owner: SeededUser;
  let other: SeededUser;
  let circle: SeededCircle;
  let ownerToken: string;

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
    owner = await insertUser(pool, { appleId: 'mock|sos-owner' });
    other = await insertUser(pool, { appleId: 'mock|sos-other' });
    circle = await insertCircle(pool, { ownerId: owner.id, name: 'SOS Circle' });
    await addMember(pool, { circleId: circle.id, userId: other.id, role: 'family_member' });
    ownerToken = (await loginAs(app, owner.appleId)).accessToken;
  });

  it('trigger records an event with notified_user_ids set to other members', async () => {
    const res = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/sos`,
      headers: bearer(ownerToken),
      payload: { locationLat: 44.95, locationLng: -93.09, locationAccuracyM: 12 },
    });
    expect(res.statusCode).toBe(201);
    const body = JSON.parse(res.body) as { id: string; notified: string[] };
    expect(body.notified).toEqual([other.id]);

    const raw = await pool.query<{ location_lat: string; notified_user_ids: string[] }>(
      `SELECT location_lat::TEXT, notified_user_ids FROM sos_events WHERE id = $1`,
      [body.id],
    );
    expect(Number(raw.rows[0]!.location_lat)).toBeCloseTo(44.95, 2);
    expect(raw.rows[0]!.notified_user_ids).toContain(other.id);
  });

  it('cancel marks canceled_at on the event', async () => {
    const trigger = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/sos`,
      headers: bearer(ownerToken),
      payload: {},
    });
    const sosId = JSON.parse(trigger.body).id as string;

    const cancel = await app.inject({
      method: 'POST',
      url: `/v1/sos/${sosId}/cancel`,
      headers: bearer(ownerToken),
    });
    expect(cancel.statusCode).toBe(204);

    const list = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}/sos`,
      headers: bearer(ownerToken),
    });
    const body = JSON.parse(list.body) as {
      events: Array<{ id: string; canceledAt: string | null }>;
    };
    expect(body.events).toHaveLength(1);
    expect(body.events[0]!.id).toBe(sosId);
    expect(body.events[0]!.canceledAt).not.toBeNull();
  });

  it('retriggering with the same eventId is idempotent', async () => {
    const eventId = randomUUID();
    const first = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/sos`,
      headers: bearer(ownerToken),
      payload: { eventId, locationLat: 44.95, locationLng: -93.09 },
    });
    expect(first.statusCode).toBe(201);
    expect(JSON.parse(first.body).id).toBe(eventId);

    // Replay (e.g. a network retry): the row already exists, so the route
    // no-ops the insert, returns 200, and skips re-paging the Circle.
    const replay = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/sos`,
      headers: bearer(ownerToken),
      payload: { eventId, locationLat: 44.95, locationLng: -93.09 },
    });
    expect(replay.statusCode).toBe(200);
    expect(JSON.parse(replay.body).id).toBe(eventId);

    const count = await pool.query<{ n: string }>(
      `SELECT COUNT(*)::text AS n FROM sos_events WHERE id = $1`,
      [eventId],
    );
    expect(count.rows[0]!.n).toBe('1');
  });

  it('triggering with no other members leaves notified empty (and skips queue)', async () => {
    // New solo circle: just the owner.
    const solo = await insertCircle(pool, { ownerId: owner.id, name: 'Solo' });
    const res = await app.inject({
      method: 'POST',
      url: `/v1/circles/${solo.id}/sos`,
      headers: bearer(ownerToken),
      payload: {},
    });
    expect(res.statusCode).toBe(201);
    expect(JSON.parse(res.body).notified).toEqual([]);
  });
});
