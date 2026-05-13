/**
 * Activities + reactions + comments. Covers create with idempotency, list with cursor,
 * round-trip encryption of `content` and `entities`, reactions, threaded comments.
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

describe('Activities', () => {
  let app: FastifyInstance;
  let pool: pg.Pool;
  let owner: SeededUser;
  let member: SeededUser;
  let circle: SeededCircle;
  let ownerToken: string;
  let memberToken: string;

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
    owner = await insertUser(pool, { appleId: 'mock|act-owner' });
    member = await insertUser(pool, { appleId: 'mock|act-member' });
    circle = await insertCircle(pool, { ownerId: owner.id, name: 'Activity Circle' });
    await addMember(pool, { circleId: circle.id, userId: member.id, role: 'family_member' });
    ownerToken = (await loginAs(app, owner.appleId)).accessToken;
    memberToken = (await loginAs(app, member.appleId)).accessToken;
  });

  it('round-trips encrypted text_note content through create + read', async () => {
    const post = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/activities`,
      headers: bearer(ownerToken),
      payload: {
        type: 'text_note',
        headline: 'Tuesday handoff',
        content: "Mom's BP was 132/84 this morning. Walked 12 minutes around the block.",
        entities: ['blood_pressure', '132/84', 'walked 12 min'],
      },
    });
    expect(post.statusCode).toBe(201);
    const { id } = JSON.parse(post.body) as { id: string };

    const get = await app.inject({
      method: 'GET',
      url: `/v1/activities/${id}`,
      headers: bearer(memberToken),
    });
    expect(get.statusCode).toBe(200);
    const body = JSON.parse(get.body) as {
      headline: string;
      content: string | null;
      entities: string[];
    };
    expect(body.headline).toBe('Tuesday handoff');
    expect(body.content).toMatch(/132\/84/);
    expect(body.entities).toContain('blood_pressure');
  });

  it('clientOpId makes activity creation idempotent', async () => {
    const opId = randomUUID();
    const first = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/activities`,
      headers: bearer(ownerToken),
      payload: { type: 'text_note', content: 'idempotent test', clientOpId: opId },
    });
    expect(first.statusCode).toBe(201);
    const firstId = JSON.parse(first.body).id as string;
    const replay = JSON.parse(first.body).replayed as boolean;
    expect(replay).toBe(false);

    const second = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/activities`,
      headers: bearer(ownerToken),
      payload: { type: 'text_note', content: 'different body', clientOpId: opId },
    });
    expect(second.statusCode).toBe(201);
    const secondBody = JSON.parse(second.body) as { id: string; replayed: boolean };
    expect(secondBody.id).toBe(firstId);
    expect(secondBody.replayed).toBe(true);
  });

  it('GET .../activities lists DESC by occurred_at and cursors correctly', async () => {
    // Seed 5 activities at staggered times via the API.
    const ids: string[] = [];
    for (let i = 0; i < 5; i++) {
      const r = await app.inject({
        method: 'POST',
        url: `/v1/circles/${circle.id}/activities`,
        headers: bearer(ownerToken),
        payload: {
          type: 'text_note',
          content: `note ${i}`,
          occurredAt: new Date(Date.now() - (5 - i) * 60_000).toISOString(),
        },
      });
      expect(r.statusCode).toBe(201);
      ids.push(JSON.parse(r.body).id);
    }

    const page1 = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}/activities?limit=3`,
      headers: bearer(memberToken),
    });
    const p1 = JSON.parse(page1.body) as {
      activities: Array<{ id: string; content: string }>;
      nextCursor: string | null;
    };
    expect(p1.activities).toHaveLength(3);
    expect(p1.nextCursor).not.toBeNull();
    // DESC order — note 4 → 3 → 2
    expect(p1.activities[0]!.content).toBe('note 4');
    expect(p1.activities[2]!.content).toBe('note 2');

    const page2 = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}/activities?limit=3&cursor=${encodeURIComponent(p1.nextCursor!)}`,
      headers: bearer(memberToken),
    });
    const p2 = JSON.parse(page2.body) as {
      activities: Array<{ content: string }>;
      nextCursor: string | null;
    };
    expect(p2.activities).toHaveLength(2);
    expect(p2.activities[0]!.content).toBe('note 1');
    expect(p2.activities[1]!.content).toBe('note 0');
    expect(p2.nextCursor).toBeNull();
  });

  it('reactions: POST adds, conflicting POST is a no-op, DELETE removes', async () => {
    const r = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/activities`,
      headers: bearer(ownerToken),
      payload: { type: 'text_note', content: 'react to me' },
    });
    const id = JSON.parse(r.body).id as string;

    const add = await app.inject({
      method: 'POST',
      url: `/v1/activities/${id}/reactions`,
      headers: bearer(memberToken),
      payload: { emoji: '❤️' },
    });
    expect(add.statusCode).toBe(201);

    // Same emoji again: should not 500. DB has a unique (activity, user, emoji).
    const addAgain = await app.inject({
      method: 'POST',
      url: `/v1/activities/${id}/reactions`,
      headers: bearer(memberToken),
      payload: { emoji: '❤️' },
    });
    expect(addAgain.statusCode).toBe(201);

    const del = await app.inject({
      method: 'DELETE',
      url: `/v1/activities/${id}/reactions/${encodeURIComponent('❤️')}`,
      headers: bearer(memberToken),
    });
    expect(del.statusCode).toBe(204);
  });

  it('comments: create + list, ordered ASC by created_at', async () => {
    const r = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/activities`,
      headers: bearer(ownerToken),
      payload: { type: 'text_note', content: 'discuss' },
    });
    const id = JSON.parse(r.body).id as string;

    await app.inject({
      method: 'POST',
      url: `/v1/activities/${id}/comments`,
      headers: bearer(memberToken),
      payload: { content: 'First comment' },
    });
    await app.inject({
      method: 'POST',
      url: `/v1/activities/${id}/comments`,
      headers: bearer(ownerToken),
      payload: { content: 'Owner reply' },
    });

    const list = await app.inject({
      method: 'GET',
      url: `/v1/activities/${id}/comments`,
      headers: bearer(memberToken),
    });
    expect(list.statusCode).toBe(200);
    const body = JSON.parse(list.body) as {
      comments: Array<{ content: string; authorUserId: string }>;
    };
    expect(body.comments).toHaveLength(2);
    expect(body.comments[0]!.content).toBe('First comment');
    expect(body.comments[0]!.authorUserId).toBe(member.id);
    expect(body.comments[1]!.content).toBe('Owner reply');
  });

  it('only the author can soft-delete an activity', async () => {
    const r = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/activities`,
      headers: bearer(ownerToken),
      payload: { type: 'text_note', content: 'mine' },
    });
    const id = JSON.parse(r.body).id as string;

    const wrongUser = await app.inject({
      method: 'DELETE',
      url: `/v1/activities/${id}`,
      headers: bearer(memberToken),
    });
    expect(wrongUser.statusCode).toBe(403);

    const author = await app.inject({
      method: 'DELETE',
      url: `/v1/activities/${id}`,
      headers: bearer(ownerToken),
    });
    expect(author.statusCode).toBe(204);

    const after = await app.inject({
      method: 'GET',
      url: `/v1/activities/${id}`,
      headers: bearer(ownerToken),
    });
    expect(after.statusCode).toBe(404);
  });
});
