#!/bin/bash
# fix-remove-from-dashboard-v2.sh
#
# Fixes two real bugs in the "Remove from Dashboard" button:
#   1. Clicking it was navigating to Inbox -- the click was bubbling up
#      into the existing row-click-opens-broadcast handler. Fixed with
#      e.stopPropagation(), matching the same pattern the existing
#      "Who's read this?" button already correctly uses.
#   2. Replaced the native browser confirm() popup with the app's own
#      confirmModal() component -- same one already used elsewhere in
#      the portal, styled properly instead of the generic browser dialog.

set -e

if grep -q "confirmModal.*Remove from Dashboard" portal/broadcasts.html; then
  echo "==> Already applied -- skipping (safe to re-run)."
  exit 0
fi

cat > .tmp-patch-fixremove.js << 'NODE_EOF'
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

const filePath = 'portal/broadcasts.html';
let { normalized: content, usesCRLF } = readNormalized(filePath);

const oldHandler = `    document.getElementById('bcList').addEventListener('click', async (e) => {
      const btn = e.target.closest('.unfeature-btn');
      if (!btn) return;
      if (!confirm('Remove this from the Dashboard? The broadcast itself will stay in everyone\\'s Inbox -- this only stops featuring it on the Dashboard.')) return;
      btn.disabled = true;
      btn.textContent = 'Removing…';
      try {
        await apiRequest('/messages/broadcasts/' + btn.dataset.conversationId + '/unfeature-from-dashboard', { method: 'POST' });
        loadBroadcasts();
      } catch (err) {
        alert(err.message);
        btn.disabled = false;
        btn.textContent = 'Remove from Dashboard';
      }
    });`;

const newHandler = `    document.getElementById('bcList').addEventListener('click', async (e) => {
      const btn = e.target.closest('.unfeature-btn');
      if (!btn) return;
      e.stopPropagation();
      const ok = await confirmModal(
        'The broadcast itself will stay in everyone\\'s Inbox -- this only stops featuring it on the Dashboard.',
        { title: 'Remove from Dashboard?', confirmLabel: 'Remove', danger: true }
      );
      if (!ok) return;
      btn.disabled = true;
      btn.textContent = 'Removing…';
      try {
        await apiRequest('/messages/broadcasts/' + btn.dataset.conversationId + '/unfeature-from-dashboard', { method: 'POST' });
        loadBroadcasts();
      } catch (err) {
        alert(err.message);
        btn.disabled = false;
        btn.textContent = 'Remove from Dashboard';
      }
    });`;

if (!content.includes(oldHandler)) {
  console.error('ERROR: could not find the unfeature click handler in broadcasts.html.');
  process.exit(1);
}
content = content.replace(oldHandler, newHandler);

// Make sure confirm-modal.js is actually loaded on this page
if (!content.includes('assets/confirm-modal.js')) {
  const scriptAnchor = /<script src="assets\/api\.js"><\/script>/;
  if (scriptAnchor.test(content)) {
    content = content.replace(scriptAnchor, '<script src="assets/api.js"></script>\n  <script src="assets/confirm-modal.js"></script>');
  } else {
    console.error('WARNING: could not find where to add confirm-modal.js script tag -- add it manually if the modal does not appear.');
  }
}

writeRestoringLineEndings(filePath, content, usesCRLF);
console.log('    Patched portal/broadcasts.html (fixed navigation bug, using proper confirm modal).');
NODE_EOF

node .tmp-patch-fixremove.js
rm .tmp-patch-fixremove.js

echo ""
echo "Done. Push with your usual save-progress.sh."
