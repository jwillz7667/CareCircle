import { z } from 'zod';

const ConfigSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().min(1).max(65_535).default(3000),
  HOST: z.string().default('0.0.0.0'),
  LOG_LEVEL: z.string().default('info'),

  DATABASE_URL: z.string().min(1),
  DIRECT_DATABASE_URL: z.string().optional(),
  REDIS_URL: z.string().min(1),

  JWT_SECRET: z.string().min(32),
  JWT_KID: z.string().default('v1'),
  JWT_ISSUER: z.string().default('carecircle.app'),
  JWT_AUDIENCE: z.string().default('carecircle.ios'),
  ACCESS_TOKEN_TTL_SECONDS: z.coerce.number().int().min(60).default(15 * 60),
  REFRESH_TOKEN_TTL_SECONDS: z.coerce.number().int().min(3600).default(30 * 24 * 3600),

  APPLE_CLIENT_ID: z.string().default('app.carecircle.ios'),
  APPLE_ISSUER: z.string().default('https://appleid.apple.com'),
  APPLE_JWKS_URL: z.string().url().default('https://appleid.apple.com/auth/keys'),
  APPLE_VERIFIER_MODE: z.enum(['real', 'mock']).default('real'),
  APPLE_MOCK_SECRET: z.string().optional(),

  APP_MASTER_KEY: z.string().min(32),

  MINIO_ENDPOINT: z.string().default('localhost'),
  MINIO_PORT: z.coerce.number().int().default(9000),
  MINIO_USE_SSL: z
    .union([z.string(), z.boolean()])
    .default(false)
    .transform((v) => v === true || v === 'true'),
  MINIO_ACCESS_KEY: z.string().min(1),
  MINIO_SECRET_KEY: z.string().min(1),
  MINIO_REGION: z.string().default('us-east-1'),
  MINIO_PUBLIC_HOST: z.string().optional(),

  RATE_LIMIT_PER_MIN: z.coerce.number().int().default(100),
  AUTH_RATE_LIMIT_PER_MIN: z.coerce.number().int().default(10),

  INFERENCE_ENABLED: z
    .union([z.string(), z.boolean()])
    .default(false)
    .transform((v) => v === true || v === 'true'),
  INFERENCE_MAX_PER_HOUR: z.coerce.number().int().min(1).default(30),
  INFERENCE_PROMPT_CHAR_LIMIT: z.coerce.number().int().min(1).max(20_000).default(8_000),
  INFERENCE_TIMEOUT_MS: z.coerce.number().int().min(1_000).max(60_000).default(20_000),
  OPENAI_API_KEY: z.string().min(1).optional(),
  OPENAI_MODEL: z.string().min(1).default('gpt-4o-mini'),
  OPENAI_BASE_URL: z.string().url().default('https://api.openai.com/v1'),
});

export type Config = z.infer<typeof ConfigSchema>;

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const parsed = ConfigSchema.safeParse(env);
  if (!parsed.success) {
    const issues = parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('; ');
    throw new Error(`Invalid environment: ${issues}`);
  }
  return parsed.data;
}
