#!/bin/bash
# setup-attendance-v1.sh
#
# Adds QR-scan-based attendance tracking: check-in and check-out, for
# both regular staff and Field Staff, reusing the same verification_token
# already printed on every ID card.
#
# Creates:
#   - server/routes/attendance.js -- scan endpoint + admin report endpoint
#   - portal/attendance-kiosk.html -- the scanning screen for your entrance
#   - portal/attendance-report.html -- admin view of daily attendance
#   - server/migrations/add_attendance_logs.sql (reference, NOT auto-run)
#
# Wires the route into server/server.js. Safe to re-run.

set -e

echo "==> Creating server/routes/attendance.js"
mkdir -p server/routes
cat > server/routes/attendance.js << 'ROUTE_EOF'
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

// POST /api/attendance/scan -- called by the kiosk on every card scan
router.post('/api/attendance/scan', async (req, res) => {
  const { token } = req.body;
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
      const { error: insertErr } = await supabase
        .from('attendance_logs')
        .insert({ [refColumn]: person.id, log_date: today, check_in_time: now });
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
      const { error: updateErr } = await supabase
        .from('attendance_logs')
        .update({ check_out_time: now })
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
        id, log_date, check_in_time, check_out_time,
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
        check_out_time: row.check_out_time
      };
    });

    return res.json({ date, logs });
  } catch (err) {
    console.error('[ATTENDANCE-LOGS-ERROR]', err);
    return res.status(500).json({ error: 'Could not load attendance logs.' });
  }
});

module.exports = router;
ROUTE_EOF

echo "==> Creating portal/attendance-kiosk.html"
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

<script>
(function(){
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

    try {
      const res = await fetch('/api/attendance/scan', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token })
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

echo "==> Creating portal/attendance-report.html"
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

          return '<div class="att-row">' +
            '<div>' + log.full_name + '</div>' +
            '<div>' + typeBadge + '</div>' +
            '<div>' + (log.department || '—') + '</div>' +
            '<div class="att-time' + (checkIn ? '' : ' missing') + '">' + (checkIn || 'Not checked in') + '</div>' +
            '<div class="att-time' + (checkOut ? '' : ' missing') + '">' + (checkOut || '—') + '</div>' +
            '</div>';
        }).join('');
      } catch (err) {
        rows.innerHTML = '<div class="att-empty">' + err.message + '</div>';
      }
    }

    init();
  </script>
</body>
</html>
REPORT_EOF

echo "==> Saving the SQL migration to server/migrations/ for reference (NOT auto-run)"
mkdir -p server/migrations
cat > server/migrations/add_attendance_logs.sql << 'SQL_EOF'
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
SQL_EOF

echo "==> Wiring the route into server/server.js"
if grep -q "require('./routes/attendance')" server/server.js; then
  echo "    Already wired in -- skipping (safe to re-run)."
else
  if ! grep -qF "app.use('/api/accounting', requireAuth);" server/server.js; then
    echo "    ERROR: could not find the expected anchor line in server/server.js."
    echo "    Nothing was changed."
    exit 1
  fi

  cat > .tmp-patch-attendance.js << 'NODE_EOF'
const fs = require('fs');
const filePath = 'server/server.js';
let content = fs.readFileSync(filePath, 'utf8');

const anchor = "app.use('/api/accounting', requireAuth);";
const insertion =
  "// --- MACDEN Attendance (auth required, checked inside the route file) ---\n" +
  "const attendanceRoutes = require('./routes/attendance');\n" +
  "app.use(attendanceRoutes);\n" +
  "// --- end attendance block ---\n\n";

content = content.replace(anchor, insertion + anchor);
fs.writeFileSync(filePath, content);
console.log('    Inserted require + mount before the requireAuth line.');
NODE_EOF

  node .tmp-patch-attendance.js
  rm .tmp-patch-attendance.js
fi

echo ""
echo "=================================================================="
echo "Files created and route wired. Remaining manual steps:"
echo ""
echo "1. Run server/migrations/add_attendance_logs.sql in the Supabase"
echo "   SQL editor (macden-accounting project)."
echo ""
echo "2. Set up a device at your entrance:"
echo "   - Open macden.com.ng/portal/attendance-kiosk.html on it"
echo "   - Log in once and leave the browser logged in on that device"
echo "     (create a dedicated account for this, or use an admin one)"
echo "   - Plug in a USB QR code scanner -- no special software needed,"
echo "     it types like a keyboard"
echo ""
echo "3. View attendance anytime at:"
echo "   macden.com.ng/portal/attendance-report.html"
echo ""
echo "Then push with your usual save-progress.sh."
echo "=================================================================="
