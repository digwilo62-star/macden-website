// Removes the fake "Tasks Assigned (coming soon)" card, replaces the other
// two placeholders with ONE real, role-appropriate card. This version
// normalizes Windows line endings (CRLF -> LF) before searching, since
// that was very likely why the last two attempts failed to match even
// against seemingly-identical content.
//
//   node fix-dashboard-stats-v3.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'accounting', 'dashboard.html');
let content = fs.readFileSync(filePath, 'utf8');

// Normalize line endings first -- this is very likely the actual root
// cause of the last two failed attempts, not a real content difference.
const hadCRLF = content.includes('\r\n');
content = content.replace(/\r\n/g, '\n');

const oldStatGrid = `        <div class="stat-grid">
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

const newStatGrid = `        <div class="stat-grid" style="grid-template-columns: repeat(2, 1fr);">
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
  console.log('STILL not matching even after normalizing line endings.');
  console.log('Diagnostic -- character codes around "stat-grid" in your file:');
  const idx = content.indexOf('stat-grid');
  if (idx !== -1) {
    const snippet = content.slice(Math.max(0, idx - 20), idx + 400);
    console.log(JSON.stringify(snippet));
  } else {
    console.log('"stat-grid" not found in the file at all.');
  }
  process.exit(1);
}

const startMarker = 'async function init() {';
const endMarker = "document.getElementById('logoutBtn').addEventListener";
const startIdx = content.indexOf(startMarker);
const endIdx = content.indexOf(endMarker);

if (startIdx !== -1 && endIdx !== -1) {
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
  console.log('Rewrote init() to fetch real role-appropriate stats.');
} else {
  console.log('WARNING: could not find init() markers.');
}

// Restore original line-ending style so the file stays consistent with the rest of your repo
if (hadCRLF) {
  content = content.replace(/\n/g, '\r\n');
}

fs.writeFileSync(filePath, content, 'utf8');
console.log('\ndashboard.html patched successfully.');

