-- =====================================================================
-- 0011 — Owner can SELECT their own circle, even before the owner row
-- has been written to circle_members.
--
-- Without this policy, `INSERT INTO circles ... RETURNING id` fails with
-- a row-level-security violation because INSERT ... RETURNING also
-- applies the SELECT policy to the new row. The pre-existing
-- circles_member_read policy uses `is_circle_member(id)` which is false
-- on a circle whose membership row has not been written yet.
--
-- Permissive policies are OR-combined, so this only widens visibility
-- to owners — non-owners still need a membership row to see the circle.
-- =====================================================================

CREATE POLICY circles_owner_read ON circles FOR SELECT TO app_user
  USING (owner_user_id = current_user_id());
