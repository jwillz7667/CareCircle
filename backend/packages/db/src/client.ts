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
  /** Server-side per-statement ceiling. A backstop against runaway queries. */
  statementTimeoutMs?: number;
  /** Max wait to check out / establish a connection before failing fast. */
  connectionTimeoutMs?: number;
  /** Idle pooled connections are closed after this long. */
  idleTimeoutMs?: number;
};

// Ceilings, not budgets: normal queries finish in tens of milliseconds. These
// stop a single wedged query or abandoned transaction from pinning a
// connection and starving the pool.
const DEFAULT_STATEMENT_TIMEOUT_MS = 15_000;
const DEFAULT_CONNECTION_TIMEOUT_MS = 5_000;
const DEFAULT_IDLE_TIMEOUT_MS = 30_000;

export function createPool(opts: PoolFactoryOptions): pg.Pool {
  const statementTimeout = opts.statementTimeoutMs ?? DEFAULT_STATEMENT_TIMEOUT_MS;
  const pool = new pg.Pool({
    connectionString: opts.connectionString,
    max: opts.max ?? 10,
    application_name: opts.applicationName ?? 'carecircle',
    connectionTimeoutMillis: opts.connectionTimeoutMs ?? DEFAULT_CONNECTION_TIMEOUT_MS,
    idleTimeoutMillis: opts.idleTimeoutMs ?? DEFAULT_IDLE_TIMEOUT_MS,
    statement_timeout: statementTimeout,
    // A transaction left open mid-flight holds locks and a connection; cap it
    // at the statement ceiling so a wedged request can't stall the pool.
    idle_in_transaction_session_timeout: statementTimeout,
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
