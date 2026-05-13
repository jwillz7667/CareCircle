import type { FastifyInstance } from 'fastify';
import { withRls } from '@carecircle/db';
import { careRecipientSchema, notFound } from '@carecircle/shared';
import { cipherFor } from '../lib/encrypt.js';
import { requireMembership } from '../lib/membership.js';

export async function recipientRoutes(app: FastifyInstance): Promise<void> {
  const { pool, circleKeys } = app.ctx;

  app.put('/v1/circles/:circleId/recipient', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId } = req.params as { circleId: string };
    await requireMembership(pool, userId, circleId, ['owner', 'family_member', 'paid_family']);

    const body = careRecipientSchema.parse(req.body);
    const cipher = await cipherFor(circleKeys, circleId);

    const row = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const existing = await client.query<{ id: string }>(
        `SELECT id FROM care_recipients WHERE circle_id = $1 AND deleted_at IS NULL LIMIT 1`,
        [circleId],
      );
      const firstNameEnc = cipher.encrypt(body.firstName);
      const lastNameEnc = cipher.encryptOptional(body.lastName);
      const dobEnc = cipher.encryptOptional(body.dateOfBirth);
      const conditionsEnc = body.primaryConditions
        ? cipher.encryptJson(body.primaryConditions)
        : null;

      if (existing.rows[0]) {
        await client.query(
          `UPDATE care_recipients
           SET first_name_enc          = $2,
               last_name_enc           = $3,
               date_of_birth_enc       = $4,
               pronouns                = $5,
               primary_conditions_enc  = $6
           WHERE id = $1`,
          [existing.rows[0].id, firstNameEnc, lastNameEnc, dobEnc, body.pronouns ?? null, conditionsEnc],
        );
        return { id: existing.rows[0].id };
      }
      const created = await client.query<{ id: string }>(
        `INSERT INTO care_recipients (
            circle_id, first_name_enc, last_name_enc, date_of_birth_enc, pronouns, primary_conditions_enc
         ) VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING id`,
        [circleId, firstNameEnc, lastNameEnc, dobEnc, body.pronouns ?? null, conditionsEnc],
      );
      const recipientId = created.rows[0]!.id;
      await client.query(`UPDATE circles SET care_recipient_id = $2 WHERE id = $1`, [
        circleId,
        recipientId,
      ]);
      return { id: recipientId };
    });

    reply.send({ id: row.id });
  });

  app.get('/v1/circles/:circleId/recipient', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId } = req.params as { circleId: string };
    await requireMembership(pool, userId, circleId);

    const cipher = await cipherFor(circleKeys, circleId);
    const row = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{
        id: string;
        first_name_enc: Buffer;
        last_name_enc: Buffer | null;
        date_of_birth_enc: Buffer | null;
        pronouns: string | null;
        primary_conditions_enc: Buffer | null;
        photo_object_key: string | null;
      }>(
        `SELECT id, first_name_enc, last_name_enc, date_of_birth_enc, pronouns, primary_conditions_enc, photo_object_key
         FROM care_recipients
         WHERE circle_id = $1 AND deleted_at IS NULL
         ORDER BY created_at ASC LIMIT 1`,
        [circleId],
      );
      return result.rows[0] ?? null;
    });
    if (!row) {
      throw notFound('No recipient yet');
    }
    reply.send({
      id: row.id,
      firstName: cipher.decrypt(row.first_name_enc),
      lastName: cipher.decryptOptional(row.last_name_enc),
      dateOfBirth: cipher.decryptOptional(row.date_of_birth_enc),
      pronouns: row.pronouns,
      primaryConditions: cipher.decryptJson<string[]>(row.primary_conditions_enc) ?? [],
      photoObjectKey: row.photo_object_key,
    });
  });
}
