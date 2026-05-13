/**
 * Circle CRUD: create, list, get, update, soft-delete. Owner-only on mutations.
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
  type SeededUser,
} from './helpers/db.js';
import { bearer, loginAs } from './helpers/auth.js';

describe('Circles', () => {
  let app: FastifyInstance;
  let pool: pg.Pool;
  let owner: SeededUser;
  let member: SeededUser;
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
    owner = await insertUser(pool, { appleId: 'mock|owner' });
    member = await insertUser(pool, { appleId: 'mock|member' });
    ownerToken = (await loginAs(app, owner.appleId)).accessToken;
    memberToken = (await loginAs(app, member.appleId)).accessToken;
  });

  it('POST /v1/circles creates a circle with the caller as owner', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/v1/circles',
      headers: bearer(ownerToken),
      payload: { name: 'My Care Group' },
    });
    expect(res.statusCode).toBe(201);
    const body = JSON.parse(res.body) as { id: string; name: string };
    expect(body.name).toBe('My Care Group');

    // The owner can immediately read it.
    const get = await app.inject({
      method: 'GET',
      url: `/v1/circles/${body.id}`,
      headers: bearer(ownerToken),
    });
    expect(get.statusCode).toBe(200);
    const got = JSON.parse(get.body) as { ownerUserId: string };
    expect(got.ownerUserId).toBe(owner.id);

    // circle_keys row was created (server-side envelope encryption seed).
    const keys = await pool.query<{ key_version: number }>(
      `SELECT key_version FROM circle_keys WHERE circle_id = $1`,
      [body.id],
    );
    expect(keys.rows[0]?.key_version).toBe(1);
  });

  it('GET /v1/circles returns only circles the caller is in', async () => {
    const circle = await insertCircle(pool, { ownerId: owner.id, name: 'Owned' });
    const otherOwner = await insertUser(pool, { appleId: 'mock|other' });
    await insertCircle(pool, { ownerId: otherOwner.id, name: 'Other' });

    const res = await app.inject({
      method: 'GET',
      url: '/v1/circles',
      headers: bearer(ownerToken),
    });
    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body) as { circles: Array<{ id: string; name: string }> };
    expect(body.circles).toHaveLength(1);
    expect(body.circles[0]!.id).toBe(circle.id);
    expect(body.circles[0]!.name).toBe('Owned');
  });

  it('PATCH /v1/circles/:id allows owner, blocks non-owner', async () => {
    const circle = await insertCircle(pool, { ownerId: owner.id, name: 'Original' });
    await addMember(pool, {
      circleId: circle.id,
      userId: member.id,
      role: 'family_member',
    });

    const ok = await app.inject({
      method: 'PATCH',
      url: `/v1/circles/${circle.id}`,
      headers: bearer(ownerToken),
      payload: { name: 'Renamed' },
    });
    expect(ok.statusCode).toBe(204);

    const denied = await app.inject({
      method: 'PATCH',
      url: `/v1/circles/${circle.id}`,
      headers: bearer(memberToken),
      payload: { name: 'Hijack' },
    });
    expect(denied.statusCode).toBe(403);
  });

  it('DELETE /v1/circles/:id allows owner only', async () => {
    const circle = await insertCircle(pool, { ownerId: owner.id });
    await addMember(pool, {
      circleId: circle.id,
      userId: member.id,
      role: 'family_member',
    });

    const denied = await app.inject({
      method: 'DELETE',
      url: `/v1/circles/${circle.id}`,
      headers: bearer(memberToken),
    });
    expect(denied.statusCode).toBe(403);

    const ok = await app.inject({
      method: 'DELETE',
      url: `/v1/circles/${circle.id}`,
      headers: bearer(ownerToken),
    });
    expect(ok.statusCode).toBe(204);

    // Soft-deleted circles disappear from list and from GET-by-id.
    const list = await app.inject({
      method: 'GET',
      url: '/v1/circles',
      headers: bearer(ownerToken),
    });
    expect(JSON.parse(list.body).circles).toEqual([]);

    const get = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}`,
      headers: bearer(ownerToken),
    });
    expect(get.statusCode).toBe(404);
  });
});
