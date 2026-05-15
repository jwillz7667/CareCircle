import type { FastifyInstance } from 'fastify';
import {
  appStoreNotificationSchema,
  forbidden,
  subscriptionSyncSchema,
} from '@carecircle/shared';
import { requireMembership } from '../lib/membership.js';
import {
  applyNotification,
  applyTransactionToCircle,
  fetchCircleSubscription,
  inviteCapForTier,
  totalSeatCapForTier,
} from '../lib/subscriptions.js';

// ---------------------------------------------------------------------
// Subscription endpoints.
//
//   POST /v1/subscriptions/sync     — authenticated, owner-only.
//       iOS sends a signed transaction from StoreKit 2 after a
//       successful purchase or restore; we verify, apply, return state.
//
//   POST /v1/subscriptions/webhook  — unauthenticated, public.
//       Apple's App Store Server Notifications V2 endpoint. We always
//       return 200 once the JWS verifies and we've persisted; Apple
//       retries on non-2xx for hours, which would mask permanent
//       failures behind retry storms.
//
//   GET  /v1/subscriptions/circle/:circleId
//       Authenticated, any member. Returns the current subscription
//       state for a circle — drives the iOS paywall + feature gates.
// ---------------------------------------------------------------------

export async function subscriptionRoutes(app: FastifyInstance): Promise<void> {
  const { pool, storekit, logger } = app.ctx;

  app.post('/v1/subscriptions/sync', async (req, reply) => {
    const userId = await app.requireUser(req);
    const body = subscriptionSyncSchema.parse(req.body);

    const membership = await requireMembership(pool, userId, body.circleId);
    if (membership.role !== 'owner') {
      throw forbidden('Only the circle owner can manage the subscription');
    }

    const tx = await storekit.verifyTransaction(body.signedTransaction);
    const renewal = body.signedRenewalInfo
      ? await storekit.verifyRenewalInfo(body.signedRenewalInfo)
      : undefined;

    if (renewal && renewal.originalTransactionId !== tx.originalTransactionId) {
      throw forbidden('Renewal info does not match transaction');
    }

    const state = await applyTransactionToCircle(pool, body.circleId, tx, renewal);
    reply.status(200).send({
      subscription: subscriptionToJson(state),
      inviteCap: inviteCapForTier(state.tier),
      seatCap: totalSeatCapForTier(state.tier),
    });
  });

  app.get('/v1/subscriptions/circle/:circleId', async (req, reply) => {
    const userId = await app.requireUser(req);
    const { circleId } = req.params as { circleId: string };
    await requireMembership(pool, userId, circleId);
    const state = await fetchCircleSubscription(pool, circleId);
    reply.send({
      subscription: subscriptionToJson(state),
      inviteCap: inviteCapForTier(state.tier),
      seatCap: totalSeatCapForTier(state.tier),
    });
  });

  // Apple posts here. No auth — JWS signature IS the auth. We accept
  // every shape and return 200 once it verifies, regardless of whether
  // we found a circle to apply it to. A 404/500 here triggers Apple's
  // long retry chain.
  //
  // Per Fastify docs, route-scoped config disables our auth plugin's
  // implicit `requireUser` (which we don't apply globally anyway — see
  // plugins/auth.ts), so simply omitting `requireUser` is enough.
  app.post('/v1/subscriptions/webhook', async (req, reply) => {
    const body = appStoreNotificationSchema.parse(req.body);
    try {
      const event = await storekit.verifyNotification(body.signedPayload);
      const applied = await applyNotification(pool, event);
      logger.info(
        {
          notificationType: event.notificationType,
          subtype: event.subtype,
          notificationUUID: event.notificationUUID,
          appliedToCircle: applied?.circleId ?? null,
          newTier: applied?.tier ?? null,
          newStatus: applied?.status ?? null,
        },
        'app store notification processed',
      );
    } catch (err) {
      // Verification failure: log and 200 anyway. If Apple's signature
      // genuinely fails, it's because of a misconfig on our side
      // (wrong bundle id, wrong root cert) — retries won't help, and a
      // 5xx burns Apple's retry budget for no gain.
      logger.warn({ err }, 'failed to verify App Store notification — returning 200 to stop retries');
    }
    reply.status(200).send({ ok: true });
  });
}

function subscriptionToJson(state: {
  circleId: string;
  tier: string;
  status: string;
  productId: string | null;
  originalTransactionId: string | null;
  renewsAt: Date | null;
  graceUntil: Date | null;
  environment: string | null;
  trialUsed: boolean;
}): Record<string, unknown> {
  return {
    circleId: state.circleId,
    tier: state.tier,
    status: state.status,
    productId: state.productId,
    originalTransactionId: state.originalTransactionId,
    renewsAt: state.renewsAt?.toISOString() ?? null,
    graceUntil: state.graceUntil?.toISOString() ?? null,
    environment: state.environment,
    trialUsed: state.trialUsed,
  };
}
