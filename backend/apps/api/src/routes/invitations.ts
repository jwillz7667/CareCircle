import { randomBytes } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { withRls } from '@carecircle/db';
import {
  acceptInvitationSchema,
  createInvitationSchema,
  conflict,
  HttpError,
  notFound,
} from '@carecircle/shared';
import { requireMembership } from '../lib/membership.js';
import { availableInviteSlots } from '../lib/subscriptions.js';

function generateCode(): string {
  const buf = randomBytes(8);
  const alpha = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  let out = '';
  for (let i = 0; i < 8; i++) {
    out += alpha[buf[i]! % alpha.length];
  }
  return out;
}

export async function invitationRoutes(app: FastifyInstance): Promise<void> {
  const { pool } = app.ctx;

  app.post('/v1/circles/:circleId/invitations', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId } = req.params as { circleId: string };
    await requireMembership(pool, userId, circleId, ['owner']);
    const body = createInvitationSchema.parse(req.body);

    const slots = await availableInviteSlots(pool, circleId);
    if (slots.remaining <= 0) {
      throw new HttpError(
        409,
        'circle_member_cap_reached',
        slots.cap === 0
          ? 'Free circles cannot send invites — upgrade to invite caregivers.'
          : `Your ${slots.tier} plan allows ${slots.cap} invites; upgrade to invite more caregivers.`,
        { tier: slots.tier, cap: slots.cap },
      );
    }

    const expiresAt = new Date(Date.now() + body.expiresInDays * 24 * 3600 * 1000);

    const row = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      let code = generateCode();
      for (let attempt = 0; attempt < 5; attempt++) {
        const dup = await client.query<{ id: string }>(
          `SELECT id FROM circle_invitations WHERE code = $1`,
          [code],
        );
        if (!dup.rows[0]) {
          break;
        }
        code = generateCode();
      }
      const result = await client.query<{
        id: string;
        code: string;
        invite_link_id: string;
        expires_at: Date;
      }>(
        `INSERT INTO circle_invitations
            (circle_id, invited_by, role, code, email, phone, expires_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         RETURNING id, code, invite_link_id, expires_at`,
        [
          circleId,
          userId,
          body.role,
          code,
          body.email ?? null,
          body.phone ?? null,
          expiresAt,
        ],
      );
      return result.rows[0]!;
    });

    reply.status(201).send({
      id: row.id,
      code: row.code,
      inviteLinkId: row.invite_link_id,
      expiresAt: row.expires_at.toISOString(),
    });
  });

  app.get('/v1/circles/:circleId/invitations', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId } = req.params as { circleId: string };
    await requireMembership(pool, userId, circleId);

    const rows = await withRls(pool, { userId, role: 'app_user' }, async (client) => {
      const result = await client.query<{
        id: string;
        code: string;
        invite_link_id: string;
        role: string;
        email: string | null;
        phone: string | null;
        expires_at: Date;
        accepted_at: Date | null;
      }>(
        `SELECT id, code, invite_link_id, role, email, phone, expires_at, accepted_at
         FROM circle_invitations
         WHERE circle_id = $1
         ORDER BY created_at DESC`,
        [circleId],
      );
      return result.rows;
    });

    reply.send({
      invitations: rows.map((r) => ({
        id: r.id,
        code: r.code,
        inviteLinkId: r.invite_link_id,
        role: r.role,
        email: r.email,
        phone: r.phone,
        expiresAt: r.expires_at.toISOString(),
        acceptedAt: r.accepted_at?.toISOString() ?? null,
      })),
    });
  });

  async function acceptInvitation(
    userId: string,
    findQuery: string,
    findParam: string,
    body: { displayName?: string },
  ): Promise<{ circleId: string; role: string }> {
    return await withRls(pool, { role: 'app_service' }, async (client) => {
      const inv = await client.query<{
        id: string;
        circle_id: string;
        role: string;
        expires_at: Date;
        accepted_at: Date | null;
      }>(findQuery, [findParam]);
      const invitation = inv.rows[0];
      if (!invitation) {
        throw notFound('Invitation not found');
      }
      if (invitation.accepted_at) {
        throw conflict('Invitation already used', { code: 'invitation_already_used' });
      }
      if (invitation.expires_at.getTime() < Date.now()) {
        throw conflict('Invitation expired', { code: 'invitation_expired' });
      }

      const user = await client.query<{ display_name: string | null }>(
        `SELECT display_name FROM users WHERE id = $1`,
        [userId],
      );
      const display = body.displayName ?? user.rows[0]?.display_name ?? 'Member';

      const existingMember = await client.query<{ id: string }>(
        `SELECT id FROM circle_members WHERE circle_id = $1 AND user_id = $2 AND deleted_at IS NULL`,
        [invitation.circle_id, userId],
      );

      if (!existingMember.rows[0]) {
        await client.query(
          `INSERT INTO circle_members (circle_id, user_id, role, status, display_name, joined_at, invited_by)
           VALUES ($1, $2, $3, 'active', $4, NOW(), (SELECT invited_by FROM circle_invitations WHERE id = $5))`,
          [invitation.circle_id, userId, invitation.role, display, invitation.id],
        );
      }

      await client.query(
        `UPDATE circle_invitations SET accepted_at = NOW(), accepted_by = $2 WHERE id = $1`,
        [invitation.id, userId],
      );

      return { circleId: invitation.circle_id, role: invitation.role };
    });
  }

  app.post('/v1/invitations/:code/accept', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { code } = req.params as { code: string };
    const body = acceptInvitationSchema.parse(req.body ?? {});
    const result = await acceptInvitation(
      userId,
      `SELECT id, circle_id, role, expires_at, accepted_at FROM circle_invitations WHERE code = $1`,
      code,
      body,
    );
    reply.send({ circleId: result.circleId, role: result.role });
  });

  app.post('/v1/invitations/link/:linkId/accept', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { linkId } = req.params as { linkId: string };
    const body = acceptInvitationSchema.parse(req.body ?? {});
    const result = await acceptInvitation(
      userId,
      `SELECT id, circle_id, role, expires_at, accepted_at FROM circle_invitations WHERE invite_link_id = $1`,
      linkId,
      body,
    );
    reply.send({ circleId: result.circleId, role: result.role });
  });
}
