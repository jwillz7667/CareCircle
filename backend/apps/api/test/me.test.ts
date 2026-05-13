/**
 * /v1/me + /v1/me/devices: profile read/update + APNs token register/unregister.
 */
import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import pg from 'pg';
import { closeTestApp, getTestApp } from './helpers/app.js';
import { makePool, resetDb, insertUser } from './helpers/db.js';
import { bearer, loginAs } from './helpers/auth.js';

describe('Me routes', () => {
  let app: FastifyInstance;
  let pool: pg.Pool;
  let access: string;

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
    await insertUser(pool, { appleId: 'mock|me', email: 'me@test.example', displayName: 'Me' });
    const login = await loginAs(app, 'mock|me', { email: 'me@test.example' });
    access = login.accessToken;
  });

  it('GET /v1/me returns the authenticated user', async () => {
    const res = await app.inject({ method: 'GET', url: '/v1/me', headers: bearer(access) });
    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body) as { email: string; displayName: string };
    expect(body.email).toBe('me@test.example');
    expect(body.displayName).toBe('Me');
  });

  it('PATCH /v1/me updates displayName', async () => {
    const res = await app.inject({
      method: 'PATCH',
      url: '/v1/me',
      headers: bearer(access),
      payload: { displayName: 'Renamed' },
    });
    expect(res.statusCode).toBe(204);
    const after = await app.inject({ method: 'GET', url: '/v1/me', headers: bearer(access) });
    expect(JSON.parse(after.body).displayName).toBe('Renamed');
  });

  it('POST /v1/me/devices registers an APNs token (and is idempotent)', async () => {
    const apnsToken = 'a'.repeat(64);
    const r1 = await app.inject({
      method: 'POST',
      url: '/v1/me/devices',
      headers: bearer(access),
      payload: { apnsToken, deviceName: "Justin's iPhone" },
    });
    expect(r1.statusCode).toBe(201);
    const id1 = JSON.parse(r1.body).id as string;

    const r2 = await app.inject({
      method: 'POST',
      url: '/v1/me/devices',
      headers: bearer(access),
      payload: { apnsToken, deviceName: 'Renamed iPhone' },
    });
    expect(r2.statusCode).toBe(201);
    // ON CONFLICT upserts the same row — same id.
    expect(JSON.parse(r2.body).id).toBe(id1);
  });

  it('DELETE /v1/me/devices/:id unregisters the device', async () => {
    const apnsToken = 'b'.repeat(64);
    const reg = await app.inject({
      method: 'POST',
      url: '/v1/me/devices',
      headers: bearer(access),
      payload: { apnsToken },
    });
    const id = JSON.parse(reg.body).id as string;
    const del = await app.inject({
      method: 'DELETE',
      url: `/v1/me/devices/${id}`,
      headers: bearer(access),
    });
    expect(del.statusCode).toBe(204);
  });

  it('DELETE /v1/me soft-deletes the account and revokes tokens', async () => {
    const del = await app.inject({ method: 'DELETE', url: '/v1/me', headers: bearer(access) });
    expect(del.statusCode).toBe(204);
    // Soft-deleted user can no longer hit /v1/me (RLS filters deleted_at IS NULL).
    const after = await app.inject({ method: 'GET', url: '/v1/me', headers: bearer(access) });
    expect(after.statusCode).toBe(404);
  });
});
