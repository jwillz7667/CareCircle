import type pg from 'pg';
import { withRls } from '@carecircle/db';
import { HttpError, forbidden, notFound } from '@carecircle/shared';

export type MemberRoleT =
  | 'owner'
  | 'family_member'
  | 'paid_aide'
  | 'paid_family'
  | 'care_recipient'
  | 'view_only';

export type Membership = {
  circleId: string;
  userId: string;
  role: MemberRoleT;
  status: 'invited' | 'active' | 'paused' | 'removed';
};

/**
 * Verify the current user has membership in circleId, optionally
 * with one of the required roles. Uses the service role so we get
 * an authoritative read regardless of RLS — caller is responsible
 * for ensuring the user identity in scope is correct.
 */
export async function requireMembership(
  pool: pg.Pool,
  userId: string,
  circleId: string,
  requiredRoles?: readonly MemberRoleT[],
): Promise<Membership> {
  const found = await withRls(pool, { role: 'app_service' }, async (client) => {
    const result = await client.query<Membership>(
      `SELECT circle_id AS "circleId",
              user_id   AS "userId",
              role,
              status
       FROM circle_members
       WHERE circle_id = $1
         AND user_id   = $2
         AND deleted_at IS NULL`,
      [circleId, userId],
    );
    return result.rows[0] ?? null;
  });

  if (!found) {
    throw notFound('Circle not found');
  }
  if (requiredRoles && !requiredRoles.includes(found.role)) {
    throw forbidden(`Requires role: ${requiredRoles.join(', ')}`);
  }
  return found;
}

export async function ensureCircleExists(pool: pg.Pool, circleId: string): Promise<void> {
  const found = await withRls(pool, { role: 'app_service' }, async (client) => {
    const result = await client.query<{ id: string }>(
      `SELECT id FROM circles WHERE id = $1 AND deleted_at IS NULL`,
      [circleId],
    );
    return result.rows[0] ?? null;
  });
  if (!found) {
    throw notFound('Circle not found');
  }
}

export function ensureNotEmpty<T>(row: T | undefined | null, message = 'Not found'): T {
  if (!row) {
    throw new HttpError(404, 'not_found', message);
  }
  return row;
}
