import type { FastifyInstance } from 'fastify';
import { withRls } from '@carecircle/db';
import { appleAuthSchema, refreshAuthSchema, HttpError } from '@carecircle/shared';

export async function authRoutes(app: FastifyInstance): Promise<void> {
  const { pool, apple, tokens, logger } = app.ctx;

  app.post('/v1/auth/apple', async (req, reply) => {
    const body = appleAuthSchema.parse(req.body);
    const claims = await apple.verify(body.identityToken, body.nonce);

    const userId = await withRls(pool, { role: 'app_service' }, async (client) => {
      const existing = await client.query<{ id: string }>(
        `SELECT id FROM users WHERE apple_user_id = $1`,
        [claims.sub],
      );
      if (existing.rows[0]) {
        if (claims.email) {
          await client.query(
            `UPDATE users
             SET email = COALESCE(email, $2),
                 is_private_email = $3,
                 updated_at = NOW()
             WHERE id = $1`,
            [existing.rows[0].id, claims.email, claims.isPrivateEmail],
          );
        }
        return existing.rows[0].id;
      }
      const displayName = body.givenName
        ? `${body.givenName}${body.familyName ? ' ' + body.familyName : ''}`
        : null;
      const created = await client.query<{ id: string }>(
        `INSERT INTO users (apple_user_id, email, is_private_email, display_name)
         VALUES ($1, $2, $3, $4)
         RETURNING id`,
        [claims.sub, claims.email ?? null, claims.isPrivateEmail, displayName],
      );
      return created.rows[0]!.id;
    });

    const access = await tokens.mintAccessToken(userId);
    const refresh = await tokens.issueRefreshToken(userId, pool, {
      userAgent: req.headers['user-agent'],
      ipAddress: req.ip,
    });

    reply.send({
      accessToken: access.token,
      accessTokenExpiresAt: access.expiresAt,
      refreshToken: refresh.token,
      refreshTokenExpiresAt: refresh.expiresAt,
      userId,
    });
  });

  app.post('/v1/auth/refresh', async (req, reply) => {
    const body = refreshAuthSchema.parse(req.body);
    const { pair } = await tokens.rotateRefreshToken(body.refreshToken, pool, {
      userAgent: req.headers['user-agent'],
      ipAddress: req.ip,
    });
    reply.send({
      accessToken: pair.accessToken,
      accessTokenExpiresAt: pair.accessExpiresAt,
      refreshToken: pair.refreshToken,
      refreshTokenExpiresAt: pair.refreshExpiresAt,
    });
  });

  app.post('/v1/auth/logout', async (req, reply) => {
    const body = refreshAuthSchema.safeParse(req.body);
    if (body.success) {
      await tokens.revokeRefreshToken(body.data.refreshToken, pool);
    } else {
      logger.warn({ issues: body.error.issues }, 'logout called without valid body');
    }
    reply.status(204).send();
  });

  // Internal: exposed in non-prod for testing the SiwA verifier path with a mock token.
  app.post('/v1/auth/_mock-token', async (req, reply) => {
    if (app.ctx.config.NODE_ENV === 'production') {
      throw new HttpError(404, 'not_found', 'Not found');
    }
    const schema = (await import('zod')).z.object({
      sub: (await import('zod')).z.string().min(1),
      email: (await import('zod')).z.string().email().optional(),
      nonce: (await import('zod')).z.string().optional(),
    });
    const body = schema.parse(req.body);
    const { signMockAppleToken } = await import('../services/apple.js');
    const token = await signMockAppleToken(app.ctx.config, {
      sub: body.sub,
      email: body.email,
      nonce: body.nonce,
    });
    reply.send({ identityToken: token });
  });
}
