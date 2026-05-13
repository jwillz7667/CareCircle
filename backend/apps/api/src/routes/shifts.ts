import type { FastifyInstance } from 'fastify';
import { withRls } from '@carecircle/db';
import { createShiftSchema, notFound } from '@carecircle/shared';
import { cipherFor } from '../lib/encrypt.js';
import { requireMembership } from '../lib/membership.js';

export async function shiftRoutes(app: FastifyInstance): Promise<void> {
  const { pool, circleKeys } = app.ctx;

  app.post('/v1/circles/:circleId/shifts', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId } = req.params as { circleId: string };
    await requireMembership(pool, userId, circleId, ['owner', 'family_member', 'paid_family']);
    const body = createShiftSchema.parse(req.body);
    const cipher = await cipherFor(circleKeys, circleId);

    const row = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{ id: string }>(
        `INSERT INTO care_shifts (
            circle_id, aide_user_id, starts_at, ends_at, services, notes_enc
         ) VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
        [
          circleId,
          body.aideUserId,
          body.startsAt,
          body.endsAt,
          body.services ?? [],
          cipher.encryptOptional(body.notes),
        ],
      );
      return result.rows[0]!;
    });
    reply.status(201).send(row);
  });

  app.get('/v1/circles/:circleId/shifts', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId } = req.params as { circleId: string };
    await requireMembership(pool, userId, circleId);

    const rows = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{
        id: string;
        aide_user_id: string;
        starts_at: Date;
        ends_at: Date;
        actual_start: Date | null;
        actual_end: Date | null;
        services: string[];
        miles_driven: string | null;
      }>(
        `SELECT id, aide_user_id, starts_at, ends_at, actual_start, actual_end, services, miles_driven
         FROM care_shifts WHERE circle_id = $1 AND deleted_at IS NULL
         ORDER BY starts_at DESC LIMIT 200`,
        [circleId],
      );
      return result.rows;
    });

    reply.send({
      shifts: rows.map((r) => ({
        id: r.id,
        aideUserId: r.aide_user_id,
        startsAt: r.starts_at.toISOString(),
        endsAt: r.ends_at.toISOString(),
        actualStart: r.actual_start?.toISOString() ?? null,
        actualEnd: r.actual_end?.toISOString() ?? null,
        services: r.services,
        milesDriven: r.miles_driven ? Number(r.miles_driven) : null,
      })),
    });
  });

  app.post('/v1/shifts/:id/clock-in', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { id } = req.params as { id: string };
    const updated = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{ id: string }>(
        `UPDATE care_shifts SET actual_start = NOW()
         WHERE id = $1 AND aide_user_id = current_user_id() AND deleted_at IS NULL
         RETURNING id`,
        [id],
      );
      return result.rows[0] ?? null;
    });
    if (!updated) {
      throw notFound('Shift not found');
    }
    reply.status(204).send();
  });

  app.post('/v1/shifts/:id/clock-out', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { id } = req.params as { id: string };
    const updated = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{ id: string }>(
        `UPDATE care_shifts SET actual_end = NOW()
         WHERE id = $1 AND aide_user_id = current_user_id() AND deleted_at IS NULL
         RETURNING id`,
        [id],
      );
      return result.rows[0] ?? null;
    });
    if (!updated) {
      throw notFound('Shift not found');
    }
    reply.status(204).send();
  });
}
