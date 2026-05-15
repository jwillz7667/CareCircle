/**
 * Google sign-in flow. Verifies:
 *   - POST /v1/auth/google verifies a Google ID token and mints
 *     access + refresh tokens.
 *   - First-time sign-in creates a user with google_user_id set and
 *     apple_user_id / password_hash null.
 *   - Repeat sign-in is idempotent on the google sub.
 *   - Unverified Google emails are rejected (401).
 *   - Cross-provider email collisions are rejected (409).
 *   - Garbage / mismatched-audience tokens fail with 401.
 *   - Display name falls back to given/family name when `name` is absent.
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import pg from 'pg';
import { closeTestApp, getTestApp } from './helpers/app.js';
import { makePool, resetDb } from './helpers/db.js';
import { bearer, loginAs } from './helpers/auth.js';
import { signMockGoogleToken } from '../src/services/google.js';
import { loadConfig } from '../src/config.js';

type AuthResponse = {
  accessToken: string;
  refreshToken: string;
  userId: string;
};

describe('Google auth', () => {
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

  it('first-time sign-in mints tokens and persists google_user_id', async () => {
    const config = loadConfig();
    const idToken = await signMockGoogleToken(config, {
      sub: 'google|first-time',
      email: 'gfirst@example.com',
      name: 'G First',
      emailVerified: true,
    });
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/google',
      payload: { idToken },
    });
    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body) as AuthResponse;
    expect(body.accessToken.split('.').length).toBe(3);
    expect(body.refreshToken.length).toBeGreaterThan(20);

    const row = await pool.query<{
      apple_user_id: string | null;
      google_user_id: string | null;
      password_hash: string | null;
      email: string | null;
      display_name: string | null;
    }>(
      `SELECT apple_user_id, google_user_id, password_hash, email, display_name
       FROM users WHERE id = $1`,
      [body.userId],
    );
    expect(row.rows[0]).toBeTruthy();
    expect(row.rows[0]!.apple_user_id).toBeNull();
    expect(row.rows[0]!.google_user_id).toBe('google|first-time');
    expect(row.rows[0]!.password_hash).toBeNull();
    expect(row.rows[0]!.email).toBe('gfirst@example.com');
    expect(row.rows[0]!.display_name).toBe('G First');

    // The bearer should resolve /v1/me.
    const me = await app.inject({
      method: 'GET',
      url: '/v1/me',
      headers: bearer(body.accessToken),
    });
    expect(me.statusCode).toBe(200);
  });

  it('is idempotent on repeated sign-in with the same sub', async () => {
    const config = loadConfig();
    const tokenA = await signMockGoogleToken(config, {
      sub: 'google|repeat',
      email: 'grepeat@example.com',
    });
    const a = await app.inject({
      method: 'POST',
      url: '/v1/auth/google',
      payload: { idToken: tokenA },
    });
    expect(a.statusCode).toBe(200);
    const tokenB = await signMockGoogleToken(config, {
      sub: 'google|repeat',
      email: 'grepeat@example.com',
    });
    const b = await app.inject({
      method: 'POST',
      url: '/v1/auth/google',
      payload: { idToken: tokenB },
    });
    expect(b.statusCode).toBe(200);

    const ja = JSON.parse(a.body) as AuthResponse;
    const jb = JSON.parse(b.body) as AuthResponse;
    expect(ja.userId).toBe(jb.userId);
  });

  it('rejects unverified Google email (401)', async () => {
    const config = loadConfig();
    const idToken = await signMockGoogleToken(config, {
      sub: 'google|unverified',
      email: 'pending-verification@example.com',
      emailVerified: false,
    });
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/google',
      payload: { idToken },
    });
    expect(res.statusCode).toBe(401);
  });

  it('rejects collision with an existing email-auth account (409)', async () => {
    // Existing email/password user owns the email.
    await app.inject({
      method: 'POST',
      url: '/v1/auth/register',
      payload: {
        email: 'collide@example.com',
        password: 'a-good-long-password-1234',
      },
    });
    const config = loadConfig();
    const idToken = await signMockGoogleToken(config, {
      sub: 'google|collide',
      email: 'collide@example.com',
    });
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/google',
      payload: { idToken },
    });
    expect(res.statusCode).toBe(409);
  });

  it('rejects collision with an existing Apple-auth account (409)', async () => {
    await loginAs(app, 'mock|apple-owns-email', { email: 'shared-apple@example.com' });
    const config = loadConfig();
    const idToken = await signMockGoogleToken(config, {
      sub: 'google|trying-to-take-over',
      email: 'shared-apple@example.com',
    });
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/google',
      payload: { idToken },
    });
    expect(res.statusCode).toBe(409);
  });

  it('rejects garbage idToken', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/google',
      payload: { idToken: 'definitely.not.a-jwt' },
    });
    expect(res.statusCode).toBeGreaterThanOrEqual(400);
  });

  it('rejects a token with the wrong audience', async () => {
    const config = loadConfig();
    const idToken = await signMockGoogleToken(config, {
      sub: 'google|wrong-aud',
      email: 'wrongaud@example.com',
      audience: 'some-other-app.googleusercontent.com',
    });
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/google',
      payload: { idToken },
    });
    expect(res.statusCode).toBe(401);
  });

  it('falls back to given+family name when `name` is missing', async () => {
    const config = loadConfig();
    const idToken = await signMockGoogleToken(config, {
      sub: 'google|namefallback',
      email: 'namefallback@example.com',
      givenName: 'Grace',
      familyName: 'Hopper',
    });
    const res = await app.inject({
      method: 'POST',
      url: '/v1/auth/google',
      payload: { idToken },
    });
    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body) as AuthResponse;
    const row = await pool.query<{ display_name: string | null }>(
      `SELECT display_name FROM users WHERE id = $1`,
      [body.userId],
    );
    expect(row.rows[0]!.display_name).toBe('Grace Hopper');
  });

  it('keeps email + display name fresh on repeat sign-in', async () => {
    const config = loadConfig();
    // First sign-in: no display name.
    const first = await app.inject({
      method: 'POST',
      url: '/v1/auth/google',
      payload: {
        idToken: await signMockGoogleToken(config, {
          sub: 'google|refresh',
          email: 'refresh-me@example.com',
        }),
      },
    });
    expect(first.statusCode).toBe(200);
    const userId = (JSON.parse(first.body) as AuthResponse).userId;

    // Second sign-in: Google now returns a name.
    const second = await app.inject({
      method: 'POST',
      url: '/v1/auth/google',
      payload: {
        idToken: await signMockGoogleToken(config, {
          sub: 'google|refresh',
          email: 'refresh-me@example.com',
          name: 'Refreshed Name',
        }),
      },
    });
    expect(second.statusCode).toBe(200);

    const row = await pool.query<{ display_name: string | null }>(
      `SELECT display_name FROM users WHERE id = $1`,
      [userId],
    );
    expect(row.rows[0]!.display_name).toBe('Refreshed Name');
  });
});
