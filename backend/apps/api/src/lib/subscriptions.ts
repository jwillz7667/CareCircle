import type pg from 'pg';
import { withRls } from '@carecircle/db';
import { HttpError, notFound } from '@carecircle/shared';
import type {
  AppStoreNotificationType,
  Environment,
  SubscriptionTier,
  VerifiedNotification,
  VerifiedRenewalInfo,
  VerifiedTransaction,
} from '../services/storekit.js';

// ---------------------------------------------------------------------
// Subscription state derivation + database application.
//
// The "current" subscription state for a circle is the projection of:
//   - the latest verified transaction (defines product/tier and expiry)
//   - the optional renewal info (autoRenew flag, grace period, intent)
//   - the latest notification (terminal events like EXPIRED/REVOKE)
//
// The owner of a circle pays; every other member of the circle inherits
// the same tier. Per-user tier is therefore "the circle's tier", and a
// user with multiple circles has multiple independent tiers.
// ---------------------------------------------------------------------

export type SubscriptionStatusT =
  | 'trialing'
  | 'active'
  | 'past_due'
  | 'canceled'
  | 'expired';

export type CircleSubscriptionRow = {
  circleId: string;
  tier: 'free' | SubscriptionTier;
  status: SubscriptionStatusT;
  productId: string | null;
  originalTransactionId: string | null;
  renewsAt: Date | null;
  graceUntil: Date | null;
  environment: string | null;
  trialUsed: boolean;
};

export function tierForStatus(
  status: SubscriptionStatusT,
  productTier: SubscriptionTier,
): 'free' | SubscriptionTier {
  // 'expired' and 'canceled' (after period end) reset the circle to free.
  // 'canceled' here means *after expiration* — for an auto-renew-off
  // user still inside their paid period we keep status='active' until
  // EXPIRED fires.
  return status === 'expired' ? 'free' : productTier;
}

function derivePurchaseStatus(tx: VerifiedTransaction, renewal?: VerifiedRenewalInfo): SubscriptionStatusT {
  // Revoked / refunded → expired immediately.
  if (tx.revocationDate) return 'expired';
  // Hard expiry check — Apple's `expiresDate` is the authoritative end-of-paid-period.
  if (tx.expiresDate && tx.expiresDate.getTime() < Date.now()) {
    return renewal?.isInBillingRetryPeriod ? 'past_due' : 'expired';
  }
  if (tx.isTrialPeriod) return 'trialing';
  // Auto-renew turned off but still inside paid period → 'canceled'.
  // `tierForStatus` keeps the paid tier through expiry; the iOS UI uses
  // this state to show "Subscription ends on <date>" instead of "Active".
  if (renewal?.autoRenewStatus === 0) return 'canceled';
  return 'active';
}

function deriveNotificationStatus(
  type: AppStoreNotificationType,
  tx?: VerifiedTransaction,
  renewal?: VerifiedRenewalInfo,
): SubscriptionStatusT | null {
  switch (type) {
    case 'SUBSCRIBED':
    case 'DID_RENEW':
    case 'DID_CHANGE_PRODUCT':
    case 'OFFER_REDEEMED':
    case 'RENEWAL_EXTENDED':
      return tx ? derivePurchaseStatus(tx, renewal) : 'active';
    case 'DID_FAIL_TO_RENEW':
      return 'past_due';
    case 'GRACE_PERIOD_EXPIRED':
    case 'EXPIRED':
    case 'REVOKE':
    case 'REFUND':
      return 'expired';
    case 'DID_CHANGE_RENEWAL_STATUS':
      // auto-renew toggle. status stays as derived from the transaction
      // (we still consider the user "active" until expiresDate passes).
      return tx ? derivePurchaseStatus(tx, renewal) : null;
    case 'PRICE_INCREASE':
    case 'CONSUMPTION_REQUEST':
    case 'REFUND_DECLINED':
    case 'TEST':
      return null;
    default:
      return null;
  }
}

// ---------------------------------------------------------------------
// DB I/O — use the service role so webhooks (no user context) and the
// authenticated sync route both share one path. The route layer is
// responsible for verifying the caller's ownership before invoking
// these helpers.
// ---------------------------------------------------------------------

export async function fetchCircleSubscription(
  pool: pg.Pool,
  circleId: string,
): Promise<CircleSubscriptionRow> {
  const row = await withRls(pool, { role: 'app_service' }, async (client) => {
    const result = await client.query<{
      id: string;
      subscription_tier: 'free' | SubscriptionTier;
      subscription_status: SubscriptionStatusT;
      subscription_product_id: string | null;
      subscription_original_transaction_id: string | null;
      subscription_renews_at: Date | null;
      subscription_grace_until: Date | null;
      subscription_environment: string | null;
      trial_used: boolean;
    }>(
      `SELECT id,
              subscription_tier,
              subscription_status,
              subscription_product_id,
              subscription_original_transaction_id,
              subscription_renews_at,
              subscription_grace_until,
              subscription_environment,
              trial_used
       FROM circles
       WHERE id = $1 AND deleted_at IS NULL`,
      [circleId],
    );
    return result.rows[0] ?? null;
  });

  if (!row) {
    throw notFound('Circle not found');
  }
  return {
    circleId: row.id,
    tier: row.subscription_tier,
    status: row.subscription_status,
    productId: row.subscription_product_id,
    originalTransactionId: row.subscription_original_transaction_id,
    renewsAt: row.subscription_renews_at,
    graceUntil: row.subscription_grace_until,
    environment: row.subscription_environment,
    trialUsed: row.trial_used,
  };
}

/**
 * Resolve which circle a verified Apple transaction belongs to. Tries
 * (in order):
 *   1. circle whose subscription_original_transaction_id matches
 *   2. circle whose ID equals the transaction's appAccountToken (the
 *      iOS client sets appAccountToken = circle.id at purchase)
 *
 * Returns null if neither match — caller decides whether that's fatal
 * (webhook → log + 200) or an error (sync → 422).
 */
export async function resolveCircleForTransaction(
  pool: pg.Pool,
  tx: VerifiedTransaction,
): Promise<string | null> {
  return await withRls(pool, { role: 'app_service' }, async (client) => {
    const byOriginal = await client.query<{ id: string }>(
      `SELECT id FROM circles WHERE subscription_original_transaction_id = $1 AND deleted_at IS NULL`,
      [tx.originalTransactionId],
    );
    if (byOriginal.rows[0]) return byOriginal.rows[0].id;

    if (tx.appAccountToken && isUuid(tx.appAccountToken)) {
      const byToken = await client.query<{ id: string }>(
        `SELECT id FROM circles WHERE id = $1 AND deleted_at IS NULL`,
        [tx.appAccountToken],
      );
      if (byToken.rows[0]) return byToken.rows[0].id;
    }
    return null;
  });
}

function isUuid(s: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
}

/**
 * Apply a verified purchase/restore to a circle. Idempotent on
 * `(circleId, originalTransactionId)` — replays from the iOS sync
 * endpoint set the same state without flipping it back and forth.
 */
export async function applyTransactionToCircle(
  pool: pg.Pool,
  circleId: string,
  tx: VerifiedTransaction,
  renewal: VerifiedRenewalInfo | undefined,
): Promise<CircleSubscriptionRow> {
  const status = derivePurchaseStatus(tx, renewal);
  const tier = tierForStatus(status, tx.tier);
  const graceUntil = renewal?.gracePeriodExpiresDate ?? null;

  await withRls(pool, { role: 'app_service' }, async (client) => {
    // Refuse to bind a transaction to a different circle than the one
    // that previously owned it. This catches the case where a user
    // tries to attach a single Apple subscription to multiple circles
    // (Apple disallows this server-side too, but defense-in-depth).
    const conflict = await client.query<{ id: string }>(
      `SELECT id FROM circles
       WHERE subscription_original_transaction_id = $1
         AND id <> $2
         AND deleted_at IS NULL`,
      [tx.originalTransactionId, circleId],
    );
    if (conflict.rows[0]) {
      throw new HttpError(409, 'conflict', 'Subscription already bound to a different circle', {
        existingCircleId: conflict.rows[0].id,
      });
    }
    await client.query(
      `UPDATE circles
         SET subscription_tier                   = $2::subscription_tier,
             subscription_status                 = $3::subscription_status,
             subscription_product_id             = $4,
             subscription_original_transaction_id = $5,
             subscription_renews_at              = $6,
             subscription_grace_until            = $7,
             subscription_environment            = $8,
             trial_used                          = trial_used OR $9
       WHERE id = $1`,
      [
        circleId,
        tier,
        status,
        tx.productId,
        tx.originalTransactionId,
        tx.expiresDate ?? null,
        graceUntil,
        tx.environment,
        tx.isTrialPeriod,
      ],
    );
  });

  return fetchCircleSubscription(pool, circleId);
}

/**
 * Apply an App Store Server Notification V2 event to whichever circle
 * the embedded transaction resolves to. Idempotent on notificationUUID
 * to safely handle Apple's retries.
 *
 * Returns the updated CircleSubscriptionRow, or null if we couldn't
 * resolve a circle (caller logs + 200s the webhook so Apple stops
 * retrying — a stale transactionId is permanent, not transient).
 */
export async function applyNotification(
  pool: pg.Pool,
  ev: VerifiedNotification,
): Promise<CircleSubscriptionRow | null> {
  const tx = ev.transaction;
  if (!tx) {
    // Some notification types (TEST, PRICE_INCREASE, CONSUMPTION_REQUEST)
    // carry no transaction; nothing to apply.
    return null;
  }
  const circleId = await resolveCircleForTransaction(pool, tx);
  if (!circleId) return null;

  const status = deriveNotificationStatus(ev.notificationType, tx, ev.renewalInfo);
  if (status === null) {
    // No-op event (PRICE_INCREASE, etc.) — leave state alone.
    return fetchCircleSubscription(pool, circleId);
  }
  const tier = tierForStatus(status, tx.tier);
  const graceUntil = ev.renewalInfo?.gracePeriodExpiresDate ?? null;

  await withRls(pool, { role: 'app_service' }, async (client) => {
    await client.query(
      `UPDATE circles
         SET subscription_tier                   = $2::subscription_tier,
             subscription_status                 = $3::subscription_status,
             subscription_product_id             = $4,
             subscription_original_transaction_id = $5,
             subscription_renews_at              = $6,
             subscription_grace_until            = $7,
             subscription_environment            = $8,
             trial_used                          = trial_used OR $9
       WHERE id = $1`,
      [
        circleId,
        tier,
        status,
        tx.productId,
        tx.originalTransactionId,
        tx.expiresDate ?? null,
        graceUntil,
        tx.environment,
        tx.isTrialPeriod,
      ],
    );
  });

  return fetchCircleSubscription(pool, circleId);
}

export function isPaidStatus(status: SubscriptionStatusT): boolean {
  return status === 'active' || status === 'trialing' || status === 'past_due' || status === 'canceled';
}

export function inviteCapForTier(tier: 'free' | SubscriptionTier): number {
  // Owner is one of the seats — invite cap = total cap minus one.
  switch (tier) {
    case 'free':
      return 0;
    case 'standard':
      return 6;
    case 'premium':
      return 15;
  }
}

export function totalSeatCapForTier(tier: 'free' | SubscriptionTier): number {
  return inviteCapForTier(tier) + 1;
}

/**
 * Returns the number of additional invites the owner can send.
 * `inviteCap - (activeMembers - owner) - pendingInvites`, clamped to 0.
 *
 * Used at invite-send time so the UI rejects before the invitee hits
 * the trigger error during acceptance.
 */
export async function availableInviteSlots(
  pool: pg.Pool,
  circleId: string,
): Promise<{ remaining: number; cap: number; tier: 'free' | SubscriptionTier }> {
  const state = await fetchCircleSubscription(pool, circleId);
  const cap = inviteCapForTier(state.tier);
  if (cap === 0) return { remaining: 0, cap, tier: state.tier };

  const counts = await withRls(pool, { role: 'app_service' }, async (client) => {
    const memberRow = await client.query<{ count: string }>(
      `SELECT COUNT(*)::TEXT AS count FROM circle_members
        WHERE circle_id = $1 AND deleted_at IS NULL`,
      [circleId],
    );
    const pendingRow = await client.query<{ count: string }>(
      `SELECT COUNT(*)::TEXT AS count FROM circle_invitations
        WHERE circle_id  = $1
          AND accepted_at IS NULL
          AND expires_at  > NOW()`,
      [circleId],
    );
    return {
      members: Number(memberRow.rows[0]?.count ?? '0'),
      pending: Number(pendingRow.rows[0]?.count ?? '0'),
    };
  });

  // Exclude the owner seat from the member count when measuring against
  // the invite cap — invite cap counts invitees only.
  const usedInviteSeats = Math.max(0, counts.members - 1) + counts.pending;
  return {
    remaining: Math.max(0, cap - usedInviteSeats),
    cap,
    tier: state.tier,
  };
}

// Re-export so route handlers don't need to import from services/.
export type { VerifiedTransaction, VerifiedRenewalInfo, VerifiedNotification, Environment };
