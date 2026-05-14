-- =====================================================================
-- 0013 Vitals
--
-- Caregiver-recorded or HealthKit-imported readings (heart rate, blood
-- pressure, weight, glucose, SpO2, temperature, respiratory rate).
-- Optional free-text notes are envelope-encrypted with the per-circle
-- DEK; the numeric value and units are plaintext so backend can serve
-- list rendering, sort, and (future) trend computation without
-- decrypting every row.
--
-- Blood pressure is recorded as two rows (systolic + diastolic) sharing
-- the same recorded_at — keeps schema simple and matches how HealthKit
-- emits its samples. UI pairs them on display.
--
-- HealthKit imports carry the source sample's UUID so re-imports are
-- idempotent (one HK sample → at most one vitals row per circle).
-- =====================================================================

CREATE TABLE vitals (
    id                       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    circle_id                UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    recorded_by_user_id      UUID NOT NULL REFERENCES users(id),
    kind                     TEXT NOT NULL,
    recorded_at              TIMESTAMPTZ NOT NULL,
    value_numeric            NUMERIC(10,3),
    value_text               TEXT,
    unit                     TEXT NOT NULL,
    source                   TEXT NOT NULL DEFAULT 'manual',
    healthkit_uuid           TEXT,
    notes_enc                BYTEA,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at               TIMESTAMPTZ,
    version                  BIGINT NOT NULL DEFAULT 1,
    client_op_id             UUID,
    CONSTRAINT vitals_kind_ck CHECK (kind IN (
        'heart_rate',
        'blood_pressure_systolic',
        'blood_pressure_diastolic',
        'body_weight',
        'blood_glucose',
        'oxygen_saturation',
        'body_temperature',
        'respiratory_rate',
        'falls',
        'walking_steadiness',
        'sleep_hours',
        'resting_heart_rate',
        'step_count'
    )),
    CONSTRAINT vitals_source_ck CHECK (source IN ('manual', 'healthkit')),
    CONSTRAINT vitals_value_present_ck CHECK (
        value_numeric IS NOT NULL OR value_text IS NOT NULL
    )
);

CREATE INDEX vitals_circle_time_idx     ON vitals(circle_id, recorded_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX vitals_circle_kind_time_idx ON vitals(circle_id, kind, recorded_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX vitals_recorder_idx        ON vitals(recorded_by_user_id);
CREATE UNIQUE INDEX vitals_client_op_idx ON vitals(circle_id, client_op_id) WHERE client_op_id IS NOT NULL;
CREATE UNIQUE INDEX vitals_healthkit_uuid_idx ON vitals(circle_id, healthkit_uuid) WHERE healthkit_uuid IS NOT NULL;

ALTER TABLE vitals ENABLE ROW LEVEL SECURITY;
ALTER TABLE vitals FORCE ROW LEVEL SECURITY;

CREATE TRIGGER trg_vitals_updated BEFORE UPDATE ON vitals FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE POLICY vitals_member_read ON vitals FOR SELECT TO app_user
  USING (is_circle_member(circle_id));

CREATE POLICY vitals_member_write ON vitals FOR INSERT TO app_user
  WITH CHECK (is_circle_member(circle_id) AND recorded_by_user_id = current_user_id());

CREATE POLICY vitals_author_update ON vitals FOR UPDATE TO app_user
  USING (recorded_by_user_id = current_user_id() AND deleted_at IS NULL)
  WITH CHECK (recorded_by_user_id = current_user_id());

CREATE POLICY vitals_author_delete ON vitals FOR DELETE TO app_user
  USING (recorded_by_user_id = current_user_id());

CREATE TRIGGER audit_vitals AFTER INSERT OR UPDATE OR DELETE ON vitals FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

CREATE TRIGGER notify_vitals AFTER INSERT OR UPDATE OR DELETE ON vitals FOR EACH ROW EXECUTE FUNCTION notify_circle_change();
