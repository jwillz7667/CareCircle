-- =====================================================================
-- 0010 NOTIFY triggers — fan out to WebSocket layer via pg-listen
--
-- A single channel "circle_changes" carries lightweight payloads:
--   { circle_id, table, row_id, op }
-- Clients re-fetch via RLS-protected API.
-- =====================================================================

CREATE OR REPLACE FUNCTION notify_circle_change() RETURNS TRIGGER AS $$
DECLARE
  v_circle_id UUID;
  v_row_id    UUID;
  v_payload   JSONB;
BEGIN
  IF (TG_OP = 'DELETE') THEN
    v_circle_id := (to_jsonb(OLD)->>'circle_id')::UUID;
    v_row_id    := (to_jsonb(OLD)->>'id')::UUID;
  ELSE
    v_circle_id := (to_jsonb(NEW)->>'circle_id')::UUID;
    v_row_id    := (to_jsonb(NEW)->>'id')::UUID;
  END IF;

  IF v_circle_id IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  v_payload := jsonb_build_object(
    'circle_id', v_circle_id,
    'table', TG_TABLE_NAME,
    'row_id', v_row_id,
    'op', TG_OP
  );

  PERFORM pg_notify('circle_changes', v_payload::TEXT);
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER notify_activities          AFTER INSERT OR UPDATE OR DELETE ON activities          FOR EACH ROW EXECUTE FUNCTION notify_circle_change();
CREATE TRIGGER notify_activity_reactions  AFTER INSERT OR UPDATE OR DELETE ON activity_reactions  FOR EACH ROW EXECUTE FUNCTION notify_circle_change();
CREATE TRIGGER notify_activity_comments   AFTER INSERT OR UPDATE OR DELETE ON activity_comments   FOR EACH ROW EXECUTE FUNCTION notify_circle_change();
CREATE TRIGGER notify_medications         AFTER INSERT OR UPDATE OR DELETE ON medications         FOR EACH ROW EXECUTE FUNCTION notify_circle_change();
CREATE TRIGGER notify_dose_events         AFTER INSERT OR UPDATE OR DELETE ON dose_events         FOR EACH ROW EXECUTE FUNCTION notify_circle_change();
CREATE TRIGGER notify_appointments        AFTER INSERT OR UPDATE OR DELETE ON appointments        FOR EACH ROW EXECUTE FUNCTION notify_circle_change();
CREATE TRIGGER notify_care_shifts         AFTER INSERT OR UPDATE OR DELETE ON care_shifts         FOR EACH ROW EXECUTE FUNCTION notify_circle_change();
CREATE TRIGGER notify_documents           AFTER INSERT OR UPDATE OR DELETE ON documents           FOR EACH ROW EXECUTE FUNCTION notify_circle_change();
CREATE TRIGGER notify_emergency_contacts  AFTER INSERT OR UPDATE OR DELETE ON emergency_contacts  FOR EACH ROW EXECUTE FUNCTION notify_circle_change();
CREATE TRIGGER notify_sos_events          AFTER INSERT OR UPDATE OR DELETE ON sos_events          FOR EACH ROW EXECUTE FUNCTION notify_circle_change();
CREATE TRIGGER notify_care_minute         AFTER INSERT OR UPDATE OR DELETE ON care_minute_entries FOR EACH ROW EXECUTE FUNCTION notify_circle_change();
CREATE TRIGGER notify_circle_members      AFTER INSERT OR UPDATE OR DELETE ON circle_members      FOR EACH ROW EXECUTE FUNCTION notify_circle_change();
CREATE TRIGGER notify_care_recipients     AFTER INSERT OR UPDATE OR DELETE ON care_recipients     FOR EACH ROW EXECUTE FUNCTION notify_circle_change();
