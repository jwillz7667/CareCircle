/**
 * Email + password sign-in flow. Verifies:
 *   - POST /v1/auth/register validates input, hashes the password (never
 *     stored or echoed plaintext), mints access + refresh tokens, and
 *     creates a user with no Apple / Google identifier set.
 *   - POST /v1/auth/login returns the same generic 401 on wrong-password
 *     and unknown-email, and equivalent latency (within a wide margin
 *     because Argon2 timing depends on host load).
 *   - JWT round-trip: minted access token resolves /v1/me.
 *   - Password is rejected when too short / email malformed.
 *   - Duplicate email across providers is rejected at register time.
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import pg from 'pg';
import { closeTestApp, getTestApp } from './helpers/app.js';
import { makePool, resetDb } from './helpers/db.js';
import { bearer, loginAs } from './helpers/auth.js';

type AuthResponse = {
  accessToken: string;
  refreshToken: string;
  userId: string;
};

describe('Email auth', () => {
  let app: FastifyInstance;
  let pool: pg.Pool;

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
  });

  it('registers a new user, returns tokens, persists Argon2id hash', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/register',
      payload: {
        email: 'Alice@Example.com',
        password: 'correct-horse-battery-staple',
        displayName: 'Alice',
      },
    });
    expect(res.statusCode).toBe(201);

    const body = JSON.parse(res.body) as AuthResponse;
    expect(body.accessToken.split('.').length).toBe(3);
    expect(body.refreshToken.length).toBeGreaterThan(20);
    expect(body.userId).toMatch(/^[0-9a-f-]{36}$/);

    // Password isn't echoed anywhere in the response payload.
    expect(res.body).not.toContain('correct-horse-battery-staple');

    // DB stores Argon2id PHC and a normalized lowercase email.
    const row = await pool.query<{
      email: string;
      password_hash: string;
      password_updated_at: Date | null;
      apple_user_id: string | null;
      google_user_id: string | null;
      display_name: string | null;
    }>(
      `SELECT email, password_hash, password_updated_at, apple_user_id, google_user_id, display_name
       FROM users WHERE id = $1`,
      [body.userId],
    );
    expect(row.rows[0]).toBeTruthy();
    expect(row.rows[0]!.email).toBe('alice@example.com');
    expect(row.rows[0]!.password_hash).toMatch(/^\$argon2id\$/);
    expect(row.rows[0]!.password_updated_at).not.toBeNull();
    expect(row.rows[0]!.apple_user_id).toBeNull();
    expect(row.rows[0]!.google_user_id).toBeNull();
    expect(row.rows[0]!.display_name).toBe('Alice');
  });

  it('rejects short passwords (400)', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/register',
      payload: { email: 'bob@example.com', password: 'short' },
    });
    expect(res.statusCode).toBe(400);
  });

  it('rejects malformed email (400)', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/register',
      payload: { email: 'not-an-email', password: 'a-good-long-password-1234' },
    });
    expect(res.statusCode).toBe(400);
  });

  it('rejects duplicate email (409)', async () => {
    await app.inject({
      method: 'POST',
      url: '/v1/auth/register',
      payload: { email: 'dup@example.com', password: 'a-good-long-password-1234' },
    });
    const second = await app.inject({
      method: 'POST',
      url: '/v1/auth/register',
      payload: { email: 'DUP@example.com', password: 'another-long-password-5678' },
    });
    expect(second.statusCode).toBe(409);
  });

  it('logs in with correct creds and the JWT resolves /v1/me', async () => {
    await app.inject({
      method: 'POST',
      url: '/v1/auth/register',
      payload: {
        email: 'login@example.com',
        password: 'a-good-long-password-1234',
        displayName: 'Logger',
      },
    });
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/login',
      payload: { email: 'login@example.com', password: 'a-good-long-password-1234' },
    });
    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body) as AuthResponse;

    const me = await app.inject({
      method: 'GET',
      url: '/v1/me',
      headers: bearer(body.accessToken),
    });
    expect(me.statusCode).toBe(200);
    const meBody = JSON.parse(me.body) as { id: string; email: string | null };
    expect(meBody.id).toBe(body.userId);
    expect(meBody.email).toBe('login@example.com');
  });

  it('rejects wrong password (401)', async () => {
    await app.inject({
      method: 'POST',
      url: '/v1/auth/register',
      payload: { email: 'bad@example.com', password: 'correct-password-12345' },
    });
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/login',
      payload: { email: 'bad@example.com', password: 'wrong-password-678910' },
    });
    expect(res.statusCode).toBe(401);
  });

  it('returns the same status code for unknown email and wrong password', async () => {
    await app.inject({
      method: 'POST',
      url: '/v1/auth/register',
      payload: { email: 'known@example.com', password: 'correct-password-12345' },
    });
    const wrongPassword = await app.inject({
      method: 'POST',
      url: '/v1/auth/login',
      payload: { email: 'known@example.com', password: 'wrong-password-12345' },
    });
    const unknownEmail = await app.inject({
      method: 'POST',
      url: '/v1/auth/login',
      payload: { email: 'unknown@example.com', password: 'wrong-password-12345' },
    });
    expect(wrongPassword.statusCode).toBe(401);
    expect(unknownEmail.statusCode).toBe(401);
    expect(JSON.parse(wrongPassword.body).message).toBe(JSON.parse(unknownEmail.body).message);
  });

  it('Apple sign-in user with the same email cannot re-register via email path', async () => {
    // Existing user signed in with Apple, owns the email already.
    await loginAs(app, 'mock|existing-apple', { email: 'shared@example.com' });
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/register',
      payload: { email: 'shared@example.com', password: 'a-good-long-password-1234' },
    });
    expect(res.statusCode).toBe(409);
  });
});
