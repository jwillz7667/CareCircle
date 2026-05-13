import { newDek, unwrapDek, wrapDek } from '@carecircle/shared';
import type pg from 'pg';
import { withRls } from '@carecircle/db';
import type { Config } from '../config.js';

/**
 * Per-circle data-encryption-key management. The DEK is randomly
 * generated on first circle creation, wrapped with the app master
 * key, and stored in `circle_keys`. Unwrapping happens server-side
 * only — the master key never leaves env.
 *
 * Cached in-memory per process to avoid hammering the DB on every
 * write. Cache invalidates on key rotation.
 */
export class CircleKeyService {
  private readonly cache = new Map<string, Buffer>();

  constructor(
    private readonly pool: pg.Pool,
    private readonly config: Config,
  ) {}

  async getOrCreate(circleId: string): Promise<Buffer> {
    const cached = this.cache.get(circleId);
    if (cached) {
      return cached;
    }

    const dek = await withRls(this.pool, { role: 'app_service' }, async (client) => {
      const existing = await client.query<{ encrypted_dek: Buffer }>(
        `SELECT encrypted_dek FROM circle_keys WHERE circle_id = $1`,
        [circleId],
      );
      if (existing.rows[0]) {
        return unwrapDek(existing.rows[0].encrypted_dek, this.config.APP_MASTER_KEY);
      }
      const fresh = newDek();
      const wrapped = wrapDek(fresh, this.config.APP_MASTER_KEY);
      await client.query(
        `INSERT INTO circle_keys (circle_id, encrypted_dek) VALUES ($1, $2)
         ON CONFLICT (circle_id) DO NOTHING`,
        [circleId, wrapped],
      );
      return fresh;
    });

    this.cache.set(circleId, dek);
    return dek;
  }

  invalidate(circleId: string): void {
    this.cache.delete(circleId);
  }
}
