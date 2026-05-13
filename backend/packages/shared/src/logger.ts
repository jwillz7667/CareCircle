import pino, { type Logger } from 'pino';

export type { Logger };

const PHI_KEYS = new Set([
  'first_name',
  'last_name',
  'firstNameEnc',
  'lastNameEnc',
  'date_of_birth',
  'dateOfBirthEnc',
  'name_enc',
  'phone_enc',
  'content_enc',
  'notes_enc',
  'transcript',
  'photo_object_keys',
  'voice_object_key',
  'visit_summary_enc',
  'prep_notes_enc',
  'resolution_notes_enc',
  'email',
  'phone',
  'apns_token',
  'identityToken',
  'refresh_token',
  'access_token',
  'authorization',
  'apple_private_key',
  'apns_private_key',
  'app_master_key',
  'jwt_secret',
]);

export function createLogger(opts: { level?: string; name?: string } = {}): Logger {
  const level = opts.level ?? process.env.LOG_LEVEL ?? 'info';
  return pino({
    name: opts.name ?? 'carecircle',
    level,
    redact: {
      paths: Array.from(PHI_KEYS).flatMap((key) => [key, `*.${key}`, `*.*.${key}`]),
      remove: false,
      censor: '[REDACTED]',
    },
    timestamp: pino.stdTimeFunctions.isoTime,
    formatters: {
      level: (label) => ({ level: label }),
    },
  });
}
