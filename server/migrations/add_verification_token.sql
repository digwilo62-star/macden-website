-- Run this in the Supabase SQL editor against the `staff` table.
-- Two separate columns, two separate jobs:
--   staff_id           -> human-readable, printed on the badge (e.g. MAC-2026-0017)
--   verification_token -> random, never shown, encoded in the QR code only

ALTER TABLE staff ADD COLUMN IF NOT EXISTS staff_id TEXT UNIQUE;
ALTER TABLE staff ADD COLUMN IF NOT EXISTS verification_token UUID DEFAULT gen_random_uuid();

CREATE UNIQUE INDEX IF NOT EXISTS idx_staff_verification_token ON staff(verification_token);

-- Backfill any existing rows that predate the default
UPDATE staff SET verification_token = gen_random_uuid() WHERE verification_token IS NULL;

-- staff_id is NOT auto-generated here on purpose -- the numbering convention
-- (prefix, sequencing, department-tied or not) still needs to be decided.
-- Assign real staff_id values manually or via a follow-up script once that's settled.
