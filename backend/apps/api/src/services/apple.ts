import { createRemoteJWKSet, jwtVerify, SignJWT, importJWK, type JWK } from 'jose';
import { HttpError } from '@carecircle/shared';
import type { Config } from '../config.js';

export type AppleClaims = {
  sub: string;
  email?: string;
  emailVerified?: boolean;
  isPrivateEmail: boolean;
};

export interface AppleVerifier {
  verify(identityToken: string, expectedNonce?: string): Promise<AppleClaims>;
}

export function createRealAppleVerifier(config: Config): AppleVerifier {
  const jwks = createRemoteJWKSet(new URL(config.APPLE_JWKS_URL), {
    cooldownDuration: 60 * 60 * 1000,
    timeoutDuration: 5_000,
  });

  return {
    async verify(identityToken: string, expectedNonce?: string): Promise<AppleClaims> {
      let payload;
      try {
        const result = await jwtVerify(identityToken, jwks, {
          issuer: config.APPLE_ISSUER,
          audience: config.APPLE_CLIENT_ID,
        });
        payload = result.payload;
      } catch (err) {
        throw new HttpError(401, 'apple_jwt_invalid', 'Apple identity token verification failed', {
          reason: err instanceof Error ? err.message : 'unknown',
        });
      }

      if (typeof payload.sub !== 'string' || !payload.sub) {
        throw new HttpError(401, 'apple_jwt_invalid', 'Apple token missing sub');
      }

      if (expectedNonce && payload.nonce !== expectedNonce) {
        throw new HttpError(401, 'apple_jwt_invalid', 'Apple nonce mismatch');
      }

      return {
        sub: payload.sub,
        email: typeof payload.email === 'string' ? payload.email : undefined,
        emailVerified:
          typeof payload.email_verified === 'boolean'
            ? payload.email_verified
            : payload.email_verified === 'true',
        isPrivateEmail:
          typeof payload.is_private_email === 'boolean'
            ? payload.is_private_email
            : payload.is_private_email === 'true',
      };
    },
  };
}

/**
 * Mock verifier for local development and tests. Tokens are signed
 * symmetrically with APPLE_MOCK_SECRET, mirroring the real claim shape.
 */
export function createMockAppleVerifier(config: Config): AppleVerifier {
  const secret = config.APPLE_MOCK_SECRET ?? config.JWT_SECRET;
  const key = new TextEncoder().encode(secret);

  return {
    async verify(identityToken: string, expectedNonce?: string): Promise<AppleClaims> {
      let payload;
      try {
        const result = await jwtVerify(identityToken, key, {
          issuer: config.APPLE_ISSUER,
          audience: config.APPLE_CLIENT_ID,
        });
        payload = result.payload;
      } catch (err) {
        throw new HttpError(401, 'apple_jwt_invalid', 'Mock Apple token verification failed', {
          reason: err instanceof Error ? err.message : 'unknown',
        });
      }

      if (typeof payload.sub !== 'string' || !payload.sub) {
        throw new HttpError(401, 'apple_jwt_invalid', 'Mock Apple token missing sub');
      }
      if (expectedNonce && payload.nonce !== expectedNonce) {
        throw new HttpError(401, 'apple_jwt_invalid', 'Mock Apple nonce mismatch');
      }
      return {
        sub: payload.sub,
        email: typeof payload.email === 'string' ? payload.email : undefined,
        emailVerified:
          typeof payload.email_verified === 'boolean' ? payload.email_verified : true,
        isPrivateEmail:
          typeof payload.is_private_email === 'boolean' ? payload.is_private_email : false,
      };
    },
  };
}

export function createAppleVerifier(config: Config): AppleVerifier {
  return config.APPLE_VERIFIER_MODE === 'mock'
    ? createMockAppleVerifier(config)
    : createRealAppleVerifier(config);
}

/**
 * Helper for tests/seed: sign a token that the mock verifier accepts.
 */
export async function signMockAppleToken(
  config: Config,
  claims: {
    sub: string;
    email?: string;
    nonce?: string;
    isPrivateEmail?: boolean;
    emailVerified?: boolean;
  },
): Promise<string> {
  const secret = config.APPLE_MOCK_SECRET ?? config.JWT_SECRET;
  const key = new TextEncoder().encode(secret);
  const builder = new SignJWT({
    email: claims.email,
    email_verified: claims.emailVerified ?? true,
    is_private_email: claims.isPrivateEmail ?? false,
    nonce: claims.nonce,
  })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setIssuer(config.APPLE_ISSUER)
    .setAudience(config.APPLE_CLIENT_ID)
    .setSubject(claims.sub)
    .setExpirationTime('1h');
  return builder.sign(key);
}

export const _internal = { importJWK: importJWK as (jwk: JWK) => Promise<unknown> };
