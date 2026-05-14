-- =====================================================================
-- 0012 End-of-shift digests
--
-- A short voice-narrated summary the off-going caregiver leaves for the
-- next caregiver. Transcript / summary / entities / structured-artifact
-- snapshot are all encrypted with the per-circle DEK (envelope cipher).
-- Realtime fan-out follows the same pattern as activities (Phase 22).
-- =====================================================================

CREATE TABLE shift_digests (
    id                       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    circle_id                UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    narrator_user_id         UUID NOT NULL REFERENCES users(id),
    shift_start_at           TIMESTAMPTZ NOT NULL,
    shift_end_at             TIMESTAMPTZ NOT NULL,
    transcript_enc           BYTEA,
    summary_enc              BYTEA,
    entities_enc             BYTEA,
    artifacts_enc            BYTEA,
    voice_object_key         TEXT,
    audio_duration_seconds   NUMERIC(7,2) NOT NULL DEFAULT 0,
    related_shift_id         UUID,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at               TIMESTAMPTZ,
    version                  BIGINT NOT NULL DEFAULT 1,
    client_op_id             UUID,
    CONSTRAINT shift_digests_window_ck CHECK (shift_end_at >= shift_start_at)
);

CREATE INDEX shift_digests_circle_time_idx ON shift_digests(circle_id, shift_end_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX shift_digests_narrator_idx    ON shift_digests(narrator_user_id);
CREATE INDEX shift_digests_related_idx     ON shift_digests(related_shift_id) WHERE related_shift_id IS NOT NULL;
CREATE UNIQUE INDEX shift_digests_client_op_idx ON shift_digests(circle_id, client_op_id) WHERE client_op_id IS NOT NULL;

ALTER TABLE shift_digests ENABLE ROW LEVEL SECURITY;
ALTER TABLE shift_digests FORCE ROW LEVEL SECURITY;

CREATE TRIGGER trg_shift_digests_updated BEFORE UPDATE ON shift_digests FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE POLICY shift_digests_member_read ON shift_digests FOR SELECT TO app_user
  USING (is_circle_member(circle_id));

CREATE POLICY shift_digests_member_write ON shift_digests FOR INSERT TO app_user
  WITH CHECK (is_circle_member(circle_id) AND narrator_user_id = current_user_id());

CREATE POLICY shift_digests_author_update ON shift_digests FOR UPDATE TO app_user
  USING (narrator_user_id = current_user_id() AND deleted_at IS NULL)
  WITH CHECK (narrator_user_id = current_user_id());

CREATE POLICY shift_digests_author_delete ON shift_digests FOR DELETE TO app_user
  USING (narrator_user_id = current_user_id());

CREATE TRIGGER audit_shift_digests AFTER INSERT OR UPDATE OR DELETE ON shift_digests FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

CREATE TRIGGER notify_shift_digests AFTER INSERT OR UPDATE OR DELETE ON shift_digests FOR EACH ROW EXECUTE FUNCTION notify_circle_change();
