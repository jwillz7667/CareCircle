import type { FastifyInstance } from 'fastify';
import { withRls } from '@carecircle/db';
import { createCircleSchema, updateCircleSchema, forbidden, notFound } from '@carecircle/shared';

export async function circleRoutes(app: FastifyInstance): Promise<void> {
  const { pool, circleKeys } = app.ctx;

  app.post('/v1/circles', async (req, reply) => {
    const userId = await app.requireUser(req);
    const body = createCircleSchema.parse(req.body);

    const circleId = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{ id: string }>(
        `INSERT INTO circles (name, owner_user_id) VALUES ($1, $2) RETURNING id`,
        [body.name, userId],
      );
      const id = result.rows[0]!.id;

      const me = await client.query<{ display_name: string | null }>(
        `SELECT display_name FROM users WHERE id = $1`,
        [userId],
      );
      const display = me.rows[0]?.display_name ?? 'Owner';
      await client.query(
        `INSERT INTO circle_members (circle_id, user_id, role, status, display_name, joined_at)
         VALUES ($1, $2, 'owner', 'active', $3, NOW())`,
        [id, userId, display],
      );
      return id;
    });

    await circleKeys.getOrCreate(circleId);
    reply.status(201).send({ id: circleId, name: body.name });
  });

  app.get('/v1/circles', async (req, reply) => {
    const userId = await app.requireUser(req);
    const rows = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{
        id: string;
        name: string;
        owner_user_id: string;
        subscription_tier: string;
        subscription_status: string;
        created_at: Date;
        member_count: string;
      }>(
        `SELECT c.id,
                c.name,
                c.owner_user_id,
                c.subscription_tier,
                c.subscription_status,
                c.created_at,
                (SELECT COUNT(*)::TEXT FROM circle_members
                  WHERE circle_id = c.id AND deleted_at IS NULL) AS member_count
         FROM circles c
         WHERE c.deleted_at IS NULL
         ORDER BY c.created_at DESC`,
      );
      return result.rows;
    });
    reply.send({
      circles: rows.map((r) => ({
        id: r.id,
        name: r.name,
        ownerUserId: r.owner_user_id,
        subscriptionTier: r.subscription_tier,
        subscriptionStatus: r.subscription_status,
        createdAt: r.created_at.toISOString(),
        memberCount: Number(r.member_count),
      })),
    });
  });

  app.get('/v1/circles/:id', async (req, reply) => {
    const userId = await app.requireUser(req);
    const params = req.params as { id: string };
    const row = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{
        id: string;
        name: string;
        owner_user_id: string;
        subscription_tier: string;
        subscription_status: string;
        settings: unknown;
        created_at: Date;
      }>(
        `SELECT id, name, owner_user_id, subscription_tier, subscription_status, settings, created_at
         FROM circles WHERE id = $1 AND deleted_at IS NULL`,
        [params.id],
      );
      return result.rows[0] ?? null;
    });
    if (!row) {
      throw notFound('Circle not found');
    }
    reply.send({
      id: row.id,
      name: row.name,
      ownerUserId: row.owner_user_id,
      subscriptionTier: row.subscription_tier,
      subscriptionStatus: row.subscription_status,
      settings: row.settings,
      createdAt: row.created_at.toISOString(),
    });
  });

  app.patch('/v1/circles/:id', async (req, reply) => {
    const userId = await app.requireUser(req);
    const params = req.params as { id: string };
    const body = updateCircleSchema.parse(req.body);

    const updated = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{ id: string }>(
        `UPDATE circles
         SET name     = COALESCE($2, name),
             settings = CASE WHEN $3::jsonb IS NOT NULL THEN settings || $3::jsonb ELSE settings END
         WHERE id = $1 AND owner_user_id = current_user_id() AND deleted_at IS NULL
         RETURNING id`,
        [params.id, body.name ?? null, body.settings ? JSON.stringify(body.settings) : null],
      );
      return result.rows[0] ?? null;
    });
    if (!updated) {
      throw forbidden('Only owner can update circle');
    }
    reply.status(204).send();
  });

  app.delete('/v1/circles/:id', async (req, reply) => {
    const userId = await app.requireUser(req);
    const params = req.params as { id: string };
    const deleted = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{ id: string }>(
        `UPDATE circles
         SET deleted_at = NOW()
         WHERE id = $1 AND owner_user_id = current_user_id() AND deleted_at IS NULL
         RETURNING id`,
        [params.id],
      );
      return result.rows[0] ?? null;
    });
    if (!deleted) {
      throw forbidden('Only owner can delete circle');
    }
    reply.status(204).send();
  });
}
