-- Run in the Supabase SQL editor.
-- Tracks staff ID card requests through an admin approval flow,
-- same pattern as your existing leave-request system.

CREATE TABLE IF NOT EXISTS id_card_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_ref_id UUID NOT NULL REFERENCES staff(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  reviewed_at TIMESTAMPTZ,
  reviewed_by UUID REFERENCES staff(id),
  rejection_reason TEXT
);

-- staff_ref_id is the internal UUID (staff.id), deliberately named differently
-- from staff.staff_id (the human-readable badge number) to avoid confusion
-- between the two -- they are not the same field.

CREATE INDEX IF NOT EXISTS idx_id_card_requests_staff ON id_card_requests(staff_ref_id);
CREATE INDEX IF NOT EXISTS idx_id_card_requests_status ON id_card_requests(status);
