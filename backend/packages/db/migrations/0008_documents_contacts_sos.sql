-- =====================================================================
-- 0008 Documents, emergency contacts, SOS events, care minute entries,
--      pending operations
-- =====================================================================

CREATE TABLE documents (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    circle_id           UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    title_enc           BYTEA NOT NULL,
    document_type       document_type NOT NULL,
    object_key          TEXT NOT NULL,
    mime_type           TEXT NOT NULL,
    size_bytes          BIGINT NOT NULL,
    encryption_nonce    BYTEA NOT NULL,
    encryption_tag      BYTEA NOT NULL,
    issued_at           DATE,
    expires_at          DATE,
    uploaded_by         UUID NOT NULL REFERENCES users(id),
    visibility          member_role[] NOT NULL DEFAULT ARRAY['owner','family_member','paid_family','care_recipient']::member_role[],
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ
);
CREATE INDEX documents_circle_idx ON documents(circle_id) WHERE deleted_at IS NULL;
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents FORCE ROW LEVEL SECURITY;
CREATE TRIGGER trg_documents_updated BEFORE UPDATE ON documents FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE POLICY documents_member_read ON documents FOR SELECT TO app_user
  USING (
    is_circle_member(circle_id) AND EXISTS (
      SELECT 1 FROM circle_members cm
      WHERE cm.circle_id = documents.circle_id
        AND cm.user_id   = current_user_id()
        AND cm.role      = ANY(documents.visibility)
        AND cm.deleted_at IS NULL
    )
  );

CREATE POLICY documents_member_write ON documents FOR INSERT TO app_user
  WITH CHECK (is_circle_member(circle_id) AND uploaded_by = current_user_id());

CREATE POLICY documents_member_update ON documents FOR UPDATE TO app_user
  USING (is_circle_member(circle_id) AND uploaded_by = current_user_id())
  WITH CHECK (is_circle_member(circle_id));

CREATE POLICY documents_member_delete ON documents FOR DELETE TO app_user
  USING (is_circle_member(circle_id) AND uploaded_by = current_user_id());

CREATE TRIGGER audit_documents AFTER INSERT OR UPDATE OR DELETE ON documents FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

CREATE TABLE emergency_contacts (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    circle_id       UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    name_enc        BYTEA NOT NULL,
    relationship    TEXT,
    phone_enc       BYTEA NOT NULL,
    is_primary      BOOLEAN NOT NULL DEFAULT FALSE,
    is_medical      BOOLEAN NOT NULL DEFAULT FALSE,
    sort_order      INT NOT NULL DEFAULT 100,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);
CREATE INDEX emergency_contacts_circle_idx ON emergency_contacts(circle_id, sort_order) WHERE deleted_at IS NULL;
ALTER TABLE emergency_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE emergency_contacts FORCE ROW LEVEL SECURITY;
CREATE TRIGGER trg_emergency_contacts_updated BEFORE UPDATE ON emergency_contacts FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE POLICY ec_member ON emergency_contacts FOR ALL TO app_user
  USING (is_circle_member(circle_id))
  WITH CHECK (is_circle_member(circle_id));

CREATE TABLE sos_events (
    id                       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    circle_id                UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    triggered_by             UUID NOT NULL REFERENCES users(id),
    triggered_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    canceled_at              TIMESTAMPTZ,
    canceled_by              UUID REFERENCES users(id),
    location_lat             NUMERIC(9,6),
    location_lng             NUMERIC(9,6),
    location_accuracy_m      NUMERIC(6,1),
    notified_user_ids        UUID[] NOT NULL DEFAULT ARRAY[]::UUID[],
    primary_contact_called   BOOLEAN NOT NULL DEFAULT FALSE,
    resolution_notes_enc     BYTEA
);
CREATE INDEX sos_circle_time_idx ON sos_events(circle_id, triggered_at DESC);
ALTER TABLE sos_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE sos_events FORCE ROW LEVEL SECURITY;
CREATE POLICY sos_member ON sos_events FOR ALL TO app_user
  USING (is_circle_member(circle_id))
  WITH CHECK (is_circle_member(circle_id) AND triggered_by = current_user_id());
CREATE TRIGGER audit_sos_events AFTER INSERT OR UPDATE OR DELETE ON sos_events FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

CREATE TABLE care_minute_entries (
    id                       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    circle_id                UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    caregiver_user_id        UUID NOT NULL REFERENCES users(id),
    shift_id                 UUID REFERENCES care_shifts(id),
    service_code             TEXT NOT NULL,
    service_description      TEXT NOT NULL,
    started_at               TIMESTAMPTZ NOT NULL,
    ended_at                 TIMESTAMPTZ NOT NULL,
    duration_minutes         INT NOT NULL,
    notes_enc                BYTEA,
    fiscal_intermediary      TEXT,
    exported_at              TIMESTAMPTZ,
    export_pdf_key           TEXT,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at               TIMESTAMPTZ
);
CREATE INDEX care_min_circle_time_idx ON care_minute_entries(circle_id, started_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX care_min_caregiver_idx   ON care_minute_entries(caregiver_user_id, started_at DESC);
ALTER TABLE care_minute_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE care_minute_entries FORCE ROW LEVEL SECURITY;
CREATE TRIGGER trg_care_minute_updated BEFORE UPDATE ON care_minute_entries FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE POLICY cm_caregiver ON care_minute_entries FOR ALL TO app_user
  USING (
    is_circle_member(circle_id) AND (
      caregiver_user_id = current_user_id()
      OR circle_member_has_role(circle_id, ARRAY['owner'])
    )
  )
  WITH CHECK (caregiver_user_id = current_user_id());
CREATE TRIGGER audit_care_minute AFTER INSERT OR UPDATE OR DELETE ON care_minute_entries FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

CREATE TABLE pending_operations (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    client_op_id    UUID NOT NULL,
    user_id         UUID NOT NULL REFERENCES users(id),
    circle_id       UUID,
    operation_type  TEXT NOT NULL,
    payload         JSONB NOT NULL,
    processed_at    TIMESTAMPTZ,
    result          JSONB,
    error           TEXT,
    received_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, client_op_id)
);
CREATE INDEX pending_ops_user_idx ON pending_operations(user_id, received_at DESC);
ALTER TABLE pending_operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE pending_operations FORCE ROW LEVEL SECURITY;
CREATE POLICY pending_ops_self ON pending_operations FOR ALL TO app_user
  USING (user_id = current_user_id())
  WITH CHECK (user_id = current_user_id());
