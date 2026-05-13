import type { FastifyInstance } from 'fastify';
import type { WebSocket } from '@fastify/websocket';
import { withRls } from '@carecircle/db';

export async function realtimeRoutes(app: FastifyInstance): Promise<void> {
  const { pool, realtime, tokens } = app.ctx;

  app.get(
    '/v1/realtime',
    { websocket: true },
    async (socket: WebSocket, req) => {
      const token =
        (req.query as { token?: string })?.token ??
        (req.headers.authorization?.toLowerCase().startsWith('bearer ')
          ? req.headers.authorization.slice(7).trim()
          : undefined);
      if (!token) {
        socket.close(4401, 'missing token');
        return;
      }
      let userId: string;
      try {
        const claims = await tokens.verifyAccessToken(token);
        userId = claims.sub;
      } catch {
        socket.close(4401, 'invalid token');
        return;
      }

      const circles = await withRls(pool, { role: 'app_service' }, async (client) => {
        const result = await client.query<{ circle_id: string }>(
          `SELECT circle_id FROM circle_members
           WHERE user_id = $1 AND deleted_at IS NULL`,
          [userId],
        );
        return result.rows.map((r) => r.circle_id);
      });

      if (circles.length === 0) {
        socket.send(JSON.stringify({ type: 'subscribed', circles: [] }));
        return;
      }

      const unsubscribers = circles.map((circleId) =>
        realtime.subscribe(circleId, (payload) => {
          if (socket.readyState === 1) {
            socket.send(
              JSON.stringify({
                type: 'change',
                circleId: payload.circle_id,
                table: payload.table,
                rowId: payload.row_id,
                op: payload.op,
              }),
            );
          }
        }),
      );

      socket.on('close', () => {
        for (const unsub of unsubscribers) {
          unsub();
        }
      });
      socket.on('error', () => {
        for (const unsub of unsubscribers) {
          unsub();
        }
      });
      socket.send(JSON.stringify({ type: 'subscribed', circles }));
    },
  );
}
