-- Run in Supabase SQL editor (macden-accounting project).
-- Tracks daily check-in/check-out via QR scan, for both regular staff
-- and Field Staff. Exactly one of staff_ref_id / field_staff_ref_id is
-- set per row, enforced by the CHECK constraint below.

CREATE TABLE IF NOT EXISTS attendance_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_ref_id UUID REFERENCES staff(id) ON DELETE CASCADE,
  field_staff_ref_id UUID REFERENCES field_staff(id) ON DELETE CASCADE,
  log_date DATE NOT NULL DEFAULT CURRENT_DATE,
  check_in_time TIMESTAMPTZ,
  check_out_time TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT one_person_type CHECK (
    (staff_ref_id IS NOT NULL AND field_staff_ref_id IS NULL) OR
    (staff_ref_id IS NULL AND field_staff_ref_id IS NOT NULL)
  )
);

-- One row per person per day -- prevents duplicate/conflicting entries
CREATE UNIQUE INDEX IF NOT EXISTS idx_attendance_staff_day
  ON attendance_logs(staff_ref_id, log_date) WHERE staff_ref_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_attendance_field_day
  ON attendance_logs(field_staff_ref_id, log_date) WHERE field_staff_ref_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_attendance_log_date ON attendance_logs(log_date);
