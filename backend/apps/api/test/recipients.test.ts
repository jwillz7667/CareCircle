/**
 * Care recipient: PUT/GET. Owner sets recipient profile (encrypted PHI fields).
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

describe('Care recipients', () => {
  let app: FastifyInstance;
  let pool: pg.Pool;
  let owner: SeededUser;
  let circle: SeededCircle;
  let token: string;

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
    owner = await insertUser(pool, { appleId: 'mock|rec-owner' });
    circle = await insertCircle(pool, { ownerId: owner.id, name: 'Recipient Circle' });
    token = (await loginAs(app, owner.appleId)).accessToken;
  });

  it('PUT creates a recipient; GET reads it back decrypted', async () => {
    const put = await app.inject({
      method: 'PUT',
      url: `/v1/circles/${circle.id}/recipient`,
      headers: bearer(token),
      payload: {
        firstName: 'Eleanor',
        lastName: 'Hartwell',
        dateOfBirth: '1944-03-12',
        pronouns: 'she/her',
        primaryConditions: ['Parkinson disease', 'hypertension'],
      },
    });
    expect(put.statusCode).toBe(200);

    const get = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}/recipient`,
      headers: bearer(token),
    });
    expect(get.statusCode).toBe(200);
    const body = JSON.parse(get.body) as {
      firstName: string;
      lastName: string | null;
      dateOfBirth: string | null;
      pronouns: string | null;
      primaryConditions: string[];
    };
    expect(body.firstName).toBe('Eleanor');
    expect(body.lastName).toBe('Hartwell');
    expect(body.dateOfBirth).toBe('1944-03-12');
    expect(body.pronouns).toBe('she/her');
    expect(body.primaryConditions).toEqual(['Parkinson disease', 'hypertension']);

    // Raw row has ciphertext, not plaintext.
    const raw = await pool.query<{ first_name_enc: Buffer }>(
      `SELECT first_name_enc FROM care_recipients WHERE circle_id = $1`,
      [circle.id],
    );
    expect(raw.rows[0]!.first_name_enc.toString('utf8')).not.toContain('Eleanor');
  });

  it('PUT a second time updates the same recipient (no duplicates)', async () => {
    await app.inject({
      method: 'PUT',
      url: `/v1/circles/${circle.id}/recipient`,
      headers: bearer(token),
      payload: { firstName: 'Eleanor' },
    });
    await app.inject({
      method: 'PUT',
      url: `/v1/circles/${circle.id}/recipient`,
      headers: bearer(token),
      payload: { firstName: 'Ellie' },
    });

    const count = await pool.query<{ n: string }>(
      `SELECT COUNT(*)::TEXT AS n FROM care_recipients WHERE circle_id = $1 AND deleted_at IS NULL`,
      [circle.id],
    );
    expect(Number(count.rows[0]!.n)).toBe(1);

    const get = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}/recipient`,
      headers: bearer(token),
    });
    expect(JSON.parse(get.body).firstName).toBe('Ellie');
  });

  it('GET 404s when no recipient is set yet', async () => {
    const res = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}/recipient`,
      headers: bearer(token),
    });
    expect(res.statusCode).toBe(404);
  });
});
