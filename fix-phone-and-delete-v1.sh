#!/bin/bash
# fix-phone-and-delete-v1.sh
#
# Adds two things:
#   1. Employee's own phone number (normalized to +234 format regardless
#      of how it was originally entered) now shows under Emergency
#      Contact on the ID card back, alongside the company line.
#   2. Permanent Delete for field staff (separate from Deactivate --
#      Delete actually removes the record; Deactivate just disables
#      their card while keeping the record).
#
# Full, safe overwrite of four files -- all fully known/controlled.

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
const { supabase } = require('../config/supabaseClient');

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
// normalizes any of those to a consistent +234XXXXXXXXXX for display on
// the card. Falls back to returning the original string unchanged if it
// can't confidently parse it, rather than guessing wrong.
function normalizeNigerianPhone(raw) {
  if (!raw) return null;
  const digits = raw.replace(/\D/g, '');
  if (!digits) return null;

  if (digits.startsWith('234') && digits.length === 13) {
    return '+' + digits;
  }
  if (digits.startsWith('0') && digits.length === 11) {
    return '+234' + digits.slice(1);
  }
  if (digits.length === 10) {
    return '+234' + digits;
  }
  return raw;
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

    if (!reqRow.staff || !reqRow.staff.staff_id) {
      return res.status(400).json({
        error: 'This staff member has no staff_id assigned yet. Assign one via Edit Staff before approving.'
      });
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
      .select('id, status, staff_ref_id, staff:staff_ref_id (id, full_name, staff_id, role, branch, phone, photo_url, department_id, departments(name), verification_token)')
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
      role: staff.role,
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

echo "==> Overwriting server/routes/fieldStaff.js"
cat > server/routes/fieldStaff.js << 'ROUTE2_EOF'
// server/routes/fieldStaff.js
//
// Manages "field staff" -- people who need a physical MACDEN ID badge but
// never log into the portal (no email, no password, no account at all).
// Entirely admin-managed: an admin adds them, generates their card, and
// can deactivate them later (which invalidates their QR verification too,
// same as it does for real staff accounts).

const express = require('express');
const router = express.Router();
const QRCode = require('qrcode');
const multer = require('multer');
const sharp = require('sharp');
const requireAuth = require('../middleware/requireAuth');
const supabase = require('../config/supabaseClient');

router.use(requireAuth);

const photoUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 3 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const allowed = ['image/jpeg', 'image/png', 'image/webp'];
    if (allowed.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Only JPG, PNG, or WEBP images are allowed.'));
    }
  }
});

function isAdmin(req) {
  return !!(req.session && req.session.staff && req.session.staff.role === 'admin');
}

// Same normalizer as idCardRequests.js -- Nigerian phone numbers show up
// in several formats (080..., +234..., etc), this makes them consistent
// for display on the card.
function normalizeNigerianPhone(raw) {
  if (!raw) return null;
  const digits = raw.replace(/\D/g, '');
  if (!digits) return null;

  if (digits.startsWith('234') && digits.length === 13) {
    return '+' + digits;
  }
  if (digits.startsWith('0') && digits.length === 11) {
    return '+234' + digits.slice(1);
  }
  if (digits.length === 10) {
    return '+234' + digits;
  }
  return raw;
}

async function generateUniqueStaffId(fieldStaffId) {
  const year = new Date().getFullYear();
  const MAX_ATTEMPTS = 8;

  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    const rand = Math.floor(1000 + Math.random() * 9000);
    const candidate = `MAC-${year}-${rand}`;

    const { error } = await supabase
      .from('field_staff')
      .update({ staff_id: candidate })
      .eq('id', fieldStaffId);

    if (!error) return candidate;
    if (error.code !== '23505') throw error;
  }

  throw new Error('Could not generate a unique Staff ID after several attempts.');
}

// List all field staff
router.get('/api/field-staff', async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ error: 'Admin access required.' });

  try {
    const { data, error } = await supabase
      .from('field_staff')
      .select('id, full_name, role, department_id, departments(name), phone, branch, photo_url, staff_id, is_active, created_at')
      .order('created_at', { ascending: false });

    if (error) throw error;
    return res.json({ fieldStaff: data });
  } catch (err) {
    console.error('[FIELD-STAFF-LIST-ERROR]', err);
    return res.status(500).json({ error: 'Could not load field staff.' });
  }
});

// Add a new field staff member
router.post('/api/field-staff', async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ error: 'Admin access required.' });
  const { fullName, role, departmentId, phone, branch } = req.body;

  if (!fullName || !fullName.trim()) {
    return res.status(400).json({ error: 'Full name is required.' });
  }

  try {
    const { data, error } = await supabase
      .from('field_staff')
      .insert({
        full_name: fullName.trim(),
        role: role || null,
        department_id: departmentId || null,
        phone: phone || null,
        branch: branch || null,
        created_by: req.session.staff.id
      })
      .select('id')
      .single();

    if (error) throw error;
    return res.json({ success: true, id: data.id });
  } catch (err) {
    console.error('[FIELD-STAFF-CREATE-ERROR]', err);
    return res.status(500).json({ error: 'Could not add field staff member.' });
  }
});

// Edit an existing field staff member
router.put('/api/field-staff/:id', async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ error: 'Admin access required.' });
  const { fullName, role, departmentId, phone, branch } = req.body;

  try {
    const { error } = await supabase
      .from('field_staff')
      .update({
        full_name: fullName ? fullName.trim() : undefined,
        role: role || null,
        department_id: departmentId || null,
        phone: phone || null,
        branch: branch || null
      })
      .eq('id', req.params.id);

    if (error) throw error;
    return res.json({ success: true });
  } catch (err) {
    console.error('[FIELD-STAFF-EDIT-ERROR]', err);
    return res.status(500).json({ error: 'Could not update field staff member.' });
  }
});

// Deactivate / reactivate
router.post('/api/field-staff/:id/deactivate', async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ error: 'Admin access required.' });
  try {
    const { error } = await supabase.from('field_staff').update({ is_active: false }).eq('id', req.params.id);
    if (error) throw error;
    return res.json({ success: true });
  } catch (err) {
    console.error('[FIELD-STAFF-DEACTIVATE-ERROR]', err);
    return res.status(500).json({ error: 'Could not deactivate.' });
  }
});

router.post('/api/field-staff/:id/reactivate', async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ error: 'Admin access required.' });
  try {
    const { error } = await supabase.from('field_staff').update({ is_active: true }).eq('id', req.params.id);
    if (error) throw error;
    return res.json({ success: true });
  } catch (err) {
    console.error('[FIELD-STAFF-REACTIVATE-ERROR]', err);
    return res.status(500).json({ error: 'Could not reactivate.' });
  }
});

// Permanent delete -- unlike deactivate, this actually removes the record.
// Their QR code stops working immediately since the row (and its
// verification_token) no longer exists at all.
router.delete('/api/field-staff/:id', async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ error: 'Admin access required.' });
  try {
    const { error } = await supabase.from('field_staff').delete().eq('id', req.params.id);
    if (error) throw error;
    return res.json({ success: true });
  } catch (err) {
    console.error('[FIELD-STAFF-DELETE-ERROR]', err);
    return res.status(500).json({ error: 'Could not delete this field staff member.' });
  }
});

// Generate/assign a staff_id if missing -- no request/approval concept
// here, the admin adding them IS the approval.
router.post('/api/field-staff/:id/generate-id', async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ error: 'Admin access required.' });

  try {
    const { data: person, error: fetchErr } = await supabase
      .from('field_staff')
      .select('id, staff_id')
      .eq('id', req.params.id)
      .single();

    if (fetchErr || !person) return res.status(404).json({ error: 'Field staff member not found.' });

    let staffId = person.staff_id;
    if (!staffId) {
      staffId = await generateUniqueStaffId(req.params.id);
    }

    return res.json({ success: true, staffId, fieldStaffId: req.params.id });
  } catch (err) {
    console.error('[FIELD-STAFF-GENERATE-ID-ERROR]', err);
    return res.status(500).json({ error: 'Could not generate ID card.' });
  }
});

// Card data + live QR for a field staff member's card view page
router.get('/api/field-staff/:id/card', async (req, res) => {
  try {
    const { data: person, error } = await supabase
      .from('field_staff')
      .select('full_name, staff_id, role, branch, phone, photo_url, department_id, departments(name), verification_token, is_active')
      .eq('id', req.params.id)
      .single();

    if (error || !person) return res.status(404).json({ error: 'Field staff member not found.' });
    if (!person.staff_id) return res.status(400).json({ error: 'No Staff ID assigned yet.' });

    const verifyUrl = `https://macden.com.ng/portal/verify.html?token=${person.verification_token}`;
    const qrDataUrl = await QRCode.toDataURL(verifyUrl, {
      errorCorrectionLevel: 'H',
      color: { dark: '#0d5c2f', light: '#fbfaf6' }
    });

    return res.json({
      full_name: person.full_name,
      staff_id: person.staff_id,
      department: person.departments ? person.departments.name : null,
      role: person.role,
      branch: person.branch || null,
      photo_url: person.photo_url || null,
      employee_phone: normalizeNigerianPhone(person.phone),
      qr_data_url: qrDataUrl
    });
  } catch (err) {
    console.error('[FIELD-STAFF-CARD-ERROR]', err);
    return res.status(500).json({ error: 'Could not load card data.' });
  }
});

// Admin uploads a photo on behalf of a field staff member -- they can't
// do this themselves (no login). Same resize/compress pipeline as the
// regular staff self-upload route.
router.post('/api/field-staff/:id/photo', (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ error: 'Admin access required.' });

  photoUpload.single('photo')(req, res, async (err) => {
    if (err) return res.status(400).json({ error: err.message });
    if (!req.file) return res.status(400).json({ error: 'No image provided.' });

    try {
      const processedBuffer = await sharp(req.file.buffer)
        .rotate()
        .resize({ width: 1200, height: 1200, fit: 'inside', withoutEnlargement: true })
        .jpeg({ quality: 82 })
        .toBuffer();

      const storagePath = `field-${req.params.id}-${Date.now()}.jpg`;
      const { error: uploadError } = await supabase.storage
        .from('staff-photos')
        .upload(storagePath, processedBuffer, { contentType: 'image/jpeg', upsert: true });

      if (uploadError) {
        console.error('Field staff photo upload error:', uploadError);
        return res.status(500).json({ error: 'Upload failed: ' + uploadError.message });
      }

      const { data: publicUrlData } = supabase.storage.from('staff-photos').getPublicUrl(storagePath);

      const { error: updateError } = await supabase
        .from('field_staff')
        .update({ photo_url: publicUrlData.publicUrl })
        .eq('id', req.params.id);

      if (updateError) {
        console.error('Field staff photo URL save error:', updateError);
        return res.status(500).json({ error: 'Could not save photo.' });
      }

      res.json({ success: true, photoUrl: publicUrlData.publicUrl });
    } catch (err) {
      console.error('Field staff photo upload unexpected error:', err);
      res.status(500).json({ error: 'Something went wrong uploading the photo.' });
    }
  });
});

module.exports = router;
ROUTE2_EOF

echo "==> Overwriting portal/field-staff.html"
mkdir -p portal
cat > portal/field-staff.html << 'PAGE_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Field Staff — MACDEN Portal</title>
<link rel="stylesheet" href="assets/portal-style.css">
<link rel="stylesheet" href="assets/portal-shell.css">
<style>
  .fs-toolbar{ display:flex; justify-content:space-between; align-items:center; margin-bottom:18px; }
  .fs-list{ background:var(--surface); border:1px solid var(--border); border-radius:var(--radius-md); overflow-x:auto; }
  .fs-header-row{ display:grid; min-width:700px; grid-template-columns: minmax(140px,1fr) minmax(100px,140px) minmax(100px,140px) minmax(110px,140px) minmax(70px,90px) minmax(180px,220px); gap:12px; padding:12px 18px; font-size:10.5px; font-weight:700; text-transform:uppercase; letter-spacing:0.04em; color:var(--text-muted); border-bottom:1px solid var(--border); }
  .fs-row{ display:grid; min-width:700px; grid-template-columns: minmax(140px,1fr) minmax(100px,140px) minmax(100px,140px) minmax(110px,140px) minmax(70px,90px) minmax(180px,220px); gap:12px; align-items:center; padding:12px 18px; border-bottom:1px solid var(--border); font-size:12.5px; }
  .fs-row:last-child{ border-bottom:none; }
  .fs-empty{ padding:50px 18px; text-align:center; color:var(--text-muted); font-size:13px; }
  .fs-status{ display:inline-block; padding:2px 9px; border-radius:999px; font-size:10.5px; font-weight:700; }
  .fs-status.active{ background:var(--success-dim); color:var(--success); }
  .fs-status.inactive{ background:var(--error-dim); color:var(--error); }
  .fs-action-btn{ border:1px solid var(--border); background:var(--surface); border-radius:var(--radius-sm); padding:5px 11px; font-size:11px; font-weight:600; cursor:pointer; font-family:var(--font-body); color:var(--text-primary); margin-right:4px; margin-bottom:4px; }
  .fs-action-btn:hover{ border-color:var(--primary); color:var(--primary); }
  .fs-action-btn.danger:hover{ border-color:var(--error); color:var(--error); background:var(--error-dim); }
  .fs-action-btn.reactivate{ background:var(--success-dim); color:var(--success); border-color:transparent; }

  .modal-backdrop{ display:none; position:fixed; inset:0; background:rgba(0,0,0,0.4); align-items:center; justify-content:center; z-index:100; }
  .modal-backdrop.visible{ display:flex; }
  .modal{ background:var(--surface); border-radius:var(--radius-md); padding:24px; width:380px; max-width:90vw; }
  .modal h3{ margin-bottom:16px; }
  .modal-actions{ display:flex; justify-content:flex-end; gap:10px; margin-top:8px; }
  .field-label{ display:block; font-size:12.5px; font-weight:600; margin-bottom:6px; }
  .field-input{ width:100%; padding:9px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); font-family:var(--font-body); box-sizing:border-box; margin-bottom:12px; }
</style>
</head>
<body>
  <div class="app-shell">
    <div class="sidebar">
      <div class="sidebar-brand"><img src="assets/logo.jpeg" alt="MACDEN"><span>MACDEN</span></div>
      <nav class="sidebar-nav">
        <a href="dashboard.html" class="sidebar-link"><i class="ti ti-layout-dashboard"></i> Dashboard</a>
        <a href="directory.html" class="sidebar-link"><i class="ti ti-users"></i> Directory</a>
        <a href="settings.html" class="sidebar-link"><i class="ti ti-settings"></i> Settings</a>
      </nav>
    </div>

    <div class="main-content">
      <div class="page-body">
        <div class="fs-toolbar">
          <div>
            <h1 class="page-greeting" style="font-size:22px;">Field Staff</h1>
            <p class="page-greeting-sub" style="margin:0;">
              <a href="manage-staff.html" style="color:var(--primary); text-decoration:none; font-weight:600;">&larr; Back to Manage Staff</a>
            </p>
            <p style="font-size:12.5px; color:var(--text-muted); margin-top:6px; max-width:520px;">
              People who need a physical MACDEN ID badge but never log into the portal —
              drivers, loaders, and other field workers. No account, no email, no password.
            </p>
          </div>
          <button class="btn btn-primary" id="addFieldStaffBtn" style="width:auto; padding:10px 20px; display:inline-flex; align-items:center; gap:8px;">
            <i class="ti ti-user-plus"></i> Add Field Worker
          </button>
        </div>

        <div class="fs-list">
          <div class="fs-header-row"><div>Name</div><div>Role</div><div>Department</div><div>Staff ID</div><div>Status</div><div>Actions</div></div>
          <div id="fsRows"><div class="fs-empty">Loading…</div></div>
        </div>
      </div>
    </div>
  </div>

  <div class="modal-backdrop" id="fieldStaffModalBackdrop">
    <div class="modal">
      <h3 id="fieldStaffModalTitle">Add Field Worker</h3>
      <div id="fieldStaffAlert" class="alert alert-error"></div>

      <div id="fsPhotoSection" style="display:none; margin-bottom:16px;">
        <label class="field-label">Photo</label>
        <div style="display:flex; align-items:center; gap:12px;">
          <div id="fsPhotoPreview" style="width:56px; height:56px; border-radius:8px; background:var(--gold-dim); display:flex; align-items:center; justify-content:center; overflow:hidden; flex-shrink:0;">
            <i class="ti ti-user" style="font-size:20px; color:var(--text-muted);"></i>
          </div>
          <button type="button" class="btn btn-ghost" id="fsPhotoUploadBtn" style="width:auto; padding:8px 14px; font-size:12.5px;">Upload Photo</button>
          <input type="file" id="fsPhotoInput" accept="image/jpeg,image/png,image/webp" style="display:none;">
        </div>
        <div id="fsPhotoAlert" class="alert alert-error" style="margin-top:8px; font-size:11.5px;"></div>
      </div>

      <label class="field-label">Full Name</label>
      <input type="text" id="fsFullName" class="field-input">

      <label class="field-label">Role</label>
      <input type="text" id="fsRole" class="field-input" placeholder="e.g. Delivery Driver">

      <label class="field-label">Department</label>
      <select id="fsDepartmentId" class="field-input">
        <option value="">None</option>
      </select>

      <label class="field-label">Phone</label>
      <input type="text" id="fsPhone" class="field-input">

      <label class="field-label">Branch</label>
      <input type="text" id="fsBranch" class="field-input">

      <div class="modal-actions">
        <button class="btn btn-ghost" id="fieldStaffCancelBtn">Cancel</button>
        <button class="btn btn-primary" id="fieldStaffSaveBtn">Save</button>
      </div>
    </div>
  </div>

  <script src="assets/api.js"></script>
  <script>
    let editingId = null;

    async function init() {
      try {
        const result = await apiRequest('/dashboard-check');
        if (result.staff.role !== 'admin') {
          document.body.innerHTML = '<div style="padding:40px; font-family:sans-serif;">Admin access only.</div>';
          return;
        }
      } catch (err) {
        window.location.href = 'login.html';
        return;
      }
      loadDepartments();
      loadFieldStaff();
    }

    async function loadDepartments() {
      try {
        const result = await apiRequest('/admin/departments');
        document.getElementById('fsDepartmentId').innerHTML =
          '<option value="">None</option>' +
          result.departments.map(d => '<option value="' + d.id + '">' + d.name + '</option>').join('');
      } catch (err) { /* non-fatal */ }
    }

    async function loadFieldStaff() {
      const rows = document.getElementById('fsRows');
      try {
        const res = await fetch('/api/field-staff', { credentials: 'include' });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Could not load field staff.');

        if (!data.fieldStaff.length) {
          rows.innerHTML = '<div class="fs-empty">No field staff added yet.</div>';
          return;
        }

        rows.innerHTML = data.fieldStaff.map(p => {
          const statusHtml = p.is_active
            ? '<span class="fs-status active">Active</span>'
            : '<span class="fs-status inactive">Deactivated</span>';
          const deptName = p.departments ? p.departments.name : '—';
          const staffIdText = p.staff_id || '<span style="color:var(--text-muted);">Not assigned</span>';
          const avatar = p.photo_url
            ? '<img src="' + p.photo_url + '" style="width:26px; height:26px; border-radius:6px; object-fit:cover; vertical-align:middle; margin-right:8px;">'
            : '<span style="display:inline-block; width:26px; height:26px; border-radius:6px; background:var(--gold-dim); vertical-align:middle; margin-right:8px;"></span>';

          const toggleBtn = p.is_active
            ? '<button class="fs-action-btn danger" onclick="deactivateFS(\'' + p.id + '\')">Deactivate</button>'
            : '<button class="fs-action-btn reactivate" onclick="reactivateFS(\'' + p.id + '\')">Reactivate</button>';

          return '<div class="fs-row">' +
            '<div>' + avatar + p.full_name + '</div>' +
            '<div>' + (p.role || '—') + '</div>' +
            '<div>' + deptName + '</div>' +
            '<div>' + staffIdText + '</div>' +
            '<div>' + statusHtml + '</div>' +
            '<div>' +
              '<button class="fs-action-btn" onclick="editFS(\'' + p.id + '\')">Edit</button>' +
              '<button class="fs-action-btn" onclick="generateCard(\'' + p.id + '\')">ID Card</button>' +
              toggleBtn +
              '<button class="fs-action-btn danger" onclick="deleteFS(\'' + p.id + '\', ' + JSON.stringify(p.full_name) + ')">Delete</button>' +
            '</div>' +
          '</div>';
        }).join('');
      } catch (err) {
        rows.innerHTML = '<div class="fs-empty">' + err.message + '</div>';
      }
    }

    function openAddModal() {
      editingId = null;
      document.getElementById('fieldStaffModalTitle').textContent = 'Add Field Worker';
      document.getElementById('fsFullName').value = '';
      document.getElementById('fsRole').value = '';
      document.getElementById('fsDepartmentId').value = '';
      document.getElementById('fsPhone').value = '';
      document.getElementById('fsBranch').value = '';
      document.getElementById('fsPhotoSection').style.display = 'none';
      document.getElementById('fieldStaffModalBackdrop').classList.add('visible');
    }

    async function editFS(id) {
      try {
        const res = await fetch('/api/field-staff', { credentials: 'include' });
        const data = await res.json();
        const p = data.fieldStaff.find(x => x.id === id);
        if (!p) return;

        editingId = id;
        document.getElementById('fieldStaffModalTitle').textContent = 'Edit Field Worker';
        document.getElementById('fsFullName').value = p.full_name || '';
        document.getElementById('fsRole').value = p.role || '';
        document.getElementById('fsDepartmentId').value = p.department_id || '';
        document.getElementById('fsPhone').value = p.phone || '';
        document.getElementById('fsBranch').value = p.branch || '';

        document.getElementById('fsPhotoSection').style.display = 'block';
        const preview = document.getElementById('fsPhotoPreview');
        if (p.photo_url) {
          preview.innerHTML = '<img src="' + p.photo_url + '" style="width:100%; height:100%; object-fit:cover;">';
        } else {
          preview.innerHTML = '<i class="ti ti-user" style="font-size:20px; color:var(--text-muted);"></i>';
        }

        document.getElementById('fieldStaffModalBackdrop').classList.add('visible');
      } catch (err) {
        alert('Could not load this person\'s details.');
      }
    }

    document.getElementById('addFieldStaffBtn').addEventListener('click', openAddModal);
    document.getElementById('fieldStaffCancelBtn').addEventListener('click', () => {
      document.getElementById('fieldStaffModalBackdrop').classList.remove('visible');
    });

    document.getElementById('fsPhotoUploadBtn').addEventListener('click', () => {
      document.getElementById('fsPhotoInput').click();
    });

    document.getElementById('fsPhotoInput').addEventListener('change', async (e) => {
      const file = e.target.files[0];
      if (!file || !editingId) return;

      const alertEl = document.getElementById('fsPhotoAlert');
      alertEl.style.display = 'none';

      const formData = new FormData();
      formData.append('photo', file);

      try {
        const res = await fetch('/api/field-staff/' + editingId + '/photo', {
          method: 'POST',
          credentials: 'include',
          body: formData
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Upload failed.');

        document.getElementById('fsPhotoPreview').innerHTML =
          '<img src="' + data.photoUrl + '" style="width:100%; height:100%; object-fit:cover;">';
      } catch (err) {
        alertEl.textContent = err.message;
        alertEl.style.display = 'block';
      }
      e.target.value = '';
    });

    document.getElementById('fieldStaffSaveBtn').addEventListener('click', async () => {
      const alertEl = document.getElementById('fieldStaffAlert');
      alertEl.style.display = 'none';

      const body = {
        fullName: document.getElementById('fsFullName').value.trim(),
        role: document.getElementById('fsRole').value.trim(),
        departmentId: document.getElementById('fsDepartmentId').value || null,
        phone: document.getElementById('fsPhone').value.trim(),
        branch: document.getElementById('fsBranch').value.trim()
      };

      if (!body.fullName) {
        alertEl.textContent = 'Full name is required.';
        alertEl.style.display = 'block';
        return;
      }

      const url = editingId ? '/api/field-staff/' + editingId : '/api/field-staff';
      const method = editingId ? 'PUT' : 'POST';

      try {
        const res = await fetch(url, {
          method,
          credentials: 'include',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(body)
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Could not save.');

        document.getElementById('fieldStaffModalBackdrop').classList.remove('visible');
        loadFieldStaff();
      } catch (err) {
        alertEl.textContent = err.message;
        alertEl.style.display = 'block';
      }
    });

    async function deactivateFS(id) {
      if (!confirm('Deactivate this field worker? Their ID card will stop verifying as active.')) return;
      try {
        const res = await fetch('/api/field-staff/' + id + '/deactivate', { method: 'POST', credentials: 'include' });
        if (!res.ok) throw new Error('Could not deactivate.');
        loadFieldStaff();
      } catch (err) {
        alert(err.message);
      }
    }

    async function reactivateFS(id) {
      try {
        const res = await fetch('/api/field-staff/' + id + '/reactivate', { method: 'POST', credentials: 'include' });
        if (!res.ok) throw new Error('Could not reactivate.');
        loadFieldStaff();
      } catch (err) {
        alert(err.message);
      }
    }

    async function deleteFS(id, name) {
      if (!confirm('Permanently delete ' + name + '? This cannot be undone -- their record and QR code will stop working immediately. If you just want to disable their card temporarily, use Deactivate instead.')) return;
      try {
        const res = await fetch('/api/field-staff/' + id, { method: 'DELETE', credentials: 'include' });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Could not delete.');
        loadFieldStaff();
      } catch (err) {
        alert(err.message);
      }
    }

    async function generateCard(id) {
      try {
        const res = await fetch('/api/field-staff/' + id + '/generate-id', { method: 'POST', credentials: 'include' });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Could not generate ID card.');
        window.open('id-card-view.html?fieldId=' + id, '_blank');
        loadFieldStaff();
      } catch (err) {
        alert(err.message);
      }
    }

    init();
  </script>
</body>
</html>
PAGE_EOF

echo "==> Overwriting portal/id-card-view.html"
cat > portal/id-card-view.html << 'VIEW_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>MACDEN Staff ID Card</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@500;700;800&family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
<script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js"></script>
<style>
  :root{
    --green:#0d5c2f;
    --green-deep:#0a4a25;
    --maroon:#6b1f1f;
    --maroon-deep:#4d1616;
    --bg:#fbfaf6;
    --ink:#1a1a1a;
    --ink-soft:#4a4a4a;
    --hairline:rgba(107,31,31,0.18);
  }
  *{box-sizing:border-box; margin:0; padding:0;}
  body{
    background:#e9e5db;
    font-family:'Inter', sans-serif;
    padding:40px;
    display:flex;
    flex-wrap:wrap;
    gap:28px;
    align-items:flex-start;
    justify-content:center;
  }
  .stage-label{ width:100%; text-align:center; font-size:13px; color:#8a8478; letter-spacing:0.08em; text-transform:uppercase; margin-bottom:6px; }
  .card{ width:85.6mm; height:53.98mm; position:relative; background:var(--bg); border-radius:2.6mm; overflow:hidden; box-shadow:0 6px 22px rgba(0,0,0,0.28); color:var(--ink); }
  .guilloche{ position:absolute; inset:0; width:100%; height:100%; z-index:1; opacity:0.55; }
  .seal{ position:absolute; z-index:2; pointer-events:none; }
  .seal img{ width:100%; height:100%; display:block; opacity:0.13; }
  .front .seal{ width:44mm; height:44mm; right:-6mm; top:50%; transform:translateY(-50%); }
  .back .seal{ width:34mm; height:34mm; left:-4mm; bottom:-6mm; }
  .microring{ position:absolute; z-index:2; pointer-events:none; opacity:0.5; }
  .front .microring{ width:44mm; height:44mm; right:-6mm; top:50%; transform:translateY(-50%); }
  .microring text{ font-family:'Inter', sans-serif; font-size:2.1px; letter-spacing:1.4px; fill:var(--green-deep); }
  .header{ position:relative; z-index:5; height:9.2mm; background:linear-gradient(90deg, var(--green-deep) 0%, var(--green) 62%, var(--maroon) 100%); display:flex; align-items:center; padding:0 3mm; gap:2mm; }
  .header img{ height:6.4mm; width:6.4mm; object-fit:contain; background:#fff; border-radius:50%; padding:0.5mm; }
  .header .wordmark{ display:flex; flex-direction:column; line-height:1; }
  .header .wordmark .name{ font-family:'Manrope', sans-serif; font-weight:800; font-size:4.1mm; color:#fff; letter-spacing:0.02em; }
  .header .wordmark .tag{ font-family:'Inter', sans-serif; font-weight:500; font-size:1.5mm; color:rgba(255,255,255,0.82); letter-spacing:0.05em; text-transform:uppercase; }
  .header .doctype{ margin-left:auto; font-family:'Inter', sans-serif; font-weight:700; font-size:2mm; color:#fff; letter-spacing:0.12em; border:0.3mm solid rgba(255,255,255,0.55); padding:0.8mm 1.6mm; border-radius:1mm; white-space:nowrap; }
  .front-body{ position:relative; z-index:5; display:flex; gap:3mm; padding:2.6mm 3mm 2mm 3mm; align-items:flex-start; }
  .photo-wrap{ position:relative; flex-shrink:0; }
  .photo{ width:19mm; height:23mm; border-radius:1.4mm; background:linear-gradient(155deg, var(--green) 0%, var(--green-deep) 45%, var(--maroon) 100%); display:flex; align-items:center; justify-content:center; box-shadow:0 0.5mm 1.5mm rgba(0,0,0,0.25); border:0.35mm solid #fff; overflow:hidden; }
  .photo img{ width:100%; height:100%; object-fit:cover; object-position:center 15%; }
  .photo .initials{ font-family:'Manrope', sans-serif; font-weight:800; font-size:6.5mm; color:#fbfaf6; letter-spacing:0.02em; }
  .ghost-photo{ position:absolute; width:9mm; height:9mm; border-radius:50%; background:var(--green-deep); overflow:hidden; display:flex; align-items:center; justify-content:center; z-index:3; left:51mm; top:33mm; }
  .ghost-photo img{ width:100%; height:100%; object-fit:cover; filter:grayscale(1) brightness(1.3) contrast(0.9); opacity:0.5; }
  .ghost-photo span{ font-family:'Manrope', sans-serif; font-weight:800; font-size:2.6mm; color:#fff; opacity:0.85; }
  .info{ display:flex; flex-direction:column; padding-top:0.5mm; min-width:0; }
  .info .label{ font-family:'Inter', sans-serif; font-weight:600; font-size:1.5mm; color:var(--maroon); letter-spacing:0.09em; text-transform:uppercase; margin-top:1.6mm; }
  .info .label:first-child{margin-top:0;}
  .info .value{ font-family:'Inter', sans-serif; font-weight:600; font-size:2.5mm; color:var(--ink); line-height:1.15; }
  .info .staff-name{ font-family:'Manrope', sans-serif; font-weight:800; font-size:3.6mm; color:var(--green-deep); line-height:1.08; margin-top:0.2mm; }
  .front-footer{ position:absolute; z-index:5; bottom:0; left:0; right:0; display:flex; justify-content:space-between; align-items:center; padding:1.2mm 3mm; background:rgba(255,255,255,0.55); border-top:0.25mm solid var(--hairline); }
  .staff-id-chip{ font-family:'Manrope', sans-serif; font-weight:800; font-size:2.3mm; color:#fff; background:linear-gradient(90deg, var(--maroon-deep), var(--maroon)); padding:0.9mm 2.2mm; border-radius:1mm; letter-spacing:0.03em; }
  .valid-line{ font-family:'Inter', sans-serif; font-weight:500; font-size:1.4mm; color:var(--ink-soft); letter-spacing:0.03em; }
  .back-body{ position:relative; z-index:5; display:flex; height:calc(100% - 9.2mm - 5mm); }
  .back-left{ flex:1; padding:2.2mm 2.6mm 1.2mm 2.6mm; display:flex; flex-direction:column; gap:1.4mm; }
  .back-left .block-label{ font-family:'Inter', sans-serif; font-weight:700; font-size:1.5mm; color:var(--maroon); letter-spacing:0.08em; text-transform:uppercase; }
  .back-left .block-value{ font-family:'Inter', sans-serif; font-weight:500; font-size:2mm; color:var(--ink); line-height:1.35; margin-top:0.3mm; }
  .back-left .divider{ height:0.25mm; background:var(--hairline); margin:0.4mm 0; }
  .property-line{ margin-top:auto; font-family:'Inter', sans-serif; font-weight:600; font-size:1.6mm; color:var(--green-deep); line-height:1.3; border-left:0.6mm solid var(--maroon); padding-left:1.4mm; }
  .back-right{ width:24mm; flex-shrink:0; display:flex; flex-direction:column; align-items:center; justify-content:center; gap:1.2mm; padding:2mm 1.6mm; background:rgba(13,92,47,0.045); border-left:0.25mm solid var(--hairline); }
  .qr-box{ width:18.5mm; height:18.5mm; background:#fff; border-radius:1mm; padding:1mm; box-shadow:0 0.4mm 1mm rgba(0,0,0,0.15); }
  .qr-box img{ width:100%; height:100%; display:block; }
  .verify-label{ font-family:'Manrope', sans-serif; font-weight:800; font-size:1.7mm; color:var(--green-deep); letter-spacing:0.06em; text-align:center; }
  .verify-sub{ font-family:'Inter', sans-serif; font-weight:500; font-size:1.25mm; color:var(--ink-soft); text-align:center; line-height:1.3; }
  .back-footer{ position:absolute; z-index:5; bottom:0; left:0; right:0; display:flex; justify-content:center; padding:1mm; background:linear-gradient(90deg, var(--green-deep), var(--maroon-deep)); }
  .back-footer span{ font-family:'Inter', sans-serif; font-weight:600; font-size:1.3mm; color:rgba(255,255,255,0.85); letter-spacing:0.1em; text-transform:uppercase; }
  #loading, #error{ width:100%; text-align:center; padding:60px 20px; font-size:15px; color:#5a5a5a; }
  #error{ color:#8a1f1f; display:none; }
  #cards{ display:none; }
  #downloadBar{ display:none; width:100%; text-align:center; margin-top:8px; }
  #downloadBtn{
    font-family:'Manrope', sans-serif; font-weight:700; font-size:14px;
    background:var(--green); color:#fff; border:none; padding:11px 24px;
    border-radius:8px; cursor:pointer; box-shadow:0 2px 8px rgba(13,92,47,0.25);
  }
  #downloadBtn:hover{ background:var(--green-deep); }
  #downloadBtn:disabled{ opacity:0.6; cursor:wait; }
  #downloadStatus{ font-size:12.5px; color:#5a5a5a; margin-top:8px; }
  @media print{
    body{ background:#fff; padding:0; display:block; }
    .stage-label{display:none;}
    #loading, #error{display:none !important;}
    .card-wrap{ page-break-after:always; display:flex; align-items:center; justify-content:center; height:100vh; }
    .card{ box-shadow:none; }
    @page{ size:85.6mm 53.98mm; margin:0; }
  }
</style>
</head>
<body>

<div id="loading">Loading staff ID card…</div>
<div id="error"></div>

<div id="cards">
<div class="stage-label">Front</div>
<div class="card-wrap">
<div class="card front">
  <svg class="guilloche" viewBox="0 0 856 540" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">
    <defs>
      <pattern id="wave1" width="60" height="60" patternUnits="userSpaceOnUse" patternTransform="rotate(8)">
        <path d="M0 30 Q15 5 30 30 T60 30" stroke="#0d5c2f" stroke-width="0.6" fill="none" opacity="0.16"/>
        <path d="M0 45 Q15 20 30 45 T60 45" stroke="#6b1f1f" stroke-width="0.5" fill="none" opacity="0.12"/>
      </pattern>
    </defs>
    <rect width="856" height="540" fill="url(#wave1)"/>
  </svg>
  <div class="seal"><img src="assets/logo-seal-mono.png" alt=""></div>
  <svg class="microring" viewBox="0 0 100 100">
    <defs><path id="ringPathFront" d="M 50, 50 m -46, 0 a 46,46 0 1,1 92,0 a 46,46 0 1,1 -92,0"/></defs>
    <text><textPath href="#ringPathFront" startOffset="0%">MACDEN COMMUNICATIONS LTD &#8226; DISTRIBUTING GOODNESS, DELIVERING TRUST &#8226; MACDEN COMMUNICATIONS LTD &#8226; DISTRIBUTING GOODNESS, DELIVERING TRUST &#8226;</textPath></text>
  </svg>
  <div class="header">
    <img src="assets/logo.jpeg" alt="MACDEN">
    <div class="wordmark"><div class="name">MACDEN</div><div class="tag">Communications Ltd</div></div>
    <div class="doctype">STAFF ID</div>
  </div>
  <div class="front-body">
    <div class="photo-wrap">
      <div class="photo" id="main-photo"></div>
    </div>
    <div class="info">
      <div class="label">Full Name</div>
      <div class="value staff-name" id="f-name"></div>
      <div class="label">Department</div>
      <div class="value" id="f-dept"></div>
      <div class="label">Role</div>
      <div class="value" id="f-role"></div>
    </div>
  </div>
  <div class="ghost-photo" id="ghost-photo"></div>
  <div class="front-footer">
    <div class="staff-id-chip" id="f-staffid"></div>
    <div class="valid-line">Valid while active</div>
  </div>
</div>
</div>

<div class="stage-label">Back</div>
<div class="card-wrap">
<div class="card back">
  <svg class="guilloche" viewBox="0 0 856 540" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">
    <rect width="856" height="540" fill="url(#wave1)"/>
  </svg>
  <div class="seal"><img src="assets/logo-seal-mono.png" alt=""></div>
  <div class="header">
    <img src="assets/logo.jpeg" alt="MACDEN">
    <div class="wordmark"><div class="name">MACDEN</div><div class="tag">Communications Ltd</div></div>
    <div class="doctype">STAFF ID</div>
  </div>
  <div class="back-body">
    <div class="back-left">
      <div>
        <div class="block-label">Head Office</div>
        <div class="block-value">Ogba, Wemco Road, Lagos, Nigeria</div>
      </div>
      <div class="divider"></div>
      <div>
        <div class="block-label">Emergency Contact</div>
        <div class="block-value">Company: +234 807 990 7796</div>
        <div class="block-value" id="b-employee-phone" style="display:none;"></div>
      </div>
      <div class="property-line">
        Property of MACDEN Communications Ltd.<br>
        If found, please return to the address above.
      </div>
    </div>
    <div class="back-right">
      <div class="qr-box"><img id="qr-img" src="" alt="QR Verification"></div>
      <div class="verify-label">VERIFY STAFF ID</div>
      <div class="verify-sub">Scan to confirm identity &amp; active status</div>
    </div>
  </div>
  <div class="back-footer"><span>This card remains the property of MACDEN Communications Ltd</span></div>
</div>
</div>
</div>

<div id="downloadBar">
  <button id="downloadBtn">Download PDF</button>
  <div id="downloadStatus"></div>
</div>

<script>
(function(){
  const params = new URLSearchParams(window.location.search);
  const requestId = params.get('requestId');
  const fieldId = params.get('fieldId');
  const $ = (id) => document.getElementById(id);

  function initials(name){
    return (name || '?').split(' ').filter(Boolean).slice(0,2).map(w => w[0].toUpperCase()).join('');
  }

  if (!requestId && !fieldId) {
    $('loading').style.display = 'none';
    $('error').style.display = 'block';
    $('error').textContent = 'No request specified.';
    return;
  }

  const fetchUrl = fieldId
    ? '/api/field-staff/' + encodeURIComponent(fieldId) + '/card'
    : '/api/id-card/card/' + encodeURIComponent(requestId);

  fetch(fetchUrl, { credentials: 'include' })
    .then(r => r.json().then(data => ({ ok: r.ok, data })))
    .then(({ ok, data }) => {
      $('loading').style.display = 'none';

      if (!ok) {
        $('error').style.display = 'block';
        $('error').textContent = data.error || 'Could not load this ID card.';
        return;
      }

      $('cards').style.display = 'flex';
      $('f-name').textContent = data.full_name;
      $('f-dept').textContent = data.department || '—';
      $('f-role').textContent = data.role;
      $('f-staffid').textContent = data.staff_id;
      $('qr-img').src = data.qr_data_url;

      if (data.employee_phone) {
        const phoneEl = $('b-employee-phone');
        phoneEl.textContent = 'Employee: ' + data.employee_phone;
        phoneEl.style.display = 'block';
      }

      const mainPhoto = $('main-photo');
      const ghostPhoto = $('ghost-photo');
      if (data.photo_url) {
        mainPhoto.innerHTML = '<img crossorigin="anonymous" src="' + data.photo_url + '" alt="">';
        ghostPhoto.innerHTML = '<img crossorigin="anonymous" src="' + data.photo_url + '" alt="">';
      } else {
        mainPhoto.innerHTML = '<span class="initials">' + initials(data.full_name) + '</span>';
        ghostPhoto.innerHTML = '<span>' + initials(data.full_name) + '</span>';
      }

      document.getElementById('downloadBar').style.display = 'block';
      document.getElementById('downloadBtn').addEventListener('click', function(){
        downloadCardAsPDF(data.full_name, data.staff_id);
      });
    })
    .catch(() => {
      $('loading').style.display = 'none';
      $('error').style.display = 'block';
      $('error').textContent = 'Something went wrong loading this card.';
    });

  async function downloadCardAsPDF(fullName, staffId){
    const btn = document.getElementById('downloadBtn');
    const status = document.getElementById('downloadStatus');
    btn.disabled = true;
    status.textContent = 'Generating PDF…';

    try {
      const front = document.querySelector('.card.front');
      const back = document.querySelector('.card.back');

      // Render each card at high resolution for print-quality output
      const [frontCanvas, backCanvas] = await Promise.all([
        html2canvas(front, { scale: 4, backgroundColor: null, useCORS: true }),
        html2canvas(back, { scale: 4, backgroundColor: null, useCORS: true })
      ]);

      const { jsPDF } = window.jspdf;
      // CR80 exact size in mm, matching the printed template
      const doc = new jsPDF({ unit: 'mm', format: [85.6, 53.98], orientation: 'landscape' });

      doc.addImage(frontCanvas.toDataURL('image/png', 1.0), 'PNG', 0, 0, 85.6, 53.98);
      doc.addPage([85.6, 53.98], 'landscape');
      doc.addImage(backCanvas.toDataURL('image/png', 1.0), 'PNG', 0, 0, 85.6, 53.98);

      const safeName = (fullName || 'staff').replace(/[^a-z0-9]+/gi, '-').toLowerCase();
      const safeId = (staffId || '').replace(/[^a-z0-9]+/gi, '-').toLowerCase();
      doc.save('macden-id-card-' + safeName + (safeId ? '-' + safeId : '') + '.pdf');

      status.textContent = 'Downloaded.';
    } catch (err) {
      console.error('PDF generation failed:', err);
      status.textContent = 'Could not generate PDF. If your photo is hosted somewhere blocking cross-site access, that may be why -- try again, or contact IT.';
    } finally {
      btn.disabled = false;
    }
  }
})();
</script>

</body>
</html>
VIEW_EOF

echo ""
echo "Done. Push with your usual save-progress.sh."
