import type { FastifyInstance } from 'fastify';
import { withRls } from '@carecircle/db';
import {
  createActivitySchema,
  commentSchema,
  reactionSchema,
  paginationSchema,
  notFound,
  forbidden,
} from '@carecircle/shared';
import { cipherFor } from '../lib/encrypt.js';
import { encodeCursor, parseCursor } from '../lib/cursor.js';
import { requireMembership } from '../lib/membership.js';

export async function activityRoutes(app: FastifyInstance): Promise<void> {
  const { pool, circleKeys } = app.ctx;

  app.post('/v1/circles/:circleId/activities', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId } = req.params as { circleId: string };
    await requireMembership(pool, userId, circleId);

    const body = createActivitySchema.parse(req.body);
    const cipher = await cipherFor(circleKeys, circleId);

    const row = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      if (body.clientOpId) {
        const existing = await client.query<{ id: string }>(
          `SELECT id FROM activities
           WHERE circle_id = $1 AND client_op_id = $2 AND deleted_at IS NULL`,
          [circleId, body.clientOpId],
        );
        if (existing.rows[0]) {
          return { id: existing.rows[0].id, replayed: true };
        }
      }

      const contentEnc = cipher.encryptOptional(body.content);
      const entitiesEnc = body.entities ? cipher.encryptJson(body.entities) : null;
      const photoKeys = body.photoObjectKeys ?? null;
      const occurredAt = body.occurredAt ? new Date(body.occurredAt) : new Date();

      const result = await client.query<{ id: string; occurred_at: Date }>(
        `INSERT INTO activities (
            circle_id, author_user_id, activity_type, headline, content_enc,
            voice_object_key, photo_object_keys, entities_enc,
            related_med_id, related_appointment_id, related_shift_id,
            occurred_at, client_op_id
         ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
         RETURNING id, occurred_at`,
        [
          circleId,
          userId,
          body.type,
          body.headline ?? null,
          contentEnc,
          body.voiceObjectKey ?? null,
          photoKeys,
          entitiesEnc,
          body.relatedMedId ?? null,
          body.relatedAppointmentId ?? null,
          body.relatedShiftId ?? null,
          occurredAt,
          body.clientOpId ?? null,
        ],
      );
      return { id: result.rows[0]!.id, occurredAt: result.rows[0]!.occurred_at, replayed: false };
    });

    reply.status(201).send({ id: row.id, replayed: row.replayed === true });
  });

  app.get('/v1/circles/:circleId/activities', async (req, reply) => {
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
        cursorClause = `AND (occurred_at, id) < ($3::timestamptz, $4::uuid)`;
      }
      const result = await client.query<{
        id: string;
        author_user_id: string;
        activity_type: string;
        headline: string | null;
        content_enc: Buffer | null;
        voice_object_key: string | null;
        photo_object_keys: string[] | null;
        entities_enc: Buffer | null;
        related_med_id: string | null;
        related_appointment_id: string | null;
        related_shift_id: string | null;
        occurred_at: Date;
        version: string;
      }>(
        `SELECT id, author_user_id, activity_type, headline, content_enc,
                voice_object_key, photo_object_keys, entities_enc,
                related_med_id, related_appointment_id, related_shift_id,
                occurred_at, version::TEXT
         FROM activities
         WHERE circle_id = $1 AND deleted_at IS NULL
           ${cursorClause}
         ORDER BY occurred_at DESC, id DESC
         LIMIT $2`,
        params,
      );
      return result.rows;
    });

    const limited = rows.slice(0, query.limit);
    const nextCursor =
      rows.length > query.limit
        ? encodeCursor(limited[limited.length - 1]!.occurred_at, limited[limited.length - 1]!.id)
        : null;

    reply.send({
      activities: limited.map((r) => ({
        id: r.id,
        authorUserId: r.author_user_id,
        type: r.activity_type,
        headline: r.headline,
        content: cipher.decryptOptional(r.content_enc),
        voiceObjectKey: r.voice_object_key,
        photoObjectKeys: r.photo_object_keys ?? [],
        entities: cipher.decryptJson<string[]>(r.entities_enc) ?? [],
        relatedMedId: r.related_med_id,
        relatedAppointmentId: r.related_appointment_id,
        relatedShiftId: r.related_shift_id,
        occurredAt: r.occurred_at.toISOString(),
        version: Number(r.version),
      })),
      nextCursor,
    });
  });

  app.get('/v1/activities/:id', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { id } = req.params as { id: string };
    const row = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{
        id: string;
        circle_id: string;
        author_user_id: string;
        activity_type: string;
        headline: string | null;
        content_enc: Buffer | null;
        voice_object_key: string | null;
        photo_object_keys: string[] | null;
        entities_enc: Buffer | null;
        occurred_at: Date;
      }>(
        `SELECT id, circle_id, author_user_id, activity_type, headline, content_enc,
                voice_object_key, photo_object_keys, entities_enc, occurred_at
         FROM activities WHERE id = $1 AND deleted_at IS NULL`,
        [id],
      );
      return result.rows[0] ?? null;
    });
    if (!row) {
      throw notFound('Activity not found');
    }
    const cipher = await cipherFor(circleKeys, row.circle_id);
    reply.send({
      id: row.id,
      circleId: row.circle_id,
      authorUserId: row.author_user_id,
      type: row.activity_type,
      headline: row.headline,
      content: cipher.decryptOptional(row.content_enc),
      voiceObjectKey: row.voice_object_key,
      photoObjectKeys: row.photo_object_keys ?? [],
      entities: cipher.decryptJson<string[]>(row.entities_enc) ?? [],
      occurredAt: row.occurred_at.toISOString(),
    });
  });

  app.delete('/v1/activities/:id', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { id } = req.params as { id: string };
    const deleted = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{ id: string }>(
        `UPDATE activities SET deleted_at = NOW()
         WHERE id = $1 AND author_user_id = current_user_id() AND deleted_at IS NULL
         RETURNING id`,
        [id],
      );
      return result.rows[0] ?? null;
    });
    if (!deleted) {
      throw forbidden('Only the author can delete');
    }
    reply.status(204).send();
  });

  // ---------- Reactions ----------

  app.post('/v1/activities/:id/reactions', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { id } = req.params as { id: string };
    const body = reactionSchema.parse(req.body);

    const circleId = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const a = await client.query<{ circle_id: string }>(
        `SELECT circle_id FROM activities WHERE id = $1 AND deleted_at IS NULL`,
        [id],
      );
      if (!a.rows[0]) {
        return null;
      }
      await client.query(
        `INSERT INTO activity_reactions (activity_id, circle_id, user_id, emoji)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT DO NOTHING`,
        [id, a.rows[0].circle_id, userId, body.emoji],
      );
      return a.rows[0].circle_id;
    });
    if (!circleId) {
      throw notFound('Activity not found');
    }
    reply.status(201).send({ ok: true });
  });

  app.delete('/v1/activities/:id/reactions/:emoji', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { id, emoji } = req.params as { id: string; emoji: string };
    await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      await client.query(
        `DELETE FROM activity_reactions
         WHERE activity_id = $1 AND user_id = $2 AND emoji = $3`,
        [id, userId, decodeURIComponent(emoji)],
      );
    });
    reply.status(204).send();
  });

  // ---------- Comments ----------

  app.post('/v1/activities/:id/comments', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { id } = req.params as { id: string };
    const body = commentSchema.parse(req.body);

    const created = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const activity = await client.query<{ circle_id: string }>(
        `SELECT circle_id FROM activities WHERE id = $1 AND deleted_at IS NULL`,
        [id],
      );
      if (!activity.rows[0]) {
        return null;
      }
      const cipher = await cipherFor(circleKeys, activity.rows[0].circle_id);
      const result = await client.query<{ id: string; created_at: Date }>(
        `INSERT INTO activity_comments (activity_id, circle_id, author_user_id, content_enc)
         VALUES ($1, $2, $3, $4) RETURNING id, created_at`,
        [id, activity.rows[0].circle_id, userId, cipher.encrypt(body.content)],
      );
      return result.rows[0]!;
    });
    if (!created) {
      throw notFound('Activity not found');
    }
    reply.status(201).send({ id: created.id, createdAt: created.created_at.toISOString() });
  });

  app.get('/v1/activities/:id/comments', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { id } = req.params as { id: string };
    const data = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const activity = await client.query<{ circle_id: string }>(
        `SELECT circle_id FROM activities WHERE id = $1 AND deleted_at IS NULL`,
        [id],
      );
      if (!activity.rows[0]) {
        return null;
      }
      const cipher = await cipherFor(circleKeys, activity.rows[0].circle_id);
      const result = await client.query<{
        id: string;
        author_user_id: string;
        content_enc: Buffer;
        created_at: Date;
      }>(
        `SELECT id, author_user_id, content_enc, created_at
         FROM activity_comments
         WHERE activity_id = $1 AND deleted_at IS NULL
         ORDER BY created_at ASC`,
        [id],
      );
      return result.rows.map((r) => ({
        id: r.id,
        authorUserId: r.author_user_id,
        content: cipher.decrypt(r.content_enc),
        createdAt: r.created_at.toISOString(),
      }));
    });
    if (!data) {
      throw notFound('Activity not found');
    }
    reply.send({ comments: data });
  });
}
