import type pg from 'pg';
import type { Logger } from '@carecircle/shared';
import type { Config } from './config.js';
import type { AppleVerifier } from './services/apple.js';
import type { CircleKeyService } from './services/circleKeys.js';
import type { InferenceService } from './services/inference.js';
import type { ObjectStorage } from './services/minio.js';
import type { QueueClient } from './services/queues.js';
import type { RealtimeBroker } from './services/realtime.js';
import type { TokenService } from './services/tokens.js';

export type AppContext = {
  config: Config;
  pool: pg.Pool;
  logger: Logger;
  apple: AppleVerifier;
  tokens: TokenService;
  storage: ObjectStorage;
  realtime: RealtimeBroker;
  circleKeys: CircleKeyService;
  queues: QueueClient;
  inference: InferenceService;
};

declare module 'fastify' {
  interface FastifyInstance {
    ctx: AppContext;
  }
}
