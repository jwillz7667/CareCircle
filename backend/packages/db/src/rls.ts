import type pg from 'pg';

/**
 * Set per-transaction RLS context. Must run inside the same transaction
 * as the subsequent queries — `SET LOCAL` is transaction-scoped, which
 * is the only safe scope under PgBouncer transaction-pool mode.
 *
 * Pass null/undefined to reset (anonymous).
 */
export async function setRlsContext(
  client: pg.PoolClient | pg.ClientBase,
  ctx: { userId?: string | null; circleId?: string | null },
): Promise<void> {
  if (ctx.userId) {
    await client.query('SELECT set_config($1, $2, true)', ['app.current_user_id', ctx.userId]);
  } else {
    await client.query('SELECT set_config($1, $2, true)', ['app.current_user_id', '']);
  }
  if (ctx.circleId) {
    await client.query('SELECT set_config($1, $2, true)', ['app.current_circle_id', ctx.circleId]);
  } else {
    await client.query('SELECT set_config($1, $2, true)', ['app.current_circle_id', '']);
  }
}

/**
 * Run a callback inside a transaction with RLS context set, scoped to
 * the chosen Postgres role. The role is always reset on exit even when
 * the callback throws.
 */
export async function withRls<T>(
  pool: pg.Pool,
  ctx: { userId?: string | null; circleId?: string | null; role?: 'app_user' | 'app_service' },
  fn: (client: pg.PoolClient) => Promise<T>,
): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    if (ctx.role) {
      await client.query(`SET LOCAL ROLE ${ctx.role}`);
    }
    await setRlsContext(client, ctx);
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}
