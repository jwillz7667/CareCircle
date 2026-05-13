/**
 * Invitations: owner creates → invitee accepts (by code and by link) → reuse rejected.
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
  type SeededCircle,
  type SeededUser,
} from './helpers/db.js';
import { bearer, loginAs } from './helpers/auth.js';

describe('Invitations', () => {
  let app: FastifyInstance;
  let pool: pg.Pool;
  let owner: SeededUser;
  let invitee: SeededUser;
  let circle: SeededCircle;
  let ownerToken: string;
  let inviteeToken: string;

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
    owner = await insertUser(pool, { appleId: 'mock|inv-owner' });
    invitee = await insertUser(pool, { appleId: 'mock|inv-guest', displayName: 'Guest' });
    circle = await insertCircle(pool, { ownerId: owner.id, name: 'Invite Circle' });
    ownerToken = (await loginAs(app, owner.appleId)).accessToken;
    inviteeToken = (await loginAs(app, invitee.appleId)).accessToken;
  });

  it('owner creates a code; invitee accepts and becomes member', async () => {
    const create = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/invitations`,
      headers: bearer(ownerToken),
      payload: { role: 'family_member' },
    });
    expect(create.statusCode).toBe(201);
    const inv = JSON.parse(create.body) as { code: string; inviteLinkId: string };

    const accept = await app.inject({
      method: 'POST',
      url: `/v1/invitations/${inv.code}/accept`,
      headers: bearer(inviteeToken),
      payload: { displayName: 'Cousin Sam' },
    });
    expect(accept.statusCode).toBe(200);
    const body = JSON.parse(accept.body) as { circleId: string; role: string };
    expect(body.circleId).toBe(circle.id);
    expect(body.role).toBe('family_member');

    // The invitee can now read the circle.
    const get = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}`,
      headers: bearer(inviteeToken),
    });
    expect(get.statusCode).toBe(200);

    // Second accept on the same code → 409.
    const reuse = await app.inject({
      method: 'POST',
      url: `/v1/invitations/${inv.code}/accept`,
      headers: bearer(inviteeToken),
      payload: {},
    });
    expect(reuse.statusCode).toBe(409);
  });

  it('link-based accept works for the alternate path', async () => {
    const create = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/invitations`,
      headers: bearer(ownerToken),
      payload: { role: 'family_member' },
    });
    const inv = JSON.parse(create.body) as { inviteLinkId: string };

    const accept = await app.inject({
      method: 'POST',
      url: `/v1/invitations/link/${inv.inviteLinkId}/accept`,
      headers: bearer(inviteeToken),
      payload: {},
    });
    expect(accept.statusCode).toBe(200);
  });

  it('rejects an expired invitation', async () => {
    const create = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/invitations`,
      headers: bearer(ownerToken),
      payload: { role: 'family_member' },
    });
    const inv = JSON.parse(create.body) as { code: string };

    // Manually expire it via direct DB.
    await pool.query(
      `UPDATE circle_invitations SET expires_at = NOW() - INTERVAL '1 day' WHERE code = $1`,
      [inv.code],
    );

    const accept = await app.inject({
      method: 'POST',
      url: `/v1/invitations/${inv.code}/accept`,
      headers: bearer(inviteeToken),
      payload: {},
    });
    expect(accept.statusCode).toBe(409);
  });

  it('non-owner cannot create invitations (403)', async () => {
    // Make invitee a family_member (not owner)
    await pool.query(
      `INSERT INTO circle_members (circle_id, user_id, role, status, display_name, joined_at)
       VALUES ($1, $2, 'family_member', 'active', 'Guest', NOW())`,
      [circle.id, invitee.id],
    );

    const res = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/invitations`,
      headers: bearer(inviteeToken),
      payload: { role: 'view_only' },
    });
    expect(res.statusCode).toBe(403);
  });
});
