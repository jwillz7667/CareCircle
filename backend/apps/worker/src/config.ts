import { z } from 'zod';

const ConfigSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  LOG_LEVEL: z.string().default('info'),

  DATABASE_URL: z.string().min(1),
  REDIS_URL: z.string().min(1),

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

  APNS_KEY_ID: z.string().optional(),
  APNS_TEAM_ID: z.string().optional(),
  APNS_BUNDLE_ID: z.string().default('app.carecircle.ios'),
  APNS_PRIVATE_KEY: z.string().optional(),
  APNS_ENVIRONMENT: z.enum(['development', 'production']).default('development'),
  APNS_MOCK_MODE: z
    .union([z.string(), z.boolean()])
    .default(true)
    .transform((v) => v === true || v === 'true'),
  // OS-level critical alerts (interruption-level `critical` + `sound.critical`)
  // require Apple's Critical Alert entitlement on the app. Sending them without
  // it gets every push rejected with APNs 400. Until the entitlement is granted
  // (filed per docs/CRITICAL_ALERTS_APPLICATION.md) this stays false and SOS
  // pushes degrade to `time-sensitive` at priority 10 — still bypasses Focus.
  SOS_CRITICAL_ALERTS_ENABLED: z
    .union([z.string(), z.boolean()])
    .default(false)
    .transform((v) => v === true || v === 'true'),

  OPENFDA_API_KEY: z.string().optional(),
  OPENAI_API_KEY: z.string().optional(),

  PDF_BUCKET: z.string().default('cc-pdf-exports'),
});

export type Config = z.infer<typeof ConfigSchema>;

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const parsed = ConfigSchema.safeParse(env);
  if (!parsed.success) {
    const issues = parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('; ');
    throw new Error(`Invalid worker environment: ${issues}`);
  }
  return parsed.data;
}
