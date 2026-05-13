-- =====================================================================
-- 0002 Helper functions for RLS
--
-- The API sets two session variables per request transaction:
--   SET LOCAL app.current_user_id = '<uuid>';
--   SET LOCAL app.current_circle_id = '<uuid>'; (optional)
-- These functions read them. STABLE so the planner can fold the call.
-- =====================================================================

CREATE OR REPLACE FUNCTION current_user_id() RETURNS UUID AS $$
DECLARE
  v_value TEXT := current_setting('app.current_user_id', TRUE);
BEGIN
  IF v_value IS NULL OR v_value = '' THEN
    RETURN NULL;
  END IF;
  RETURN v_value::UUID;
EXCEPTION WHEN invalid_text_representation THEN
  RETURN NULL;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION current_circle_id() RETURNS UUID AS $$
DECLARE
  v_value TEXT := current_setting('app.current_circle_id', TRUE);
BEGIN
  IF v_value IS NULL OR v_value = '' THEN
    RETURN NULL;
  END IF;
  RETURN v_value::UUID;
EXCEPTION WHEN invalid_text_representation THEN
  RETURN NULL;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION is_circle_member(p_circle_id UUID) RETURNS BOOLEAN AS $$
DECLARE
  v_exists BOOLEAN;
BEGIN
  EXECUTE 'SELECT EXISTS (
    SELECT 1 FROM circle_members
    WHERE circle_id = $1
      AND user_id   = current_user_id()
      AND deleted_at IS NULL
  )'
  INTO v_exists
  USING p_circle_id;
  RETURN v_exists;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION circle_member_has_role(p_circle_id UUID, p_roles TEXT[])
RETURNS BOOLEAN AS $$
DECLARE
  v_exists BOOLEAN;
BEGIN
  EXECUTE 'SELECT EXISTS (
    SELECT 1 FROM circle_members
    WHERE circle_id = $1
      AND user_id   = current_user_id()
      AND role::TEXT = ANY($2)
      AND deleted_at IS NULL
  )'
  INTO v_exists
  USING p_circle_id, p_roles;
  RETURN v_exists;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION current_user_id() TO app_user, app_service, app_anon;
GRANT EXECUTE ON FUNCTION current_circle_id() TO app_user, app_service, app_anon;
GRANT EXECUTE ON FUNCTION is_circle_member(UUID) TO app_user, app_service;
GRANT EXECUTE ON FUNCTION circle_member_has_role(UUID, TEXT[]) TO app_user, app_service;

CREATE OR REPLACE FUNCTION set_updated_at() RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
