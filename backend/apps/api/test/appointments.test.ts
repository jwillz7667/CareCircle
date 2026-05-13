/**
 * Appointments: CRUD + attendees junction + reminders array round-trip.
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

describe('Appointments', () => {
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
    owner = await insertUser(pool, { appleId: 'mock|appt-owner' });
    circle = await insertCircle(pool, { ownerId: owner.id, name: 'Appt Circle' });
    token = (await loginAs(app, owner.appleId)).accessToken;
  });

  it('creates, lists, patches, deletes an appointment', async () => {
    const startsAt = new Date(Date.now() + 86_400_000).toISOString();
    const create = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/appointments`,
      headers: bearer(token),
      payload: {
        title: 'Cardiology follow-up',
        provider: 'Dr. Chen',
        location: 'St. Mary Cardiac Center',
        startsAt,
        durationMinutes: 45,
        prepNotes: 'Bring med list',
        reminderMinutesBefore: [1440, 60, 15],
        attendees: [owner.id],
      },
    });
    expect(create.statusCode).toBe(201);
    const { id } = JSON.parse(create.body) as { id: string };

    const list = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}/appointments`,
      headers: bearer(token),
    });
    const body = JSON.parse(list.body) as {
      appointments: Array<{
        title: string;
        provider: string | null;
        location: string | null;
        durationMinutes: number;
        prepNotes: string | null;
        reminderMinutesBefore: number[];
      }>;
    };
    expect(body.appointments).toHaveLength(1);
    expect(body.appointments[0]!.title).toBe('Cardiology follow-up');
    expect(body.appointments[0]!.provider).toBe('Dr. Chen');
    expect(body.appointments[0]!.location).toBe('St. Mary Cardiac Center');
    expect(body.appointments[0]!.durationMinutes).toBe(45);
    expect(body.appointments[0]!.prepNotes).toBe('Bring med list');
    expect(body.appointments[0]!.reminderMinutesBefore).toEqual([1440, 60, 15]);

    // Attendee row was added.
    const attendees = await pool.query<{ user_id: string }>(
      `SELECT user_id FROM appointment_attendees WHERE appointment_id = $1`,
      [id],
    );
    expect(attendees.rows.map((r) => r.user_id)).toContain(owner.id);

    // PATCH duration.
    const patch = await app.inject({
      method: 'PATCH',
      url: `/v1/appointments/${id}`,
      headers: bearer(token),
      payload: { durationMinutes: 60 },
    });
    expect(patch.statusCode).toBe(204);
    const list2 = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}/appointments`,
      headers: bearer(token),
    });
    expect(JSON.parse(list2.body).appointments[0].durationMinutes).toBe(60);

    // DELETE.
    const del = await app.inject({
      method: 'DELETE',
      url: `/v1/appointments/${id}`,
      headers: bearer(token),
    });
    expect(del.statusCode).toBe(204);
  });
});
