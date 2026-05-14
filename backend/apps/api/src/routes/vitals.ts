import type { FastifyInstance } from 'fastify';
import { withRls } from '@carecircle/db';
import {
  createVitalSchema,
  listVitalsQuerySchema,
  notFound,
  forbidden,
} from '@carecircle/shared';
import { cipherFor, type FieldCipher } from '../lib/encrypt.js';
import { encodeCursor, parseCursor } from '../lib/cursor.js';
import { requireMembership } from '../lib/membership.js';

type VitalRow = {
  id: string;
  circle_id: string;
  recorded_by_user_id: string;
  kind: string;
  recorded_at: Date;
  value_numeric: string | null;
  value_text: string | null;
  unit: string;
  source: string;
  healthkit_uuid: string | null;
  notes_enc: Buffer | null;
  created_at: Date;
  version: string;
};

export async function vitalRoutes(app: FastifyInstance): Promise<void> {
  const { pool, circleKeys } = app.ctx;

  app.post('/v1/circles/:circleId/vitals', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId } = req.params as { circleId: string };
    await requireMembership(pool, userId, circleId);

    const body = createVitalSchema.parse(req.body);
    const cipher = await cipherFor(circleKeys, circleId);

    const row = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      if (body.clientOpId) {
        const existing = await client.query<{ id: string }>(
          `SELECT id FROM vitals
           WHERE circle_id = $1 AND client_op_id = $2 AND deleted_at IS NULL`,
          [circleId, body.clientOpId],
        );
        if (existing.rows[0]) {
          return { id: existing.rows[0].id, replayed: true };
        }
      }

      if (body.source === 'healthkit' && body.healthkitUUID) {
        const existing = await client.query<{ id: string }>(
          `SELECT id FROM vitals
           WHERE circle_id = $1 AND healthkit_uuid = $2 AND deleted_at IS NULL`,
          [circleId, body.healthkitUUID],
        );
        if (existing.rows[0]) {
          return { id: existing.rows[0].id, replayed: true };
        }
      }

      const notesEnc = cipher.encryptOptional(body.notes ?? null);

      const result = await client.query<{ id: string }>(
        `INSERT INTO vitals (
            circle_id, recorded_by_user_id, kind, recorded_at,
            value_numeric, value_text, unit, source, healthkit_uuid,
            notes_enc, client_op_id
         ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
         RETURNING id`,
        [
          circleId,
          userId,
          body.kind,
          new Date(body.recordedAt),
          body.valueNumeric ?? null,
          body.valueText ?? null,
          body.unit,
          body.source,
          body.healthkitUUID ?? null,
          notesEnc,
          body.clientOpId ?? null,
        ],
      );
      return { id: result.rows[0]!.id, replayed: false };
    });

    reply.status(201).send({ id: row.id, replayed: row.replayed === true });
  });

  app.get('/v1/circles/:circleId/vitals', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId } = req.params as { circleId: string };
    await requireMembership(pool, userId, circleId);
    const query = listVitalsQuerySchema.parse(req.query);
    const cursor = parseCursor(query.cursor);
    const cipher = await cipherFor(circleKeys, circleId);

    const rows = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const params: unknown[] = [circleId, query.limit + 1];
      const filters: string[] = [];
      if (query.kind) {
        params.push(query.kind);
        filters.push(`AND kind = $${params.length}`);
      }
      if (query.source) {
        params.push(query.source);
        filters.push(`AND source = $${params.length}`);
      }
      if (cursor) {
        params.push(cursor.occurredAt, cursor.id);
        filters.push(`AND (recorded_at, id) < ($${params.length - 1}::timestamptz, $${params.length}::uuid)`);
      }
      const result = await client.query<VitalRow>(
        `SELECT id, circle_id, recorded_by_user_id, kind, recorded_at,
                value_numeric::TEXT, value_text, unit, source, healthkit_uuid,
                notes_enc, created_at, version::TEXT
         FROM vitals
         WHERE circle_id = $1 AND deleted_at IS NULL
           ${filters.join('\n           ')}
         ORDER BY recorded_at DESC, id DESC
         LIMIT $2`,
        params,
      );
      return result.rows;
    });

    const limited = rows.slice(0, query.limit);
    const nextCursor =
      rows.length > query.limit
        ? encodeCursor(limited[limited.length - 1]!.recorded_at, limited[limited.length - 1]!.id)
        : null;

    reply.send({
      vitals: limited.map((r) => serialize(r, cipher)),
      nextCursor,
    });
  });

  app.get('/v1/vitals/:id', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { id } = req.params as { id: string };
    const row = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<VitalRow>(
        `SELECT id, circle_id, recorded_by_user_id, kind, recorded_at,
                value_numeric::TEXT, value_text, unit, source, healthkit_uuid,
                notes_enc, created_at, version::TEXT
         FROM vitals WHERE id = $1 AND deleted_at IS NULL`,
        [id],
      );
      return result.rows[0] ?? null;
    });
    if (!row) {
      throw notFound('Vital not found');
    }
    const cipher = await cipherFor(circleKeys, row.circle_id);
    reply.send(serialize(row, cipher));
  });

  app.delete('/v1/vitals/:id', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { id } = req.params as { id: string };
    const deleted = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{ id: string }>(
        `UPDATE vitals SET deleted_at = NOW()
         WHERE id = $1 AND recorded_by_user_id = current_user_id() AND deleted_at IS NULL
         RETURNING id`,
        [id],
      );
      return result.rows[0] ?? null;
    });
    if (!deleted) {
      throw forbidden('Only the recorder can delete');
    }
    reply.status(204).send();
  });
}

function serialize(r: VitalRow, cipher: FieldCipher) {
  return {
    id: r.id,
    circleId: r.circle_id,
    recordedByUserId: r.recorded_by_user_id,
    kind: r.kind,
    recordedAt: r.recorded_at.toISOString(),
    valueNumeric: r.value_numeric !== null ? Number(r.value_numeric) : null,
    valueText: r.value_text,
    unit: r.unit,
    source: r.source,
    healthkitUUID: r.healthkit_uuid,
    notes: cipher.decryptOptional(r.notes_enc),
    createdAt: r.created_at.toISOString(),
    version: Number(r.version),
  };
}
