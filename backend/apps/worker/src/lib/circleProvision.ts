import { newDek, unwrapDek, wrapDek } from '@carecircle/shared';
import type pg from 'pg';

/**
 * The iOS client owns Circle identity in CloudKit and never calls
 * `POST /v1/circles`, so the backend-of-record only learns a Circle exists
 * when the sync projector first touches one of its rows. This helper makes
 * that touch self-healing: it idempotently materialises the Circle, its
 * envelope-wrapped DEK, and an owner membership for the submitting user,
 * then returns the unwrapped DEK so the caller can encrypt PHI columns.
 *
 * Runs inside the caller's transaction (under the `app_service` role) so the
 * provisioning and the content insert commit atomically. The owner is the
 * first user to sync into the Circle; subsequent `create_member` ops reconcile
 * the full roster. Client UUIDs are random, so cross-tenant collision is not a
 * concern.
 */
export async function ensureCircleProvisioned(
  client: pg.PoolClient,
  params: { circleId: string; ownerUserId: string; masterKey: string },
): Promise<Buffer> {
  const { circleId, ownerUserId, masterKey } = params;

  await client.query(
    `INSERT INTO circles (id, name, owner_user_id)
     VALUES ($1, $2, $3)
     ON CONFLICT (id) DO NOTHING`,
    [circleId, 'Care Circle', ownerUserId],
  );

  const existing = await client.query<{ encrypted_dek: Buffer }>(
    `SELECT encrypted_dek FROM circle_keys WHERE circle_id = $1`,
    [circleId],
  );
  let dek: Buffer;
  if (existing.rows[0]) {
    dek = unwrapDek(existing.rows[0].encrypted_dek, masterKey);
  } else {
    const fresh = newDek();
    await client.query(
      `INSERT INTO circle_keys (circle_id, encrypted_dek)
       VALUES ($1, $2)
       ON CONFLICT (circle_id) DO NOTHING`,
      [circleId, wrapDek(fresh, masterKey)],
    );
    // Re-read to win any race where a concurrent op inserted first; the
    // persisted DEK is authoritative, not the one we just generated.
    const reread = await client.query<{ encrypted_dek: Buffer }>(
      `SELECT encrypted_dek FROM circle_keys WHERE circle_id = $1`,
      [circleId],
    );
    const persisted = reread.rows[0];
    if (!persisted) {
      throw new Error(`circle_keys row vanished for circle ${circleId}`);
    }
    dek = unwrapDek(persisted.encrypted_dek, masterKey);
  }

  await client.query(
    `INSERT INTO circle_members (circle_id, user_id, role, status, display_name)
     SELECT $1, $2, 'owner', 'active', COALESCE(u.display_name, 'Member')
     FROM users u
     WHERE u.id = $2
     ON CONFLICT (circle_id, user_id) DO NOTHING`,
    [circleId, ownerUserId],
  );

  return dek;
}
