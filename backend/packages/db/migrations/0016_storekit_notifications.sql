-- =====================================================================
-- 0016 StoreKit notification idempotency + monotonic ordering
--
-- App Store Server Notifications V2 are delivered at-least-once: Apple
-- retries the same notificationUUID for hours on any non-2xx and can
-- redeliver even after a 2xx. They can also arrive out of order (a stale
-- EXPIRED landing after a newer DID_RENEW). Before 0016 the webhook
-- applied every notification with an unconditional UPDATE, so a retry was
-- harmless only by luck and an out-of-order delivery could regress a
-- circle's subscription to an older state.
--
-- This migration adds:
--   1. `storekit_notifications` — an append-only ledger keyed on the
--      notificationUUID. The webhook inserts ON CONFLICT DO NOTHING; a
--      conflict means "already processed" and the apply is skipped.
--   2. `circles.subscription_event_at` — the signedDate of the last
--      event (webhook OR client sync) applied to the subscription. The
--      apply path refuses to overwrite newer state with an older event.
-- =====================================================================

-- Service-only ledger: only the webhook (no user context) writes here.
-- Same posture as circle_keys / refresh_tokens — revoke app_user, force RLS.
CREATE TABLE storekit_notifications (
  -- TEXT, not UUID: Apple's notificationUUID is a UUID today, but the PK's
  -- job is dedupe, not validation — don't couple the ledger to a format.
  notification_uuid        TEXT PRIMARY KEY,
  notification_type        TEXT NOT NULL,
  subtype                  TEXT,
  circle_id                UUID REFERENCES circles(id) ON DELETE SET NULL,
  original_transaction_id  TEXT,
  environment              TEXT,
  -- Apple's per-notification signedDate; the monotonic ordering key.
  signed_date              TIMESTAMPTZ,
  applied                  BOOLEAN NOT NULL DEFAULT FALSE,
  applied_status           subscription_status,
  received_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX storekit_notifications_circle_idx
  ON storekit_notifications (circle_id, signed_date DESC);

GRANT SELECT, INSERT, UPDATE ON storekit_notifications TO app_service;
REVOKE ALL ON storekit_notifications FROM app_user, app_anon;
ALTER TABLE storekit_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE storekit_notifications FORCE ROW LEVEL SECURITY;

-- Monotonic ordering guard on the circle's subscription. NULL until the
-- first event applies; thereafter the apply path only advances it.
ALTER TABLE circles
  ADD COLUMN subscription_event_at TIMESTAMPTZ;
