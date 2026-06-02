import type { FastifyInstance } from 'fastify';
import type { WebSocket } from '@fastify/websocket';
import { withRls } from '@carecircle/db';

// A removed member keeps an open socket; re-checking membership on this
// cadence bounds how long they keep receiving a circle's change frames
// after losing access (the row data behind each frame is still RLS-gated,
// so this only tightens change-metadata exposure).
const MEMBERSHIP_RECHECK_INTERVAL_MS = 30_000;

export async function realtimeRoutes(app: FastifyInstance): Promise<void> {
  const { pool, realtime, tokens } = app.ctx;

  app.get('/v1/realtime', { websocket: true }, async (socket: WebSocket, req) => {
    // The token must arrive in the Authorization header, never the query
    // string: query strings land in access logs, proxy history, and
    // referrer headers. Native URLSession sets headers on the WS upgrade.
    const authHeader = req.headers.authorization;
    const token = authHeader?.toLowerCase().startsWith('bearer ')
      ? authHeader.slice(7).trim()
      : undefined;
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

    const fetchCircleIds = (): Promise<string[]> =>
      withRls(pool, { role: 'app_service' }, async (client) => {
        const result = await client.query<{ circle_id: string }>(
          `SELECT circle_id FROM circle_members
           WHERE user_id = $1 AND deleted_at IS NULL`,
          [userId],
        );
        return result.rows.map((r) => r.circle_id);
      });

    // circleId -> unsubscribe handle, reconciled on a timer so membership
    // changes take effect without forcing the client to reconnect.
    const subscriptions = new Map<string, () => void>();

    const subscribe = (circleId: string): void => {
      if (subscriptions.has(circleId)) {
        return;
      }
      const unsubscribe = realtime.subscribe(circleId, (payload) => {
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
      });
      subscriptions.set(circleId, unsubscribe);
    };

    // Returns true when the subscription set changed.
    const reconcile = (circleIds: string[]): boolean => {
      const next = new Set(circleIds);
      let changed = false;
      for (const [circleId, unsubscribe] of subscriptions) {
        if (!next.has(circleId)) {
          unsubscribe();
          subscriptions.delete(circleId);
          changed = true;
        }
      }
      for (const circleId of next) {
        if (!subscriptions.has(circleId)) {
          subscribe(circleId);
          changed = true;
        }
      }
      return changed;
    };

    reconcile(await fetchCircleIds());
    socket.send(JSON.stringify({ type: 'subscribed', circles: [...subscriptions.keys()] }));

    const timer = setInterval(() => {
      void (async () => {
        try {
          const changed = reconcile(await fetchCircleIds());
          if (changed && socket.readyState === 1) {
            socket.send(
              JSON.stringify({ type: 'subscribed', circles: [...subscriptions.keys()] }),
            );
          }
        } catch {
          // Transient DB error — keep the socket and retry on the next tick.
        }
      })();
    }, MEMBERSHIP_RECHECK_INTERVAL_MS);

    const cleanup = (): void => {
      clearInterval(timer);
      for (const unsubscribe of subscriptions.values()) {
        unsubscribe();
      }
      subscriptions.clear();
    };

    socket.on('close', cleanup);
    socket.on('error', cleanup);
  });
}
