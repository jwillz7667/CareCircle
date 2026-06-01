import type { FastifyInstance } from 'fastify';
import archiver from 'archiver';
import { withRls } from '@carecircle/db';
import { registerDeviceSchema, updateMeSchema, notFound } from '@carecircle/shared';
import { collectUserExportEntries } from '../lib/dataExport.js';

export async function meRoutes(app: FastifyInstance): Promise<void> {
  const { pool, tokens, circleKeys, queues } = app.ctx;

  app.get('/v1/me', async (req, reply) => {
    const userId = await app.requireUser(req);
    const row = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{
        id: string;
        email: string | null;
        display_name: string | null;
        photo_object_key: string | null;
        is_private_email: boolean;
        created_at: Date;
      }>(
        `SELECT id, email, display_name, photo_object_key, is_private_email, created_at
         FROM users WHERE id = $1 AND deleted_at IS NULL`,
        [userId],
      );
      return result.rows[0] ?? null;
    });
    if (!row) {
      throw notFound('User not found');
    }
    reply.send({
      id: row.id,
      email: row.email,
      displayName: row.display_name,
      photoObjectKey: row.photo_object_key,
      isPrivateEmail: row.is_private_email,
      createdAt: row.created_at.toISOString(),
    });
  });

  app.patch('/v1/me', async (req, reply) => {
    const userId = await app.requireUser(req);
    const body = updateMeSchema.parse(req.body);
    await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      await client.query(
        `UPDATE users
         SET display_name      = COALESCE($2, display_name),
             photo_object_key  = COALESCE($3, photo_object_key)
         WHERE id = $1`,
        [userId, body.displayName ?? null, body.photoObjectKey ?? null],
      );
    });
    reply.status(204).send();
  });

  app.delete('/v1/me', async (req, reply) => {
    const userId = await app.requireUser(req);
    await withRls(pool, { role: 'app_service' }, async (client) => {
      await client.query(`UPDATE users SET deleted_at = NOW() WHERE id = $1`, [userId]);
    });
    await tokens.revokeAllForUser(userId, pool);
    // The account is already inaccessible (soft-deleted + tokens revoked); the
    // cascading teardown runs out-of-band. A failed enqueue is logged but must
    // not fail the request — the job is keyed so a retry coalesces.
    try {
      await queues.account.add('delete', { userId }, { jobId: `account-delete:${userId}` });
    } catch (err) {
      app.log.error({ err, userId }, 'failed to enqueue account deletion cascade');
    }
    reply.status(204).send();
  });

  app.post('/v1/me/export', async (req, reply) => {
    const userId = await app.requireUser(req);
    // Gather and decrypt everything up front so a read failure surfaces as a
    // clean 500 before any archive bytes are written to the response.
    const entries = await collectUserExportEntries({ pool, circleKeys, userId });
    const archive = archiver('zip', { zlib: { level: 9 } });
    archive.on('warning', (err) => {
      app.log.warn({ err, userId }, 'export archive warning');
    });
    for (const entry of entries) {
      archive.append(entry.content, { name: entry.name });
    }
    void archive.finalize();
    void reply.header('content-type', 'application/zip');
    void reply.header('content-disposition', 'attachment; filename="carecircle-export.zip"');
    return reply.send(archive);
  });

  app.post('/v1/me/devices', async (req, reply) => {
    const userId = await app.requireUser(req);
    const body = registerDeviceSchema.parse(req.body);
    const row = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{ id: string }>(
        `INSERT INTO devices (user_id, apns_token, device_name, os_version, app_version, locale, timezone)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         ON CONFLICT (user_id, apns_token)
         DO UPDATE SET device_name = EXCLUDED.device_name,
                       os_version  = EXCLUDED.os_version,
                       app_version = EXCLUDED.app_version,
                       locale      = EXCLUDED.locale,
                       timezone    = EXCLUDED.timezone,
                       last_active_at = NOW()
         RETURNING id`,
        [
          userId,
          body.apnsToken,
          body.deviceName ?? null,
          body.osVersion ?? null,
          body.appVersion ?? null,
          body.locale ?? null,
          body.timezone ?? null,
        ],
      );
      return result.rows[0]!;
    });
    reply.status(201).send({ id: row.id });
  });

  app.delete('/v1/me/devices/:deviceId', async (req, reply) => {
    const userId = await app.requireUser(req);
    const params = req.params as { deviceId: string };
    await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      await client.query(`DELETE FROM devices WHERE id = $1 AND user_id = $2`, [
        params.deviceId,
        userId,
      ]);
    });
    reply.status(204).send();
  });
}
