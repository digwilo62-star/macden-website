#!/bin/bash
# fix-dashboard-parallel-load-v1.sh
#
# Speed fix: the Dashboard's data (unread count, announcements, leave
# stats, pending staff approvals) was loading in sequence -- each call
# waiting for the previous one to finish, even though none of them
# actually depend on each other. Now they all fire at the same time.
# Total load time drops from "sum of every call" to roughly "the single
# slowest call" -- the more calls there are, the bigger the improvement.
#
# Uses Promise.allSettled (not Promise.all) so each piece still fails
# independently exactly like before -- one slow/broken call can't stop
# the others from rendering.

set -e

if grep -q "Promise.allSettled" portal/dashboard.html; then
  echo "==> Already applied -- skipping (safe to re-run)."
  exit 0
fi

cat > .tmp-patch-parallel.js << 'NODE_EOF'
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

const oldBlock = `      try {
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
        const result = await apiRequest('/messages/announcements/active');
        renderAnnouncements(result.announcements || []);
      } catch (err) {
        document.getElementById('announcementsContainer').innerHTML =
          '<div class="empty-note">Could not load announcements.</div>';
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
      loadPendingStaff();
    }`;

const newBlock = `      // These four don't depend on each other's results, so run them all
      // at once instead of one after another -- cuts load time from the
      // sum of every call down to roughly the slowest single one.
      await Promise.allSettled([
        (async () => {
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
        })(),
        (async () => {
          try {
            const result = await apiRequest('/messages/announcements/active');
            renderAnnouncements(result.announcements || []);
          } catch (err) {
            document.getElementById('announcementsContainer').innerHTML =
              '<div class="empty-note">Could not load announcements.</div>';
          }
        })(),
        (async () => {
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
        })(),
        loadPendingStaff()
      ]);
    }`;

if (!content.includes(oldBlock)) {
  console.error('ERROR: could not find the sequential dashboard-load block in dashboard.html.');
  process.exit(1);
}
content = content.replace(oldBlock, newBlock);

writeRestoringLineEndings(filePath, content, usesCRLF);
console.log('    Patched portal/dashboard.html (parallel loading instead of sequential).');
NODE_EOF

node .tmp-patch-parallel.js
rm .tmp-patch-parallel.js

echo ""
echo "Done. Push with your usual save-progress.sh."
