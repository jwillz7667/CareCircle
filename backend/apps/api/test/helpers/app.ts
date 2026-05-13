/**
 * Shared Fastify app for in-process integration tests. We build once per
 * vitest worker; closing happens in afterAll. skipStartupTasks=true skips
 * pg-listen + MinIO bucket ensure (the realtime tests opt in explicitly).
 */
import './env.js';
import type { FastifyInstance } from 'fastify';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';

let cached: FastifyInstance | null = null;

export async function getTestApp(): Promise<FastifyInstance> {
  if (cached) {
    return cached;
  }
  const config = loadConfig();
  const app = await buildApp({ config, skipStartupTasks: true });
  await app.ready();
  cached = app;
  return app;
}

export async function closeTestApp(): Promise<void> {
  if (cached) {
    await cached.close();
    cached = null;
  }
}
