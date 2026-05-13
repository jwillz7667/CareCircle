/**
 * Test login helpers. Uses signMockAppleToken to produce a SiwA-shaped
 * token that the mock verifier accepts, then exchanges it via /v1/auth/apple
 * for an access + refresh pair.
 */
import './env.js';
import type { FastifyInstance } from 'fastify';
import { signMockAppleToken } from '../../src/services/apple.js';
import { loadConfig } from '../../src/config.js';

export type LoginResult = {
  userId: string;
  accessToken: string;
  refreshToken: string;
};

export async function loginAs(
  app: FastifyInstance,
  appleId: string,
  opts: { email?: string; givenName?: string; familyName?: string } = {},
): Promise<LoginResult> {
  const config = loadConfig();
  const identityToken = await signMockAppleToken(config, {
    sub: appleId,
    email: opts.email,
  });
  const res = await app.inject({
    method: 'POST',
    url: '/v1/auth/apple',
    payload: {
      identityToken,
      givenName: opts.givenName,
      familyName: opts.familyName,
    },
  });
  if (res.statusCode !== 200) {
    throw new Error(
      `loginAs(${appleId}) failed: ${res.statusCode} ${res.body}`,
    );
  }
  const body = JSON.parse(res.body) as {
    userId: string;
    accessToken: string;
    refreshToken: string;
  };
  return body;
}

export function bearer(token: string): { authorization: string } {
  return { authorization: `Bearer ${token}` };
}
