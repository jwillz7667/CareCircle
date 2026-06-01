import { readdir, readFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const here = dirname(fileURLToPath(import.meta.url));
const MIGRATIONS_DIR = resolve(here, '../../../packages/db/migrations');

export type MigrateOptions = {
  connectionString: string;
  /** When false, suppresses per-migration stdout (used by the test harness). */
  log?: boolean;
};

export type MigrateResult = {
  applied: number;
  total: number;
};

async function ensureLedger(client: pg.PoolClient): Promise<void> {
  await client.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      name        TEXT PRIMARY KEY,
      applied_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `);
}

async function listApplied(client: pg.PoolClient): Promise<Set<string>> {
  const { rows } = await client.query<{ name: string }>('SELECT name FROM schema_migrations');
  return new Set(rows.map((r) => r.name));
}

async function applyMigration(
  client: pg.PoolClient,
  name: string,
  sqlText: string,
  log: boolean,
): Promise<void> {
  if (log) {
    console.log(`→ applying ${name}`);
  }
  await client.query('BEGIN');
  try {
    await client.query(sqlText);
    await client.query('INSERT INTO schema_migrations (name) VALUES ($1)', [name]);
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  }
}

/**
 * Applies every pending SQL migration in `packages/db/migrations` in lexical
 * order, each inside its own transaction. Idempotent: already-applied files
 * (tracked in `schema_migrations`) are skipped, so it is safe to run on every
 * deploy and from the test harness.
 */
export async function runMigrations(opts: MigrateOptions): Promise<MigrateResult> {
  const log = opts.log ?? true;
  const pool = new pg.Pool({ connectionString: opts.connectionString });
  const client = await pool.connect();
  try {
    await ensureLedger(client);
    const applied = await listApplied(client);
    const files = (await readdir(MIGRATIONS_DIR)).filter((f) => f.endsWith('.sql')).sort();

    if (files.length === 0) {
      throw new Error(`No migrations found in ${MIGRATIONS_DIR}`);
    }

    let appliedCount = 0;
    for (const file of files) {
      if (applied.has(file)) {
        continue;
      }
      const sqlText = await readFile(join(MIGRATIONS_DIR, file), 'utf8');
      await applyMigration(client, file, sqlText, log);
      appliedCount += 1;
    }
    if (log) {
      console.log(
        `Done. ${appliedCount} new migration(s) applied. ${applied.size + appliedCount} total.`,
      );
    }
    return { applied: appliedCount, total: applied.size + appliedCount };
  } finally {
    client.release();
    await pool.end();
  }
}

const invokedDirectly = process.argv[1] === fileURLToPath(import.meta.url);
if (invokedDirectly) {
  const connectionString = process.env.DIRECT_DATABASE_URL ?? process.env.DATABASE_URL;
  if (!connectionString) {
    console.error('DATABASE_URL or DIRECT_DATABASE_URL is required.');
    process.exit(1);
  }
  runMigrations({ connectionString }).catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
