/**
 * POST /v1/inference/extract — PHI-redacted entity extraction for clients
 * on iOS < 26 where Foundation Models is unavailable. Returns the same
 * JSON shape the on-device extractor produces.
 *
 * Per-user fixed-window rate limit (default 30/hour) caps cost runaway.
 * The limiter is in-memory: correct for the single-instance Railway
 * deployment, swap to Redis when the API horizontally scales.
 */
import type { FastifyInstance } from 'fastify';
import {
  inferenceExtractSchema,
  rateLimited,
  serviceUnavailable,
} from '@carecircle/shared';

type Bucket = { count: number; resetAt: number };

export async function inferenceRoutes(app: FastifyInstance): Promise<void> {
  const { config, inference, logger } = app.ctx;
  const buckets = new Map<string, Bucket>();
  const windowMs = 60 * 60 * 1_000;

  function check(userId: string): void {
    const now = Date.now();
    const bucket = buckets.get(userId);
    if (!bucket || bucket.resetAt <= now) {
      buckets.set(userId, { count: 1, resetAt: now + windowMs });
      return;
    }
    if (bucket.count >= config.INFERENCE_MAX_PER_HOUR) {
      const retryAfter = Math.max(1, Math.ceil((bucket.resetAt - now) / 1_000));
      throw rateLimited(`Inference quota exceeded; retry in ${retryAfter}s`);
    }
    bucket.count += 1;
  }

  // Periodically sweep expired buckets so a flood of one-off users doesn't
  // leak memory. Fastify's onClose hook tears this down with the app.
  const sweepHandle = setInterval(() => {
    const now = Date.now();
    for (const [key, b] of buckets) {
      if (b.resetAt <= now) {
        buckets.delete(key);
      }
    }
  }, windowMs).unref();
  app.addHook('onClose', async () => {
    clearInterval(sweepHandle);
  });

  app.post('/v1/inference/extract', async (req, reply) => {
    const userId = await app.requireUser(req);
    if (!inference.isEnabled) {
      throw serviceUnavailable('Inference is currently disabled');
    }
    check(userId);

    const body = inferenceExtractSchema.parse(req.body);
    const result = await inference.extract({
      redactedTranscript: body.redactedTranscript,
      locale: body.locale,
    });

    logger.info(
      {
        userId,
        transcriptLength: body.redactedTranscript.length,
        durationMs: result.durationMs,
        model: result.model,
      },
      'inference.extract',
    );

    reply.send({
      ...result.entities,
      model: result.model,
    });
  });
}
