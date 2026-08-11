#!/bin/bash
# setup-id-card-requests.sh (v2 -- corrected auth shape + relative paths)
#
# Adds the staff ID card request/approval flow:
#   - staff submit a request (button wired in separately via
#     fix-settings-idcard-button.sh)
#   - admins approve/reject via a new standalone page, portal/id-card-requests.html
#     (linked in via fix-managestaff-idcard-link.sh)
#   - approved cards render live at portal/id-card-view.html?requestId=...
#     using real staff data and a live-generated QR code
#
# Auth shape verified against your real requireAuth.js and manage-staff.html.
# Does NOT touch server/server.js beyond the route mount, and does not
# touch settings.html or manage-staff.html -- those are separate scripts.

set -e

echo "==> Creating server/routes/idCardRequests.js"
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
const { supabase } = require('../config/supabaseClient');

router.use(requireAuth);

// *** VERIFIED against real server/middleware/requireAuth.js ***
// requireAuth checks req.session.staff (an object). manage-staff.html
// confirms that object has a .role field. This assumes it also has .id --
// standard, but flagging since it's the one piece not directly confirmed.
function getSessionStaffId(req) {
  return req.session && req.session.staff && req.session.staff.id;
}
function isAdmin(req) {
  return !!(req.session && req.session.staff && req.session.staff.role === 'admin');
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
      .select('id, status, staff_ref_id, staff:staff_ref_id (id, full_name, staff_id, role, branch, photo_url, department_id, departments(name), verification_token)')
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
      qr_data_url: qrDataUrl
    });
  } catch (err) {
    console.error('[ID-CARD-VIEW-ERROR]', err);
    return res.status(500).json({ error: 'Could not load card data.' });
  }
});

module.exports = router;
ROUTE_EOF

echo "==> Creating portal/id-card-view.html"
mkdir -p portal
cat > portal/id-card-view.html << 'VIEW_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>MACDEN Staff ID Card</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@500;700;800&family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
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
  .photo img{ width:100%; height:100%; object-fit:cover; }
  .photo .initials{ font-family:'Manrope', sans-serif; font-weight:800; font-size:6.5mm; color:#fbfaf6; letter-spacing:0.02em; }
  .ghost-photo{ position:absolute; width:9mm; height:9mm; border-radius:50%; background:var(--green-deep); overflow:hidden; display:flex; align-items:center; justify-content:center; z-index:3; left:51mm; top:33mm; }
  .ghost-photo img{ width:100%; height:100%; object-fit:cover; filter:grayscale(1); mix-blend-mode:multiply; opacity:0.7; }
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

<script>
(function(){
  const requestId = new URLSearchParams(window.location.search).get('requestId');
  const $ = (id) => document.getElementById(id);

  function initials(name){
    return (name || '?').split(' ').filter(Boolean).slice(0,2).map(w => w[0].toUpperCase()).join('');
  }

  if (!requestId) {
    $('loading').style.display = 'none';
    $('error').style.display = 'block';
    $('error').textContent = 'No request specified.';
    return;
  }

  fetch('/api/id-card/card/' + encodeURIComponent(requestId), { credentials: 'include' })
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

      const mainPhoto = $('main-photo');
      const ghostPhoto = $('ghost-photo');
      if (data.photo_url) {
        mainPhoto.innerHTML = '<img src="' + data.photo_url + '" alt="">';
        ghostPhoto.innerHTML = '<img src="' + data.photo_url + '" alt="">';
      } else {
        mainPhoto.innerHTML = '<span class="initials">' + initials(data.full_name) + '</span>';
        ghostPhoto.innerHTML = '<span>' + initials(data.full_name) + '</span>';
      }
    })
    .catch(() => {
      $('loading').style.display = 'none';
      $('error').style.display = 'block';
      $('error').textContent = 'Something went wrong loading this card.';
    });
})();
</script>

</body>
</html>
VIEW_EOF

echo "==> Creating portal/id-card-requests.html"
cat > portal/id-card-requests.html << 'REQ_EOF'
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
      const hasStaffId = !!staff.staff_id;
      const avatarContent = staff.photo_url
        ? '<img src="' + staff.photo_url + '" alt="">'
        : initials(staff.full_name);

      return '<div class="request-card" data-id="' + r.id + '">' +
        '<div class="avatar">' + avatarContent + '</div>' +
        '<div class="req-info">' +
          '<div class="req-name">' + (staff.full_name || 'Unknown') + '</div>' +
          '<div class="req-meta">' + (staff.role || '') + ' · ' + dept + '</div>' +
          (hasStaffId ? '' : '<div class="req-warn">No staff ID assigned yet — assign one via Edit Staff before approving.</div>') +
        '</div>' +
        '<div class="actions">' +
          '<button class="reject-btn" data-action="reject" data-id="' + r.id + '">Reject</button>' +
          '<button class="approve-btn" data-action="approve" data-id="' + r.id + '"' + (hasStaffId ? '' : ' disabled') + '>Approve</button>' +
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
REQ_EOF

echo "==> Saving the SQL migration to server/migrations/ for reference (NOT auto-run)"
mkdir -p server/migrations
cat > server/migrations/add_id_card_requests.sql << 'SQL_EOF'
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
SQL_EOF

echo "==> Wiring the route into server/server.js"
if grep -q "require('./routes/idCardRequests')" server/server.js; then
  echo "    Already wired in -- skipping (safe to re-run)."
else
  if ! grep -qF "app.use('/api/accounting', requireAuth);" server/server.js; then
    echo "    ERROR: could not find the expected anchor line in server/server.js."
    echo "    Nothing was changed."
    exit 1
  fi

  cat > .tmp-patch-idcard.js << 'NODE_EOF'
const fs = require('fs');
const filePath = 'server/server.js';
let content = fs.readFileSync(filePath, 'utf8');

const anchor = "app.use('/api/accounting', requireAuth);";
const insertion =
  "// --- MACDEN ID Card Requests (auth required, checked inside the route file) ---\n" +
  "const idCardRoutes = require('./routes/idCardRequests');\n" +
  "app.use(idCardRoutes);\n" +
  "// --- end ID card requests block ---\n\n";

content = content.replace(anchor, insertion + anchor);
fs.writeFileSync(filePath, content);
console.log('    Inserted require + mount before the requireAuth line.');
NODE_EOF

  node .tmp-patch-idcard.js
  rm .tmp-patch-idcard.js
fi

echo "==> Installing qrcode"
npm install qrcode --save

echo ""
echo "=================================================================="
echo "Files created and route wired. Remaining manual steps:"
echo ""
echo "1. Run server/migrations/add_id_card_requests.sql in the Supabase"
echo "   SQL editor (macden-accounting project, not rossyluxe)."
echo ""
echo "2. Add logo-seal-mono.png to portal/assets/ -- referenced by"
echo "   id-card-view.html for the watermark seal."
echo ""
echo "3. Run fix-settings-idcard-button.sh to wire the button into"
echo "   portal/settings.html."
echo ""
echo "4. Run fix-managestaff-idcard-link.sh to add the approval-queue"
echo "   link into portal/manage-staff.html."
echo ""
echo "Then push with your usual save-progress.sh."
echo "=================================================================="
