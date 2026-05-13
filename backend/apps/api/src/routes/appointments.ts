import type { FastifyInstance } from 'fastify';
import { withRls } from '@carecircle/db';
import { createAppointmentSchema, notFound } from '@carecircle/shared';
import { cipherFor } from '../lib/encrypt.js';
import { requireMembership } from '../lib/membership.js';

export async function appointmentRoutes(app: FastifyInstance): Promise<void> {
  const { pool, circleKeys } = app.ctx;

  app.post('/v1/circles/:circleId/appointments', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId } = req.params as { circleId: string };
    await requireMembership(pool, userId, circleId);
    const body = createAppointmentSchema.parse(req.body);
    const cipher = await cipherFor(circleKeys, circleId);

    const row = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const appt = await client.query<{ id: string }>(
        `INSERT INTO appointments (
            circle_id, title_enc, provider_enc, location_enc, starts_at, duration_minutes,
            transport_responsible, prep_notes_enc, reminder_minutes_before, created_by
         ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
         RETURNING id`,
        [
          circleId,
          cipher.encrypt(body.title),
          cipher.encryptOptional(body.provider),
          cipher.encryptOptional(body.location),
          body.startsAt,
          body.durationMinutes,
          body.transportResponsible ?? null,
          cipher.encryptOptional(body.prepNotes),
          body.reminderMinutesBefore ?? [1440, 60],
          userId,
        ],
      );
      const apptId = appt.rows[0]!.id;
      if (body.attendees?.length) {
        for (const attendee of body.attendees) {
          await client.query(
            `INSERT INTO appointment_attendees (appointment_id, user_id, circle_id)
             VALUES ($1, $2, $3) ON CONFLICT DO NOTHING`,
            [apptId, attendee, circleId],
          );
        }
      }
      return { id: apptId };
    });
    reply.status(201).send(row);
  });

  app.get('/v1/circles/:circleId/appointments', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId } = req.params as { circleId: string };
    await requireMembership(pool, userId, circleId);
    const cipher = await cipherFor(circleKeys, circleId);

    const rows = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{
        id: string;
        title_enc: Buffer;
        provider_enc: Buffer | null;
        location_enc: Buffer | null;
        starts_at: Date;
        duration_minutes: number;
        transport_responsible: string | null;
        prep_notes_enc: Buffer | null;
        reminder_minutes_before: number[];
      }>(
        `SELECT id, title_enc, provider_enc, location_enc, starts_at, duration_minutes,
                transport_responsible, prep_notes_enc, reminder_minutes_before
         FROM appointments
         WHERE circle_id = $1 AND deleted_at IS NULL
         ORDER BY starts_at ASC`,
        [circleId],
      );
      return result.rows;
    });

    reply.send({
      appointments: rows.map((r) => ({
        id: r.id,
        title: cipher.decrypt(r.title_enc),
        provider: cipher.decryptOptional(r.provider_enc),
        location: cipher.decryptOptional(r.location_enc),
        startsAt: r.starts_at.toISOString(),
        durationMinutes: r.duration_minutes,
        transportResponsible: r.transport_responsible,
        prepNotes: cipher.decryptOptional(r.prep_notes_enc),
        reminderMinutesBefore: r.reminder_minutes_before,
      })),
    });
  });

  app.patch('/v1/appointments/:id', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { id } = req.params as { id: string };
    const body = createAppointmentSchema.partial().parse(req.body);

    const updated = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const existing = await client.query<{ circle_id: string }>(
        `SELECT circle_id FROM appointments WHERE id = $1 AND deleted_at IS NULL`,
        [id],
      );
      if (!existing.rows[0]) {
        return null;
      }
      const cipher = await cipherFor(circleKeys, existing.rows[0].circle_id);
      const result = await client.query<{ id: string }>(
        `UPDATE appointments SET
            title_enc            = COALESCE($2, title_enc),
            provider_enc         = COALESCE($3, provider_enc),
            location_enc         = COALESCE($4, location_enc),
            starts_at            = COALESCE($5, starts_at),
            duration_minutes     = COALESCE($6, duration_minutes),
            transport_responsible = COALESCE($7, transport_responsible),
            prep_notes_enc       = COALESCE($8, prep_notes_enc),
            reminder_minutes_before = COALESCE($9, reminder_minutes_before)
         WHERE id = $1 RETURNING id`,
        [
          id,
          body.title ? cipher.encrypt(body.title) : null,
          body.provider ? cipher.encrypt(body.provider) : null,
          body.location ? cipher.encrypt(body.location) : null,
          body.startsAt ?? null,
          body.durationMinutes ?? null,
          body.transportResponsible ?? null,
          body.prepNotes ? cipher.encrypt(body.prepNotes) : null,
          body.reminderMinutesBefore ?? null,
        ],
      );
      return result.rows[0] ?? null;
    });
    if (!updated) {
      throw notFound('Appointment not found');
    }
    reply.status(204).send();
  });

  app.delete('/v1/appointments/:id', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { id } = req.params as { id: string };
    const deleted = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{ id: string }>(
        `UPDATE appointments SET deleted_at = NOW()
         WHERE id = $1 AND deleted_at IS NULL RETURNING id`,
        [id],
      );
      return result.rows[0] ?? null;
    });
    if (!deleted) {
      throw notFound('Appointment not found');
    }
    reply.status(204).send();
  });
}
