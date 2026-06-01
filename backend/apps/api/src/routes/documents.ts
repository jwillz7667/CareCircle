import { randomBytes } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { withRls } from '@carecircle/db';
import {
  createDocumentSchema,
  uploadUrlSchema,
  forbidden,
  notFound,
} from '@carecircle/shared';
import { cipherFor } from '../lib/encrypt.js';
import { requireMembership } from '../lib/membership.js';
import { requireEntitlement } from '../lib/subscriptions.js';

/**
 * Reduce a client-supplied filename to a safe key suffix. The object key is
 * built from a server-controlled prefix (`circleId/date/random-`) followed by
 * this suffix; without sanitization a name like `../other/x` or one with NUL /
 * control bytes would let the client steer the stored path or smuggle control
 * characters into S3/MinIO keys and Content-Disposition headers. Keep only the
 * basename, allowlist printable filename characters, drop leading dots so the
 * suffix can never become a `.`/`..` segment, and cap the length.
 */
function sanitizeFilename(name: string | undefined): string {
  if (!name) {
    return 'object';
  }
  const base = name.split(/[\\/]/).pop() ?? 'object';
  const cleaned = base
    .replace(/[^A-Za-z0-9._-]/g, '_')
    .replace(/^\.+/, '')
    .slice(0, 128);
  return cleaned.length > 0 ? cleaned : 'object';
}

export async function documentRoutes(app: FastifyInstance): Promise<void> {
  const { pool, storage, circleKeys } = app.ctx;

  app.post('/v1/circles/:circleId/documents/upload-url', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId } = req.params as { circleId: string };
    await requireMembership(pool, userId, circleId);
    await requireEntitlement(pool, circleId);
    const body = uploadUrlSchema.parse(req.body);

    const objectKey = `${circleId}/${new Date().toISOString().slice(0, 10)}/${randomBytes(12).toString('hex')}-${sanitizeFilename(body.filename)}`;
    const url = await storage.presignPut(body.bucket, objectKey, body.contentType);
    reply.send({ bucket: body.bucket, objectKey, url, expiresInSeconds: 300 });
  });

  app.post('/v1/circles/:circleId/documents', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId } = req.params as { circleId: string };
    await requireMembership(pool, userId, circleId);
    await requireEntitlement(pool, circleId);
    const body = createDocumentSchema.parse(req.body);
    const cipher = await cipherFor(circleKeys, circleId);

    const row = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const visibility = body.visibility ?? [
        'owner',
        'family_member',
        'paid_family',
        'care_recipient',
      ];
      const result = await client.query<{ id: string }>(
        `INSERT INTO documents (
            circle_id, title_enc, document_type, object_key, mime_type, size_bytes,
            encryption_nonce, encryption_tag, issued_at, expires_at, uploaded_by, visibility
         ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12::member_role[])
         RETURNING id`,
        [
          circleId,
          cipher.encrypt(body.title),
          body.documentType,
          body.objectKey,
          body.mimeType,
          body.sizeBytes,
          Buffer.from(body.encryptionNonce, 'base64'),
          Buffer.from(body.encryptionTag, 'base64'),
          body.issuedAt ?? null,
          body.expiresAt ?? null,
          userId,
          visibility,
        ],
      );
      return result.rows[0]!;
    });
    reply.status(201).send({ id: row.id });
  });

  app.get('/v1/circles/:circleId/documents', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId } = req.params as { circleId: string };
    await requireMembership(pool, userId, circleId);
    const cipher = await cipherFor(circleKeys, circleId);

    const rows = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{
        id: string;
        title_enc: Buffer;
        document_type: string;
        object_key: string;
        mime_type: string;
        size_bytes: string;
        issued_at: Date | null;
        expires_at: Date | null;
        uploaded_by: string;
        created_at: Date;
      }>(
        `SELECT id, title_enc, document_type, object_key, mime_type, size_bytes::TEXT,
                issued_at, expires_at, uploaded_by, created_at
         FROM documents WHERE circle_id = $1 AND deleted_at IS NULL
         ORDER BY created_at DESC`,
        [circleId],
      );
      return result.rows;
    });

    reply.send({
      documents: rows.map((r) => ({
        id: r.id,
        title: cipher.decrypt(r.title_enc),
        documentType: r.document_type,
        objectKey: r.object_key,
        mimeType: r.mime_type,
        sizeBytes: Number(r.size_bytes),
        issuedAt: r.issued_at ? r.issued_at.toISOString().slice(0, 10) : null,
        expiresAt: r.expires_at ? r.expires_at.toISOString().slice(0, 10) : null,
        uploadedBy: r.uploaded_by,
        createdAt: r.created_at.toISOString(),
      })),
    });
  });

  app.get('/v1/documents/:id/download-url', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { id } = req.params as { id: string };
    const data = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{
        object_key: string;
        encryption_nonce: Buffer;
        encryption_tag: Buffer;
        circle_id: string;
      }>(
        `SELECT object_key, encryption_nonce, encryption_tag, circle_id
         FROM documents WHERE id = $1 AND deleted_at IS NULL`,
        [id],
      );
      return result.rows[0] ?? null;
    });
    if (!data) {
      throw notFound('Document not found');
    }
    const url = await storage.presignGet('cc-documents', data.object_key);
    reply.send({
      url,
      objectKey: data.object_key,
      encryptionNonce: data.encryption_nonce.toString('base64'),
      encryptionTag: data.encryption_tag.toString('base64'),
    });
  });

  app.delete('/v1/documents/:id', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { id } = req.params as { id: string };
    const deleted = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{ id: string; uploaded_by: string }>(
        `SELECT id, uploaded_by FROM documents WHERE id = $1 AND deleted_at IS NULL`,
        [id],
      );
      const doc = result.rows[0];
      if (!doc) {
        return null;
      }
      if (doc.uploaded_by !== userId) {
        throw forbidden('Only the uploader can delete');
      }
      await client.query(`UPDATE documents SET deleted_at = NOW() WHERE id = $1`, [id]);
      return doc;
    });
    if (!deleted) {
      throw notFound('Document not found');
    }
    reply.status(204).send();
  });
}
