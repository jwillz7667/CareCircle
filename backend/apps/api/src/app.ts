import Fastify, { type FastifyInstance, type FastifyBaseLogger } from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import websocket from '@fastify/websocket';
import { createPool, createDb } from '@carecircle/db';
import { createLogger } from '@carecircle/shared';
import { loadConfig, type Config } from './config.js';
import { createAppleVerifier } from './services/apple.js';
import { createGoogleVerifier } from './services/google.js';
import { createPasswordService } from './services/passwords.js';
import { createTokenService } from './services/tokens.js';
import { createObjectStorage } from './services/minio.js';
import { createQueueClient } from './services/queues.js';
import { createRealtimeBroker } from './services/realtime.js';
import { createStoreKitService } from './services/storekit.js';
import { createInferenceService, type InferenceService } from './services/inference.js';
import { CircleKeyService } from './services/circleKeys.js';
import authPlugin from './plugins/auth.js';
import errorsPlugin from './plugins/errors.js';
import { healthRoutes } from './routes/health.js';
import { authRoutes } from './routes/auth.js';
import { emailAuthRoutes } from './routes/emailAuth.js';
import { googleAuthRoutes } from './routes/googleAuth.js';
import { meRoutes } from './routes/me.js';
import { circleRoutes } from './routes/circles.js';
import { recipientRoutes } from './routes/recipients.js';
import { memberRoutes } from './routes/members.js';
import { invitationRoutes } from './routes/invitations.js';
import { activityRoutes } from './routes/activities.js';
import { medicationRoutes } from './routes/medications.js';
import { appointmentRoutes } from './routes/appointments.js';
import { shiftRoutes } from './routes/shifts.js';
import { documentRoutes } from './routes/documents.js';
import { emergencyContactRoutes } from './routes/emergencyContacts.js';
import { sosRoutes } from './routes/sos.js';
import { careMinuteRoutes } from './routes/careMinutes.js';
import { syncRoutes } from './routes/sync.js';
import { realtimeRoutes } from './routes/realtime.js';
import { inferenceRoutes } from './routes/inference.js';
import { digestRoutes } from './routes/digests.js';
import { vitalRoutes } from './routes/vitals.js';
import { subscriptionRoutes } from './routes/subscriptions.js';
import type { AppContext } from './types.js';

export type BuildOptions = {
  config?: Config;
  skipStartupTasks?: boolean;
  overrides?: {
    inference?: InferenceService;
  };
};

export async function buildApp(opts: BuildOptions = {}): Promise<FastifyInstance> {
  const config = opts.config ?? loadConfig();
  const logger = createLogger({ level: config.LOG_LEVEL, name: 'carecircle-api' });
  const pool = createPool({ connectionString: config.DATABASE_URL, applicationName: 'cc-api' });
  // Eagerly bind the drizzle handle so consumers can grab it later if needed.
  createDb(pool);
  const apple = createAppleVerifier(config);
  const google = createGoogleVerifier(config);
  const passwords = createPasswordService();
  const tokens = createTokenService(config);
  const storage = createObjectStorage(config);
  const realtime = createRealtimeBroker(config, logger);
  const circleKeys = new CircleKeyService(pool, config);
  const queues = createQueueClient(config);
  const inference = opts.overrides?.inference ?? createInferenceService(config, logger);
  const storekit = createStoreKitService(config);
  const ctx: AppContext = {
    config,
    pool,
    logger,
    apple,
    google,
    passwords,
    tokens,
    storage,
    realtime,
    circleKeys,
    queues,
    inference,
    storekit,
  };

  const app = Fastify({
    // pino's standalone `Logger` type requires `msgPrefix`, which Fastify's
    // `FastifyBaseLogger` omits; passing the logger at Fastify's expected type
    // keeps `buildApp` returning the default-generic `FastifyInstance` instead
    // of widening every route's logger param and breaking assignability.
    loggerInstance: logger as unknown as FastifyBaseLogger,
    disableRequestLogging: config.NODE_ENV === 'test',
    trustProxy: true,
    bodyLimit: 5 * 1024 * 1024,
    pluginTimeout: 30_000,
  });
  app.decorate('ctx', ctx);

  await app.register(helmet, { contentSecurityPolicy: false });
  await app.register(cors, {
    origin: false,
    credentials: false,
  });
  await app.register(rateLimit, {
    max: config.RATE_LIMIT_PER_MIN,
    timeWindow: '1 minute',
    keyGenerator: (req) => req.auth?.userId ?? req.ip,
  });
  await app.register(websocket);
  await app.register(errorsPlugin);
  await app.register(authPlugin, { tokenService: tokens });

  await app.register(async (instance) => {
    await healthRoutes(instance);
    await authRoutes(instance);
    await emailAuthRoutes(instance);
    await googleAuthRoutes(instance);
    await meRoutes(instance);
    await circleRoutes(instance);
    await recipientRoutes(instance);
    await memberRoutes(instance);
    await invitationRoutes(instance);
    await activityRoutes(instance);
    await medicationRoutes(instance);
    await appointmentRoutes(instance);
    await shiftRoutes(instance);
    await documentRoutes(instance);
    await emergencyContactRoutes(instance);
    await sosRoutes(instance);
    await careMinuteRoutes(instance);
    await syncRoutes(instance);
    await realtimeRoutes(instance);
    await inferenceRoutes(instance);
    await digestRoutes(instance);
    await vitalRoutes(instance);
    await subscriptionRoutes(instance);
  });

  if (!opts.skipStartupTasks) {
    app.addHook('onReady', async () => {
      // Fire MinIO bucket setup in the background — a slow private-DNS
      // resolution or an unreachable MinIO must not block API startup
      // past Fastify's onReady timeout (default 10s).
      void storage
        .ensureBuckets()
        .catch((err) => logger.warn({ err }, 'failed to ensure MinIO buckets — continuing'));
      // Realtime LISTEN connection is fast; await it so we surface DB issues.
      await realtime.start();
    });
  }

  app.addHook('onClose', async () => {
    await realtime.stop();
    await queues.close();
    await pool.end();
  });

  return app;
}
