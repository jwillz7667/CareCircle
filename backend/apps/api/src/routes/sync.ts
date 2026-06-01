import type { FastifyInstance } from 'fastify';
import { withRls } from '@carecircle/db';
import { syncBatchSchema, syncStatusSchema, type SyncOpStatusT } from '@carecircle/shared';

type OpStateRow = { client_op_id: string; processed_at: Date | null; error: string | null };

function statusOf(row: OpStateRow | undefined): SyncOpStatusT {
  if (!row) {
    return 'unknown';
  }
  if (!row.processed_at) {
    return 'pending';
  }
  return row.error ? 'failed' : 'applied';
}

export async function syncRoutes(app: FastifyInstance): Promise<void> {
  const { pool, queues } = app.ctx;

  app.post('/v1/sync/batch', async (req, reply) => {
    const userId = await app.requireUser(req);
    const body = syncBatchSchema.parse(req.body);

    const states = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      for (const op of body.operations) {
        await client.query(
          `INSERT INTO pending_operations (client_op_id, user_id, circle_id, operation_type, payload)
           VALUES ($1, $2, $3, $4, $5)
           ON CONFLICT (user_id, client_op_id) DO NOTHING`,
          [op.clientOpId, userId, op.circleId ?? null, op.operationType, op.payload],
        );
      }
      const rows = await client.query<OpStateRow>(
        `SELECT client_op_id, processed_at, error
         FROM pending_operations
         WHERE user_id = $1 AND client_op_id = ANY($2::uuid[])`,
        [userId, body.operations.map((op) => op.clientOpId)],
      );
      return rows.rows;
    });

    // A single per-user job coalesces a burst of batches; the projector
    // reselects every unprocessed op for the user, so one drain covers them
    // all. removeOnComplete frees the jobId for the next batch.
    await queues.sync.add(
      'drain',
      { userId },
      {
        jobId: `sync:${userId}`,
        attempts: 5,
        backoff: { type: 'exponential', delay: 2_000 },
        removeOnComplete: true,
        removeOnFail: 100,
      },
    );

    const byId = new Map(states.map((row) => [row.client_op_id, row]));
    const acks = body.operations.map((op) => {
      const row = byId.get(op.clientOpId);
      const status = statusOf(row);
      return status === 'failed'
        ? { clientOpId: op.clientOpId, status, error: row?.error ?? undefined }
        : { clientOpId: op.clientOpId, status };
    });
    reply.send({ acks });
  });

  // Lightweight confirmation poll: the client retains an op locally until the
  // projector reports it applied (or permanently failed), then drops it.
  app.post('/v1/sync/status', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { clientOpIds } = syncStatusSchema.parse(req.body);

    const states = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const rows = await client.query<OpStateRow>(
        `SELECT client_op_id, processed_at, error
         FROM pending_operations
         WHERE user_id = $1 AND client_op_id = ANY($2::uuid[])`,
        [userId, clientOpIds],
      );
      return rows.rows;
    });

    const byId = new Map(states.map((row) => [row.client_op_id, row]));
    const statuses = clientOpIds.map((clientOpId) => {
      const row = byId.get(clientOpId);
      const status = statusOf(row);
      return status === 'failed'
        ? { clientOpId, status, error: row?.error ?? undefined }
        : { clientOpId, status };
    });
    reply.send({ statuses });
  });
}
