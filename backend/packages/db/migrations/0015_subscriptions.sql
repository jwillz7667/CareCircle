-- =====================================================================
-- 0015 Subscriptions: rename tiers, App Store transaction tracking,
--                     new per-tier member caps
--
-- Renames `family` → `standard` and `pro` → `premium` on the existing
-- `subscription_tier` enum. Adds App Store transaction tracking columns
-- so the backend can verify and apply signed JWS transactions to a
-- circle. Drops the unused `revenuecat_subscriber_id` (RC never wired).
--
-- Replaces the member-cap trigger with the new owner-pays caps:
--   free      = 1 member  (owner only, no invites)
--   standard  = 7 members (owner + 6 invitees, includes care recipient)
--   premium   = 16 members (owner + 15 invitees)
--
-- `ALTER TYPE … RENAME VALUE` preserves existing rows; no UPDATE pass
-- is needed. Existing migrations + Drizzle schema reflect the new
-- values after 0015.
-- =====================================================================

-- 1. Rename enum values in place. Requires Postgres 10+.
ALTER TYPE subscription_tier RENAME VALUE 'family' TO 'standard';
ALTER TYPE subscription_tier RENAME VALUE 'pro'    TO 'premium';

-- 2. App Store transaction tracking columns on `circles`.
--    `subscription_original_transaction_id` is the stable identifier
--    Apple uses across renewals; the webhook looks circles up by it.
ALTER TABLE circles
    ADD COLUMN subscription_product_id              TEXT,
    ADD COLUMN subscription_original_transaction_id TEXT UNIQUE,
    ADD COLUMN subscription_grace_until             TIMESTAMPTZ,
    ADD COLUMN subscription_environment             TEXT,
    ADD COLUMN trial_used                           BOOLEAN NOT NULL DEFAULT FALSE;

-- 3. Drop unused RevenueCat column — we verify directly against Apple.
ALTER TABLE circles DROP COLUMN revenuecat_subscriber_id;

-- 4. Replace member-cap trigger with new caps.
--    `SELECT … FOR UPDATE` on the circles row serializes concurrent
--    member inserts for the same circle so two inserts can't both
--    squeeze past the cap on a race.
CREATE OR REPLACE FUNCTION enforce_circle_member_cap() RETURNS TRIGGER AS $$
DECLARE
  v_count INT;
  v_cap   INT;
  v_tier  subscription_tier;
BEGIN
  SELECT subscription_tier INTO v_tier FROM circles
   WHERE id = NEW.circle_id FOR UPDATE;

  SELECT COUNT(*) INTO v_count FROM circle_members
   WHERE circle_id = NEW.circle_id AND deleted_at IS NULL;

  v_cap := CASE v_tier
             WHEN 'free'     THEN 1
             WHEN 'standard' THEN 7
             WHEN 'premium'  THEN 16
           END;

  IF v_count >= v_cap THEN
    RAISE EXCEPTION 'Circle has reached its member cap of % for current plan', v_cap
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
