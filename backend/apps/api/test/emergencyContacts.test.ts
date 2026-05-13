/**
 * Emergency contacts: list, create with encrypted name+phone, patch, soft-delete.
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

describe('Emergency contacts', () => {
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
    owner = await insertUser(pool, { appleId: 'mock|ec-owner' });
    circle = await insertCircle(pool, { ownerId: owner.id, name: 'EC Circle' });
    token = (await loginAs(app, owner.appleId)).accessToken;
  });

  it('create + list + patch + delete', async () => {
    const create = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/emergency-contacts`,
      headers: bearer(token),
      payload: {
        name: 'Dr. Susan Park',
        relationship: 'PCP',
        phone: '+1 612 555 0142',
        isPrimary: false,
        isMedical: true,
        sortOrder: 10,
      },
    });
    expect(create.statusCode).toBe(201);
    const { id } = JSON.parse(create.body) as { id: string };

    // Raw row is encrypted.
    const raw = await pool.query<{ name_enc: Buffer; phone_enc: Buffer }>(
      `SELECT name_enc, phone_enc FROM emergency_contacts WHERE id = $1`,
      [id],
    );
    expect(raw.rows[0]!.name_enc.toString('utf8')).not.toContain('Susan');
    expect(raw.rows[0]!.phone_enc.toString('utf8')).not.toContain('612');

    const list = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}/emergency-contacts`,
      headers: bearer(token),
    });
    const body = JSON.parse(list.body) as {
      contacts: Array<{
        id: string;
        name: string;
        phone: string;
        relationship: string | null;
        isMedical: boolean;
      }>;
    };
    expect(body.contacts).toHaveLength(1);
    expect(body.contacts[0]!.name).toBe('Dr. Susan Park');
    expect(body.contacts[0]!.phone).toBe('+1 612 555 0142');
    expect(body.contacts[0]!.isMedical).toBe(true);

    const patch = await app.inject({
      method: 'PATCH',
      url: `/v1/emergency-contacts/${id}`,
      headers: bearer(token),
      payload: { isPrimary: true },
    });
    expect(patch.statusCode).toBe(204);

    const del = await app.inject({
      method: 'DELETE',
      url: `/v1/emergency-contacts/${id}`,
      headers: bearer(token),
    });
    expect(del.statusCode).toBe(204);

    const list2 = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}/emergency-contacts`,
      headers: bearer(token),
    });
    expect(JSON.parse(list2.body).contacts).toEqual([]);
  });
});
