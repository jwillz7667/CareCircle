-- =====================================================================
-- 0005 Circle members, invitations, member cap trigger
-- =====================================================================

CREATE TABLE circle_members (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    circle_id           UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role                member_role NOT NULL,
    status              member_status NOT NULL DEFAULT 'active',
    display_name        TEXT NOT NULL,
    permissions         JSONB NOT NULL DEFAULT '{}'::jsonb,
    notification_prefs  JSONB NOT NULL DEFAULT '{"push": true, "digest": "daily"}'::jsonb,
    invited_by          UUID REFERENCES users(id),
    invited_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    joined_at           TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ,
    UNIQUE(circle_id, user_id)
);

CREATE INDEX circle_members_user_idx   ON circle_members(user_id)   WHERE deleted_at IS NULL;
CREATE INDEX circle_members_circle_idx ON circle_members(circle_id) WHERE deleted_at IS NULL;

ALTER TABLE circle_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE circle_members FORCE ROW LEVEL SECURITY;

CREATE TRIGGER trg_circle_members_updated BEFORE UPDATE ON circle_members FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE POLICY circle_members_read ON circle_members FOR SELECT TO app_user
  USING (is_circle_member(circle_id));

CREATE POLICY circle_members_owner_insert ON circle_members FOR INSERT TO app_user
  WITH CHECK (
    circle_member_has_role(circle_id, ARRAY['owner'])
    OR (
      user_id = current_user_id()
      AND EXISTS (
        SELECT 1 FROM circles WHERE id = circle_id AND owner_user_id = current_user_id()
      )
    )
  );

CREATE POLICY circle_members_owner_update ON circle_members FOR UPDATE TO app_user
  USING (circle_member_has_role(circle_id, ARRAY['owner']))
  WITH CHECK (circle_member_has_role(circle_id, ARRAY['owner']));

CREATE POLICY circle_members_owner_delete ON circle_members FOR DELETE TO app_user
  USING (circle_member_has_role(circle_id, ARRAY['owner']));

CREATE OR REPLACE FUNCTION enforce_circle_member_cap() RETURNS TRIGGER AS $$
DECLARE
  v_count INT;
  v_cap   INT;
  v_tier  subscription_tier;
BEGIN
  SELECT COUNT(*) INTO v_count FROM circle_members
   WHERE circle_id = NEW.circle_id AND deleted_at IS NULL;

  SELECT subscription_tier INTO v_tier FROM circles WHERE id = NEW.circle_id;

  v_cap := CASE v_tier
             WHEN 'free' THEN 3
             ELSE 8
           END;

  IF v_count >= v_cap THEN
    RAISE EXCEPTION 'Circle has reached its member cap of % for current plan', v_cap
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER circle_members_cap_trg
  BEFORE INSERT ON circle_members
  FOR EACH ROW EXECUTE FUNCTION enforce_circle_member_cap();

CREATE TRIGGER audit_circle_members AFTER INSERT OR UPDATE OR DELETE ON circle_members FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

CREATE TABLE circle_invitations (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    circle_id       UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    invited_by      UUID NOT NULL REFERENCES users(id),
    role            member_role NOT NULL,
    code            TEXT NOT NULL UNIQUE,
    invite_link_id  UUID NOT NULL DEFAULT uuid_generate_v4(),
    email           CITEXT,
    phone           TEXT,
    expires_at      TIMESTAMPTZ NOT NULL,
    accepted_at     TIMESTAMPTZ,
    accepted_by     UUID REFERENCES users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX circle_invitations_circle_idx ON circle_invitations(circle_id);
CREATE INDEX circle_invitations_link_idx   ON circle_invitations(invite_link_id);

ALTER TABLE circle_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE circle_invitations FORCE ROW LEVEL SECURITY;

CREATE POLICY invitations_member_read ON circle_invitations FOR SELECT TO app_user
  USING (is_circle_member(circle_id));

CREATE POLICY invitations_owner_create ON circle_invitations FOR INSERT TO app_user
  WITH CHECK (circle_member_has_role(circle_id, ARRAY['owner']));

CREATE POLICY invitations_owner_update ON circle_invitations FOR UPDATE TO app_user
  USING (is_circle_member(circle_id) OR accepted_by = current_user_id())
  WITH CHECK (is_circle_member(circle_id) OR accepted_by = current_user_id());

CREATE POLICY invitations_owner_delete ON circle_invitations FOR DELETE TO app_user
  USING (circle_member_has_role(circle_id, ARRAY['owner']));

-- Cross-member visibility on users: members of the same circle can read each other's minimal profile.
-- Postgres ORs SELECT policies, so this composes with users_self_read from 0004.
CREATE POLICY users_circle_co_member_read ON users FOR SELECT TO app_user
  USING (
    EXISTS (
      SELECT 1 FROM circle_members cm1
      JOIN circle_members cm2 ON cm1.circle_id = cm2.circle_id
      WHERE cm1.user_id = current_user_id()
        AND cm2.user_id = users.id
        AND cm1.deleted_at IS NULL
        AND cm2.deleted_at IS NULL
    )
  );
