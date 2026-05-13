import type { FastifyInstance } from 'fastify';
import { withRls } from '@carecircle/db';
import { syncBatchSchema } from '@carecircle/shared';

export async function syncRoutes(app: FastifyInstance): Promise<void> {
  const { pool } = app.ctx;

  app.post('/v1/sync/batch', async (req, reply) => {
    const userId = await app.requireUser(req);
    const body = syncBatchSchema.parse(req.body);

    const result = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const acks: Array<{ clientOpId: string; status: 'queued' | 'duplicate' }> = [];
      for (const op of body.operations) {
        const insert = await client.query<{ id: string }>(
          `INSERT INTO pending_operations (client_op_id, user_id, circle_id, operation_type, payload)
           VALUES ($1, $2, $3, $4, $5)
           ON CONFLICT (user_id, client_op_id) DO NOTHING
           RETURNING id`,
          [op.clientOpId, userId, op.circleId ?? null, op.operationType, op.payload],
        );
        acks.push({
          clientOpId: op.clientOpId,
          status: insert.rows[0] ? 'queued' : 'duplicate',
        });
      }
      return acks;
    });
    reply.send({ acks: result });
  });
}
