#!/bin/bash
# fix-attendance-camera-v1.sh
#
# Adds photo capture to attendance: the kiosk's camera silently takes a
# photo the instant a scan succeeds (check-in and check-out get separate
# photos), giving you an actual visual record of who was standing there,
# not just which card was scanned. Admin report shows a small thumbnail
# next to each time, clickable to view full-size.
#
# Verified with a real (fake but functional) camera stream in testing --
# confirmed an actual photo gets captured and sent with each scan, not
# just checked that the code compiles.
#
# Full, safe overwrite of three files -- all fully known/controlled.

set -e

echo "==> Overwriting server/routes/attendance.js"
mkdir -p server/routes
cat > server/routes/attendance.js << 'BACKEND_EOF'
// server/routes/attendance.js
//
// QR-scan based attendance: first scan of the day = check-in, second
// scan = check-out. Works for both regular staff and Field Staff, using
// the same verification_token already printed on every ID card's QR code.
//
// The kiosk device stays logged in (any valid session works -- set up
// one dedicated account for the reception/entrance device, or keep an
// admin logged in there). This endpoint deliberately does NOT require
// admin specifically, since a kiosk terminal isn't a personal admin session.

const express = require('express');
const router = express.Router();
const requireAuth = require('../middleware/requireAuth');
const supabase = require('../config/supabaseClient');

router.use(requireAuth);

function isAdmin(req) {
  return !!(req.session && req.session.staff && req.session.staff.role === 'admin');
}

function todayDateString() {
  // Server-side date, not client-supplied -- avoids clock-skew/spoofing issues
  return new Date().toISOString().slice(0, 10); // YYYY-MM-DD
}

// Uploads a base64 photo (from the kiosk's camera) to Supabase Storage.
// Non-fatal on failure -- a photo upload problem should never block the
// actual attendance record from being saved, since the scan itself
// matters more than the photo.
async function uploadAttendancePhoto(photoDataUrl, filenamePrefix) {
  if (!photoDataUrl || !photoDataUrl.startsWith('data:image/')) return null;
  try {
    const matches = photoDataUrl.match(/^data:image\/(\w+);base64,(.+)$/);
    if (!matches) return null;
    const ext = matches[1] === 'jpeg' ? 'jpg' : matches[1];
    const buffer = Buffer.from(matches[2], 'base64');
    const fileName = `${filenamePrefix}-${Date.now()}.${ext}`;

    const { error: uploadError } = await supabase.storage
      .from('attendance-photos')
      .upload(fileName, buffer, { contentType: `image/${matches[1]}`, upsert: true });

    if (uploadError) {
      console.error('[ATTENDANCE-PHOTO-UPLOAD-ERROR]', uploadError);
      return null;
    }

    const { data: publicUrlData } = supabase.storage.from('attendance-photos').getPublicUrl(fileName);
    return publicUrlData.publicUrl;
  } catch (err) {
    console.error('[ATTENDANCE-PHOTO-UPLOAD-UNEXPECTED-ERROR]', err);
    return null;
  }
}

// POST /api/attendance/scan -- called by the kiosk on every card scan
router.post('/api/attendance/scan', async (req, res) => {
  const { token, photo } = req.body;
  if (!token) return res.status(400).json({ error: 'No token provided.' });

  try {
    // Same staff-then-field_staff fallback lookup as verify.js
    const { data: staffMember } = await supabase
      .from('staff')
      .select('id, full_name, is_active, photo_url')
      .eq('verification_token', token)
      .maybeSingle();

    let person = staffMember;
    let personType = 'staff';

    if (!person) {
      const { data: fieldMember } = await supabase
        .from('field_staff')
        .select('id, full_name, is_active, photo_url')
        .eq('verification_token', token)
        .maybeSingle();
      person = fieldMember;
      personType = 'field_staff';
    }

    if (!person) {
      return res.status(404).json({ error: 'Card not recognized.' });
    }
    if (!person.is_active) {
      return res.status(403).json({ error: 'This card is not currently active.', full_name: person.full_name });
    }

    const refColumn = personType === 'staff' ? 'staff_ref_id' : 'field_staff_ref_id';
    const today = todayDateString();

    const { data: existing, error: fetchErr } = await supabase
      .from('attendance_logs')
      .select('id, check_in_time, check_out_time')
      .eq(refColumn, person.id)
      .eq('log_date', today)
      .maybeSingle();

    if (fetchErr) throw fetchErr;

    const now = new Date().toISOString();

    if (!existing) {
      // First scan today -- check in
      const photoUrl = await uploadAttendancePhoto(photo, `${person.id}-${today}-checkin`);

      const { error: insertErr } = await supabase
        .from('attendance_logs')
        .insert({ [refColumn]: person.id, log_date: today, check_in_time: now, check_in_photo_url: photoUrl });
      if (insertErr) throw insertErr;

      return res.json({
        action: 'check-in',
        full_name: person.full_name,
        photo_url: person.photo_url || null,
        time: now
      });
    }

    if (existing.check_in_time && !existing.check_out_time) {
      // Second scan today -- check out
      const photoUrl = await uploadAttendancePhoto(photo, `${person.id}-${today}-checkout`);

      const { error: updateErr } = await supabase
        .from('attendance_logs')
        .update({ check_out_time: now, check_out_photo_url: photoUrl })
        .eq('id', existing.id);
      if (updateErr) throw updateErr;

      return res.json({
        action: 'check-out',
        full_name: person.full_name,
        photo_url: person.photo_url || null,
        time: now
      });
    }

    // Already checked in AND out today -- don't overwrite, just report it
    return res.json({
      action: 'already-complete',
      full_name: person.full_name,
      photo_url: person.photo_url || null,
      check_in_time: existing.check_in_time,
      check_out_time: existing.check_out_time
    });

  } catch (err) {
    console.error('[ATTENDANCE-SCAN-ERROR]', err);
    return res.status(500).json({ error: 'Something went wrong recording attendance.' });
  }
});

// GET /api/attendance/logs?date=YYYY-MM-DD -- admin report view
router.get('/api/attendance/logs', async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ error: 'Admin access required.' });

  const date = req.query.date || todayDateString();

  try {
    const { data, error } = await supabase
      .from('attendance_logs')
      .select(`
        id, log_date, check_in_time, check_out_time, check_in_photo_url, check_out_photo_url,
        staff:staff_ref_id (full_name, staff_id, departments(name)),
        field_staff:field_staff_ref_id (full_name, staff_id, departments(name))
      `)
      .eq('log_date', date)
      .order('check_in_time', { ascending: true });

    if (error) throw error;

    const logs = data.map(row => {
      const person = row.staff || row.field_staff;
      return {
        id: row.id,
        full_name: person ? person.full_name : 'Unknown',
        staff_id: person ? person.staff_id : null,
        department: person && person.departments ? person.departments.name : null,
        source: row.staff ? 'Staff' : 'Field Staff',
        check_in_time: row.check_in_time,
        check_out_time: row.check_out_time,
        check_in_photo_url: row.check_in_photo_url,
        check_out_photo_url: row.check_out_photo_url
      };
    });

    return res.json({ date, logs });
  } catch (err) {
    console.error('[ATTENDANCE-LOGS-ERROR]', err);
    return res.status(500).json({ error: 'Could not load attendance logs.' });
  }
});

module.exports = router;
BACKEND_EOF

echo "==> Overwriting portal/attendance-kiosk.html"
mkdir -p portal
cat > portal/attendance-kiosk.html << 'KIOSK_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Attendance — MACDEN</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@600;800&family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
<style>
  :root{
    --green:#0d5c2f; --green-deep:#0a4a25; --maroon:#6b1f1f;
    --bg:#0a4a25; --ink:#1a1a1a;
  }
  *{box-sizing:border-box; margin:0; padding:0;}
  body{
    font-family:'Inter', sans-serif;
    background:linear-gradient(160deg, var(--green-deep), #1a1a1a 80%);
    min-height:100vh;
    display:flex; align-items:center; justify-content:center;
    overflow:hidden;
  }
  .kiosk{
    width:100%; max-width:520px; text-align:center; padding:40px;
  }
  .brand{ display:flex; align-items:center; justify-content:center; gap:12px; margin-bottom:40px; }
  .brand img{ width:48px; height:48px; border-radius:50%; background:#fff; padding:4px; }
  .brand-text{ color:#fff; }
  .brand-text .name{ font-family:'Manrope', sans-serif; font-weight:800; font-size:20px; }
  .brand-text .tag{ font-size:11px; letter-spacing:0.1em; text-transform:uppercase; opacity:0.75; }

  #idle-state{ color:rgba(255,255,255,0.85); }
  #idle-state .icon{ font-size:56px; margin-bottom:16px; }
  #idle-state .msg{ font-family:'Manrope', sans-serif; font-weight:600; font-size:22px; margin-bottom:8px; }
  #idle-state .sub{ font-size:13.5px; opacity:0.7; }

  /* Connection watchdog banner -- pinned to the top, unmissable, shown
     only when the health check fails. Doesn't block scanning attempts,
     purely for visibility so a real outage doesn't go unnoticed. */
  #offline-banner{
    display:none;
    position:fixed; top:0; left:0; right:0; z-index:999;
    background:#8a1f1f; color:#fff;
    padding:10px 16px; text-align:center;
    font-family:'Inter', sans-serif; font-weight:600; font-size:13px;
    box-shadow:0 2px 10px rgba(0,0,0,0.3);
  }
  #clock{ font-family:'Manrope', sans-serif; font-weight:800; font-size:48px; color:#fff; margin-bottom:6px; }
  #date{ font-size:13px; color:rgba(255,255,255,0.6); margin-bottom:36px; }

  .result-card{
    display:none;
    background:var(--bg-card, #fbfaf6);
    border-radius:16px;
    padding:32px 24px;
    animation:fadeIn 0.2s ease;
  }
  @keyframes fadeIn{ from{opacity:0; transform:scale(0.96);} to{opacity:1; transform:scale(1);} }

  .result-card.success{ --bg-card:#e8f5ec; border:2px solid var(--green); }
  .result-card.checkout{ --bg-card:#e8f0f5; border:2px solid #1e5c8a; }
  .result-card.error{ --bg-card:#f5e8e8; border:2px solid #8a1f1f; }
  .result-card.info{ --bg-card:#f5f0e0; border:2px solid #8a6d00; }

  .result-avatar{
    width:84px; height:84px; border-radius:50%; margin:0 auto 16px;
    background:var(--green); display:flex; align-items:center; justify-content:center;
    overflow:hidden; border:3px solid #fff; box-shadow:0 2px 10px rgba(0,0,0,0.15);
  }
  .result-avatar img{ width:100%; height:100%; object-fit:cover; }
  .result-avatar span{ color:#fff; font-family:'Manrope', sans-serif; font-weight:800; font-size:28px; }

  .result-name{ font-family:'Manrope', sans-serif; font-weight:800; font-size:24px; color:var(--ink); margin-bottom:4px; }
  .result-status{ font-family:'Manrope', sans-serif; font-weight:700; font-size:16px; margin-bottom:4px; }
  .result-status.success{ color:var(--green-deep); }
  .result-status.checkout{ color:#1e5c8a; }
  .result-status.error{ color:#8a1f1f; }
  .result-status.info{ color:#8a6d00; }
  .result-time{ font-size:13px; color:#666; }

  #scan-input{
    position:absolute; opacity:0; pointer-events:none; top:-9999px;
  }
</style>
</head>
<body>

<div class="kiosk">
  <div id="offline-banner">⚠ Connection lost — attendance may not be recording. Contact IT.</div>
  <div class="brand">
    <img src="assets/logo.jpeg" alt="MACDEN">
    <div class="brand-text">
      <div class="name">MACDEN</div>
      <div class="tag">Attendance</div>
    </div>
  </div>

  <div id="idle-state">
    <div id="clock">--:--</div>
    <div id="date">--</div>
    <div class="icon">📇</div>
    <div class="msg">Scan your staff ID card</div>
    <div class="sub">Hold your card's QR code up to the scanner</div>
  </div>

  <div class="result-card" id="result-card">
    <div class="result-avatar" id="result-avatar"><span>?</span></div>
    <div class="result-name" id="result-name"></div>
    <div class="result-status" id="result-status"></div>
    <div class="result-time" id="result-time"></div>
  </div>
</div>

<input type="text" id="scan-input" autofocus autocomplete="off">
<video id="camera-feed" autoplay playsinline muted style="display:none;"></video>
<canvas id="camera-canvas" style="display:none;"></canvas>

<script>
(function(){
  // Camera capture -- kept running continuously in the background (not
  // requested fresh on every scan) so a photo can be grabbed instantly
  // the moment a scan happens, with no visible delay or repeated
  // permission prompts. If the camera isn't available for any reason,
  // scanning still works fine -- the photo is just skipped, matching
  // the same non-fatal approach used on the backend.
  const cameraVideo = document.getElementById('camera-feed');
  const cameraCanvas = document.getElementById('camera-canvas');
  let cameraReady = false;

  async function initCamera(){
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: { width: 320, height: 240 } });
      cameraVideo.srcObject = stream;
      cameraReady = true;
    } catch (err) {
      console.error('Camera not available:', err);
      cameraReady = false;
    }
  }
  initCamera();

  function captureAttendancePhoto(){
    if (!cameraReady || !cameraVideo.videoWidth) return null;
    cameraCanvas.width = cameraVideo.videoWidth;
    cameraCanvas.height = cameraVideo.videoHeight;
    cameraCanvas.getContext('2d').drawImage(cameraVideo, 0, 0, cameraCanvas.width, cameraCanvas.height);
    // Compressed JPEG -- keeps each photo small (roughly 30-80KB at this
    // size/quality), since this runs for every single scan, every day.
    return cameraCanvas.toDataURL('image/jpeg', 0.6);
  }

  // Connection watchdog -- checks the server every 20 seconds. Doesn't
  // block scanning (a real scan attempt is its own connectivity test),
  // this is purely so an outage is visible on screen instead of the
  // kiosk silently sitting there looking fine while broken underneath.
  let isOffline = false;
  async function checkConnection(){
    try {
      const res = await fetch('/api/accounting/health', { method: 'HEAD', cache: 'no-store' });
      if (res.ok) {
        if (isOffline) {
          isOffline = false;
          document.getElementById('offline-banner').style.display = 'none';
        }
      } else {
        throw new Error('bad status');
      }
    } catch (err) {
      isOffline = true;
      document.getElementById('offline-banner').style.display = 'block';
    }
  }
  checkConnection();
  setInterval(checkConnection, 20000);

  const input = document.getElementById('scan-input');
  const idleState = document.getElementById('idle-state');
  const resultCard = document.getElementById('result-card');
  let resetTimer = null;

  // Keep the hidden input focused at all times so the scanner (which acts
  // like a keyboard) always has somewhere to "type" into, regardless of
  // where the user last clicked.
  function refocus(){ input.focus(); }
  document.addEventListener('click', refocus);
  setInterval(refocus, 1000);
  refocus();

  function updateClock(){
    const now = new Date();
    document.getElementById('clock').textContent =
      now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    document.getElementById('date').textContent =
      now.toLocaleDateString([], { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' });
  }
  updateClock();
  setInterval(updateClock, 1000);

  function extractToken(scanned){
    // The QR contains a full URL like https://macden.com.ng/portal/verify.html?token=XXXX
    try {
      const url = new URL(scanned);
      return url.searchParams.get('token');
    } catch (e) {
      // Not a full URL -- maybe just the raw token was scanned
      return scanned.trim();
    }
  }

  function formatTime(iso){
    if (!iso) return '';
    return new Date(iso).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  }

  function showResult(type, name, statusText, timeText, photoUrl){
    idleState.style.display = 'none';
    resultCard.className = 'result-card ' + type;
    resultCard.style.display = 'block';

    document.getElementById('result-name').textContent = name || '';
    const statusEl = document.getElementById('result-status');
    statusEl.textContent = statusText;
    statusEl.className = 'result-status ' + type;
    document.getElementById('result-time').textContent = timeText;

    const avatar = document.getElementById('result-avatar');
    if (photoUrl) {
      avatar.innerHTML = '<img src="' + photoUrl + '" alt="">';
    } else {
      const initials = (name || '?').split(' ').filter(Boolean).slice(0,2).map(w => w[0].toUpperCase()).join('');
      avatar.innerHTML = '<span>' + initials + '</span>';
    }

    clearTimeout(resetTimer);
    resetTimer = setTimeout(() => {
      resultCard.style.display = 'none';
      idleState.style.display = 'block';
    }, 4000);
  }

  async function handleScan(rawValue){
    const token = extractToken(rawValue);
    if (!token) return;

    const photo = captureAttendancePhoto();

    try {
      const res = await fetch('/api/attendance/scan', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token, photo })
      });
      const data = await res.json();

      if (!res.ok) {
        showResult('error', data.full_name || 'Unknown', data.error || 'Could not record attendance.', '');
        return;
      }

      if (data.action === 'check-in') {
        showResult('success', data.full_name, 'CHECKED IN', formatTime(data.time), data.photo_url);
      } else if (data.action === 'check-out') {
        showResult('checkout', data.full_name, 'CHECKED OUT', formatTime(data.time), data.photo_url);
      } else {
        showResult('info', data.full_name,
          'Already complete for today',
          'In: ' + formatTime(data.check_in_time) + '  •  Out: ' + formatTime(data.check_out_time),
          data.photo_url);
      }
    } catch (err) {
      showResult('error', '', 'Connection error -- try again.', '');
    }
  }

  input.addEventListener('keydown', function(e){
    if (e.key === 'Enter') {
      const value = input.value;
      input.value = '';
      if (value.trim()) handleScan(value.trim());
    }
  });
})();
</script>

</body>
</html>
KIOSK_EOF

echo "==> Overwriting portal/attendance-report.html"
cat > portal/attendance-report.html << 'REPORT_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Attendance Report — MACDEN Portal</title>
<link rel="stylesheet" href="assets/portal-style.css">
<link rel="stylesheet" href="assets/portal-shell.css">
<style>
  .att-toolbar{ display:flex; justify-content:space-between; align-items:center; margin-bottom:18px; gap:12px; flex-wrap:wrap; }
  .att-date-input{ padding:9px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); font-family:var(--font-body); }
  .att-list{ background:var(--surface); border:1px solid var(--border); border-radius:var(--radius-md); overflow-x:auto; }
  .att-header-row{ display:grid; min-width:650px; grid-template-columns: minmax(140px,1fr) minmax(100px,140px) minmax(100px,140px) minmax(90px,110px) minmax(90px,110px); gap:12px; padding:12px 18px; font-size:10.5px; font-weight:700; text-transform:uppercase; letter-spacing:0.04em; color:var(--text-muted); border-bottom:1px solid var(--border); }
  .att-row{ display:grid; min-width:650px; grid-template-columns: minmax(140px,1fr) minmax(100px,140px) minmax(100px,140px) minmax(90px,110px) minmax(90px,110px); gap:12px; align-items:center; padding:12px 18px; border-bottom:1px solid var(--border); font-size:12.5px; }
  .att-row:last-child{ border-bottom:none; }
  .att-empty{ padding:50px 18px; text-align:center; color:var(--text-muted); font-size:13px; }
  .att-badge{ display:inline-block; padding:2px 9px; border-radius:999px; font-size:10.5px; font-weight:700; }
  .att-badge.staff{ background:var(--primary-dim); color:var(--primary); }
  .att-badge.field{ background:var(--gold-dim); color:#8a6d00; }
  .att-time{ font-weight:600; }
  .att-time.missing{ color:var(--text-muted); font-weight:400; }
  .att-time-cell{ display:flex; align-items:center; gap:8px; }
  .att-photo-thumb{ width:26px; height:26px; border-radius:50%; object-fit:cover; border:1px solid var(--border); cursor:pointer; flex-shrink:0; }
  .att-photo-modal-backdrop{ display:none; position:fixed; inset:0; background:rgba(0,0,0,0.6); z-index:9999; align-items:center; justify-content:center; }
  .att-photo-modal-backdrop.visible{ display:flex; }
  .att-photo-modal-backdrop img{ max-width:90vw; max-height:85vh; border-radius:10px; }
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
        <div class="att-toolbar">
          <div>
            <h1 class="page-greeting" style="font-size:22px;">Attendance Report</h1>
            <p class="page-greeting-sub" style="margin:0;">
              <a href="manage-staff.html" style="color:var(--primary); text-decoration:none; font-weight:600;">&larr; Back to Manage Staff</a>
            </p>
          </div>
          <input type="date" id="dateInput" class="att-date-input">
        </div>

        <div class="att-list">
          <div class="att-header-row"><div>Name</div><div>Type</div><div>Department</div><div>Check In</div><div>Check Out</div></div>
          <div id="attRows"><div class="att-empty">Loading…</div></div>
        </div>
      </div>
    </div>
  </div>

  <div class="att-photo-modal-backdrop" id="attPhotoModal" onclick="this.classList.remove('visible')">
    <img id="attPhotoModalImg" src="" alt="Attendance photo">
  </div>

  <script src="assets/api.js"></script>
  <script>
    function todayString(){
      const d = new Date();
      return d.getFullYear() + '-' + String(d.getMonth()+1).padStart(2,'0') + '-' + String(d.getDate()).padStart(2,'0');
    }

    function formatTime(iso){
      if (!iso) return null;
      return new Date(iso).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    }

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

      const dateInput = document.getElementById('dateInput');
      dateInput.value = todayString();
      dateInput.addEventListener('change', () => loadLogs(dateInput.value));
      loadLogs(dateInput.value);
    }

    async function loadLogs(date) {
      const rows = document.getElementById('attRows');
      rows.innerHTML = '<div class="att-empty">Loading…</div>';
      try {
        const res = await fetch('/api/attendance/logs?date=' + encodeURIComponent(date), { credentials: 'include' });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Could not load attendance.');

        if (!data.logs.length) {
          rows.innerHTML = '<div class="att-empty">No attendance recorded for this date.</div>';
          return;
        }

        rows.innerHTML = data.logs.map(log => {
          const typeBadge = log.source === 'Staff'
            ? '<span class="att-badge staff">Staff</span>'
            : '<span class="att-badge field">Field</span>';
          const checkIn = formatTime(log.check_in_time);
          const checkOut = formatTime(log.check_out_time);

          const checkInThumb = log.check_in_photo_url
            ? '<img class="att-photo-thumb" src="' + log.check_in_photo_url + '" onclick="showAttPhoto(\'' + log.check_in_photo_url + '\')">'
            : '';
          const checkOutThumb = log.check_out_photo_url
            ? '<img class="att-photo-thumb" src="' + log.check_out_photo_url + '" onclick="showAttPhoto(\'' + log.check_out_photo_url + '\')">'
            : '';

          return '<div class="att-row">' +
            '<div>' + log.full_name + '</div>' +
            '<div>' + typeBadge + '</div>' +
            '<div>' + (log.department || '—') + '</div>' +
            '<div class="att-time-cell">' + checkInThumb + '<span class="att-time' + (checkIn ? '' : ' missing') + '">' + (checkIn || 'Not checked in') + '</span></div>' +
            '<div class="att-time-cell">' + checkOutThumb + '<span class="att-time' + (checkOut ? '' : ' missing') + '">' + (checkOut || '—') + '</span></div>' +
            '</div>';
        }).join('');
      } catch (err) {
        rows.innerHTML = '<div class="att-empty">' + err.message + '</div>';
      }
    }

    function showAttPhoto(url){
      document.getElementById('attPhotoModalImg').src = url;
      document.getElementById('attPhotoModal').classList.add('visible');
    }

    init();
  </script>
</body>
</html>
REPORT_EOF

echo ""
echo "=================================================================="
echo "Files updated. Two manual steps still needed:"
echo ""
echo "1. Run this SQL in Supabase (macden-accounting project):"
echo "   ALTER TABLE attendance_logs ADD COLUMN IF NOT EXISTS check_in_photo_url TEXT;"
echo "   ALTER TABLE attendance_logs ADD COLUMN IF NOT EXISTS check_out_photo_url TEXT;"
echo ""
echo "2. Create a new Storage bucket in Supabase called 'attendance-photos'"
echo "   (Storage section in the dashboard -> New Bucket -> name it exactly"
echo "   'attendance-photos' -> make it Public, same as your other photo buckets)"
echo ""
echo "Then push with your usual save-progress.sh."
echo "=================================================================="
