#!/bin/bash
# fix-attendance-logout-viewport-v1.sh
#
# Two fixes to both attendance pages:
#   1. Added the missing Help/Logout block to the sidebar (was never
#      there at all on these two pages)
#   2. Removed an inconsistent mobile viewport tag that was causing a
#      broken, squeezed layout on phones -- your app intentionally has
#      no mobile-specific CSS, so every other page renders as a shrunk
#      desktop layout on mobile; these two pages now match that same
#      (consistent, if unpolished) behavior instead of trying to
#      actually fit a phone screen with desktop-only CSS underneath.
#
# Full, safe overwrite of both files -- fully known/controlled.

set -e

echo "==> Overwriting portal/my-attendance.html"
mkdir -p portal
cat > portal/my-attendance.html << 'MYATT_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>My Attendance — MACDEN Portal</title>
<link rel="stylesheet" href="assets/portal-style.css">
<link rel="stylesheet" href="assets/portal-shell.css">
<style>
  .my-att-list{ background:var(--surface); border:1px solid var(--border); border-radius:var(--radius-md); overflow:hidden; }
  .my-att-header-row{ display:grid; grid-template-columns: minmax(120px,1fr) minmax(90px,120px) minmax(90px,120px) minmax(70px,90px); gap:12px; padding:12px 18px; font-size:10.5px; font-weight:700; text-transform:uppercase; letter-spacing:0.04em; color:var(--text-muted); border-bottom:1px solid var(--border); }
  .my-att-row{ display:grid; grid-template-columns: minmax(120px,1fr) minmax(90px,120px) minmax(90px,120px) minmax(70px,90px); gap:12px; align-items:center; padding:12px 18px; border-bottom:1px solid var(--border); font-size:12.5px; }
  .my-att-row:last-child{ border-bottom:none; }
  .my-att-empty{ padding:50px 18px; text-align:center; color:var(--text-muted); font-size:13px; }
  .my-att-date .day{ font-weight:600; color:var(--text-primary); }
  .my-att-date .sub{ font-size:11px; color:var(--text-muted); }
  .my-att-time{ font-weight:600; }
  .my-att-time.missing{ color:var(--text-muted); font-weight:400; }
  .my-att-status{ display:inline-block; padding:2px 9px; border-radius:999px; font-size:10.5px; font-weight:700; }
  .my-att-status.present{ background:var(--primary-dim); color:var(--primary); }
  .my-att-status.partial{ background:#f5e6c8; color:#8a6d00; }
</style>
</head>
<body>
  <div class="app-shell">
    <div class="sidebar">
      <div class="sidebar-brand"><img src="assets/logo.jpeg" alt="MACDEN"><span>MACDEN</span></div>
      <nav class="sidebar-nav">
        <a href="dashboard.html" class="sidebar-link"><i class="ti ti-layout-dashboard"></i> Dashboard</a>
        <a href="inbox.html" class="sidebar-link"><i class="ti ti-mail"></i> Inbox</a>
        <a href="my-attendance.html" class="sidebar-link active"><i class="ti ti-clock"></i> Attendance</a>
        <a href="directory.html" class="sidebar-link"><i class="ti ti-users"></i> Directory</a>
        <a href="settings.html" class="sidebar-link"><i class="ti ti-settings"></i> Settings</a>
      </nav>
      <div class="sidebar-logout">
        <a href="help.html" class="sidebar-link" style="margin-bottom:6px;"><i class="ti ti-help-circle"></i> Help</a>
        <button id="logoutBtn"><i class="ti ti-logout"></i> Logout</button>
      </div>
    </div>

    <div class="main-content">
      <div class="page-body">
        <h1 class="page-greeting" style="font-size:22px;">My Attendance History</h1>
        <p class="page-greeting-sub" style="margin:0 0 18px;">Your recent check-in and check-out records.</p>

        <div class="my-att-list">
          <div class="my-att-header-row"><div>Date</div><div>Check In</div><div>Check Out</div><div>Status</div></div>
          <div id="myAttRows"><div class="my-att-empty">Loading…</div></div>
        </div>
      </div>
    </div>
  </div>

  <script src="assets/api.js"></script>
  <script>
    function formatTime(iso){
      if (!iso) return null;
      return new Date(iso).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    }

    function formatDate(dateStr){
      const d = new Date(dateStr + 'T00:00:00');
      const today = new Date();
      const yesterday = new Date();
      yesterday.setDate(today.getDate() - 1);

      const isToday = d.toDateString() === today.toDateString();
      const isYesterday = d.toDateString() === yesterday.toDateString();

      const dayLabel = d.toLocaleDateString([], { weekday: 'short', month: 'short', day: 'numeric', year: 'numeric' });
      const subLabel = isToday ? 'Today' : isYesterday ? 'Yesterday' : '';
      return { dayLabel, subLabel };
    }

    async function init() {
      try {
        await apiRequest('/dashboard-check');
      } catch (err) {
        window.location.href = 'login.html';
        return;
      }
      loadHistory();
    }

    async function loadHistory() {
      const rows = document.getElementById('myAttRows');
      try {
        const res = await fetch('/api/attendance/my-history?limit=30', { credentials: 'include' });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Could not load your attendance history.');

        if (!data.history.length) {
          rows.innerHTML = '<div class="my-att-empty">No attendance recorded yet. Scan your ID card at the entrance kiosk to get started.</div>';
          return;
        }

        rows.innerHTML = data.history.map(row => {
          const { dayLabel, subLabel } = formatDate(row.log_date);
          const checkIn = formatTime(row.check_in_time);
          const checkOut = formatTime(row.check_out_time);

          let statusHtml;
          if (checkIn && checkOut) {
            statusHtml = '<span class="my-att-status present">Present</span>';
          } else if (checkIn) {
            statusHtml = '<span class="my-att-status partial">In progress</span>';
          } else {
            statusHtml = '';
          }

          return '<div class="my-att-row">' +
            '<div class="my-att-date"><div class="day">' + dayLabel + '</div>' + (subLabel ? '<div class="sub">' + subLabel + '</div>' : '') + '</div>' +
            '<div class="my-att-time' + (checkIn ? '' : ' missing') + '">' + (checkIn || 'Not checked in') + '</div>' +
            '<div class="my-att-time' + (checkOut ? '' : ' missing') + '">' + (checkOut || '—') + '</div>' +
            '<div>' + statusHtml + '</div>' +
            '</div>';
        }).join('');
      } catch (err) {
        rows.innerHTML = '<div class="my-att-empty">' + err.message + '</div>';
      }
    }

    document.getElementById('logoutBtn').addEventListener('click', async () => {
      await apiRequest('/auth/logout', { method: 'POST' });
      window.location.href = 'login.html';
    });

    init();
  </script>
</body>
</html>
MYATT_EOF

echo "==> Overwriting portal/attendance-report.html"
cat > portal/attendance-report.html << 'REPORT_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
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
  .att-photo-wrap{ position:relative; display:inline-flex; flex-shrink:0; }
  .att-photo-badge{ position:absolute; bottom:-2px; right:-2px; width:12px; height:12px; border-radius:50%; background:var(--primary); border:1.5px solid var(--surface); display:flex; align-items:center; justify-content:center; }
  .att-photo-badge svg{ width:7px; height:7px; }
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
      <div class="sidebar-logout">
        <a href="help.html" class="sidebar-link" style="margin-bottom:6px;"><i class="ti ti-help-circle"></i> Help</a>
        <button id="logoutBtn"><i class="ti ti-logout"></i> Logout</button>
      </div>
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

          const cameraBadge = '<span class="att-photo-badge"><svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.5"><path d="M3 8h4l2-3h6l2 3h4v12H3z"/><circle cx="12" cy="14" r="3"/></svg></span>';
          const checkInThumb = log.check_in_photo_url
            ? '<span class="att-photo-wrap"><img class="att-photo-thumb" src="' + log.check_in_photo_url + '" onclick="showAttPhoto(\'' + log.check_in_photo_url + '\')">' + cameraBadge + '</span>'
            : '';
          const checkOutThumb = log.check_out_photo_url
            ? '<span class="att-photo-wrap"><img class="att-photo-thumb" src="' + log.check_out_photo_url + '" onclick="showAttPhoto(\'' + log.check_out_photo_url + '\')">' + cameraBadge + '</span>'
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

    document.getElementById('logoutBtn').addEventListener('click', async () => {
      await apiRequest('/auth/logout', { method: 'POST' });
      window.location.href = 'login.html';
    });

    init();
  </script>
</body>
</html>
REPORT_EOF

echo ""
echo "Done. Push with your usual save-progress.sh."
