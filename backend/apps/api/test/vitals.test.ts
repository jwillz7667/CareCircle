/**
 * Vitals: create + idempotency (clientOpId AND healthkit_uuid), list with
 * cursor, kind / source filtering, single-fetch, soft-delete by recorder
 * only, membership enforcement, encrypted-notes round trip.
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

describe('Vitals', () => {
  let app: FastifyInstance;
  let pool: pg.Pool;
  let owner: SeededUser;
  let member: SeededUser;
  let outsider: SeededUser;
  let circle: SeededCircle;
  let ownerToken: string;
  let memberToken: string;
  let outsiderToken: string;

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
    owner = await insertUser(pool, { appleId: 'mock|vitals-owner' });
    member = await insertUser(pool, { appleId: 'mock|vitals-member' });
    outsider = await insertUser(pool, { appleId: 'mock|vitals-outsider' });
    circle = await insertCircle(pool, { ownerId: owner.id, name: 'Vitals Circle' });
    await addMember(pool, { circleId: circle.id, userId: member.id, role: 'paid_aide' });
    ownerToken = (await loginAs(app, owner.appleId)).accessToken;
    memberToken = (await loginAs(app, member.appleId)).accessToken;
    outsiderToken = (await loginAs(app, outsider.appleId)).accessToken;
  });

  function makePayload(overrides: Partial<Record<string, unknown>> = {}) {
    return {
      kind: 'heart_rate',
      recordedAt: new Date().toISOString(),
      valueNumeric: 72,
      unit: 'bpm',
      source: 'manual',
      notes: 'Resting, after walking to the kitchen.',
      ...overrides,
    };
  }

  it('creates a manual vital and round-trips encrypted notes through read', async () => {
    const post = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/vitals`,
      headers: bearer(memberToken),
      payload: makePayload(),
    });
    expect(post.statusCode).toBe(201);
    const { id } = JSON.parse(post.body) as { id: string };

    const get = await app.inject({
      method: 'GET',
      url: `/v1/vitals/${id}`,
      headers: bearer(ownerToken),
    });
    expect(get.statusCode).toBe(200);
    const body = JSON.parse(get.body) as {
      kind: string;
      valueNumeric: number | null;
      valueText: string | null;
      unit: string;
      source: string;
      notes: string | null;
      recordedByUserId: string;
      circleId: string;
    };
    expect(body.kind).toBe('heart_rate');
    expect(body.valueNumeric).toBe(72);
    expect(body.valueText).toBeNull();
    expect(body.unit).toBe('bpm');
    expect(body.source).toBe('manual');
    expect(body.notes).toBe('Resting, after walking to the kitchen.');
    expect(body.recordedByUserId).toBe(member.id);
    expect(body.circleId).toBe(circle.id);
  });

  it('clientOpId makes vital creation idempotent', async () => {
    const opId = randomUUID();
    const first = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/vitals`,
      headers: bearer(memberToken),
      payload: makePayload({ clientOpId: opId }),
    });
    expect(first.statusCode).toBe(201);
    const firstId = JSON.parse(first.body).id as string;
    expect(JSON.parse(first.body).replayed).toBe(false);

    const second = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/vitals`,
      headers: bearer(memberToken),
      payload: makePayload({ clientOpId: opId, valueNumeric: 99 }),
    });
    expect(second.statusCode).toBe(201);
    const body = JSON.parse(second.body) as { id: string; replayed: boolean };
    expect(body.id).toBe(firstId);
    expect(body.replayed).toBe(true);
  });

  it('HealthKit UUID makes vital creation idempotent across clients', async () => {
    const hkUUID = randomUUID();
    const first = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/vitals`,
      headers: bearer(memberToken),
      payload: makePayload({
        source: 'healthkit',
        healthkitUUID: hkUUID,
        notes: undefined,
      }),
    });
    expect(first.statusCode).toBe(201);
    const firstId = JSON.parse(first.body).id as string;

    const second = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/vitals`,
      headers: bearer(memberToken),
      payload: makePayload({
        source: 'healthkit',
        healthkitUUID: hkUUID,
        valueNumeric: 84,
      }),
    });
    expect(second.statusCode).toBe(201);
    const body = JSON.parse(second.body) as { id: string; replayed: boolean };
    expect(body.id).toBe(firstId);
    expect(body.replayed).toBe(true);
  });

  it('GET listing returns DESC by recorded_at and cursors correctly', async () => {
    for (let i = 0; i < 4; i++) {
      const r = await app.inject({
        method: 'POST',
        url: `/v1/circles/${circle.id}/vitals`,
        headers: bearer(memberToken),
        payload: makePayload({
          recordedAt: new Date(Date.now() - (4 - i) * 60 * 60 * 1000).toISOString(),
          valueNumeric: 60 + i,
        }),
      });
      expect(r.statusCode).toBe(201);
    }

    const page1 = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}/vitals?limit=2`,
      headers: bearer(ownerToken),
    });
    const p1 = JSON.parse(page1.body) as {
      vitals: Array<{ valueNumeric: number | null }>;
      nextCursor: string | null;
    };
    expect(p1.vitals).toHaveLength(2);
    expect(p1.nextCursor).not.toBeNull();
    expect(p1.vitals[0]!.valueNumeric).toBe(63);
    expect(p1.vitals[1]!.valueNumeric).toBe(62);

    const page2 = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}/vitals?limit=2&cursor=${encodeURIComponent(p1.nextCursor!)}`,
      headers: bearer(ownerToken),
    });
    const p2 = JSON.parse(page2.body) as {
      vitals: Array<{ valueNumeric: number | null }>;
      nextCursor: string | null;
    };
    expect(p2.vitals).toHaveLength(2);
    expect(p2.vitals[0]!.valueNumeric).toBe(61);
    expect(p2.vitals[1]!.valueNumeric).toBe(60);
    expect(p2.nextCursor).toBeNull();
  });

  it('filters by kind and source', async () => {
    await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/vitals`,
      headers: bearer(memberToken),
      payload: makePayload({ kind: 'heart_rate', valueNumeric: 72 }),
    });
    await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/vitals`,
      headers: bearer(memberToken),
      payload: makePayload({
        kind: 'body_weight',
        valueNumeric: 170,
        unit: 'lb',
      }),
    });
    await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/vitals`,
      headers: bearer(memberToken),
      payload: makePayload({
        kind: 'heart_rate',
        valueNumeric: 80,
        source: 'healthkit',
        healthkitUUID: randomUUID(),
      }),
    });

    const byKind = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}/vitals?kind=heart_rate`,
      headers: bearer(ownerToken),
    });
    const bk = JSON.parse(byKind.body) as { vitals: Array<unknown> };
    expect(bk.vitals).toHaveLength(2);

    const bySource = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}/vitals?source=healthkit`,
      headers: bearer(ownerToken),
    });
    const bs = JSON.parse(bySource.body) as { vitals: Array<{ source: string }> };
    expect(bs.vitals).toHaveLength(1);
    expect(bs.vitals[0]!.source).toBe('healthkit');
  });

  it('outsider cannot list or fetch vitals', async () => {
    const post = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/vitals`,
      headers: bearer(memberToken),
      payload: makePayload(),
    });
    const id = JSON.parse(post.body).id as string;

    const list = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}/vitals`,
      headers: bearer(outsiderToken),
    });
    expect(list.statusCode).toBe(404);

    const single = await app.inject({
      method: 'GET',
      url: `/v1/vitals/${id}`,
      headers: bearer(outsiderToken),
    });
    expect(single.statusCode).toBe(404);
  });

  it('only the recorder can soft-delete a vital', async () => {
    const post = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/vitals`,
      headers: bearer(memberToken),
      payload: makePayload(),
    });
    const id = JSON.parse(post.body).id as string;

    const wrongUser = await app.inject({
      method: 'DELETE',
      url: `/v1/vitals/${id}`,
      headers: bearer(ownerToken),
    });
    expect(wrongUser.statusCode).toBe(403);

    const author = await app.inject({
      method: 'DELETE',
      url: `/v1/vitals/${id}`,
      headers: bearer(memberToken),
    });
    expect(author.statusCode).toBe(204);

    const after = await app.inject({
      method: 'GET',
      url: `/v1/vitals/${id}`,
      headers: bearer(memberToken),
    });
    expect(after.statusCode).toBe(404);
  });

  it('rejects payloads with no numeric or text value', async () => {
    const r = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/vitals`,
      headers: bearer(memberToken),
      payload: {
        kind: 'heart_rate',
        recordedAt: new Date().toISOString(),
        unit: 'bpm',
      },
    });
    expect(r.statusCode).toBeGreaterThanOrEqual(400);
    expect(r.statusCode).toBeLessThan(500);
  });

  it('rejects unauthenticated callers', async () => {
    const r = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}/vitals`,
    });
    expect(r.statusCode).toBe(401);
  });
});
