/**
 * End-of-shift digests. Covers create with idempotency, list with cursor,
 * round-trip encryption of transcript / summary / entities / artifacts,
 * single-fetch, soft-delete by narrator only, and membership enforcement.
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

describe('Shift digests', () => {
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
    owner = await insertUser(pool, { appleId: 'mock|digest-owner' });
    member = await insertUser(pool, { appleId: 'mock|digest-member' });
    outsider = await insertUser(pool, { appleId: 'mock|digest-outsider' });
    circle = await insertCircle(pool, { ownerId: owner.id, name: 'Digest Circle' });
    await addMember(pool, { circleId: circle.id, userId: member.id, role: 'paid_aide' });
    ownerToken = (await loginAs(app, owner.appleId)).accessToken;
    memberToken = (await loginAs(app, member.appleId)).accessToken;
    outsiderToken = (await loginAs(app, outsider.appleId)).accessToken;
  });

  function makePayload(overrides: Partial<Record<string, unknown>> = {}) {
    return {
      shiftStartAt: new Date(Date.now() - 8 * 60 * 60 * 1000).toISOString(),
      shiftEndAt: new Date().toISOString(),
      transcript: "Mom had a calm afternoon. Took 2pm and 6pm meds. BP 128/82 at 4pm. Walked to the mailbox.",
      summary: "Calm shift, all doses on time, BP stable.",
      audioDurationSeconds: 23.5,
      entities: {
        medications: [
          {
            id: randomUUID(),
            name: 'lisinopril',
            details: '10mg, 2pm',
            confidence: 'high',
          },
        ],
        vitals: [],
        appointments: [],
        meals: [],
        symptoms: [],
        generalNotes: [],
        summary: null,
      },
      artifacts: {
        doses: [
          {
            id: randomUUID(),
            medicationName: 'lisinopril',
            dosage: '10mg',
            scheduledAt: new Date(Date.now() - 6 * 60 * 60 * 1000).toISOString(),
            takenAt: new Date(Date.now() - 6 * 60 * 60 * 1000).toISOString(),
            status: 'taken',
          },
        ],
        appointments: [],
        vitals: [],
        journal: [],
      },
      ...overrides,
    };
  }

  it('round-trips encrypted transcript, summary, entities, artifacts through create + read', async () => {
    const payload = makePayload();
    const post = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/digests`,
      headers: bearer(memberToken),
      payload,
    });
    expect(post.statusCode).toBe(201);
    const { id } = JSON.parse(post.body) as { id: string };

    const get = await app.inject({
      method: 'GET',
      url: `/v1/digests/${id}`,
      headers: bearer(ownerToken),
    });
    expect(get.statusCode).toBe(200);
    const body = JSON.parse(get.body) as {
      transcript: string | null;
      summary: string | null;
      entities: { medications: Array<{ name: string }> } | null;
      artifacts: { doses: Array<{ medicationName: string; status: string }> } | null;
      audioDurationSeconds: number;
      narratorUserId: string;
      circleId: string;
    };
    expect(body.transcript).toMatch(/BP 128\/82/);
    expect(body.summary).toBe('Calm shift, all doses on time, BP stable.');
    expect(body.entities?.medications?.[0]?.name).toBe('lisinopril');
    expect(body.artifacts?.doses?.[0]?.medicationName).toBe('lisinopril');
    expect(body.artifacts?.doses?.[0]?.status).toBe('taken');
    expect(body.audioDurationSeconds).toBeCloseTo(23.5);
    expect(body.narratorUserId).toBe(member.id);
    expect(body.circleId).toBe(circle.id);
  });

  it('clientOpId makes digest creation idempotent', async () => {
    const opId = randomUUID();
    const first = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/digests`,
      headers: bearer(memberToken),
      payload: makePayload({ clientOpId: opId, summary: 'first attempt' }),
    });
    expect(first.statusCode).toBe(201);
    const firstId = JSON.parse(first.body).id as string;
    expect(JSON.parse(first.body).replayed).toBe(false);

    const second = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/digests`,
      headers: bearer(memberToken),
      payload: makePayload({ clientOpId: opId, summary: 'different summary' }),
    });
    expect(second.statusCode).toBe(201);
    const body = JSON.parse(second.body) as { id: string; replayed: boolean };
    expect(body.id).toBe(firstId);
    expect(body.replayed).toBe(true);
  });

  it('GET listing returns DESC by shift_end_at and cursors correctly', async () => {
    for (let i = 0; i < 4; i++) {
      const offset = (4 - i) * 60 * 60 * 1000;
      const r = await app.inject({
        method: 'POST',
        url: `/v1/circles/${circle.id}/digests`,
        headers: bearer(memberToken),
        payload: makePayload({
          shiftStartAt: new Date(Date.now() - offset - 8 * 60 * 60 * 1000).toISOString(),
          shiftEndAt: new Date(Date.now() - offset).toISOString(),
          summary: `digest ${i}`,
        }),
      });
      expect(r.statusCode).toBe(201);
    }

    const page1 = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}/digests?limit=2`,
      headers: bearer(ownerToken),
    });
    const p1 = JSON.parse(page1.body) as {
      digests: Array<{ summary: string | null }>;
      nextCursor: string | null;
    };
    expect(p1.digests).toHaveLength(2);
    expect(p1.nextCursor).not.toBeNull();
    expect(p1.digests[0]!.summary).toBe('digest 3');
    expect(p1.digests[1]!.summary).toBe('digest 2');

    const page2 = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}/digests?limit=2&cursor=${encodeURIComponent(p1.nextCursor!)}`,
      headers: bearer(ownerToken),
    });
    const p2 = JSON.parse(page2.body) as {
      digests: Array<{ summary: string | null }>;
      nextCursor: string | null;
    };
    expect(p2.digests).toHaveLength(2);
    expect(p2.digests[0]!.summary).toBe('digest 1');
    expect(p2.digests[1]!.summary).toBe('digest 0');
    expect(p2.nextCursor).toBeNull();
  });

  it('outsider cannot list or fetch digests', async () => {
    const post = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/digests`,
      headers: bearer(memberToken),
      payload: makePayload(),
    });
    const id = JSON.parse(post.body).id as string;

    const list = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}/digests`,
      headers: bearer(outsiderToken),
    });
    expect(list.statusCode).toBe(404);

    const single = await app.inject({
      method: 'GET',
      url: `/v1/digests/${id}`,
      headers: bearer(outsiderToken),
    });
    expect(single.statusCode).toBe(404);
  });

  it('only the narrator can soft-delete a digest', async () => {
    const post = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/digests`,
      headers: bearer(memberToken),
      payload: makePayload(),
    });
    const id = JSON.parse(post.body).id as string;

    const wrongUser = await app.inject({
      method: 'DELETE',
      url: `/v1/digests/${id}`,
      headers: bearer(ownerToken),
    });
    expect(wrongUser.statusCode).toBe(403);

    const author = await app.inject({
      method: 'DELETE',
      url: `/v1/digests/${id}`,
      headers: bearer(memberToken),
    });
    expect(author.statusCode).toBe(204);

    const after = await app.inject({
      method: 'GET',
      url: `/v1/digests/${id}`,
      headers: bearer(memberToken),
    });
    expect(after.statusCode).toBe(404);
  });

  it('rejects payload where shift_end_at < shift_start_at via CHECK constraint', async () => {
    const reverse = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/digests`,
      headers: bearer(memberToken),
      payload: makePayload({
        shiftStartAt: new Date().toISOString(),
        shiftEndAt: new Date(Date.now() - 60_000).toISOString(),
      }),
    });
    expect(reverse.statusCode).toBeGreaterThanOrEqual(400);
  });

  it('rejects unauthenticated callers', async () => {
    const r = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}/digests`,
    });
    expect(r.statusCode).toBe(401);
  });
});
