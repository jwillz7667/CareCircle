import { createRemoteJWKSet, jwtVerify, SignJWT } from 'jose';
import { HttpError } from '@carecircle/shared';
import type { Config } from '../config.js';

// Google ID-token claim shape (the subset we care about). Google
// guarantees `sub` (a stable per-app numeric string) and signs every
// token issued to a known client_id.
export type GoogleClaims = {
  sub: string;
  email?: string;
  emailVerified: boolean;
  name?: string;
  givenName?: string;
  familyName?: string;
};

export interface GoogleVerifier {
  verify(idToken: string): Promise<GoogleClaims>;
}

// Google rotates JWKS keys daily; the URL is stable.
const GOOGLE_JWKS_URL = 'https://www.googleapis.com/oauth2/v3/certs';
const GOOGLE_ISSUERS = new Set(['https://accounts.google.com', 'accounts.google.com']);

export function createRealGoogleVerifier(config: Config): GoogleVerifier {
  const jwks = createRemoteJWKSet(new URL(GOOGLE_JWKS_URL), {
    cooldownDuration: 60 * 60 * 1000,
    timeoutDuration: 5_000,
  });

  return {
    async verify(idToken: string): Promise<GoogleClaims> {
      let payload;
      try {
        const result = await jwtVerify(idToken, jwks, {
          audience: config.GOOGLE_CLIENT_IDS,
        });
        payload = result.payload;
      } catch (err) {
        throw new HttpError(401, 'google_jwt_invalid', 'Google identity token verification failed', {
          reason: err instanceof Error ? err.message : 'unknown',
        });
      }

      if (typeof payload.iss !== 'string' || !GOOGLE_ISSUERS.has(payload.iss)) {
        throw new HttpError(401, 'google_jwt_invalid', 'Google token issuer mismatch');
      }
      if (typeof payload.sub !== 'string' || !payload.sub) {
        throw new HttpError(401, 'google_jwt_invalid', 'Google token missing sub');
      }

      return {
        sub: payload.sub,
        email: typeof payload.email === 'string' ? payload.email : undefined,
        emailVerified: payload.email_verified === true || payload.email_verified === 'true',
        name: typeof payload.name === 'string' ? payload.name : undefined,
        givenName: typeof payload.given_name === 'string' ? payload.given_name : undefined,
        familyName: typeof payload.family_name === 'string' ? payload.family_name : undefined,
      };
    },
  };
}

// Symmetric-key mock verifier for dev/test — mirrors the Apple pattern.
// The mock audience is whichever client ID is configured first.
export function createMockGoogleVerifier(config: Config): GoogleVerifier {
  const secret = config.GOOGLE_MOCK_SECRET ?? config.JWT_SECRET;
  const key = new TextEncoder().encode(secret);

  return {
    async verify(idToken: string): Promise<GoogleClaims> {
      let payload;
      try {
        const result = await jwtVerify(idToken, key, {
          audience: config.GOOGLE_CLIENT_IDS,
        });
        payload = result.payload;
      } catch (err) {
        throw new HttpError(401, 'google_jwt_invalid', 'Mock Google token verification failed', {
          reason: err instanceof Error ? err.message : 'unknown',
        });
      }

      if (typeof payload.iss !== 'string' || !GOOGLE_ISSUERS.has(payload.iss)) {
        throw new HttpError(401, 'google_jwt_invalid', 'Mock Google token issuer mismatch');
      }
      if (typeof payload.sub !== 'string' || !payload.sub) {
        throw new HttpError(401, 'google_jwt_invalid', 'Mock Google token missing sub');
      }

      return {
        sub: payload.sub,
        email: typeof payload.email === 'string' ? payload.email : undefined,
        emailVerified: payload.email_verified === true || payload.email_verified === 'true',
        name: typeof payload.name === 'string' ? payload.name : undefined,
        givenName: typeof payload.given_name === 'string' ? payload.given_name : undefined,
        familyName: typeof payload.family_name === 'string' ? payload.family_name : undefined,
      };
    },
  };
}

export function createGoogleVerifier(config: Config): GoogleVerifier {
  return config.GOOGLE_VERIFIER_MODE === 'mock'
    ? createMockGoogleVerifier(config)
    : createRealGoogleVerifier(config);
}

/**
 * Helper for tests/seed: sign a token the mock verifier accepts.
 */
export async function signMockGoogleToken(
  config: Config,
  claims: {
    sub: string;
    email?: string;
    name?: string;
    givenName?: string;
    familyName?: string;
    emailVerified?: boolean;
    audience?: string;
  },
): Promise<string> {
  const secret = config.GOOGLE_MOCK_SECRET ?? config.JWT_SECRET;
  const key = new TextEncoder().encode(secret);
  const audience = claims.audience ?? config.GOOGLE_CLIENT_IDS[0] ?? 'carecircle.google.ios';
  const builder = new SignJWT({
    email: claims.email,
    email_verified: claims.emailVerified ?? true,
    name: claims.name,
    given_name: claims.givenName,
    family_name: claims.familyName,
  })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setIssuer('https://accounts.google.com')
    .setAudience(audience)
    .setSubject(claims.sub)
    .setExpirationTime('1h');
  return builder.sign(key);
}
