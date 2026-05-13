import type { FastifyInstance, FastifyRequest } from 'fastify';
import fp from 'fastify-plugin';
import { unauthorized } from '@carecircle/shared';
import type { TokenService } from '../services/tokens.js';

declare module 'fastify' {
  interface FastifyRequest {
    auth?: { userId: string };
  }
}

export type AuthOptions = {
  tokenService: TokenService;
};

async function authPlugin(app: FastifyInstance, opts: AuthOptions): Promise<void> {
  const { tokenService } = opts;

  app.decorate('requireUser', async (req: FastifyRequest) => {
    if (req.auth?.userId) {
      return req.auth.userId;
    }
    const header = req.headers.authorization;
    if (!header || !header.toLowerCase().startsWith('bearer ')) {
      throw unauthorized('Missing bearer token');
    }
    const token = header.slice(7).trim();
    if (!token) {
      throw unauthorized('Empty bearer token');
    }
    const claims = await tokenService.verifyAccessToken(token);
    req.auth = { userId: claims.sub };
    return claims.sub;
  });
}

export default fp(authPlugin, { name: 'cc-auth' });

declare module 'fastify' {
  interface FastifyInstance {
    requireUser: (req: FastifyRequest) => Promise<string>;
  }
}
