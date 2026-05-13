import type { FastifyInstance } from 'fastify';

export async function healthRoutes(app: FastifyInstance): Promise<void> {
  app.get('/health', async () => {
    return { ok: true, ts: new Date().toISOString() };
  });

  app.get('/v1/health', async () => {
    const { pool } = app.ctx;
    const client = await pool.connect();
    try {
      await client.query('SELECT 1');
      return { ok: true, db: 'up' };
    } finally {
      client.release();
    }
  });
}
