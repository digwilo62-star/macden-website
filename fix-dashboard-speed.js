// Dashboard currently makes 4 separate database calls ONE AFTER ANOTHER
// (dashboard-check, unread-count, leave stats, pending-staff) -- each one
// waits for the last to finish before starting. Running the 3 independent
// ones (unread-count, leave stats, pending-staff) at the SAME TIME instead
// cuts real, measurable load time -- total wait becomes the slowest single
// call, not the sum of all of them.
//
//   node fix-dashboard-speed.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'accounting', 'dashboard.html');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');

if (content.includes('// Run independently')) {
  console.log('Already parallelized, skipping.');
  process.exit(0);
}

// Wrap the 3 independent try/catch blocks (unread, leave stats,
// pending-staff) so they run at the same time instead of sequentially.
// Uses Promise.allSettled so one failing doesn't block the others --
// matches the existing behavior where each has its own try/catch already.
const startMarker = "      try {\n        const unread = await apiRequest('/messages/unread-count');";
const endMarker = "\n\n      loadPendingStaff();";

const startIdx = content.indexOf(startMarker);
const endIdx = content.indexOf(endMarker);

if (startIdx === -1 || endIdx === -1) {
  console.log('WARNING: could not find the expected markers. Nothing changed -- paste back dashboard.html again if this persists.');
  process.exit(1);
}

const oldSection = content.slice(startIdx, endIdx);

// Turn each existing try/catch block into its own async function, then run
// all of them together with Promise.allSettled -- same individual error
// handling as before, just no longer blocking each other.
const newSection = `      // Run independently and at the same time, instead of one after
      // another -- this was the main reason dashboard loads felt slow.
      const unreadTask = (async () => {
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
      })();

      const secondaryStatTask = (async () => {
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
      })();

      const pendingStaffTask = loadPendingStaff();

      await Promise.allSettled([unreadTask, secondaryStatTask, pendingStaffTask]);`;

content = content.slice(0, startIdx) + newSection + content.slice(endIdx + '\n\n      loadPendingStaff();'.length);

fs.writeFileSync(filePath, content, 'utf8');
console.log('Dashboard now loads its 3 independent stats in parallel instead of one after another.');

