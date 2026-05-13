import type { Config } from 'drizzle-kit';

export default {
  schema: './src/schema.ts',
  out: './migrations',
  dialect: 'postgresql',
  dbCredentials: {
    url: process.env.DATABASE_URL ?? 'postgres://carecircle:carecircle@localhost:5433/carecircle',
  },
  strict: true,
  verbose: true,
} satisfies Config;
