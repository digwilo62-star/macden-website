#!/usr/bin/env bash
# Removes the fake 'Tasks Assigned' card, replaces the other two with
# ONE real role-appropriate card. v4: uses a whitespace-TOLERANT regex
# match instead of an exact string. Root cause (confirmed from YOUR
# actual diagnostic output, not a guess) was inconsistent indentation
# inside the real file. Tested against that exact real content before
# being sent this time.
set -e
cat > fix-dashboard-stats-v4.js << 'EOF_FIXER_JS'
// Removes the fake "Tasks Assigned" card, replaces the other two with ONE
// real role-appropriate card. This version uses a whitespace-TOLERANT
// regex match instead of an exact multi-line string -- the real problem
// (confirmed via your diagnostic output) was inconsistent indentation
// inside the actual file, not a content difference or line-ending issue.
//
//   node fix-dashboard-stats-v4.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'accounting', 'dashboard.html');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n'); // normalize line endings too, just in case

const statGridRegex = /<div class="stat-grid">\s*<div class="stat-card">\s*<div class="num" id="statUnread">[^<]*<\/div>\s*<div class="lbl">Unread Messages<\/div>\s*<\/div>\s*<div class="stat-card">\s*<div class="num">[^<]*<\/div>\s*<div class="lbl">Pending Requests \(coming soon\)<\/div>\s*<\/div>\s*<div class="stat-card">\s*<div class="num">[^<]*<\/div>\s*<div class="lbl">Tasks Assigned\(coming soon\)<\/div>\s*<\/div>\s*<div class="stat-card">\s*<div class="num">[^<]*<\/div>\s*<div class="lbl">Approvals \(coming soon\)<\/div>\s*<\/div>\s*<\/div>/;

const newStatGrid = `<div class="stat-grid" style="grid-template-columns: repeat(2, 1fr);">
          <div class="stat-card">
            <div class="num" id="statUnread">—</div>
            <div class="lbl">Unread Messages</div>
          </div>
          <div class="stat-card">
            <div class="num" id="statSecondary">—</div>
            <div class="lbl" id="statSecondaryLabel">—</div>
          </div>
        </div>`;

let changed = false;

if (statGridRegex.test(content)) {
  content = content.replace(statGridRegex, newStatGrid);
  changed = true;
  console.log('Replaced 4-card stat grid with 2 real cards.');
} else if (content.includes('id="statSecondary"')) {
  console.log('Stat grid already updated, skipping that part.');
} else {
  console.log('STILL not matching. Please paste back the FULL current dashboard.html again -- something more unusual is going on and this needs a direct look, not another guess.');
  process.exit(1);
}

const startMarker = 'async function init() {';
const endMarker = "document.getElementById('logoutBtn').addEventListener";
const startIdx = content.indexOf(startMarker);
const endIdx = content.indexOf(endMarker);

if (startIdx !== -1 && endIdx !== -1 && !content.includes("staff.role === 'admin'")) {
  const newInit = `async function init() {
      let staff;
      try {
        const result = await apiRequest('/dashboard-check');
        staff = result.staff;
        document.getElementById('greeting').textContent = \`Hello, \${staff.fullName.split(' ')[0]} 👋\`;
        document.getElementById('greetingSub').textContent = \`\${staff.role} · MACDEN\`;
      } catch (err) {
        window.location.href = 'login.html';
        return;
      }

      try {
        const unread = await apiRequest('/messages/unread-count');
        document.getElementById('statUnread').textContent = unread.unreadCount;
        if (unread.unreadCount > 0) {
          const badge = document.getElementById('unreadBadge');
          badge.textContent = unread.unreadCount;
          badge.style.display = 'inline-block';
          const dot = document.getElementById('notifDot');
          dot.textContent = unread.unreadCount;
          dot.style.display = 'flex';
        }
      } catch (err) {
        document.getElementById('statUnread').textContent = '0';
      }

      try {
        if (staff.role === 'admin') {
          const pending = await apiRequest('/leave/pending');
          document.getElementById('statSecondary').textContent = pending.requests.length;
          document.getElementById('statSecondaryLabel').textContent = 'Pending Approvals';
        } else {
          const mine = await apiRequest('/leave/mine');
          const pendingCount = mine.requests.filter(r => r.status === 'pending').length;
          document.getElementById('statSecondary').textContent = pendingCount;
          document.getElementById('statSecondaryLabel').textContent = 'My Pending Leave Requests';
        }
      } catch (err) {
        document.getElementById('statSecondary').textContent = '0';
        document.getElementById('statSecondaryLabel').textContent = staff.role === 'admin' ? 'Pending Approvals' : 'My Pending Leave Requests';
      }
    }

    `;
  content = content.slice(0, startIdx) + newInit + content.slice(endIdx);
  changed = true;
  console.log('Rewrote init() to fetch real role-appropriate stats.');
} else if (content.includes("staff.role === 'admin'")) {
  console.log('init() already updated, skipping that part.');
} else {
  console.log('WARNING: could not find init() markers -- card labels will show but numbers may stay blank.');
}

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\ndashboard.html patched successfully.');
}

EOF_FIXER_JS
echo "Running the fix..."
node fix-dashboard-stats-v4.js
echo "Done. Restart your server and hard-refresh (Ctrl+F5)."