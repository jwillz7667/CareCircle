import createSubscriber, { type Subscriber } from 'pg-listen';
import type { Logger } from '@carecircle/shared';
import type { Config } from '../config.js';

export type ChangePayload = {
  circle_id: string;
  table: string;
  row_id: string;
  op: 'INSERT' | 'UPDATE' | 'DELETE';
};

export type Listener = (payload: ChangePayload) => void;

export interface RealtimeBroker {
  subscribe(circleId: string, listener: Listener): () => void;
  start(): Promise<void>;
  stop(): Promise<void>;
  publishLocal(payload: ChangePayload): void;
}

export function createRealtimeBroker(config: Config, logger: Logger): RealtimeBroker {
  const listeners = new Map<string, Set<Listener>>();
  let subscriber: Subscriber | null = null;
  let running = false;

  function publishLocal(payload: ChangePayload): void {
    const set = listeners.get(payload.circle_id);
    if (!set || set.size === 0) {
      return;
    }
    for (const fn of set) {
      try {
        fn(payload);
      } catch (err) {
        logger.error({ err }, 'realtime listener threw');
      }
    }
  }

  return {
    subscribe(circleId, listener) {
      let set = listeners.get(circleId);
      if (!set) {
        set = new Set();
        listeners.set(circleId, set);
      }
      set.add(listener);
      return () => {
        const current = listeners.get(circleId);
        if (!current) {
          return;
        }
        current.delete(listener);
        if (current.size === 0) {
          listeners.delete(circleId);
        }
      };
    },
    async start() {
      if (running) {
        return;
      }
      running = true;
      subscriber = createSubscriber({ connectionString: config.DATABASE_URL });
      subscriber.notifications.on('circle_changes', (raw) => {
        try {
          const payload = typeof raw === 'string' ? (JSON.parse(raw) as ChangePayload) : (raw as ChangePayload);
          if (!payload?.circle_id) {
            return;
          }
          publishLocal(payload);
        } catch (err) {
          logger.error({ err }, 'failed to parse notify payload');
        }
      });
      subscriber.events.on('error', (err) => {
        logger.error({ err }, 'pg-listen error');
      });
      await subscriber.connect();
      await subscriber.listenTo('circle_changes');
    },
    async stop() {
      if (!running) {
        return;
      }
      running = false;
      if (subscriber) {
        await subscriber.unlistenAll();
        await subscriber.close();
        subscriber = null;
      }
      listeners.clear();
    },
    publishLocal,
  };
}
