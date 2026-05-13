-- =====================================================================
-- 0004 Users, devices, circles, circle_keys, care_recipients
-- =====================================================================

CREATE TABLE users (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    apple_user_id       TEXT UNIQUE NOT NULL,
    email               CITEXT UNIQUE,
    is_private_email    BOOLEAN NOT NULL DEFAULT FALSE,
    display_name        TEXT,
    photo_object_key    TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ
);
CREATE INDEX users_apple_id_idx ON users(apple_user_id);
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE users FORCE ROW LEVEL SECURITY;

CREATE TABLE devices (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    apns_token      TEXT NOT NULL,
    device_name     TEXT,
    os_version      TEXT,
    app_version     TEXT,
    locale          TEXT,
    timezone        TEXT,
    last_active_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, apns_token)
);
CREATE INDEX devices_user_idx ON devices(user_id);
ALTER TABLE devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE devices FORCE ROW LEVEL SECURITY;

CREATE TABLE circles (
    id                       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name                     TEXT NOT NULL,
    owner_user_id            UUID NOT NULL REFERENCES users(id),
    care_recipient_id        UUID,
    subscription_tier        subscription_tier NOT NULL DEFAULT 'free',
    subscription_status      subscription_status NOT NULL DEFAULT 'active',
    subscription_renews_at   TIMESTAMPTZ,
    revenuecat_subscriber_id TEXT,
    settings                 JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at               TIMESTAMPTZ
);
CREATE INDEX circles_owner_idx ON circles(owner_user_id);
ALTER TABLE circles ENABLE ROW LEVEL SECURITY;
ALTER TABLE circles FORCE ROW LEVEL SECURITY;

CREATE TABLE circle_keys (
    circle_id           UUID PRIMARY KEY REFERENCES circles(id) ON DELETE CASCADE,
    encrypted_dek       BYTEA NOT NULL,
    key_version         INT NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    rotated_at          TIMESTAMPTZ
);
GRANT SELECT, INSERT, UPDATE ON circle_keys TO app_service;
REVOKE ALL ON circle_keys FROM app_user, app_anon;
ALTER TABLE circle_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE circle_keys FORCE ROW LEVEL SECURITY;

CREATE TABLE care_recipients (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    circle_id               UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    first_name_enc          BYTEA NOT NULL,
    last_name_enc           BYTEA,
    date_of_birth_enc       BYTEA,
    photo_object_key        TEXT,
    has_user_account        BOOLEAN NOT NULL DEFAULT FALSE,
    user_id                 UUID REFERENCES users(id),
    primary_conditions_enc  BYTEA,
    pronouns                TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at              TIMESTAMPTZ
);

ALTER TABLE circles
  ADD CONSTRAINT circles_recipient_fk
  FOREIGN KEY (care_recipient_id) REFERENCES care_recipients(id);
CREATE INDEX care_recipients_circle_idx ON care_recipients(circle_id);
ALTER TABLE care_recipients ENABLE ROW LEVEL SECURITY;
ALTER TABLE care_recipients FORCE ROW LEVEL SECURITY;

-- updated_at triggers
CREATE TRIGGER trg_users_updated           BEFORE UPDATE ON users           FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_circles_updated         BEFORE UPDATE ON circles         FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_care_recipients_updated BEFORE UPDATE ON care_recipients FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- RLS policies
-- (Cross-member visibility policy lives in 0005 after circle_members exists.)
CREATE POLICY users_self_read ON users FOR SELECT TO app_user
  USING (id = current_user_id());

CREATE POLICY users_self_write ON users FOR UPDATE TO app_user
  USING (id = current_user_id())
  WITH CHECK (id = current_user_id());

CREATE POLICY users_insert ON users FOR INSERT TO app_user
  WITH CHECK (id = current_user_id());

CREATE POLICY devices_self ON devices FOR ALL TO app_user
  USING (user_id = current_user_id())
  WITH CHECK (user_id = current_user_id());

CREATE POLICY circles_member_read ON circles FOR SELECT TO app_user
  USING (is_circle_member(id));

CREATE POLICY circles_owner_update ON circles FOR UPDATE TO app_user
  USING (owner_user_id = current_user_id())
  WITH CHECK (owner_user_id = current_user_id());

CREATE POLICY circles_owner_delete ON circles FOR DELETE TO app_user
  USING (owner_user_id = current_user_id());

CREATE POLICY circles_insert ON circles FOR INSERT TO app_user
  WITH CHECK (owner_user_id = current_user_id());

CREATE POLICY care_recipients_member ON care_recipients FOR ALL TO app_user
  USING (is_circle_member(circle_id))
  WITH CHECK (is_circle_member(circle_id));

-- Audit triggers
CREATE TRIGGER audit_care_recipients   AFTER INSERT OR UPDATE OR DELETE ON care_recipients FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();
