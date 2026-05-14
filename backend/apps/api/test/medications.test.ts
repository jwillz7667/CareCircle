/**
 * Medications + dose events. Verifies envelope encryption of name/dosage, schedule
 * round-trip, dose mark, list ordering, soft-delete.
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

describe('Medications', () => {
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
    owner = await insertUser(pool, { appleId: 'mock|med-owner' });
    circle = await insertCircle(pool, { ownerId: owner.id, name: 'Med Circle' });
    token = (await loginAs(app, owner.appleId)).accessToken;
  });

  it('creates a medication with encrypted name/dosage and lists it back decrypted', async () => {
    const post = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/medications`,
      headers: bearer(token),
      payload: {
        name: 'Lisinopril',
        genericName: 'Lisinopril',
        dosage: '10 mg',
        form: 'tablet',
        rxcui: '314076',
        color: 'pink',
        schedule: { times: ['08:00', '20:00'] },
        startDate: '2026-05-01',
      },
    });
    expect(post.statusCode).toBe(201);
    const { id } = JSON.parse(post.body) as { id: string };

    // The raw row should have ciphertext, not plaintext.
    const raw = await pool.query<{ name_enc: Buffer }>(
      `SELECT name_enc FROM medications WHERE id = $1`,
      [id],
    );
    expect(raw.rows[0]!.name_enc.length).toBeGreaterThan(0);
    expect(raw.rows[0]!.name_enc.toString('utf8')).not.toContain('Lisinopril');

    const list = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}/medications`,
      headers: bearer(token),
    });
    const body = JSON.parse(list.body) as {
      medications: Array<{
        id: string;
        name: string;
        dosage: string;
        schedule: { times: string[] };
        rxcui: string | null;
        startDate: string | null;
      }>;
    };
    expect(body.medications).toHaveLength(1);
    expect(body.medications[0]!.name).toBe('Lisinopril');
    expect(body.medications[0]!.dosage).toBe('10 mg');
    expect(body.medications[0]!.schedule.times).toEqual(['08:00', '20:00']);
    expect(body.medications[0]!.rxcui).toBe('314076');
    expect(body.medications[0]!.startDate).toBe('2026-05-01');
  });

  it('PATCH /v1/medications/:id updates encrypted fields', async () => {
    const post = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/medications`,
      headers: bearer(token),
      payload: { name: 'Metformin', dosage: '500 mg' },
    });
    const id = JSON.parse(post.body).id as string;

    const patch = await app.inject({
      method: 'PATCH',
      url: `/v1/medications/${id}`,
      headers: bearer(token),
      payload: { dosage: '1000 mg', status: 'active' },
    });
    expect(patch.statusCode).toBe(204);

    const list = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}/medications`,
      headers: bearer(token),
    });
    const meds = JSON.parse(list.body).medications as Array<{ dosage: string }>;
    expect(meds[0]!.dosage).toBe('1000 mg');
  });

  it('marks a dose as taken and records the event', async () => {
    const med = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/medications`,
      headers: bearer(token),
      payload: { name: 'Atorvastatin', dosage: '20 mg' },
    });
    const medId = JSON.parse(med.body).id as string;
    const scheduledAt = new Date().toISOString();

    const mark = await app.inject({
      method: 'POST',
      url: `/v1/medications/${medId}/doses/mark`,
      headers: bearer(token),
      payload: { scheduledAt, status: 'taken', notes: 'with breakfast' },
    });
    expect(mark.statusCode).toBe(201);
    const markedDoseId = JSON.parse(mark.body).id as string;

    const doses = await app.inject({
      method: 'GET',
      url: `/v1/medications/${medId}/doses`,
      headers: bearer(token),
    });
    const body = JSON.parse(doses.body) as {
      doses: Array<{ status: string; takenAt: string | null; notes: string | null }>;
    };
    expect(body.doses).toHaveLength(1);
    expect(body.doses[0]!.status).toBe('taken');
    expect(body.doses[0]!.takenAt).not.toBeNull();
    expect(body.doses[0]!.notes).toBe('with breakfast');

    const single = await app.inject({
      method: 'GET',
      url: `/v1/doses/${markedDoseId}`,
      headers: bearer(token),
    });
    expect(single.statusCode).toBe(200);
    const dose = JSON.parse(single.body) as {
      id: string;
      medicationId: string;
      circleId: string;
      status: string;
      notes: string | null;
    };
    expect(dose.id).toBe(markedDoseId);
    expect(dose.medicationId).toBe(medId);
    expect(dose.circleId).toBe(circle.id);
    expect(dose.status).toBe('taken');
    expect(dose.notes).toBe('with breakfast');

    const missing = await app.inject({
      method: 'GET',
      url: `/v1/doses/00000000-0000-0000-0000-000000000000`,
      headers: bearer(token),
    });
    expect(missing.statusCode).toBe(404);
  });

  it('DELETE soft-deletes (status flips to discontinued, list excludes it)', async () => {
    const post = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/medications`,
      headers: bearer(token),
      payload: { name: 'OldMed', dosage: '1 mg' },
    });
    const id = JSON.parse(post.body).id as string;

    const del = await app.inject({
      method: 'DELETE',
      url: `/v1/medications/${id}`,
      headers: bearer(token),
    });
    expect(del.statusCode).toBe(204);

    const list = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}/medications`,
      headers: bearer(token),
    });
    expect(JSON.parse(list.body).medications).toEqual([]);

    // The underlying row still exists with status discontinued.
    const raw = await pool.query<{ status: string; deleted_at: Date | null }>(
      `SELECT status, deleted_at FROM medications WHERE id = $1`,
      [id],
    );
    expect(raw.rows[0]!.status).toBe('discontinued');
    expect(raw.rows[0]!.deleted_at).not.toBeNull();
  });
});
