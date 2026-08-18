#!/bin/bash
# fix-dashboard-announcements-v2-v1.sh
#
# Points the Dashboard's Announcements card at the new, standalone
# system instead of the old broadcast-through-messages one, and changes
# clicking an item to open the popup card instead of navigating into
# Inbox. Requires fix-announcements-backend-v1.sh (or the corrected
# version) to already be applied.

set -e

if grep -q "showAnnouncementCard" portal/dashboard.html; then
  echo "==> Already applied -- skipping (safe to re-run)."
  exit 0
fi

cat > .tmp-patch-dashv2.js << 'NODE_EOF'
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

// 1. Point both fetch calls at the new endpoint
const oldFetch1 = `const result = await apiRequest('/messages/announcements/active');`;
const newFetch1 = `const result = await apiRequest('/announcements/active');`;
if (!content.includes(oldFetch1)) {
  console.error('ERROR: could not find the main announcements fetch call.');
  process.exit(1);
}
content = content.replace(oldFetch1, newFetch1);

const oldFetch2 = `apiRequest('/messages/announcements/active')`;
const newFetch2 = `apiRequest('/announcements/active')`;
if (!content.includes(oldFetch2)) {
  console.error('ERROR: could not find the live-update announcements fetch call.');
  process.exit(1);
}
content = content.replace(oldFetch2, newFetch2);

// 2. Replace the card HTML -- clickable div instead of a link into Inbox
const oldCardFn = `    function announcementCardHtml(a){
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
    }`;

const newCardFn = `    function announcementCardHtml(a){
      const posted = new Date(a.sentAt);
      const postedStr = posted.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) +
        ' — ' + posted.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
      const snippet = (a.body || '').length > 140 ? a.body.slice(0, 140) + '…' : (a.body || '');
      return '<div class="ann-dash-card" data-id="' + a.id + '" style="cursor:pointer; ' +
        'border-left:4px solid var(--primary); background:var(--primary-dim); border-radius:8px; ' +
        'padding:12px 14px; margin-bottom:10px;">' +
        '<div style="font-weight:700; font-size:13.5px; color:var(--text-primary); margin-bottom:3px;">' + a.subject + '</div>' +
        '<div style="font-size:12.5px; color:var(--text-secondary); margin-bottom:6px; line-height:1.4;">' + snippet + '</div>' +
        '<div style="font-size:10.5px; color:var(--text-muted);">Posted ' + postedStr + '</div>' +
        '</div>';
    }`;

if (!content.includes(oldCardFn)) {
  console.error('ERROR: could not find announcementCardHtml() in dashboard.html.');
  process.exit(1);
}
content = content.replace(oldCardFn, newCardFn);

// 3. Attach click listeners after rendering, instead of relying on <a> navigation
const oldRenderEnd = `      container.innerHTML = html;
      const toggleBtn = document.getElementById('announcementsToggle');`;

const newRenderEnd = `      container.innerHTML = html;
      container.querySelectorAll('.ann-dash-card').forEach(el => {
        el.addEventListener('click', () => showAnnouncementCard(el.dataset.id));
      });
      const toggleBtn = document.getElementById('announcementsToggle');`;

if (!content.includes(oldRenderEnd)) {
  console.error('ERROR: could not find the renderAnnouncements container.innerHTML line.');
  process.exit(1);
}
content = content.replace(oldRenderEnd, newRenderEnd);

// 4. Include the popup card script
const scriptAnchor = /<script src="assets\/api\.js"><\/script>/;
if (scriptAnchor.test(content) && !content.includes('announcement-card.js')) {
  content = content.replace(scriptAnchor, '<script src="assets/api.js"></script>\n  <script src="assets/announcement-card.js"></script>');
}

writeRestoringLineEndings(filePath, content, usesCRLF);
console.log('    Patched portal/dashboard.html (points to new Announcements system, opens popup card).');
NODE_EOF

node .tmp-patch-dashv2.js
rm .tmp-patch-dashv2.js

echo ""
echo "Done. Push with your usual save-progress.sh."
