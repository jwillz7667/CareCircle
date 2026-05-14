/**
 * Inference route: auth + happy path + disabled (503) + rate-limit (429).
 * Uses an injected stub service so the OpenAI client is never invoked.
 */
import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import pg from 'pg';
import { buildApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import type { InferenceService } from '../src/services/inference.js';
import { closeTestApp, getTestApp } from './helpers/app.js';
import { bearer, loginAs } from './helpers/auth.js';
import { insertUser, makePool, resetDb, type SeededUser } from './helpers/db.js';

function makeStub(opts: { isEnabled?: boolean } = {}): InferenceService {
  return {
    isEnabled: opts.isEnabled ?? true,
    model: 'stub-model',
    async extract({ redactedTranscript }) {
      const summary =
        redactedTranscript.length > 0
          ? `Summary for ${redactedTranscript.length} chars`
          : null;
      return {
        entities: {
          medications: [
            {
              id: randomUUID(),
              name: 'Lisinopril',
              details: '10mg morning',
              confidence: 'high' as const,
            },
          ],
          vitals: [],
          appointments: [],
          meals: [],
          symptoms: [],
          generalNotes: [],
          summary,
        },
        model: 'stub-model',
        durationMs: 4,
      };
    },
  };
}

async function buildEnabledApp(opts: {
  inference: InferenceService;
  maxPerHour?: number;
}): Promise<FastifyInstance> {
  process.env.INFERENCE_ENABLED = 'true';
  process.env.OPENAI_API_KEY = 'sk-test-stub';
  if (opts.maxPerHour !== undefined) {
    process.env.INFERENCE_MAX_PER_HOUR = String(opts.maxPerHour);
  } else {
    process.env.INFERENCE_MAX_PER_HOUR = '10000';
  }
  const config = loadConfig();
  const app = await buildApp({
    config,
    skipStartupTasks: true,
    overrides: { inference: opts.inference },
  });
  await app.ready();
  return app;
}

describe('POST /v1/inference/extract (disabled by default)', () => {
  let app: FastifyInstance;
  let pool: pg.Pool;
  let user: SeededUser;
  let token: string;

  beforeAll(async () => {
    app = await getTestApp();
    pool = makePool();
  });
  afterAll(async () => {
    await closeTestApp();
    await pool.end();
  });
  beforeEach(async () => {
    await resetDb(pool);
    user = await insertUser(pool, { appleId: 'mock|infer-disabled' });
    token = (await loginAs(app, user.appleId)).accessToken;
  });

  it('returns 401 without a bearer token', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/v1/inference/extract',
      payload: { redactedTranscript: 'test note' },
    });
    expect(res.statusCode).toBe(401);
  });

  it('returns 503 when inference is disabled', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/v1/inference/extract',
      headers: bearer(token),
      payload: { redactedTranscript: 'test note' },
    });
    expect(res.statusCode).toBe(503);
    const body = JSON.parse(res.body) as { error?: { code?: string } };
    expect(body.error?.code).toBe('service_unavailable');
  });
});

describe('POST /v1/inference/extract (enabled with stub)', () => {
  let app: FastifyInstance;
  let pool: pg.Pool;
  let user: SeededUser;
  let token: string;

  beforeAll(async () => {
    pool = makePool();
    app = await buildEnabledApp({ inference: makeStub() });
  });
  afterAll(async () => {
    await app.close();
    await pool.end();
    delete process.env.INFERENCE_ENABLED;
    delete process.env.OPENAI_API_KEY;
    delete process.env.INFERENCE_MAX_PER_HOUR;
  });
  beforeEach(async () => {
    await resetDb(pool);
    user = await insertUser(pool, { appleId: 'mock|infer-ok' });
    token = (await loginAs(app, user.appleId)).accessToken;
  });

  it('returns the ExtractedEntities shape with model identifier', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/v1/inference/extract',
      headers: bearer(token),
      payload: {
        redactedTranscript:
          '[RECIPIENT] took Lisinopril 10mg this morning. Mood is good.',
      },
    });
    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body) as {
      medications: Array<{ id: string; name: string; confidence: string }>;
      vitals: unknown[];
      appointments: unknown[];
      meals: unknown[];
      symptoms: unknown[];
      generalNotes: unknown[];
      summary: string | null;
      model: string;
    };
    expect(body.medications).toHaveLength(1);
    expect(body.medications[0]!.name).toBe('Lisinopril');
    expect(body.medications[0]!.id).toMatch(/^[0-9a-f-]{36}$/);
    expect(body.medications[0]!.confidence).toBe('high');
    expect(body.summary).toContain('Summary for');
    expect(body.model).toBe('stub-model');
  });

  it('rejects an empty transcript with 400 from Zod', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/v1/inference/extract',
      headers: bearer(token),
      payload: { redactedTranscript: '' },
    });
    expect(res.statusCode).toBe(400);
  });

  it('rejects a transcript longer than the schema limit', async () => {
    const huge = 'a'.repeat(8_001);
    const res = await app.inject({
      method: 'POST',
      url: '/v1/inference/extract',
      headers: bearer(token),
      payload: { redactedTranscript: huge },
    });
    expect(res.statusCode).toBe(400);
  });
});

describe('POST /v1/inference/extract rate limit', () => {
  let app: FastifyInstance;
  let pool: pg.Pool;
  let user: SeededUser;
  let token: string;

  beforeAll(async () => {
    pool = makePool();
    app = await buildEnabledApp({ inference: makeStub(), maxPerHour: 3 });
  });
  afterAll(async () => {
    await app.close();
    await pool.end();
    delete process.env.INFERENCE_ENABLED;
    delete process.env.OPENAI_API_KEY;
    delete process.env.INFERENCE_MAX_PER_HOUR;
  });
  beforeEach(async () => {
    await resetDb(pool);
    user = await insertUser(pool, { appleId: 'mock|infer-rl' });
    token = (await loginAs(app, user.appleId)).accessToken;
  });

  it('returns 429 once the per-user quota is exhausted', async () => {
    for (let i = 0; i < 3; i += 1) {
      const ok = await app.inject({
        method: 'POST',
        url: '/v1/inference/extract',
        headers: bearer(token),
        payload: { redactedTranscript: `call ${i}` },
      });
      expect(ok.statusCode).toBe(200);
    }
    const limited = await app.inject({
      method: 'POST',
      url: '/v1/inference/extract',
      headers: bearer(token),
      payload: { redactedTranscript: 'over' },
    });
    expect(limited.statusCode).toBe(429);
    const body = JSON.parse(limited.body) as { error?: { code?: string } };
    expect(body.error?.code).toBe('rate_limited');
  });
});

describe('POST /v1/inference/extract upstream failure', () => {
  let app: FastifyInstance;
  let pool: pg.Pool;
  let user: SeededUser;
  let token: string;

  beforeAll(async () => {
    pool = makePool();
    const failing: InferenceService = {
      isEnabled: true,
      model: 'stub-model',
      async extract() {
        const err = new Error('Upstream returned 502');
        (err as Error & { status?: number; code?: string }).status = 502;
        (err as Error & { status?: number; code?: string }).code = 'upstream_error';
        // Re-create a real HttpError so the error handler emits the proper code.
        const { upstreamError } = await import('@carecircle/shared');
        throw upstreamError('Upstream returned 502');
      },
    };
    app = await buildEnabledApp({ inference: failing });
  });
  afterAll(async () => {
    await app.close();
    await pool.end();
    delete process.env.INFERENCE_ENABLED;
    delete process.env.OPENAI_API_KEY;
    delete process.env.INFERENCE_MAX_PER_HOUR;
  });
  beforeEach(async () => {
    await resetDb(pool);
    user = await insertUser(pool, { appleId: 'mock|infer-upstream' });
    token = (await loginAs(app, user.appleId)).accessToken;
  });

  it('surfaces upstream errors as 502 upstream_error', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/v1/inference/extract',
      headers: bearer(token),
      payload: { redactedTranscript: 'hello' },
    });
    expect(res.statusCode).toBe(502);
    const body = JSON.parse(res.body) as { error?: { code?: string } };
    expect(body.error?.code).toBe('upstream_error');
  });
});
