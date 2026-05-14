import type { FastifyInstance } from 'fastify';
import { withRls } from '@carecircle/db';
import {
  createShiftDigestSchema,
  paginationSchema,
  notFound,
  forbidden,
  type ExtractedEntitiesT,
  type ShiftDigestArtifactsT,
} from '@carecircle/shared';
import { cipherFor } from '../lib/encrypt.js';
import { encodeCursor, parseCursor } from '../lib/cursor.js';
import { requireMembership } from '../lib/membership.js';

type DigestRow = {
  id: string;
  circle_id: string;
  narrator_user_id: string;
  shift_start_at: Date;
  shift_end_at: Date;
  transcript_enc: Buffer | null;
  summary_enc: Buffer | null;
  entities_enc: Buffer | null;
  artifacts_enc: Buffer | null;
  voice_object_key: string | null;
  audio_duration_seconds: string;
  related_shift_id: string | null;
  created_at: Date;
  version: string;
};

export async function digestRoutes(app: FastifyInstance): Promise<void> {
  const { pool, circleKeys } = app.ctx;

  app.post('/v1/circles/:circleId/digests', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId } = req.params as { circleId: string };
    await requireMembership(pool, userId, circleId);

    const body = createShiftDigestSchema.parse(req.body);
    const cipher = await cipherFor(circleKeys, circleId);

    const row = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      if (body.clientOpId) {
        const existing = await client.query<{ id: string }>(
          `SELECT id FROM shift_digests
           WHERE circle_id = $1 AND client_op_id = $2 AND deleted_at IS NULL`,
          [circleId, body.clientOpId],
        );
        if (existing.rows[0]) {
          return { id: existing.rows[0].id, replayed: true };
        }
      }

      const transcriptEnc = cipher.encryptOptional(body.transcript ?? null);
      const summaryEnc = cipher.encryptOptional(body.summary ?? null);
      const entitiesEnc = body.entities ? cipher.encryptJson(body.entities) : null;
      const artifactsEnc = body.artifacts ? cipher.encryptJson(body.artifacts) : null;

      const result = await client.query<{ id: string }>(
        `INSERT INTO shift_digests (
            circle_id, narrator_user_id, shift_start_at, shift_end_at,
            transcript_enc, summary_enc, entities_enc, artifacts_enc,
            voice_object_key, audio_duration_seconds,
            related_shift_id, client_op_id
         ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
         RETURNING id`,
        [
          circleId,
          userId,
          new Date(body.shiftStartAt),
          new Date(body.shiftEndAt),
          transcriptEnc,
          summaryEnc,
          entitiesEnc,
          artifactsEnc,
          body.voiceObjectKey ?? null,
          body.audioDurationSeconds,
          body.relatedShiftId ?? null,
          body.clientOpId ?? null,
        ],
      );
      return { id: result.rows[0]!.id, replayed: false };
    });

    reply.status(201).send({ id: row.id, replayed: row.replayed === true });
  });

  app.get('/v1/circles/:circleId/digests', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId } = req.params as { circleId: string };
    await requireMembership(pool, userId, circleId);
    const query = paginationSchema.parse(req.query);
    const cursor = parseCursor(query.cursor);
    const cipher = await cipherFor(circleKeys, circleId);

    const rows = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const params: unknown[] = [circleId, query.limit + 1];
      let cursorClause = '';
      if (cursor) {
        params.push(cursor.occurredAt, cursor.id);
        cursorClause = `AND (shift_end_at, id) < ($3::timestamptz, $4::uuid)`;
      }
      const result = await client.query<DigestRow>(
        `SELECT id, circle_id, narrator_user_id, shift_start_at, shift_end_at,
                transcript_enc, summary_enc, entities_enc, artifacts_enc,
                voice_object_key, audio_duration_seconds::TEXT,
                related_shift_id, created_at, version::TEXT
         FROM shift_digests
         WHERE circle_id = $1 AND deleted_at IS NULL
           ${cursorClause}
         ORDER BY shift_end_at DESC, id DESC
         LIMIT $2`,
        params,
      );
      return result.rows;
    });

    const limited = rows.slice(0, query.limit);
    const nextCursor =
      rows.length > query.limit
        ? encodeCursor(limited[limited.length - 1]!.shift_end_at, limited[limited.length - 1]!.id)
        : null;

    reply.send({
      digests: limited.map((r) => serialize(r, cipher)),
      nextCursor,
    });
  });

  app.get('/v1/digests/:id', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { id } = req.params as { id: string };
    const row = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<DigestRow>(
        `SELECT id, circle_id, narrator_user_id, shift_start_at, shift_end_at,
                transcript_enc, summary_enc, entities_enc, artifacts_enc,
                voice_object_key, audio_duration_seconds::TEXT,
                related_shift_id, created_at, version::TEXT
         FROM shift_digests WHERE id = $1 AND deleted_at IS NULL`,
        [id],
      );
      return result.rows[0] ?? null;
    });
    if (!row) {
      throw notFound('Shift digest not found');
    }
    const cipher = await cipherFor(circleKeys, row.circle_id);
    reply.send(serialize(row, cipher));
  });

  app.delete('/v1/digests/:id', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { id } = req.params as { id: string };
    const deleted = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{ id: string }>(
        `UPDATE shift_digests SET deleted_at = NOW()
         WHERE id = $1 AND narrator_user_id = current_user_id() AND deleted_at IS NULL
         RETURNING id`,
        [id],
      );
      return result.rows[0] ?? null;
    });
    if (!deleted) {
      throw forbidden('Only the narrator can delete');
    }
    reply.status(204).send();
  });
}

function serialize(r: DigestRow, cipher: { decryptOptional: (b: Buffer | null) => string | null; decryptJson: <T>(b: Buffer | null) => T | null }) {
  return {
    id: r.id,
    circleId: r.circle_id,
    narratorUserId: r.narrator_user_id,
    shiftStartAt: r.shift_start_at.toISOString(),
    shiftEndAt: r.shift_end_at.toISOString(),
    transcript: cipher.decryptOptional(r.transcript_enc),
    summary: cipher.decryptOptional(r.summary_enc),
    entities: cipher.decryptJson<ExtractedEntitiesT>(r.entities_enc),
    artifacts: cipher.decryptJson<ShiftDigestArtifactsT>(r.artifacts_enc),
    voiceObjectKey: r.voice_object_key,
    audioDurationSeconds: Number(r.audio_duration_seconds),
    relatedShiftId: r.related_shift_id,
    createdAt: r.created_at.toISOString(),
    version: Number(r.version),
  };
}
