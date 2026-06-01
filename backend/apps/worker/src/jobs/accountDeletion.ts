import { Client as MinioClient } from 'minio';
import type pg from 'pg';
import { withRls } from '@carecircle/db';
import type { Logger } from '@carecircle/shared';
import type { Config } from '../config.js';
import type { AccountDeletionJobData } from '../queues.js';

const PHOTOS_BUCKET = 'cc-photos';
const VOICE_BUCKET = 'cc-voice';
const DOCUMENTS_BUCKET = 'cc-documents';
const PDF_BUCKET = 'cc-pdf-exports';

// MinIO's DeleteObjects API caps a single request at 1000 keys.
const REMOVE_BATCH = 1_000;

function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    out.push(items.slice(i, i + size));
  }
  return out;
}

/**
 * Tears down a soft-deleted account: any circles the user owns are themselves
 * soft-deleted and their members tombstoned, the user is removed from every
 * other circle, push tokens are dropped, directly-identifying profile fields
 * are scrubbed (the row itself is retained as a tombstone so foreign keys and
 * the audit trail hold), and the associated object-storage blobs are purged.
 *
 * The DB mutation is one transaction; object purging is best-effort afterwards
 * so a storage hiccup leaves orphaned blobs rather than blocking closure (the
 * job retries, and a re-run is idempotent — every step is already-applied-safe).
 */
export async function runAccountDeletionJob(
  data: AccountDeletionJobData,
  ctx: { pool: pg.Pool; config: Config; logger: Logger; minio: MinioClient },
): Promise<{ ownedCircles: number; objectsPurged: number }> {
  const { pool, logger, minio } = ctx;
  const { userId } = data;

  const purge = await withRls(pool, { role: 'app_service' }, async (client) => {
    const owned = await client.query<{ id: string }>(
      `SELECT id FROM circles WHERE owner_user_id = $1`,
      [userId],
    );
    const ownedIds = owned.rows.map((r) => r.id);

    const photoKeys = new Set<string>();
    const voiceKeys = new Set<string>();
    const documentKeys = new Set<string>();
    const pdfKeys = new Set<string>();

    if (ownedIds.length > 0) {
      const recipientPhotos = await client.query<{ photo_object_key: string }>(
        `SELECT photo_object_key FROM care_recipients
         WHERE circle_id = ANY($1::uuid[]) AND photo_object_key IS NOT NULL`,
        [ownedIds],
      );
      for (const r of recipientPhotos.rows) {
        photoKeys.add(r.photo_object_key);
      }

      const activityMedia = await client.query<{
        voice_object_key: string | null;
        photo_object_keys: string[] | null;
      }>(
        `SELECT voice_object_key, photo_object_keys FROM activities
         WHERE circle_id = ANY($1::uuid[])`,
        [ownedIds],
      );
      for (const r of activityMedia.rows) {
        if (r.voice_object_key) {
          voiceKeys.add(r.voice_object_key);
        }
        for (const key of r.photo_object_keys ?? []) {
          photoKeys.add(key);
        }
      }

      const shiftVoice = await client.query<{ voice_object_key: string }>(
        `SELECT voice_object_key FROM shift_digests
         WHERE circle_id = ANY($1::uuid[]) AND voice_object_key IS NOT NULL`,
        [ownedIds],
      );
      for (const r of shiftVoice.rows) {
        voiceKeys.add(r.voice_object_key);
      }

      const docs = await client.query<{ object_key: string }>(
        `SELECT object_key FROM documents WHERE circle_id = ANY($1::uuid[])`,
        [ownedIds],
      );
      for (const r of docs.rows) {
        documentKeys.add(r.object_key);
      }

      const pdfs = await client.query<{ export_pdf_key: string }>(
        `SELECT export_pdf_key FROM care_minute_entries
         WHERE circle_id = ANY($1::uuid[]) AND export_pdf_key IS NOT NULL`,
        [ownedIds],
      );
      for (const r of pdfs.rows) {
        pdfKeys.add(r.export_pdf_key);
      }

      await client.query(
        `UPDATE circle_members SET deleted_at = NOW(), status = 'removed'
         WHERE circle_id = ANY($1::uuid[]) AND deleted_at IS NULL`,
        [ownedIds],
      );
      await client.query(
        `UPDATE circles SET deleted_at = NOW()
         WHERE id = ANY($1::uuid[]) AND deleted_at IS NULL`,
        [ownedIds],
      );
    }

    const me = await client.query<{ photo_object_key: string | null }>(
      `SELECT photo_object_key FROM users WHERE id = $1`,
      [userId],
    );
    const myPhoto = me.rows[0]?.photo_object_key;
    if (myPhoto) {
      photoKeys.add(myPhoto);
    }

    await client.query(
      `UPDATE circle_members SET deleted_at = NOW(), status = 'removed'
       WHERE user_id = $1 AND deleted_at IS NULL`,
      [userId],
    );

    await client.query(`DELETE FROM devices WHERE user_id = $1`, [userId]);

    await client.query(
      `UPDATE users
       SET email = NULL, display_name = NULL, photo_object_key = NULL,
           apple_user_id = NULL, google_user_id = NULL, password_hash = NULL,
           deleted_at = COALESCE(deleted_at, NOW())
       WHERE id = $1`,
      [userId],
    );

    await client.query(
      `INSERT INTO audit_log (actor_id, circle_id, action, table_name, row_id)
       VALUES ($1, NULL, 'ACCOUNT_DELETED', 'users', $1)`,
      [userId],
    );

    return {
      ownedCircles: ownedIds.length,
      photos: [...photoKeys],
      voice: [...voiceKeys],
      documents: [...documentKeys],
      pdfs: [...pdfKeys],
    };
  });

  const removals: Array<[string, string[]]> = [
    [PHOTOS_BUCKET, purge.photos],
    [VOICE_BUCKET, purge.voice],
    [DOCUMENTS_BUCKET, purge.documents],
    [PDF_BUCKET, purge.pdfs],
  ];
  let objectsPurged = 0;
  for (const [bucket, keys] of removals) {
    for (const batch of chunk(keys, REMOVE_BATCH)) {
      try {
        await minio.removeObjects(bucket, batch);
        objectsPurged += batch.length;
      } catch (err) {
        logger.warn(
          { err, bucket, count: batch.length, userId },
          'failed to purge objects for deleted account',
        );
      }
    }
  }

  logger.info(
    { userId, ownedCircles: purge.ownedCircles, objectsPurged },
    'account deletion complete',
  );
  return { ownedCircles: purge.ownedCircles, objectsPurged };
}
