import { readdir, readFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const here = dirname(fileURLToPath(import.meta.url));
const MIGRATIONS_DIR = resolve(here, '../../../packages/db/migrations');

const connectionString = process.env.DIRECT_DATABASE_URL ?? process.env.DATABASE_URL;
if (!connectionString) {
  console.error('DATABASE_URL or DIRECT_DATABASE_URL is required.');
  process.exit(1);
}

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

async function applyMigration(client: pg.PoolClient, name: string, sqlText: string): Promise<void> {
  console.log(`→ applying ${name}`);
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

async function main(): Promise<void> {
  const pool = new pg.Pool({ connectionString });
  const client = await pool.connect();
  try {
    await ensureLedger(client);
    const applied = await listApplied(client);
    const files = (await readdir(MIGRATIONS_DIR))
      .filter((f) => f.endsWith('.sql'))
      .sort();

    if (files.length === 0) {
      console.error(`No migrations found in ${MIGRATIONS_DIR}`);
      process.exit(1);
    }

    let appliedCount = 0;
    for (const file of files) {
      if (applied.has(file)) {
        continue;
      }
      const sqlText = await readFile(join(MIGRATIONS_DIR, file), 'utf8');
      await applyMigration(client, file, sqlText);
      appliedCount += 1;
    }
    console.log(`Done. ${appliedCount} new migration(s) applied. ${applied.size + appliedCount} total.`);
  } finally {
    client.release();
    await pool.end();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
