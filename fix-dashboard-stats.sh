#!/usr/bin/env bash
# Removes the fake 'Tasks Assigned (coming soon)' card, replaces the
# other two placeholders with ONE real, role-appropriate card: staff see
# 'My Pending Leave Requests', admin sees 'Pending Approvals'.
set -e
cat > fix-dashboard-stats.js << 'EOF_FIXER_JS'
// Removes the fake "Tasks Assigned (coming soon)" card, and replaces the
// other two placeholder cards with ONE real, role-appropriate card:
// staff see "My Pending Leave Requests", admin sees "Pending Approvals".
// Edits accounting/dashboard.html in place.
//
//   node fix-dashboard-stats.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'accounting', 'dashboard.html');
let content = fs.readFileSync(filePath, 'utf8');

// ---- 1. Replace the 4-card stat grid with a 2-card version ----
const oldStatGrid = `<div class="stat-grid">
          <div class="stat-card">
            <div class="num" id="statUnread">—</div>
            <div class="lbl">Unread Messages</div>
          </div>
          <div class="stat-card">
            <div class="num">—</div>
            <div class="lbl">Pending Requests (coming soon)</div>
          </div>
          <div class="stat-card">
            <div class="num">—</div>
            <div class="lbl">Tasks Assigned(coming soon)</div>
          </div>
          <div class="stat-card">
            <div class="num">—</div>
            <div class="lbl">Approvals (coming soon)</div>
          </div>
        </div>`;

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

if (content.includes(oldStatGrid)) {
  content = content.replace(oldStatGrid, newStatGrid);
  changed = true;
  console.log('Replaced 4-card stat grid with 2 real cards.');
} else if (content.includes('id="statSecondary"')) {
  console.log('Stat grid already updated, skipping that part.');
} else {
  console.log('WARNING: exact stat-grid markup not found -- trying a looser match...');
  const gridStart = content.indexOf('<div class="stat-grid">');
  const gridEnd = content.indexOf('</div>\n      </div>\n    </div>\n  </div>\n\n  <script');
  if (gridStart !== -1) {
    console.log('Found <div class="stat-grid"> at least -- please paste back your current dashboard.html so this can be fixed precisely.');
  } else {
    console.log('Could not find the stat grid at all. Please paste back your current dashboard.html.');
  }
  process.exit(1);
}

// ---- 2. Rewrite init() to fetch role-appropriate secondary stat ----
const startMarker = 'async function init() {';
const endMarker = "document.getElementById('logoutBtn').addEventListener";

const startIdx = content.indexOf(startMarker);
const endIdx = content.indexOf(endMarker);

if (startIdx === -1 || endIdx === -1) {
  console.log('WARNING: could not find init() function markers -- the card labels will show but numbers will stay blank. Paste back your current dashboard.html for a precise fix.');
} else {
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

      // Second stat card shows something different depending on role --
      // real data either way, no more "coming soon" placeholders.
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
}

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\ndashboard.html patched successfully.');
}

EOF_FIXER_JS
echo "Running the fix..."
node fix-dashboard-stats.js
echo "Done. Restart your server and hard-refresh (Ctrl+F5)."