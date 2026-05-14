/**
 * Test environment defaults — applied before any test imports config.
 * Real values come from process.env (.env or CI), these are just fallbacks
 * to make `vitest run` work in a fresh shell against the docker stack.
 */
const defaults: Record<string, string> = {
  NODE_ENV: 'test',
  LOG_LEVEL: 'error',
  HOST: '127.0.0.1',
  PORT: '3001',
  DATABASE_URL: 'postgres://carecircle:carecircle@localhost:5433/carecircle',
  DIRECT_DATABASE_URL: 'postgres://carecircle:carecircle@localhost:5433/carecircle',
  REDIS_URL: 'redis://localhost:6390',
  JWT_SECRET: 'test-jwt-secret-please-rotate-32-bytes-min',
  JWT_KID: 'test-v1',
  JWT_ISSUER: 'carecircle-test',
  JWT_AUDIENCE: 'carecircle.test',
  APPLE_CLIENT_ID: 'Res.CareCircle',
  APPLE_ISSUER: 'https://appleid.apple.com',
  APPLE_VERIFIER_MODE: 'mock',
  APPLE_MOCK_SECRET: 'test-mock-apple-secret-please-rotate-32',
  APP_MASTER_KEY: 'test-master-key-32-bytes-minimum-rotate',
  MINIO_ENDPOINT: 'localhost',
  MINIO_PORT: '9100',
  MINIO_USE_SSL: 'false',
  MINIO_ACCESS_KEY: 'carecircle-minio',
  MINIO_SECRET_KEY: 'carecircle-minio-secret-please-rotate',
  MINIO_REGION: 'us-east-1',
  RATE_LIMIT_PER_MIN: '10000',
  AUTH_RATE_LIMIT_PER_MIN: '10000',
  APNS_BUNDLE_ID: 'Res.CareCircle',
  APNS_MOCK_MODE: 'true',
  INFERENCE_ENABLED: 'false',
  INFERENCE_MAX_PER_HOUR: '10000',
  OPENAI_MODEL: 'gpt-4o-mini',
  OPENAI_BASE_URL: 'http://127.0.0.1:1/mock',
};
for (const [key, value] of Object.entries(defaults)) {
  if (!process.env[key]) {
    process.env[key] = value;
  }
}
