import type { FastifyInstance, FastifyError } from 'fastify';
import fp from 'fastify-plugin';
import { HttpError } from '@carecircle/shared';
import { ZodError } from 'zod';

async function errorsPlugin(app: FastifyInstance): Promise<void> {
  app.setErrorHandler((err: FastifyError, _req, reply) => {
    if (err instanceof HttpError) {
      reply.status(err.status).send({
        error: { code: err.code, message: err.message, details: err.details },
      });
      return;
    }
    if (err instanceof ZodError) {
      reply.status(400).send({
        error: {
          code: 'validation_failed',
          message: 'Validation failed',
          details: { issues: err.issues },
        },
      });
      return;
    }
    if (err.validation) {
      reply.status(400).send({
        error: {
          code: 'validation_failed',
          message: err.message,
          details: { issues: err.validation },
        },
      });
      return;
    }
    const status = typeof err.statusCode === 'number' ? err.statusCode : 500;
    if (status >= 500) {
      app.log.error({ err }, 'unhandled error');
    }
    reply.status(status).send({
      error: {
        code: status >= 500 ? 'internal_error' : 'bad_request',
        message: status >= 500 ? 'Internal error' : err.message,
      },
    });
  });
}

export default fp(errorsPlugin, { name: 'cc-errors' });
