#!/bin/bash
# fix-remove-from-dashboard-v3.sh
#
# Real fix this time: the "Remove from Dashboard" click was being
# intercepted by the row's OWN click listener (which navigates to
# Inbox) before my delegated listener at the list-container level ever
# got a chance to run -- in event bubbling, a listener on the row itself
# fires before one on an ancestor container, so stopPropagation() called
# at the container level was always too late.
#
# Fixed by attaching the listener directly to each button, exactly
# matching the working pattern the existing "Who's read this?" button
# already uses -- verified this time with an actual simulated click,
# not just checking the code exists.

set -e

if grep -q "list.querySelectorAll('.unfeature-btn')" portal/broadcasts.html; then
  echo "==> Already applied -- skipping (safe to re-run)."
  exit 0
fi

cat > .tmp-patch-v3.js << 'NODE_EOF'
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

// Remove the old, incorrectly-placed delegated listener entirely
const oldDelegated = `    document.getElementById('bcList').addEventListener('click', async (e) => {
      const btn = e.target.closest('.unfeature-btn');
      if (!btn) return;
      e.stopPropagation();
      const ok = await confirmModal(
`;

if (!content.includes(oldDelegated)) {
  console.error('ERROR: could not find the old delegated listener start in broadcasts.html.');
  process.exit(1);
}

// Find the full old block (from the marker above through its closing });)
const startIdx = content.indexOf(oldDelegated);
const endMarker = '    });';
const endIdx = content.indexOf(endMarker, startIdx) + endMarker.length;
const fullOldBlock = content.slice(startIdx, endIdx);

content = content.slice(0, startIdx) + content.slice(endIdx);

// Add the correct per-button listener, right after the existing
// who-read-btn attachment loop (same place, same pattern, same timing)
const anchor = `        list.querySelectorAll('.who-read-btn').forEach(btn => {
          btn.addEventListener('click', (e) => {
            e.stopPropagation();
            viewReadStatus(btn.dataset.conversationId, btn.dataset.subject);
          });
        });`;

const newAttachment = anchor + `

        list.querySelectorAll('.unfeature-btn').forEach(btn => {
          btn.addEventListener('click', async (e) => {
            e.stopPropagation();
            const ok = await confirmModal(
              'The broadcast stays in the Inbox for every staff member regardless -- this only stops featuring it on the Dashboard.',
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
          });
        });`;

if (!content.includes(anchor)) {
  console.error('ERROR: could not find the who-read-btn attachment loop (after removing old block).');
  process.exit(1);
}
content = content.replace(anchor, newAttachment);

writeRestoringLineEndings(filePath, content, usesCRLF);
console.log('    Patched portal/broadcasts.html (button-level listener, correct bubble-order fix).');
NODE_EOF

node .tmp-patch-v3.js
rm .tmp-patch-v3.js

echo ""
echo "Done. Push with your usual save-progress.sh."
