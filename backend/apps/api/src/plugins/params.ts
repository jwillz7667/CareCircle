import type { FastifyInstance, FastifyRequest } from 'fastify';
import fp from 'fastify-plugin';
import { HttpError } from '@carecircle/shared';

// Route params that are always UUIDs across the API. A malformed value here
// would otherwise reach a `WHERE id = $1::uuid` query and surface as a
// Postgres `invalid input syntax for type uuid` → 500 + error-log spam.
// Validating once in a global hook turns those into a clean 400 without
// touching every individual route's `req.params as { ... }` cast.
//
// `code` (invitation redemption code) and `emoji` (reaction key) are NOT
// UUIDs and are intentionally excluded.
const UUID_PARAM_KEYS = ['id', 'circleId', 'memberId', 'deviceId', 'linkId'] as const;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function paramsPlugin(app: FastifyInstance): Promise<void> {
  app.addHook('preValidation', async (req: FastifyRequest) => {
    const params = req.params as Record<string, unknown> | undefined;
    if (!params) {
      return;
    }
    for (const key of UUID_PARAM_KEYS) {
      const value = params[key];
      if (typeof value === 'string' && !UUID_RE.test(value)) {
        throw new HttpError(400, 'validation_failed', `Invalid ${key}: expected a UUID`, {
          param: key,
        });
      }
    }
  });
}

export default fp(paramsPlugin, { name: 'cc-params' });
