/**
 * Vitest global setup — runs once before the whole suite. Applies the SQL
 * migrations against the test database so a fresh Postgres (CI service
 * container or a locally-`docker compose up`'d stack) has the full schema
 * before any test connects. Idempotent: re-running against an already-migrated
 * database is a no-op, so this is safe alongside an explicit CI migrate step.
 */
import './env.js';
import { runMigrations } from '@carecircle/migrator/migrate';

export default async function globalSetup(): Promise<void> {
  const connectionString = process.env.DIRECT_DATABASE_URL ?? process.env.DATABASE_URL;
  if (!connectionString) {
    throw new Error('DATABASE_URL or DIRECT_DATABASE_URL is required to run the test suite.');
  }
  await runMigrations({ connectionString, log: false });
}
