import type { FastifyInstance } from 'fastify';
import { withRls } from '@carecircle/db';
import { emergencyContactSchema, notFound } from '@carecircle/shared';
import { cipherFor } from '../lib/encrypt.js';
import { requireMembership } from '../lib/membership.js';

export async function emergencyContactRoutes(app: FastifyInstance): Promise<void> {
  const { pool, circleKeys } = app.ctx;

  app.get('/v1/circles/:circleId/emergency-contacts', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId } = req.params as { circleId: string };
    await requireMembership(pool, userId, circleId);
    const cipher = await cipherFor(circleKeys, circleId);

    const rows = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{
        id: string;
        name_enc: Buffer;
        relationship: string | null;
        phone_enc: Buffer;
        is_primary: boolean;
        is_medical: boolean;
        sort_order: number;
      }>(
        `SELECT id, name_enc, relationship, phone_enc, is_primary, is_medical, sort_order
         FROM emergency_contacts
         WHERE circle_id = $1 AND deleted_at IS NULL
         ORDER BY sort_order, id`,
        [circleId],
      );
      return result.rows;
    });

    reply.send({
      contacts: rows.map((r) => ({
        id: r.id,
        name: cipher.decrypt(r.name_enc),
        relationship: r.relationship,
        phone: cipher.decrypt(r.phone_enc),
        isPrimary: r.is_primary,
        isMedical: r.is_medical,
        sortOrder: r.sort_order,
      })),
    });
  });

  app.post('/v1/circles/:circleId/emergency-contacts', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId } = req.params as { circleId: string };
    await requireMembership(pool, userId, circleId);
    const body = emergencyContactSchema.parse(req.body);
    const cipher = await cipherFor(circleKeys, circleId);

    const row = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{ id: string }>(
        `INSERT INTO emergency_contacts (
            circle_id, name_enc, relationship, phone_enc, is_primary, is_medical, sort_order
         ) VALUES ($1, $2, $3, $4, $5, $6, $7)
         RETURNING id`,
        [
          circleId,
          cipher.encrypt(body.name),
          body.relationship ?? null,
          cipher.encrypt(body.phone),
          body.isPrimary,
          body.isMedical,
          body.sortOrder,
        ],
      );
      return result.rows[0]!;
    });
    reply.status(201).send(row);
  });

  app.patch('/v1/emergency-contacts/:id', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { id } = req.params as { id: string };
    const body = emergencyContactSchema.partial().parse(req.body);

    const updated = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const existing = await client.query<{ circle_id: string }>(
        `SELECT circle_id FROM emergency_contacts WHERE id = $1 AND deleted_at IS NULL`,
        [id],
      );
      if (!existing.rows[0]) {
        return null;
      }
      const cipher = await cipherFor(circleKeys, existing.rows[0].circle_id);
      const result = await client.query<{ id: string }>(
        `UPDATE emergency_contacts SET
            name_enc      = COALESCE($2, name_enc),
            relationship  = COALESCE($3, relationship),
            phone_enc     = COALESCE($4, phone_enc),
            is_primary    = COALESCE($5, is_primary),
            is_medical    = COALESCE($6, is_medical),
            sort_order    = COALESCE($7, sort_order)
         WHERE id = $1 RETURNING id`,
        [
          id,
          body.name ? cipher.encrypt(body.name) : null,
          body.relationship ?? null,
          body.phone ? cipher.encrypt(body.phone) : null,
          body.isPrimary ?? null,
          body.isMedical ?? null,
          body.sortOrder ?? null,
        ],
      );
      return result.rows[0] ?? null;
    });
    if (!updated) {
      throw notFound('Contact not found');
    }
    reply.status(204).send();
  });

  app.delete('/v1/emergency-contacts/:id', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { id } = req.params as { id: string };
    const deleted = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{ id: string }>(
        `UPDATE emergency_contacts SET deleted_at = NOW()
         WHERE id = $1 AND deleted_at IS NULL RETURNING id`,
        [id],
      );
      return result.rows[0] ?? null;
    });
    if (!deleted) {
      throw notFound('Contact not found');
    }
    reply.status(204).send();
  });
}
