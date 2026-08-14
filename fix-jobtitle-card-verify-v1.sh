#!/bin/bash
# fix-jobtitle-card-verify-v1.sh
#
# Makes the ID card and QR verification page show the real job title
# instead of the account permission level (staff/admin). Requires
# fix-job-title-v1.sh to have been run first (that's what adds the
# job_title field to Edit Staff and the database).
#
# Full, safe overwrite of two files -- fully known/controlled.

set -e

echo "==> Overwriting server/routes/idCardRequests.js"
mkdir -p server/routes
cat > server/routes/idCardRequests.js << 'ROUTE1_EOF'
// server/routes/idCardRequests.js
//
// Staff ID card request + approval flow, same shape as your existing
// leave-request system: staff submits a request, it sits pending until
// an admin approves or rejects it. Approval doesn't generate a static
// file -- it just flips a status flag. The actual card is rendered live
// (with a live QR code) whenever someone with permission opens the view
// page, using portal/id-card-view.html.
//
// Auth shape verified against server/middleware/requireAuth.js and
// portal/manage-staff.html -- req.session.staff is the object, .role
// is confirmed present. See getSessionStaffId() / isAdmin() below.

const express = require('express');
const router = express.Router();
const QRCode = require('qrcode');
const requireAuth = require('../middleware/requireAuth');
const supabase = require('../config/supabaseClient');

router.use(requireAuth);

// Auth shape fully confirmed against your codebase (leave.js, settings.js,
// messages.js, etc. all use req.session.staff.id and req.session.staff.role).
function getSessionStaffId(req) {
  return req.session && req.session.staff && req.session.staff.id;
}
function isAdmin(req) {
  return !!(req.session && req.session.staff && req.session.staff.role === 'admin');
}

// Nigerian phone numbers show up in several formats depending on who typed
// them in (080..., 0803..., +234..., 234..., or just the 10 digits). This
// normalizes any of those to a consistent "+234 XXX XXX XXXX" for display,
// matching the spacing of the company contact number on the card. Falls
// back to returning the original string unchanged if it can't confidently
// parse it, rather than guessing wrong.
function normalizeNigerianPhone(raw) {
  if (!raw) return null;
  const digits = raw.replace(/\D/g, '');
  if (!digits) return null;

  let local;
  if (digits.startsWith('234') && digits.length === 13) {
    local = digits.slice(3);
  } else if (digits.startsWith('0') && digits.length === 11) {
    local = digits.slice(1);
  } else if (digits.length === 10) {
    local = digits;
  } else {
    return raw;
  }

  return '+234 ' + local.slice(0, 3) + ' ' + local.slice(3, 6) + ' ' + local.slice(6);
}

// Generates a random, collision-checked staff_id like MAC-2026-4831.
// Retries a few times against the DB's unique constraint if unlucky.
async function generateUniqueStaffId(staffRefId) {
  const year = new Date().getFullYear();
  const MAX_ATTEMPTS = 8;

  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    const rand = Math.floor(1000 + Math.random() * 9000); // 4-digit, 1000-9999
    const candidate = `MAC-${year}-${rand}`;

    const { error } = await supabase
      .from('staff')
      .update({ staff_id: candidate })
      .eq('id', staffRefId);

    if (!error) return candidate;
    if (error.code !== '23505') throw error; // real error, not a collision -- bail out
    // otherwise: collision, loop and try another random number
  }

  throw new Error('Could not generate a unique Staff ID after several attempts.');
}

// Staff: submit a new request
router.post('/api/id-card/request', async (req, res) => {
  const staffId = getSessionStaffId(req);
  if (!staffId) return res.status(401).json({ error: 'Not authenticated.' });

  try {
    const { data: existing, error: existingErr } = await supabase
      .from('id_card_requests')
      .select('id, status')
      .eq('staff_ref_id', staffId)
      .order('requested_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (existingErr) throw existingErr;

    if (existing && existing.status === 'pending') {
      return res.status(409).json({ error: 'You already have a pending request.' });
    }
    if (existing && existing.status === 'approved') {
      return res.status(409).json({ error: 'You already have an approved card.', requestId: existing.id });
    }

    const { data: created, error: insertErr } = await supabase
      .from('id_card_requests')
      .insert({ staff_ref_id: staffId })
      .select('id, status, requested_at')
      .single();

    if (insertErr) throw insertErr;

    return res.json({ success: true, request: created });
  } catch (err) {
    console.error('[ID-CARD-REQUEST-ERROR]', err);
    return res.status(500).json({ error: 'Could not submit request.' });
  }
});

// Staff: check their own latest request status
router.get('/api/id-card/request/status', async (req, res) => {
  const staffId = getSessionStaffId(req);
  if (!staffId) return res.status(401).json({ error: 'Not authenticated.' });

  try {
    const { data, error } = await supabase
      .from('id_card_requests')
      .select('id, status, requested_at, reviewed_at, rejection_reason')
      .eq('staff_ref_id', staffId)
      .order('requested_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (error) throw error;
    return res.json({ request: data || null });
  } catch (err) {
    console.error('[ID-CARD-STATUS-ERROR]', err);
    return res.status(500).json({ error: 'Could not check request status.' });
  }
});

// Admin: list pending requests
router.get('/api/id-card/requests', async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ error: 'Admin access required.' });

  try {
    const { data, error } = await supabase
      .from('id_card_requests')
      .select('id, status, requested_at, staff:staff_ref_id (id, full_name, staff_id, role, department_id, departments(name), photo_url)')
      .eq('status', 'pending')
      .order('requested_at', { ascending: true });

    if (error) throw error;
    return res.json({ requests: data });
  } catch (err) {
    console.error('[ID-CARD-LIST-ERROR]', err);
    return res.status(500).json({ error: 'Could not load requests.' });
  }
});

// Admin: approve a request
router.post('/api/id-card/requests/:id/approve', async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ error: 'Admin access required.' });
  const reviewerId = getSessionStaffId(req);

  try {
    const { data: reqRow, error: reqErr } = await supabase
      .from('id_card_requests')
      .select('id, staff_ref_id, staff:staff_ref_id (staff_id)')
      .eq('id', req.params.id)
      .single();

    if (reqErr || !reqRow) return res.status(404).json({ error: 'Request not found.' });

    // Auto-assign a random staff_id if this person doesn't have one yet,
    // same as the Field Staff "Generate ID Card" action already does --
    // no reason to make an admin manually type one into Edit Staff first.
    if (!reqRow.staff || !reqRow.staff.staff_id) {
      await generateUniqueStaffId(reqRow.staff_ref_id);
    }

    const { error: updateErr } = await supabase
      .from('id_card_requests')
      .update({ status: 'approved', reviewed_at: new Date().toISOString(), reviewed_by: reviewerId })
      .eq('id', req.params.id);

    if (updateErr) throw updateErr;
    return res.json({ success: true });
  } catch (err) {
    console.error('[ID-CARD-APPROVE-ERROR]', err);
    return res.status(500).json({ error: 'Could not approve request.' });
  }
});

// Admin: reject a request
router.post('/api/id-card/requests/:id/reject', async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ error: 'Admin access required.' });
  const reviewerId = getSessionStaffId(req);
  const reason = (req.body && req.body.reason) || null;

  try {
    const { error } = await supabase
      .from('id_card_requests')
      .update({ status: 'rejected', reviewed_at: new Date().toISOString(), reviewed_by: reviewerId, rejection_reason: reason })
      .eq('id', req.params.id);

    if (error) throw error;
    return res.json({ success: true });
  } catch (err) {
    console.error('[ID-CARD-REJECT-ERROR]', err);
    return res.status(500).json({ error: 'Could not reject request.' });
  }
});

// Staff or admin: fetch the real data + a live QR code for an APPROVED request.
// This is what portal/id-card-view.html calls to render the actual card.
router.get('/api/id-card/card/:requestId', async (req, res) => {
  const staffId = getSessionStaffId(req);
  if (!staffId) return res.status(401).json({ error: 'Not authenticated.' });

  try {
    const { data: reqRow, error: reqErr } = await supabase
      .from('id_card_requests')
      .select('id, status, staff_ref_id, staff:staff_ref_id (id, full_name, staff_id, role, job_title, branch, phone, photo_url, department_id, departments(name), verification_token)')
      .eq('id', req.params.requestId)
      .single();

    if (reqErr || !reqRow) return res.status(404).json({ error: 'Request not found.' });
    if (reqRow.status !== 'approved') return res.status(403).json({ error: 'This request has not been approved yet.' });

    const isOwner = reqRow.staff_ref_id === staffId;
    if (!isOwner && !isAdmin(req)) {
      return res.status(403).json({ error: 'Not authorized to view this card.' });
    }

    const staff = reqRow.staff;
    const verifyUrl = `https://macden.com.ng/portal/verify.html?token=${staff.verification_token}`;
    const qrDataUrl = await QRCode.toDataURL(verifyUrl, {
      errorCorrectionLevel: 'H',
      color: { dark: '#0d5c2f', light: '#fbfaf6' }
    });

    return res.json({
      full_name: staff.full_name,
      staff_id: staff.staff_id,
      department: staff.departments ? staff.departments.name : null,
      role: staff.job_title || '',
      branch: staff.branch || null,
      photo_url: staff.photo_url || null,
      employee_phone: normalizeNigerianPhone(staff.phone),
      qr_data_url: qrDataUrl
    });
  } catch (err) {
    console.error('[ID-CARD-VIEW-ERROR]', err);
    return res.status(500).json({ error: 'Could not load card data.' });
  }
});

// Admin: generate an ID card directly for a staff member, bypassing the
// request/approval flow entirely. For workers who can't log in themselves
// to request one (no desktop access, unfamiliar with the portal, etc.).
// Auto-assigns a random staff_id if the person doesn't already have one.
router.post('/api/id-card/admin-generate/:staffRefId', async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ error: 'Admin access required.' });
  const adminId = getSessionStaffId(req);
  const staffRefId = req.params.staffRefId;

  try {
    const { data: staff, error: staffErr } = await supabase
      .from('staff')
      .select('id, staff_id, full_name')
      .eq('id', staffRefId)
      .single();

    if (staffErr || !staff) return res.status(404).json({ error: 'Staff member not found.' });

    let finalStaffId = staff.staff_id;
    if (!finalStaffId) {
      finalStaffId = await generateUniqueStaffId(staffRefId);
    }

    // Reuse an existing request if one's already there, otherwise create
    // a fresh one that's immediately approved -- no pending step needed
    // when an admin is generating it directly on someone's behalf.
    const { data: existing, error: existingErr } = await supabase
      .from('id_card_requests')
      .select('id, status')
      .eq('staff_ref_id', staffRefId)
      .order('requested_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (existingErr) throw existingErr;

    let requestId;
    if (existing && existing.status === 'approved') {
      requestId = existing.id;
    } else if (existing) {
      const { error: updateErr } = await supabase
        .from('id_card_requests')
        .update({ status: 'approved', reviewed_at: new Date().toISOString(), reviewed_by: adminId })
        .eq('id', existing.id);
      if (updateErr) throw updateErr;
      requestId = existing.id;
    } else {
      const { data: created, error: insertErr } = await supabase
        .from('id_card_requests')
        .insert({
          staff_ref_id: staffRefId,
          status: 'approved',
          reviewed_at: new Date().toISOString(),
          reviewed_by: adminId
        })
        .select('id')
        .single();
      if (insertErr) throw insertErr;
      requestId = created.id;
    }

    return res.json({ success: true, requestId, staffId: finalStaffId });
  } catch (err) {
    console.error('[ID-CARD-ADMIN-GENERATE-ERROR]', err);
    return res.status(500).json({ error: 'Could not generate ID card.' });
  }
});

module.exports = router;
ROUTE1_EOF

echo "==> Overwriting server/routes/verify.js"
cat > server/routes/verify.js << 'ROUTE2_EOF'
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
ROUTE2_EOF

echo ""
echo "Done. Push with your usual save-progress.sh."
