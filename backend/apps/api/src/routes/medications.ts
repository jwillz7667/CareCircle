import type { FastifyInstance } from 'fastify';
import { withRls } from '@carecircle/db';
import {
  createMedicationSchema,
  markDoseSchema,
  notFound,
} from '@carecircle/shared';
import { cipherFor } from '../lib/encrypt.js';
import { requireMembership } from '../lib/membership.js';

export async function medicationRoutes(app: FastifyInstance): Promise<void> {
  const { pool, circleKeys } = app.ctx;

  app.post('/v1/circles/:circleId/medications', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId } = req.params as { circleId: string };
    await requireMembership(pool, userId, circleId);
    const body = createMedicationSchema.parse(req.body);
    const cipher = await cipherFor(circleKeys, circleId);

    const row = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{ id: string }>(
        `INSERT INTO medications (
           circle_id, name_enc, generic_name_enc, dosage_enc, form, rxcui, color,
           status, schedule, prescribing_provider_enc, pharmacy_enc, notes_enc,
           start_date, end_date
         ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
         RETURNING id`,
        [
          circleId,
          cipher.encrypt(body.name),
          cipher.encryptOptional(body.genericName),
          cipher.encrypt(body.dosage),
          body.form ?? null,
          body.rxcui ?? null,
          body.color ?? null,
          body.status,
          JSON.stringify(body.schedule ?? {}),
          cipher.encryptOptional(body.prescribingProvider),
          cipher.encryptOptional(body.pharmacy),
          cipher.encryptOptional(body.notes),
          body.startDate ?? null,
          body.endDate ?? null,
        ],
      );
      return result.rows[0]!;
    });
    reply.status(201).send({ id: row.id });
  });

  app.get('/v1/circles/:circleId/medications', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId } = req.params as { circleId: string };
    await requireMembership(pool, userId, circleId);
    const cipher = await cipherFor(circleKeys, circleId);

    const rows = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{
        id: string;
        name_enc: Buffer;
        generic_name_enc: Buffer | null;
        dosage_enc: Buffer;
        form: string | null;
        rxcui: string | null;
        color: string | null;
        status: string;
        schedule: unknown;
        start_date: Date | null;
        end_date: Date | null;
      }>(
        `SELECT id, name_enc, generic_name_enc, dosage_enc, form, rxcui, color,
                status, schedule, start_date, end_date
         FROM medications
         WHERE circle_id = $1 AND deleted_at IS NULL
         ORDER BY status, start_date NULLS LAST, id`,
        [circleId],
      );
      return result.rows;
    });

    reply.send({
      medications: rows.map((r) => ({
        id: r.id,
        name: cipher.decrypt(r.name_enc),
        genericName: cipher.decryptOptional(r.generic_name_enc),
        dosage: cipher.decrypt(r.dosage_enc),
        form: r.form,
        rxcui: r.rxcui,
        color: r.color,
        status: r.status,
        schedule: r.schedule,
        startDate: r.start_date ? r.start_date.toISOString().slice(0, 10) : null,
        endDate: r.end_date ? r.end_date.toISOString().slice(0, 10) : null,
      })),
    });
  });

  app.patch('/v1/medications/:id', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { id } = req.params as { id: string };
    const body = createMedicationSchema.partial().parse(req.body);

    const updated = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const existing = await client.query<{ circle_id: string }>(
        `SELECT circle_id FROM medications WHERE id = $1 AND deleted_at IS NULL`,
        [id],
      );
      if (!existing.rows[0]) {
        return null;
      }
      const cipher = await cipherFor(circleKeys, existing.rows[0].circle_id);
      const result = await client.query<{ id: string }>(
        `UPDATE medications SET
            name_enc            = COALESCE($2, name_enc),
            generic_name_enc    = COALESCE($3, generic_name_enc),
            dosage_enc          = COALESCE($4, dosage_enc),
            form                = COALESCE($5, form),
            rxcui               = COALESCE($6, rxcui),
            color               = COALESCE($7, color),
            status              = COALESCE($8::med_status, status),
            schedule            = COALESCE($9::jsonb, schedule),
            notes_enc           = COALESCE($10, notes_enc)
         WHERE id = $1
         RETURNING id`,
        [
          id,
          body.name ? cipher.encrypt(body.name) : null,
          body.genericName ? cipher.encrypt(body.genericName) : null,
          body.dosage ? cipher.encrypt(body.dosage) : null,
          body.form ?? null,
          body.rxcui ?? null,
          body.color ?? null,
          body.status ?? null,
          body.schedule ? JSON.stringify(body.schedule) : null,
          body.notes ? cipher.encrypt(body.notes) : null,
        ],
      );
      return result.rows[0] ?? null;
    });
    if (!updated) {
      throw notFound('Medication not found');
    }
    reply.status(204).send();
  });

  app.delete('/v1/medications/:id', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { id } = req.params as { id: string };
    const deleted = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{ id: string }>(
        `UPDATE medications SET deleted_at = NOW(), status = 'discontinued'
         WHERE id = $1 AND deleted_at IS NULL RETURNING id`,
        [id],
      );
      return result.rows[0] ?? null;
    });
    if (!deleted) {
      throw notFound('Medication not found');
    }
    reply.status(204).send();
  });

  app.post('/v1/medications/:id/doses/mark', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { id } = req.params as { id: string };
    const body = markDoseSchema.parse(req.body);

    const data = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const med = await client.query<{ circle_id: string }>(
        `SELECT circle_id FROM medications WHERE id = $1 AND deleted_at IS NULL`,
        [id],
      );
      if (!med.rows[0]) {
        return null;
      }
      const cipher = await cipherFor(circleKeys, med.rows[0].circle_id);
      const notesEnc = cipher.encryptOptional(body.notes);
      const result = await client.query<{ id: string }>(
        `INSERT INTO dose_events
            (medication_id, circle_id, scheduled_at, taken_at, marked_by, status, notes_enc)
         VALUES ($1, $2, $3, CASE WHEN $4 IN ('taken','late') THEN NOW() ELSE NULL END, $5, $4::dose_status, $6)
         RETURNING id`,
        [id, med.rows[0].circle_id, body.scheduledAt, body.status, userId, notesEnc],
      );
      return { id: result.rows[0]!.id, circleId: med.rows[0].circle_id };
    });
    if (!data) {
      throw notFound('Medication not found');
    }
    reply.status(201).send({ id: data.id });
  });

  app.get('/v1/medications/:id/doses', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { id } = req.params as { id: string };
    const data = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const med = await client.query<{ circle_id: string }>(
        `SELECT circle_id FROM medications WHERE id = $1 AND deleted_at IS NULL`,
        [id],
      );
      if (!med.rows[0]) {
        return null;
      }
      const cipher = await cipherFor(circleKeys, med.rows[0].circle_id);
      const doses = await client.query<{
        id: string;
        scheduled_at: Date;
        taken_at: Date | null;
        marked_by: string | null;
        status: string;
        notes_enc: Buffer | null;
      }>(
        `SELECT id, scheduled_at, taken_at, marked_by, status, notes_enc
         FROM dose_events WHERE medication_id = $1
         ORDER BY scheduled_at DESC LIMIT 200`,
        [id],
      );
      return doses.rows.map((d) => ({
        id: d.id,
        scheduledAt: d.scheduled_at.toISOString(),
        takenAt: d.taken_at?.toISOString() ?? null,
        markedBy: d.marked_by,
        status: d.status,
        notes: cipher.decryptOptional(d.notes_enc),
      }));
    });
    if (!data) {
      throw notFound('Medication not found');
    }
    reply.send({ doses: data });
  });

  app.get('/v1/doses/:id', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { id } = req.params as { id: string };
    const data = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{
        id: string;
        medication_id: string;
        circle_id: string;
        scheduled_at: Date;
        taken_at: Date | null;
        marked_by: string | null;
        status: string;
        notes_enc: Buffer | null;
      }>(
        `SELECT id, medication_id, circle_id, scheduled_at, taken_at, marked_by, status, notes_enc
         FROM dose_events WHERE id = $1`,
        [id],
      );
      const row = result.rows[0];
      if (!row) {
        return null;
      }
      const cipher = await cipherFor(circleKeys, row.circle_id);
      return {
        id: row.id,
        medicationId: row.medication_id,
        circleId: row.circle_id,
        scheduledAt: row.scheduled_at.toISOString(),
        takenAt: row.taken_at?.toISOString() ?? null,
        markedBy: row.marked_by,
        status: row.status,
        notes: cipher.decryptOptional(row.notes_enc),
      };
    });
    if (!data) {
      throw notFound('Dose not found');
    }
    reply.send(data);
  });
}
