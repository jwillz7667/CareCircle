import { randomBytes } from 'node:crypto';
import { SignJWT, jwtVerify } from 'jose';
import { hashTokenSHA256, HttpError } from '@carecircle/shared';
import { withRls } from '@carecircle/db';
import type pg from 'pg';
import type { Config } from '../config.js';

export type AccessPayload = {
  sub: string;
  iat: number;
  exp: number;
};

export type TokenPair = {
  accessToken: string;
  refreshToken: string;
  accessExpiresAt: number;
  refreshExpiresAt: number;
};

export type TokenService = {
  mintAccessToken(userId: string): Promise<{ token: string; expiresAt: number }>;
  verifyAccessToken(token: string): Promise<AccessPayload>;
  issueRefreshToken(
    userId: string,
    pool: pg.Pool,
    meta?: { userAgent?: string; ipAddress?: string; rotatedFrom?: string | null },
  ): Promise<{ token: string; expiresAt: number; id: string }>;
  rotateRefreshToken(
    rawRefreshToken: string,
    pool: pg.Pool,
    meta?: { userAgent?: string; ipAddress?: string },
  ): Promise<{ userId: string; pair: TokenPair }>;
  revokeRefreshToken(rawRefreshToken: string, pool: pg.Pool): Promise<void>;
  revokeAllForUser(userId: string, pool: pg.Pool): Promise<void>;
};

export function createTokenService(config: Config): TokenService {
  const secretKey = new TextEncoder().encode(config.JWT_SECRET);

  async function mintAccessToken(userId: string): Promise<{ token: string; expiresAt: number }> {
    const now = Math.floor(Date.now() / 1000);
    const expiresAt = now + config.ACCESS_TOKEN_TTL_SECONDS;
    const token = await new SignJWT({})
      .setProtectedHeader({ alg: 'HS256', kid: config.JWT_KID })
      .setIssuer(config.JWT_ISSUER)
      .setAudience(config.JWT_AUDIENCE)
      .setSubject(userId)
      .setIssuedAt(now)
      .setExpirationTime(expiresAt)
      .sign(secretKey);
    return { token, expiresAt };
  }

  async function verifyAccessToken(token: string): Promise<AccessPayload> {
    try {
      const { payload } = await jwtVerify(token, secretKey, {
        issuer: config.JWT_ISSUER,
        audience: config.JWT_AUDIENCE,
      });
      if (typeof payload.sub !== 'string' || typeof payload.exp !== 'number' || typeof payload.iat !== 'number') {
        throw new HttpError(401, 'unauthorized', 'Invalid access token claims');
      }
      return { sub: payload.sub, iat: payload.iat, exp: payload.exp };
    } catch (err) {
      if (err instanceof HttpError) {
        throw err;
      }
      throw new HttpError(401, 'unauthorized', 'Invalid access token', {
        reason: err instanceof Error ? err.message : 'unknown',
      });
    }
  }

  async function issueRefreshToken(
    userId: string,
    pool: pg.Pool,
    meta?: { userAgent?: string; ipAddress?: string; rotatedFrom?: string | null },
  ): Promise<{ token: string; expiresAt: number; id: string }> {
    const raw = randomBytes(48).toString('base64url');
    const hash = hashTokenSHA256(raw);
    const expiresAt = new Date(Date.now() + config.REFRESH_TOKEN_TTL_SECONDS * 1000);

    return await withRls(pool, { role: 'app_service' }, async (client) => {
      const result = await client.query<{ id: string }>(
        `INSERT INTO refresh_tokens (user_id, token_hash, expires_at, rotated_from, user_agent, ip_address)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING id`,
        [userId, hash, expiresAt, meta?.rotatedFrom ?? null, meta?.userAgent ?? null, meta?.ipAddress ?? null],
      );
      return {
        token: raw,
        expiresAt: Math.floor(expiresAt.getTime() / 1000),
        id: result.rows[0]!.id,
      };
    });
  }

  async function rotateRefreshToken(
    rawRefreshToken: string,
    pool: pg.Pool,
    meta?: { userAgent?: string; ipAddress?: string },
  ): Promise<{ userId: string; pair: TokenPair }> {
    const hash = hashTokenSHA256(rawRefreshToken);
    return await withRls(pool, { role: 'app_service' }, async (client) => {
      const row = await client.query<{
        id: string;
        user_id: string;
        expires_at: Date;
        revoked_at: Date | null;
      }>(
        `SELECT id, user_id, expires_at, revoked_at
         FROM refresh_tokens
         WHERE token_hash = $1
         FOR UPDATE`,
        [hash],
      );
      const tokenRow = row.rows[0];
      if (!tokenRow) {
        throw new HttpError(401, 'unauthorized', 'Refresh token unknown');
      }
      if (tokenRow.revoked_at) {
        // Reuse of revoked token: kill the whole user session for safety.
        await client.query(
          `UPDATE refresh_tokens SET revoked_at = NOW()
           WHERE user_id = $1 AND revoked_at IS NULL`,
          [tokenRow.user_id],
        );
        throw new HttpError(401, 'unauthorized', 'Refresh token reuse detected');
      }
      if (tokenRow.expires_at.getTime() < Date.now()) {
        throw new HttpError(401, 'unauthorized', 'Refresh token expired');
      }

      // Mark this token revoked, issue a new one rotated from it.
      await client.query(
        `UPDATE refresh_tokens SET revoked_at = NOW(), last_used_at = NOW() WHERE id = $1`,
        [tokenRow.id],
      );

      const access = await mintAccessToken(tokenRow.user_id);
      const newRaw = randomBytes(48).toString('base64url');
      const newHash = hashTokenSHA256(newRaw);
      const newExpiresAt = new Date(Date.now() + config.REFRESH_TOKEN_TTL_SECONDS * 1000);
      await client.query(
        `INSERT INTO refresh_tokens (user_id, token_hash, expires_at, rotated_from, user_agent, ip_address)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [
          tokenRow.user_id,
          newHash,
          newExpiresAt,
          tokenRow.id,
          meta?.userAgent ?? null,
          meta?.ipAddress ?? null,
        ],
      );

      return {
        userId: tokenRow.user_id,
        pair: {
          accessToken: access.token,
          refreshToken: newRaw,
          accessExpiresAt: access.expiresAt,
          refreshExpiresAt: Math.floor(newExpiresAt.getTime() / 1000),
        },
      };
    });
  }

  async function revokeRefreshToken(rawRefreshToken: string, pool: pg.Pool): Promise<void> {
    const hash = hashTokenSHA256(rawRefreshToken);
    await withRls(pool, { role: 'app_service' }, async (client) => {
      await client.query(
        `UPDATE refresh_tokens SET revoked_at = NOW() WHERE token_hash = $1 AND revoked_at IS NULL`,
        [hash],
      );
    });
  }

  async function revokeAllForUser(userId: string, pool: pg.Pool): Promise<void> {
    await withRls(pool, { role: 'app_service' }, async (client) => {
      await client.query(
        `UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = $1 AND revoked_at IS NULL`,
        [userId],
      );
    });
  }

  return {
    mintAccessToken,
    verifyAccessToken,
    issueRefreshToken,
    rotateRefreshToken,
    revokeRefreshToken,
    revokeAllForUser,
  };
}

export async function countActiveRefreshTokens(pool: pg.Pool, userId: string): Promise<number> {
  return await withRls(pool, { role: 'app_service' }, async (client) => {
    const result = await client.query<{ n: string }>(
      `SELECT COUNT(*)::TEXT AS n FROM refresh_tokens WHERE user_id = $1 AND revoked_at IS NULL`,
      [userId],
    );
    return Number(result.rows[0]?.n ?? '0');
  });
}
