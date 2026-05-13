-- =====================================================================
-- 0006 Activities, reactions, comments
-- =====================================================================

CREATE TABLE activities (
    id                       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    circle_id                UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    author_user_id           UUID NOT NULL REFERENCES users(id),
    activity_type            activity_type NOT NULL,
    headline                 TEXT,
    content_enc              BYTEA,
    voice_object_key         TEXT,
    photo_object_keys        TEXT[],
    entities_enc             BYTEA,
    related_med_id           UUID,
    related_appointment_id   UUID,
    related_shift_id         UUID,
    occurred_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at               TIMESTAMPTZ,
    version                  BIGINT NOT NULL DEFAULT 1,
    client_op_id             UUID
);

CREATE INDEX activities_circle_time_idx ON activities(circle_id, occurred_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX activities_author_idx      ON activities(author_user_id);
CREATE INDEX activities_med_idx         ON activities(related_med_id) WHERE related_med_id IS NOT NULL;
CREATE UNIQUE INDEX activities_client_op_idx ON activities(circle_id, client_op_id) WHERE client_op_id IS NOT NULL;

ALTER TABLE activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE activities FORCE ROW LEVEL SECURITY;

CREATE TRIGGER trg_activities_updated BEFORE UPDATE ON activities FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE POLICY activities_member_read ON activities FOR SELECT TO app_user
  USING (is_circle_member(circle_id));

CREATE POLICY activities_member_write ON activities FOR INSERT TO app_user
  WITH CHECK (is_circle_member(circle_id) AND author_user_id = current_user_id());

CREATE POLICY activities_author_update ON activities FOR UPDATE TO app_user
  USING (author_user_id = current_user_id() AND deleted_at IS NULL)
  WITH CHECK (author_user_id = current_user_id());

CREATE POLICY activities_author_delete ON activities FOR DELETE TO app_user
  USING (author_user_id = current_user_id());

CREATE TRIGGER audit_activities AFTER INSERT OR UPDATE OR DELETE ON activities FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

CREATE TABLE activity_reactions (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    activity_id     UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
    circle_id       UUID NOT NULL,
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    emoji           TEXT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(activity_id, user_id, emoji)
);

CREATE INDEX reactions_activity_idx ON activity_reactions(activity_id);
ALTER TABLE activity_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity_reactions FORCE ROW LEVEL SECURITY;

CREATE POLICY reactions_member ON activity_reactions FOR ALL TO app_user
  USING (is_circle_member(circle_id))
  WITH CHECK (is_circle_member(circle_id) AND user_id = current_user_id());

CREATE TABLE activity_comments (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    activity_id     UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
    circle_id       UUID NOT NULL,
    author_user_id  UUID NOT NULL REFERENCES users(id),
    content_enc     BYTEA NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX comments_activity_idx ON activity_comments(activity_id, created_at);
ALTER TABLE activity_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity_comments FORCE ROW LEVEL SECURITY;

CREATE TRIGGER trg_activity_comments_updated BEFORE UPDATE ON activity_comments FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE POLICY comments_member ON activity_comments FOR ALL TO app_user
  USING (is_circle_member(circle_id))
  WITH CHECK (is_circle_member(circle_id) AND author_user_id = current_user_id());
