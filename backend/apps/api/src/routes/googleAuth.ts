import type { FastifyInstance } from 'fastify';
import { withRls } from '@carecircle/db';
import { googleAuthSchema, HttpError } from '@carecircle/shared';

export async function googleAuthRoutes(app: FastifyInstance): Promise<void> {
  const { pool, google, tokens, logger, config } = app.ctx;

  const googleLimit = {
    config: {
      rateLimit: { max: config.AUTH_RATE_LIMIT_PER_MIN, timeWindow: '1 minute' },
    },
  };

  app.post('/v1/auth/google', googleLimit, async (req, reply) => {
    const body = googleAuthSchema.parse(req.body);
    const claims = await google.verify(body.idToken);

    // Google's `sub` is the stable cross-session identifier. We refuse
    // to issue a CareCircle session if the email is unverified — Google
    // does this for accounts in flux (e.g. password resets in progress)
    // and we'd rather the user retry than risk attaching the wrong
    // person to an existing email-auth account.
    if (claims.email && !claims.emailVerified) {
      throw new HttpError(401, 'google_email_unverified', 'Google email is not yet verified');
    }

    const result = await withRls(pool, { role: 'app_service' }, async (client) => {
      const existing = await client.query<{ id: string; email: string | null }>(
        `SELECT id, email FROM users WHERE google_user_id = $1 AND deleted_at IS NULL`,
        [claims.sub],
      );
      if (existing.rows[0]) {
        // Keep email + display name fresh on each sign-in.
        if (claims.email || claims.name) {
          await client.query(
            `UPDATE users
             SET email = COALESCE($2, email),
                 display_name = COALESCE(display_name, $3),
                 updated_at = NOW()
             WHERE id = $1`,
            [
              existing.rows[0].id,
              claims.email ?? null,
              claims.name ?? buildDisplayName(claims.givenName, claims.familyName),
            ],
          );
        }
        return { kind: 'existing' as const, userId: existing.rows[0].id };
      }

      // Collision check: same email already attached to a different
      // provider (Apple or email/password). Reject so a stolen Google
      // session can't hijack an account that signed up another way.
      if (claims.email) {
        const collision = await client.query<{ id: string }>(
          `SELECT id FROM users WHERE email = $1 AND deleted_at IS NULL`,
          [claims.email],
        );
        if (collision.rows[0]) {
          return { kind: 'collision' as const };
        }
      }

      const displayName =
        claims.name ??
        buildDisplayName(body.givenName ?? claims.givenName, body.familyName ?? claims.familyName);
      const created = await client.query<{ id: string }>(
        `INSERT INTO users (google_user_id, email, display_name, is_private_email)
         VALUES ($1, $2, $3, FALSE)
         RETURNING id`,
        [claims.sub, claims.email ?? null, displayName],
      );
      return { kind: 'created' as const, userId: created.rows[0]!.id };
    });

    if (result.kind === 'collision') {
      throw new HttpError(
        409,
        'email_provider_conflict',
        'An account with this email already exists with a different sign-in method',
      );
    }

    const access = await tokens.mintAccessToken(result.userId);
    const refresh = await tokens.issueRefreshToken(result.userId, pool, {
      userAgent: req.headers['user-agent'],
      ipAddress: req.ip,
    });

    logger.info(
      { userId: result.userId, kind: result.kind, ip: req.ip },
      'google sign-in',
    );

    reply.send({
      accessToken: access.token,
      accessTokenExpiresAt: access.expiresAt,
      refreshToken: refresh.token,
      refreshTokenExpiresAt: refresh.expiresAt,
      userId: result.userId,
    });
  });

  // Non-prod helper: mint a mock Google token the verifier accepts.
  // Mirrors `/v1/auth/_mock-token` for Apple.
  app.post('/v1/auth/_mock-google-token', async (req, reply) => {
    if (app.ctx.config.NODE_ENV === 'production') {
      throw new HttpError(404, 'not_found', 'Not found');
    }
    const z = (await import('zod')).z;
    const schema = z.object({
      sub: z.string().min(1),
      email: z.string().email().optional(),
      name: z.string().optional(),
      audience: z.string().optional(),
    });
    const body = schema.parse(req.body);
    const { signMockGoogleToken } = await import('../services/google.js');
    const token = await signMockGoogleToken(app.ctx.config, body);
    reply.send({ idToken: token });
  });
}

function buildDisplayName(given: string | undefined, family: string | undefined): string | null {
  const parts = [given, family].filter((p): p is string => Boolean(p && p.trim().length));
  if (parts.length === 0) return null;
  return parts.join(' ');
}
