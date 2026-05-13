-- =====================================================================
-- 0003 Enums + immutable audit log
-- =====================================================================

CREATE TYPE subscription_tier   AS ENUM ('free', 'family', 'pro');
CREATE TYPE subscription_status AS ENUM ('trialing', 'active', 'past_due', 'canceled', 'expired');
CREATE TYPE member_role         AS ENUM (
  'owner', 'family_member', 'paid_aide', 'paid_family', 'care_recipient', 'view_only'
);
CREATE TYPE member_status       AS ENUM ('invited', 'active', 'paused', 'removed');
CREATE TYPE activity_type       AS ENUM (
  'voice_note', 'text_note', 'photo',
  'med_taken', 'med_skipped', 'med_missed',
  'vital_logged', 'appointment_logged',
  'shift_started', 'shift_ended',
  'document_added', 'sos_triggered', 'system'
);
CREATE TYPE med_status          AS ENUM ('active', 'as_needed', 'discontinued');
CREATE TYPE dose_status         AS ENUM ('scheduled', 'taken', 'skipped', 'missed', 'late');
CREATE TYPE document_type       AS ENUM (
  'insurance_card', 'advance_directive', 'dnr', 'med_list',
  'visit_summary', 'eob', 'lab_result', 'identification', 'other'
);

CREATE TABLE audit_log (
    id           BIGSERIAL PRIMARY KEY,
    occurred_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    actor_id     UUID,
    circle_id    UUID,
    action       TEXT NOT NULL,
    table_name   TEXT NOT NULL,
    row_id       UUID,
    diff         JSONB,
    ip_address   INET,
    user_agent   TEXT
);

CREATE INDEX audit_log_circle_time_idx ON audit_log(circle_id, occurred_at DESC);
CREATE INDEX audit_log_actor_time_idx  ON audit_log(actor_id, occurred_at DESC);

GRANT SELECT, INSERT ON audit_log TO app_user, app_service;
REVOKE UPDATE, DELETE ON audit_log FROM app_user, app_service;
GRANT USAGE, SELECT ON SEQUENCE audit_log_id_seq TO app_user, app_service;

ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log FORCE ROW LEVEL SECURITY;

CREATE POLICY audit_log_member_read ON audit_log
  FOR SELECT TO app_user
  USING (
    circle_id IS NULL OR is_circle_member(circle_id)
  );

CREATE POLICY audit_log_insert ON audit_log
  FOR INSERT TO app_user
  WITH CHECK (TRUE);

CREATE OR REPLACE FUNCTION audit_trigger_fn() RETURNS TRIGGER AS $$
DECLARE
  v_old JSONB;
  v_new JSONB;
  v_row_id UUID;
  v_circle_id UUID;
BEGIN
  IF (TG_OP = 'DELETE') THEN
    v_old := to_jsonb(OLD);
    v_row_id := OLD.id;
    v_circle_id := NULLIF(v_old->>'circle_id', '')::UUID;
  ELSIF (TG_OP = 'UPDATE') THEN
    v_old := to_jsonb(OLD);
    v_new := to_jsonb(NEW);
    v_row_id := NEW.id;
    v_circle_id := NULLIF(v_new->>'circle_id', '')::UUID;
  ELSE
    v_new := to_jsonb(NEW);
    v_row_id := NEW.id;
    v_circle_id := NULLIF(v_new->>'circle_id', '')::UUID;
  END IF;

  INSERT INTO audit_log (actor_id, circle_id, action, table_name, row_id, diff)
  VALUES (
    current_user_id(),
    v_circle_id,
    TG_OP,
    TG_TABLE_NAME,
    v_row_id,
    jsonb_build_object('before', v_old, 'after', v_new)
  );

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
