import type { FastifyInstance } from 'fastify';
import { withRls } from '@carecircle/db';
import { emailLoginSchema, emailRegisterSchema, HttpError } from '@carecircle/shared';

export async function emailAuthRoutes(app: FastifyInstance): Promise<void> {
  const { pool, tokens, passwords, logger, config } = app.ctx;

  // Both endpoints are credential-stuffing / signup-abuse targets, so they
  // get the tighter AUTH_RATE_LIMIT_PER_MIN (10/min default in prod, 10000
  // in tests). Register gets half — signup floods are less common than
  // login floods, and we'd rather not throttle a real user retrying after
  // a transient 5xx.
  const loginMax = config.AUTH_RATE_LIMIT_PER_MIN;
  const registerMax = Math.max(1, Math.floor(config.AUTH_RATE_LIMIT_PER_MIN / 2));
  const registerLimit = {
    config: { rateLimit: { max: registerMax, timeWindow: '1 minute' } },
  };
  const loginLimit = {
    config: { rateLimit: { max: loginMax, timeWindow: '1 minute' } },
  };

  app.post('/v1/auth/register', registerLimit, async (req, reply) => {
    const body = emailRegisterSchema.parse(req.body);
    const passwordHash = await passwords.hash(body.password);

    const result = await withRls(pool, { role: 'app_service' }, async (client) => {
      // Reject if any account already uses this email — regardless of
      // which provider created it. Account linking is a follow-up
      // feature; for v1 we want a single email -> single account
      // invariant so users can never end up wondering which sign-in
      // method is "the right one."
      const existing = await client.query<{ id: string }>(
        `SELECT id FROM users WHERE email = $1 AND deleted_at IS NULL`,
        [body.email],
      );
      if (existing.rows[0]) {
        return { kind: 'conflict' as const };
      }
      const created = await client.query<{ id: string }>(
        `INSERT INTO users (email, password_hash, password_updated_at, display_name, is_private_email)
         VALUES ($1, $2, NOW(), $3, FALSE)
         RETURNING id`,
        [body.email, passwordHash, body.displayName ?? null],
      );
      return { kind: 'created' as const, userId: created.rows[0]!.id };
    });

    if (result.kind === 'conflict') {
      throw new HttpError(409, 'email_already_in_use', 'An account with this email already exists');
    }

    const access = await tokens.mintAccessToken(result.userId);
    const refresh = await tokens.issueRefreshToken(result.userId, pool, {
      userAgent: req.headers['user-agent'],
      ipAddress: req.ip,
    });

    logger.info({ userId: result.userId, ip: req.ip }, 'email registration');

    reply.status(201).send({
      accessToken: access.token,
      accessTokenExpiresAt: access.expiresAt,
      refreshToken: refresh.token,
      refreshTokenExpiresAt: refresh.expiresAt,
      userId: result.userId,
    });
  });

  app.post('/v1/auth/login', loginLimit, async (req, reply) => {
    const body = emailLoginSchema.parse(req.body);

    const lookup = await withRls(pool, { role: 'app_service' }, async (client) => {
      const result = await client.query<{ id: string; password_hash: string | null }>(
        `SELECT id, password_hash FROM users WHERE email = $1 AND deleted_at IS NULL`,
        [body.email],
      );
      return result.rows[0] ?? null;
    });

    // Always run a verify, even when the user doesn't exist, so the
    // response time doesn't reveal which emails have accounts.
    const ok = await passwords.verify(lookup?.password_hash, body.password);

    if (!ok || !lookup) {
      logger.warn({ email: body.email, ip: req.ip }, 'email login failed');
      throw new HttpError(401, 'invalid_credentials', 'Email or password incorrect');
    }

    const access = await tokens.mintAccessToken(lookup.id);
    const refresh = await tokens.issueRefreshToken(lookup.id, pool, {
      userAgent: req.headers['user-agent'],
      ipAddress: req.ip,
    });

    logger.info({ userId: lookup.id, ip: req.ip }, 'email login');

    reply.send({
      accessToken: access.token,
      accessTokenExpiresAt: access.expiresAt,
      refreshToken: refresh.token,
      refreshTokenExpiresAt: refresh.expiresAt,
      userId: lookup.id,
    });
  });
}
