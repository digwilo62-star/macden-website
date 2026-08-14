#!/bin/bash
# fix-autoassign-on-approve-v1.sh
#
# Approving a staff ID card request now auto-assigns a random staff_id
# automatically, same as the Field Staff "Generate ID Card" action already
# does -- no more requiring an admin to manually type one into Edit Staff
# first. Removes the "No staff ID assigned yet" warning and disabled
# Approve button from the queue page, since it's no longer needed.
#
# Full, safe overwrite of two files -- fully known/controlled.

set -e

echo "==> Overwriting server/routes/idCardRequests.js"
mkdir -p server/routes
cat > server/routes/idCardRequests.js << 'ROUTE_EOF'
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
ROUTE_EOF

echo "==> Overwriting portal/id-card-requests.html"
mkdir -p portal
cat > portal/id-card-requests.html << 'PAGE_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>ID Card Requests — MACDEN Portal</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@700;800&family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
<style>
  :root{
    --green:#0d5c2f; --green-deep:#0a4a25; --maroon:#6b1f1f;
    --bg:#fbfaf6; --ink:#1a1a1a; --ink-soft:#5a5a5a;
  }
  *{box-sizing:border-box; margin:0; padding:0;}
  body{ font-family:'Inter', sans-serif; background:#f2f0ea; padding:32px; }
  .wrap{ max-width:820px; margin:0 auto; }
  h1{ font-family:'Manrope', sans-serif; font-weight:800; font-size:22px; color:var(--green-deep); margin-bottom:4px; }
  .sub{ color:var(--ink-soft); font-size:13.5px; margin-bottom:24px; }
  .empty{ background:#fff; border-radius:10px; padding:40px 20px; text-align:center; color:var(--ink-soft); font-size:14px; }
  .request-card{
    background:#fff; border-radius:10px; padding:16px 18px; margin-bottom:12px;
    display:flex; align-items:center; gap:14px;
    box-shadow:0 1px 4px rgba(0,0,0,0.06);
  }
  .avatar{
    width:44px; height:44px; border-radius:8px; flex-shrink:0;
    background:linear-gradient(155deg, var(--green), var(--maroon));
    display:flex; align-items:center; justify-content:center;
    color:#fff; font-family:'Manrope', sans-serif; font-weight:800; font-size:15px;
    overflow:hidden;
  }
  .avatar img{ width:100%; height:100%; object-fit:cover; }
  .req-info{ flex:1; min-width:0; }
  .req-name{ font-family:'Manrope', sans-serif; font-weight:700; font-size:15px; color:var(--ink); }
  .req-meta{ font-size:12.5px; color:var(--ink-soft); margin-top:2px; }
  .req-warn{ font-size:12px; color:#8a1f1f; font-weight:600; margin-top:4px; }
  .actions{ display:flex; gap:8px; flex-shrink:0; }
  button{
    font-family:'Inter', sans-serif; font-weight:600; font-size:13px;
    padding:8px 14px; border-radius:7px; border:none; cursor:pointer;
  }
  .approve-btn{ background:var(--green); color:#fff; }
  .approve-btn:hover{ background:var(--green-deep); }
  .reject-btn{ background:#f2e7e7; color:#8a1f1f; }
  .reject-btn:hover{ background:#e8d5d5; }
  button:disabled{ opacity:0.5; cursor:not-allowed; }
  .toast{
    position:fixed; bottom:24px; left:50%; transform:translateX(-50%);
    background:var(--ink); color:#fff; padding:10px 18px; border-radius:8px;
    font-size:13.5px; display:none;
  }
</style>
</head>
<body>

<div class="wrap">
  <h1>ID Card Requests</h1>
  <div class="sub">Pending staff requests for a printable MACDEN staff ID card.</div>
  <div id="list"></div>
</div>

<div class="toast" id="toast"></div>

<script>
(function(){
  const $ = (id) => document.getElementById(id);

  function initials(name){
    return (name || '?').split(' ').filter(Boolean).slice(0,2).map(w => w[0].toUpperCase()).join('');
  }

  function showToast(msg){
    const t = $('toast');
    t.textContent = msg;
    t.style.display = 'block';
    setTimeout(() => { t.style.display = 'none'; }, 3000);
  }

  function renderRequests(requests){
    const list = $('list');
    if (!requests.length) {
      list.innerHTML = '<div class="empty">No pending ID card requests right now.</div>';
      return;
    }

    list.innerHTML = requests.map(r => {
      const staff = r.staff || {};
      const dept = staff.departments ? staff.departments.name : '—';
      const avatarContent = staff.photo_url
        ? '<img src="' + staff.photo_url + '" alt="">'
        : initials(staff.full_name);

      return '<div class="request-card" data-id="' + r.id + '">' +
        '<div class="avatar">' + avatarContent + '</div>' +
        '<div class="req-info">' +
          '<div class="req-name">' + (staff.full_name || 'Unknown') + '</div>' +
          '<div class="req-meta">' + (staff.role || '') + ' · ' + dept + '</div>' +
        '</div>' +
        '<div class="actions">' +
          '<button class="reject-btn" data-action="reject" data-id="' + r.id + '">Reject</button>' +
          '<button class="approve-btn" data-action="approve" data-id="' + r.id + '">Approve</button>' +
        '</div>' +
      '</div>';
    }).join('');
  }

  function loadRequests(){
    fetch('/api/id-card/requests', { credentials: 'include' })
      .then(r => r.json().then(data => ({ ok: r.ok, data })))
      .then(({ ok, data }) => {
        if (!ok) {
          $('list').innerHTML = '<div class="empty">' + (data.error || 'Could not load requests.') + '</div>';
          return;
        }
        renderRequests(data.requests || []);
      })
      .catch(() => {
        $('list').innerHTML = '<div class="empty">Something went wrong loading requests.</div>';
      });
  }

  document.addEventListener('click', function(e){
    const btn = e.target.closest('button[data-action]');
    if (!btn) return;

    const id = btn.dataset.id;
    const action = btn.dataset.action;
    const card = btn.closest('.request-card');
    const allButtons = card.querySelectorAll('button');
    allButtons.forEach(b => b.disabled = true);

    const url = '/api/id-card/requests/' + id + '/' + action;
    fetch(url, { method: 'POST', credentials: 'include', headers: {'Content-Type': 'application/json'} })
      .then(r => r.json().then(data => ({ ok: r.ok, data })))
      .then(({ ok, data }) => {
        if (!ok) {
          showToast(data.error || 'Action failed.');
          allButtons.forEach(b => b.disabled = false);
          return;
        }
        showToast(action === 'approve' ? 'Card approved.' : 'Request rejected.');
        loadRequests();
      })
      .catch(() => {
        showToast('Something went wrong.');
        allButtons.forEach(b => b.disabled = false);
      });
  });

  loadRequests();
})();
</script>

</body>
</html>
PAGE_EOF

echo ""
echo "Done. Push with your usual save-progress.sh."
