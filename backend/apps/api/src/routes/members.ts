import type { FastifyInstance } from 'fastify';
import { withRls } from '@carecircle/db';
import { z } from 'zod';
import { memberRoleSchema, notFound, conflict } from '@carecircle/shared';
import { requireMembership } from '../lib/membership.js';

const updateMemberSchema = z.object({
  role: memberRoleSchema.optional(),
  displayName: z.string().min(1).max(80).optional(),
  status: z.enum(['active', 'paused']).optional(),
});

export async function memberRoutes(app: FastifyInstance): Promise<void> {
  const { pool } = app.ctx;

  app.get('/v1/circles/:circleId/members', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId } = req.params as { circleId: string };
    await requireMembership(pool, userId, circleId);

    const rows = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{
        id: string;
        user_id: string;
        role: string;
        status: string;
        display_name: string;
        joined_at: Date | null;
        invited_at: Date;
        user_photo_object_key: string | null;
      }>(
        `SELECT cm.id, cm.user_id, cm.role, cm.status, cm.display_name,
                cm.joined_at, cm.invited_at,
                u.photo_object_key AS user_photo_object_key
         FROM circle_members cm
         JOIN users u ON u.id = cm.user_id
         WHERE cm.circle_id = $1 AND cm.deleted_at IS NULL
         ORDER BY cm.role, cm.display_name`,
        [circleId],
      );
      return result.rows;
    });

    reply.send({
      members: rows.map((r) => ({
        id: r.id,
        userId: r.user_id,
        role: r.role,
        status: r.status,
        displayName: r.display_name,
        joinedAt: r.joined_at?.toISOString() ?? null,
        invitedAt: r.invited_at.toISOString(),
        photoObjectKey: r.user_photo_object_key,
      })),
    });
  });

  app.patch('/v1/circles/:circleId/members/:memberId', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId, memberId } = req.params as { circleId: string; memberId: string };
    await requireMembership(pool, userId, circleId, ['owner']);
    const body = updateMemberSchema.parse(req.body);

    const result = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const updated = await client.query<{ id: string }>(
        `UPDATE circle_members
         SET role         = COALESCE($3, role),
             display_name = COALESCE($4, display_name),
             status       = COALESCE($5::member_status, status)
         WHERE id = $1 AND circle_id = $2 AND deleted_at IS NULL
         RETURNING id`,
        [memberId, circleId, body.role ?? null, body.displayName ?? null, body.status ?? null],
      );
      return updated.rows[0] ?? null;
    });
    if (!result) {
      throw notFound('Member not found');
    }
    reply.status(204).send();
  });

  app.delete('/v1/circles/:circleId/members/:memberId', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId, memberId } = req.params as { circleId: string; memberId: string };
    await requireMembership(pool, userId, circleId, ['owner']);

    const removed = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const isOwner = await client.query<{ role: string; user_id: string }>(
        `SELECT role, user_id FROM circle_members WHERE id = $1 AND circle_id = $2`,
        [memberId, circleId],
      );
      const target = isOwner.rows[0];
      if (target?.role === 'owner') {
        throw conflict('Cannot remove the owner');
      }
      const result = await client.query<{ id: string }>(
        `UPDATE circle_members SET deleted_at = NOW(), status = 'removed'
         WHERE id = $1 AND circle_id = $2 AND deleted_at IS NULL
         RETURNING id`,
        [memberId, circleId],
      );
      return result.rows[0] ?? null;
    });
    if (!removed) {
      throw notFound('Member not found');
    }
    reply.status(204).send();
  });
}
