-- Run in the Supabase SQL editor (macden-accounting project).
-- Separate from `staff` entirely -- these are people who need a physical
-- ID badge but never log into the portal. No email, no password, no
-- account. Admin-managed only.

CREATE TABLE IF NOT EXISTS field_staff (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name TEXT NOT NULL,
  role TEXT,
  department_id UUID REFERENCES departments(id),
  phone TEXT,
  branch TEXT,
  photo_url TEXT,
  staff_id TEXT UNIQUE,
  verification_token UUID NOT NULL DEFAULT gen_random_uuid(),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID REFERENCES staff(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_field_staff_verification_token ON field_staff(verification_token);
CREATE INDEX IF NOT EXISTS idx_field_staff_active ON field_staff(is_active);
