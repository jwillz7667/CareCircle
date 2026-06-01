-- =====================================================================
-- 0017 Restrict NULL-circle audit_log rows to their actor
--
-- The original audit_log_member_read policy (migration 0003) read:
--   USING (circle_id IS NULL OR is_circle_member(circle_id))
-- The `circle_id IS NULL OR` clause made EVERY circle-less audit row (auth
-- events, account-level actions, anything written before a circle exists)
-- readable by EVERY app_user. Those rows carry actor_id, action, IP and
-- user-agent — a cross-tenant information leak.
--
-- Restrict NULL-circle rows to the actor that produced them; circle-scoped
-- rows stay gated on membership exactly as before.
-- =====================================================================

DROP POLICY audit_log_member_read ON audit_log;

CREATE POLICY audit_log_member_read ON audit_log
  FOR SELECT TO app_user
  USING (
    (circle_id IS NOT NULL AND is_circle_member(circle_id))
    OR (circle_id IS NULL AND actor_id = current_user_id())
  );
