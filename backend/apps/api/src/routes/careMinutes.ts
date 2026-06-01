import type { FastifyInstance } from 'fastify';
import { withRls } from '@carecircle/db';
import {
  careMinuteSchema,
  conflict,
  exportCareMinutesSchema,
  hcbsByCode,
  validationFailed,
} from '@carecircle/shared';
import { cipherFor } from '../lib/encrypt.js';
import { requireMembership } from '../lib/membership.js';

function minutesBetween(start: string | Date, end: string | Date): number {
  const s = start instanceof Date ? start.getTime() : Date.parse(start);
  const e = end instanceof Date ? end.getTime() : Date.parse(end);
  return Math.max(0, Math.round((e - s) / 60_000));
}

export async function careMinuteRoutes(app: FastifyInstance): Promise<void> {
  const { pool, circleKeys, queues } = app.ctx;

  app.post('/v1/circles/:circleId/care-minutes', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId } = req.params as { circleId: string };
    await requireMembership(pool, userId, circleId, [
      'owner',
      'family_member',
      'paid_aide',
      'paid_family',
    ]);
    const body = careMinuteSchema.parse(req.body);
    if (!hcbsByCode(body.serviceCode)) {
      throw validationFailed({ serviceCode: 'unknown HCBS code' });
    }
    const cipher = await cipherFor(circleKeys, circleId);
    const duration = minutesBetween(body.startedAt, body.endedAt);
    if (duration <= 0) {
      throw validationFailed({ endedAt: 'must be after startedAt' });
    }

    const row = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const overlap = await client.query<{ id: string }>(
        `SELECT id FROM care_minute_entries
         WHERE circle_id = $1
           AND caregiver_user_id = $2
           AND deleted_at IS NULL
           AND (started_at, ended_at) OVERLAPS ($3::timestamptz, $4::timestamptz)`,
        [circleId, userId, body.startedAt, body.endedAt],
      );
      if (overlap.rows[0]) {
        throw conflict('Overlapping care-minutes entry');
      }
      const result = await client.query<{ id: string }>(
        `INSERT INTO care_minute_entries (
            circle_id, caregiver_user_id, shift_id, service_code, service_description,
            started_at, ended_at, duration_minutes, notes_enc, fiscal_intermediary
         ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
         RETURNING id`,
        [
          circleId,
          userId,
          body.shiftId ?? null,
          body.serviceCode,
          body.serviceDescription,
          body.startedAt,
          body.endedAt,
          duration,
          cipher.encryptOptional(body.notes),
          body.fiscalIntermediary ?? null,
        ],
      );
      return result.rows[0]!;
    });
    reply.status(201).send({ id: row.id, durationMinutes: duration });
  });

  app.get('/v1/circles/:circleId/care-minutes', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId } = req.params as { circleId: string };
    await requireMembership(pool, userId, circleId);
    const cipher = await cipherFor(circleKeys, circleId);

    const rows = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{
        id: string;
        caregiver_user_id: string;
        service_code: string;
        service_description: string;
        started_at: Date;
        ended_at: Date;
        duration_minutes: number;
        notes_enc: Buffer | null;
        fiscal_intermediary: string | null;
        exported_at: Date | null;
      }>(
        `SELECT id, caregiver_user_id, service_code, service_description,
                started_at, ended_at, duration_minutes, notes_enc, fiscal_intermediary, exported_at
         FROM care_minute_entries
         WHERE circle_id = $1 AND deleted_at IS NULL
         ORDER BY started_at DESC LIMIT 500`,
        [circleId],
      );
      return result.rows;
    });

    reply.send({
      entries: rows.map((r) => ({
        id: r.id,
        caregiverUserId: r.caregiver_user_id,
        serviceCode: r.service_code,
        serviceDescription: r.service_description,
        startedAt: r.started_at.toISOString(),
        endedAt: r.ended_at.toISOString(),
        durationMinutes: r.duration_minutes,
        notes: cipher.decryptOptional(r.notes_enc),
        fiscalIntermediary: r.fiscal_intermediary,
        exportedAt: r.exported_at?.toISOString() ?? null,
      })),
    });
  });

  app.post('/v1/circles/:circleId/care-minutes/export-pdf', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId } = req.params as { circleId: string };
    await requireMembership(pool, userId, circleId, [
      'owner',
      'family_member',
      'paid_aide',
      'paid_family',
    ]);
    const body = exportCareMinutesSchema.parse(req.body ?? {});
    const job = await queues.pdf.add(
      'care_minutes_export',
      {
        jobType: 'care_minutes_export',
        circleId,
        caregiverUserId: userId,
        startDate: body.startDate,
        endDate: body.endDate,
        fiscalIntermediary: body.fiscalIntermediary,
      },
      // A double-tapped export for the same closed range coalesces into one job.
      { jobId: `pdf:${circleId}:${userId}:${body.startDate}:${body.endDate}` },
    );
    reply.status(202).send({ jobId: job.id });
  });
}
