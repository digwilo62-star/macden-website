#!/bin/bash
# fix-dashboard-announcements-display-v1.sh
#
# Fills in the Dashboard's Announcements card for real -- fetches and
# displays all currently-active announcements (multiple can show at once),
# replacing the "not built yet" placeholder.

set -e

if grep -q "announcementsContainer" portal/dashboard.html; then
  echo "==> Already applied -- skipping (safe to re-run)."
  exit 0
fi

cat > .tmp-patch-dash.js << 'NODE_EOF'
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

// 1. Replace the static placeholder with a container JS will fill
const oldPlaceholder = `<div class="empty-note">Company-wide broadcasts aren't built yet — this fills in once the Broadcasts feature is live.</div>`;
const newPlaceholder = `<div id="announcementsContainer"><div class="empty-note">Loading announcements…</div></div>`;

if (!content.includes(oldPlaceholder)) {
  console.error('ERROR: could not find the Announcements placeholder in dashboard.html.');
  process.exit(1);
}
content = content.replace(oldPlaceholder, newPlaceholder);

// 2. Add the fetch + render, right after the existing unread-count block
const anchor = `      } catch (err) {
        document.getElementById('statUnread').textContent = '0';
      }`;

const newBlock = anchor + `

      try {
        const result = await apiRequest('/messages/announcements/active');
        const container = document.getElementById('announcementsContainer');
        const items = result.announcements || [];

        if (items.length === 0) {
          container.innerHTML = '<div class="empty-note">No announcements right now.</div>';
        } else {
          container.innerHTML = items.map(a => {
            const posted = new Date(a.sentAt);
            const postedStr = posted.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) +
              ' — ' + posted.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
            const snippet = (a.body || '').length > 140 ? a.body.slice(0, 140) + '…' : (a.body || '');
            return '<a href="inbox.html?id=' + a.conversationId + '" style="text-decoration:none; display:block; ' +
              'border-left:4px solid var(--primary); background:var(--primary-dim); border-radius:8px; ' +
              'padding:12px 14px; margin-bottom:10px;">' +
              '<div style="font-weight:700; font-size:13.5px; color:var(--text-primary); margin-bottom:3px;">' + a.subject + '</div>' +
              '<div style="font-size:12.5px; color:var(--text-secondary); margin-bottom:6px; line-height:1.4;">' + snippet + '</div>' +
              '<div style="font-size:10.5px; color:var(--text-muted);">Posted ' + postedStr + '</div>' +
              '</a>';
          }).join('');
        }
      } catch (err) {
        document.getElementById('announcementsContainer').innerHTML =
          '<div class="empty-note">Could not load announcements.</div>';
      }`;

if (!content.includes(anchor)) {
  console.error('ERROR: could not find the unread-count catch block in dashboard.html.');
  process.exit(1);
}
content = content.replace(anchor, newBlock);

writeRestoringLineEndings(filePath, content, usesCRLF);
console.log('    Patched portal/dashboard.html (Announcements card now shows real data).');
NODE_EOF

node .tmp-patch-dash.js
rm .tmp-patch-dash.js

echo ""
echo "Done. Push with your usual save-progress.sh."
