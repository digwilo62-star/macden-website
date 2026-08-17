#!/bin/bash
# fix-dashboard-attendance-card-v1.sh
#
# Adds an "Attendance Today" card to the Dashboard, right alongside
# Announcements and Quick Actions. Shows different content depending on
# who's logged in: admins see "X of Y staff checked in today" with a
# link to the full report; regular staff see their own status ("You
# checked in today at 8:03 AM") with a link to their personal history.

set -e

if grep -q "attendanceCardPanel" portal/dashboard.html; then
  echo "==> Already applied -- skipping (safe to re-run)."
  exit 0
fi

cat > .tmp-patch-attcard.js << 'NODE_EOF'
const fs = require('fs');

function readNormalized(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  const usesCRLF = raw.includes('\r\n');
  return { normalized: raw.replace(/\r\n/g, '\n'), usesCRLF };
}
function writeRestoringLineEndings(filePath, normalizedContent, usesCRLF) {
  const out = usesCRLF ? normalizedContent.replace(/\n/g, '\r\n') : normalizedContent;
  fs.writeFileSync(filePath, out);
}

const filePath = 'portal/dashboard.html';
let { normalized: content, usesCRLF } = readNormalized(filePath);

// 1. Add the card HTML, right after the Quick Actions panel
const anchor = `          <div class="panel">
            <div class="panel-header"><h2>Quick Actions</h2></div>
            <a href="inbox.html" class="quick-action"><i class="ti ti-mail"></i> Open Inbox</a>
            <a href="leave.html" class="quick-action"><i class="ti ti-calendar-event"></i> Request Leave</a>
            <a href="directory.html" class="quick-action"><i class="ti ti-users"></i> Staff Directory</a>
          </div>
        </div>`;

const newBlock = `          <div class="panel">
            <div class="panel-header"><h2>Quick Actions</h2></div>
            <a href="inbox.html" class="quick-action"><i class="ti ti-mail"></i> Open Inbox</a>
            <a href="leave.html" class="quick-action"><i class="ti ti-calendar-event"></i> Request Leave</a>
            <a href="directory.html" class="quick-action"><i class="ti ti-users"></i> Staff Directory</a>
          </div>
          <div class="panel" id="attendanceCardPanel">
            <div class="panel-header"><h2>Attendance Today</h2></div>
            <div id="attendanceCardBody" style="padding:8px 0;">
              <div class="empty-note">Loading…</div>
            </div>
          </div>
        </div>`;

if (!content.includes(anchor)) {
  console.error('ERROR: could not find the Quick Actions panel in dashboard.html.');
  process.exit(1);
}
content = content.replace(anchor, newBlock);

// 2. Add the load-and-render logic, inside the Promise.allSettled block
// alongside the other independent dashboard widgets
const jsAnchor = `        (async () => {
          try {
            const result = await apiRequest('/messages/announcements/active');
            renderAnnouncements(result.announcements || []);
          } catch (err) {
            document.getElementById('announcementsContainer').innerHTML =
              '<div class="empty-note">Could not load announcements.</div>';
          }
        })(),`;

const jsNewBlock = jsAnchor + `
        (async () => {
          const body = document.getElementById('attendanceCardBody');
          try {
            if (staff.role === 'admin') {
              const res = await fetch('/api/attendance/summary-today', { credentials: 'include' });
              const data = await res.json();
              if (!res.ok) throw new Error(data.error || 'Could not load.');
              body.innerHTML =
                '<div style="font-family:\\'Manrope\\',sans-serif; font-weight:800; font-size:28px; color:var(--primary); margin-bottom:2px;">' +
                  data.checkedInCount + ' <span style="font-size:16px; font-weight:600; color:var(--text-secondary);">of ' + data.totalActiveStaff + '</span>' +
                '</div>' +
                '<div style="font-size:12.5px; color:var(--text-secondary); margin-bottom:12px;">staff checked in today</div>' +
                '<a href="attendance-report.html" style="font-size:12.5px; font-weight:600; color:var(--primary); text-decoration:none;">View full report &rarr;</a>';
            } else {
              const res = await fetch('/api/attendance/my-today', { credentials: 'include' });
              const data = await res.json();
              if (!res.ok) throw new Error(data.error || 'Could not load.');
              if (data.checkedIn) {
                const time = new Date(data.checkInTime).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
                body.innerHTML =
                  '<div style="display:flex; align-items:center; gap:10px; margin-bottom:12px;">' +
                    '<span style="width:32px; height:32px; border-radius:50%; background:var(--primary); display:flex; align-items:center; justify-content:center; flex-shrink:0;"><i class="ti ti-check" style="color:#fff; font-size:18px;"></i></span>' +
                    '<div><div style="font-size:13px; color:var(--text-primary);">You checked in today</div><div style="font-weight:700; color:var(--primary);">at ' + time + '</div></div>' +
                  '</div>' +
                  '<a href="my-attendance.html" style="font-size:12.5px; font-weight:600; color:var(--primary); text-decoration:none;">View my attendance history &rarr;</a>';
              } else {
                body.innerHTML =
                  '<div style="font-size:13px; color:var(--text-secondary); margin-bottom:12px;">You have not checked in yet today.</div>' +
                  '<a href="my-attendance.html" style="font-size:12.5px; font-weight:600; color:var(--primary); text-decoration:none;">View my attendance history &rarr;</a>';
              }
            }
          } catch (err) {
            body.innerHTML = '<div class="empty-note">Could not load attendance.</div>';
          }
        })(),`;

if (!content.includes(jsAnchor)) {
  console.error('ERROR: could not find the announcements Promise.allSettled block in dashboard.html.');
  process.exit(1);
}
content = content.replace(jsAnchor, jsNewBlock);

writeRestoringLineEndings(filePath, content, usesCRLF);
console.log('    Patched portal/dashboard.html (Attendance Today card added).');
NODE_EOF

node .tmp-patch-attcard.js
rm .tmp-patch-attcard.js

echo ""
echo "Done. Push with your usual save-progress.sh."
