import type { FastifyInstance } from 'fastify';
import { withRls } from '@carecircle/db';
import { triggerSosSchema, notFound } from '@carecircle/shared';
import { requireMembership } from '../lib/membership.js';

export async function sosRoutes(app: FastifyInstance): Promise<void> {
  const { pool, queues } = app.ctx;

  app.post('/v1/circles/:circleId/sos', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId } = req.params as { circleId: string };
    await requireMembership(pool, userId, circleId);
    const body = triggerSosSchema.parse(req.body ?? {});

    const row = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const members = await client.query<{ user_id: string }>(
        `SELECT user_id FROM circle_members
         WHERE circle_id = $1 AND deleted_at IS NULL AND user_id <> $2`,
        [circleId, userId],
      );
      const notified = members.rows.map((r) => r.user_id);

      // COALESCE lets the server mint the id when the client omits one; a
      // supplied eventId hits ON CONFLICT DO NOTHING on retry, so a duplicate
      // fire returns no row and we skip the (already-sent) push.
      const result = await client.query<{ id: string }>(
        `INSERT INTO sos_events (
            id, circle_id, triggered_by, location_lat, location_lng, location_accuracy_m, notified_user_ids
         ) VALUES (COALESCE($1::uuid, gen_random_uuid()), $2, $3, $4, $5, $6, $7::uuid[])
         ON CONFLICT (id) DO NOTHING
         RETURNING id`,
        [
          body.eventId ?? null,
          circleId,
          userId,
          body.locationLat ?? null,
          body.locationLng ?? null,
          body.locationAccuracyM ?? null,
          notified,
        ],
      );
      const inserted = result.rows[0] ?? null;
      return {
        id: inserted?.id ?? body.eventId!,
        notified,
        created: inserted !== null,
      };
    });
    if (row.created && row.notified.length > 0) {
      await queues.push.add('sos', {
        userIds: row.notified,
        circleId,
        alert: {
          title: 'SOS triggered',
          body: 'Tap to view location and call.',
        },
        category: 'cc_sos',
        threadId: `sos:${circleId}`,
        critical: true,
        payload: { sosId: row.id, circleId },
      });
    }
    reply.status(row.created ? 201 : 200).send({ id: row.id, notified: row.notified });
  });

  app.post('/v1/sos/:id/cancel', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { id } = req.params as { id: string };
    const updated = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{ id: string }>(
        `UPDATE sos_events
         SET canceled_at = NOW(), canceled_by = current_user_id()
         WHERE id = $1 AND canceled_at IS NULL
         RETURNING id`,
        [id],
      );
      return result.rows[0] ?? null;
    });
    if (!updated) {
      throw notFound('SOS not found');
    }
    reply.status(204).send();
  });

  app.get('/v1/circles/:circleId/sos', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId } = req.params as { circleId: string };
    await requireMembership(pool, userId, circleId);
    const rows = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{
        id: string;
        triggered_by: string;
        triggered_at: Date;
        canceled_at: Date | null;
        canceled_by: string | null;
        location_lat: string | null;
        location_lng: string | null;
      }>(
        `SELECT id, triggered_by, triggered_at, canceled_at, canceled_by,
                location_lat::TEXT, location_lng::TEXT
         FROM sos_events WHERE circle_id = $1
         ORDER BY triggered_at DESC LIMIT 50`,
        [circleId],
      );
      return result.rows;
    });
    reply.send({
      events: rows.map((r) => ({
        id: r.id,
        triggeredBy: r.triggered_by,
        triggeredAt: r.triggered_at.toISOString(),
        canceledAt: r.canceled_at?.toISOString() ?? null,
        canceledBy: r.canceled_by,
        locationLat: r.location_lat ? Number(r.location_lat) : null,
        locationLng: r.location_lng ? Number(r.location_lng) : null,
      })),
    });
  });
}
