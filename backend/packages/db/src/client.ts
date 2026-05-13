import { drizzle, type NodePgDatabase } from 'drizzle-orm/node-postgres';
import pg from 'pg';
import * as schema from './schema.js';

export type Database = NodePgDatabase<typeof schema>;

export type PoolFactoryOptions = {
  connectionString: string;
  max?: number;
  applicationName?: string;
  /**
   * When set, every connection from this pool runs `SET ROLE` after
   * connect — required to scope queries to the RLS-bound app_user role.
   */
  role?: 'app_user' | 'app_service' | 'app_anon' | null;
};

export function createPool(opts: PoolFactoryOptions): pg.Pool {
  const pool = new pg.Pool({
    connectionString: opts.connectionString,
    max: opts.max ?? 10,
    application_name: opts.applicationName ?? 'carecircle',
  });
  if (opts.role) {
    pool.on('connect', (client) => {
      void client.query(`SET ROLE ${opts.role}`);
    });
  }
  return pool;
}

export function createDb(pool: pg.Pool): Database {
  return drizzle(pool, { schema });
}

export { schema };
