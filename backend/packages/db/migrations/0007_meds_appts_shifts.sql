-- =====================================================================
-- 0007 Medications, dose events, appointments, attendees, care shifts
-- =====================================================================

CREATE TABLE medications (
    id                       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    circle_id                UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    name_enc                 BYTEA NOT NULL,
    generic_name_enc         BYTEA,
    dosage_enc               BYTEA NOT NULL,
    form                     TEXT,
    rxcui                    TEXT,
    color                    TEXT,
    status                   med_status NOT NULL DEFAULT 'active',
    schedule                 JSONB NOT NULL DEFAULT '{}'::jsonb,
    prescribing_provider_enc BYTEA,
    pharmacy_enc             BYTEA,
    notes_enc                BYTEA,
    start_date               DATE,
    end_date                 DATE,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at               TIMESTAMPTZ
);
CREATE INDEX medications_circle_idx ON medications(circle_id) WHERE deleted_at IS NULL;
ALTER TABLE medications ENABLE ROW LEVEL SECURITY;
ALTER TABLE medications FORCE ROW LEVEL SECURITY;
CREATE TRIGGER trg_medications_updated BEFORE UPDATE ON medications FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE POLICY medications_member ON medications FOR ALL TO app_user
  USING (is_circle_member(circle_id))
  WITH CHECK (is_circle_member(circle_id));
CREATE TRIGGER audit_medications AFTER INSERT OR UPDATE OR DELETE ON medications FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

CREATE TABLE dose_events (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    medication_id   UUID NOT NULL REFERENCES medications(id) ON DELETE CASCADE,
    circle_id       UUID NOT NULL,
    scheduled_at    TIMESTAMPTZ NOT NULL,
    taken_at        TIMESTAMPTZ,
    marked_by       UUID REFERENCES users(id),
    status          dose_status NOT NULL DEFAULT 'scheduled',
    notes_enc       BYTEA,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX dose_events_med_time_idx    ON dose_events(medication_id, scheduled_at);
CREATE INDEX dose_events_circle_time_idx ON dose_events(circle_id, scheduled_at DESC);
ALTER TABLE dose_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE dose_events FORCE ROW LEVEL SECURITY;
CREATE TRIGGER trg_dose_events_updated BEFORE UPDATE ON dose_events FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE POLICY dose_events_member ON dose_events FOR ALL TO app_user
  USING (is_circle_member(circle_id))
  WITH CHECK (is_circle_member(circle_id));
CREATE TRIGGER audit_dose_events AFTER INSERT OR UPDATE OR DELETE ON dose_events FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

CREATE TABLE appointments (
    id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    circle_id                   UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    title_enc                   BYTEA NOT NULL,
    provider_enc                BYTEA,
    location_enc                BYTEA,
    starts_at                   TIMESTAMPTZ NOT NULL,
    duration_minutes            INT NOT NULL DEFAULT 60,
    transport_responsible       UUID REFERENCES users(id),
    prep_notes_enc              BYTEA,
    visit_summary_enc           BYTEA,
    reminder_minutes_before     INT[] NOT NULL DEFAULT ARRAY[1440, 60]::INT[],
    created_by                  UUID NOT NULL REFERENCES users(id),
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at                  TIMESTAMPTZ
);
CREATE INDEX appointments_circle_time_idx ON appointments(circle_id, starts_at) WHERE deleted_at IS NULL;
ALTER TABLE appointments ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointments FORCE ROW LEVEL SECURITY;
CREATE TRIGGER trg_appointments_updated BEFORE UPDATE ON appointments FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE POLICY appointments_member ON appointments FOR ALL TO app_user
  USING (is_circle_member(circle_id))
  WITH CHECK (is_circle_member(circle_id));
CREATE TRIGGER audit_appointments AFTER INSERT OR UPDATE OR DELETE ON appointments FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

CREATE TABLE appointment_attendees (
    appointment_id  UUID REFERENCES appointments(id) ON DELETE CASCADE,
    user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
    circle_id       UUID NOT NULL,
    PRIMARY KEY (appointment_id, user_id)
);
ALTER TABLE appointment_attendees ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointment_attendees FORCE ROW LEVEL SECURITY;
CREATE POLICY attendees_member ON appointment_attendees FOR ALL TO app_user
  USING (is_circle_member(circle_id))
  WITH CHECK (is_circle_member(circle_id));

CREATE TABLE care_shifts (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    circle_id               UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    aide_user_id            UUID NOT NULL REFERENCES users(id),
    starts_at               TIMESTAMPTZ NOT NULL,
    ends_at                 TIMESTAMPTZ NOT NULL,
    actual_start            TIMESTAMPTZ,
    actual_end              TIMESTAMPTZ,
    services                TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    notes_enc               BYTEA,
    miles_driven            NUMERIC(6,2),
    geofence_auto_detected  BOOLEAN NOT NULL DEFAULT FALSE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at              TIMESTAMPTZ
);
CREATE INDEX care_shifts_circle_time_idx ON care_shifts(circle_id, starts_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX care_shifts_aide_idx ON care_shifts(aide_user_id);
ALTER TABLE care_shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE care_shifts FORCE ROW LEVEL SECURITY;
CREATE TRIGGER trg_care_shifts_updated BEFORE UPDATE ON care_shifts FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE POLICY shifts_member ON care_shifts FOR ALL TO app_user
  USING (is_circle_member(circle_id))
  WITH CHECK (is_circle_member(circle_id));
CREATE TRIGGER audit_care_shifts AFTER INSERT OR UPDATE OR DELETE ON care_shifts FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();
