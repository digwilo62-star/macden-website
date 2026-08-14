// server/routes/verify.js
//
// Public staff verification endpoint. Scanned from the QR code on the back
// of a staff ID card. Deliberately returns ONLY what's needed to confirm
// someone is a real, active MACDEN staff member -- no email, phone, or
// other PII that isn't already visible on the printed card itself.
//
// Looked up by verification_token (random UUID), never by the human-readable
// staff ID, so the endpoint can't be scraped by guessing sequential IDs.

const express = require('express');
const router = express.Router();
const rateLimit = require('express-rate-limit');
const supabase = require('../config/supabaseClient');

// Basic abuse protection: this is a public, unauthenticated endpoint,
// so throttle it independently of your normal API rate limits.
const verifyLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 30,                  // 30 lookups per IP per window is generous for real scans, tight for scraping
  message: { error: 'Too many verification requests. Please try again shortly.' }
});

router.get('/api/verify/:token', verifyLimiter, async (req, res) => {
  const { token } = req.params;

  // UUID shape check before hitting the DB at all
  const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!uuidPattern.test(token)) {
    return res.status(400).json({ valid: false, error: 'Invalid verification code.' });
  }

  try {
    // NOTE: department_id is a foreign key, not the name itself. This assumes
    // a `departments` table with a `name` column and a standard Supabase/PostgREST
    // relationship Postgres can embed automatically.
    const { data: staffMember, error } = await supabase
      .from('staff')
      .select('full_name, staff_id, department_id, departments(name), role, job_title, branch, photo_url, is_active')
      .eq('verification_token', token)
      .maybeSingle();

    if (staffMember) {
      return res.json({
        valid: true,
        active: staffMember.is_active,
        full_name: staffMember.full_name,
        staff_id: staffMember.staff_id,
        department: staffMember.departments ? staffMember.departments.name : null,
        role: staffMember.job_title || '',
        branch: staffMember.branch || null,
        photo_url: staffMember.photo_url || null
      });
    }

    // Not a regular staff account -- check field_staff (no-login badge holders)
    const { data: fieldMember, error: fieldError } = await supabase
      .from('field_staff')
      .select('full_name, staff_id, department_id, departments(name), role, branch, photo_url, is_active')
      .eq('verification_token', token)
      .maybeSingle();

    if (fieldError) throw fieldError;

    if (!fieldMember) {
      return res.status(404).json({ valid: false, error: 'No matching staff record found.' });
    }

    return res.json({
      valid: true,
      active: fieldMember.is_active,
      full_name: fieldMember.full_name,
      staff_id: fieldMember.staff_id,
      department: fieldMember.departments ? fieldMember.departments.name : null,
      role: fieldMember.role,
      branch: fieldMember.branch || null,
      photo_url: fieldMember.photo_url || null
    });

  } catch (err) {
    console.error('[VERIFY-ERROR]', err);
    return res.status(500).json({ valid: false, error: 'Verification service temporarily unavailable.' });
  }
});

module.exports = router;
