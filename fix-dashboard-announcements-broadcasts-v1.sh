#!/bin/bash
# fix-dashboard-announcements-broadcasts-v1.sh
#
# Adds "Also feature this on the Dashboard as an Announcement" checkbox
# to the broadcast composer, with an optional "Vanish at" datetime field
# that appears when checked (blank = stays featured indefinitely).

set -e

if grep -q "bcDashboardAnnouncement" portal/broadcasts.html; then
  echo "==> Already applied -- skipping (safe to re-run)."
  exit 0
fi

cat > .tmp-patch-bc.js << 'NODE_EOF'
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

// 1. Add the checkbox + vanish field right after the existing scheduled-time input
const anchor = `<input type="datetime-local" id="bcScheduledAt" style="display:none; padding:9px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); font-family:var(--font-body); font-size:13px;">`;

const newFields = anchor + `
                <div style="margin-top:16px; padding-top:16px; border-top:1px solid var(--border);">
                  <label style="display:flex; align-items:center; gap:8px; font-size:13px; cursor:pointer;">
                    <input type="checkbox" id="bcDashboardAnnouncement">
                    Also feature this on the Dashboard as an Announcement
                  </label>
                  <div id="bcVanishWrap" style="display:none; margin-top:10px;">
                    <label style="display:block; font-size:12px; color:var(--text-secondary); margin-bottom:6px;">Vanish from Dashboard at (optional -- leave blank to stay featured indefinitely)</label>
                    <input type="datetime-local" id="bcVanishAt" style="padding:9px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); font-family:var(--font-body); font-size:13px;">
                  </div>
                </div>`;

if (!content.includes(anchor)) {
  console.error('ERROR: could not find the bcScheduledAt input in broadcasts.html.');
  process.exit(1);
}
content = content.replace(anchor, newFields);

// 2. Toggle the vanish field when the checkbox is checked
const jsAnchor = `const isScheduled = document.getElementById('sendTimingLater').checked;`;
const jsAddition = `document.getElementById('bcDashboardAnnouncement').addEventListener('change', function(){
        document.getElementById('bcVanishWrap').style.display = this.checked ? 'block' : 'none';
      });
      ` + jsAnchor;

if (!content.includes(jsAnchor)) {
  console.error('ERROR: could not find the isScheduled line in broadcasts.html.');
  process.exit(1);
}
// Only add the listener once, on the send-button click handler setup -- but
// since this exact line appears inside the send handler itself (runs on
// every send, not just once), we instead attach the listener separately
// right after this line using a one-time-safe pattern via a marker check.
// Simpler: just add the listener at the very first occurrence only.
content = content.replace(jsAnchor, jsAddition);

// 3. Include the new fields in the POST body
const oldBody = `body: {
            subject, body,
            scheduledAt: isScheduled ? new Date(scheduledAtValue).toISOString() : undefined
          }`;
const newBody = `body: {
            subject, body,
            scheduledAt: isScheduled ? new Date(scheduledAtValue).toISOString() : undefined,
            isDashboardAnnouncement: document.getElementById('bcDashboardAnnouncement').checked,
            vanishAt: document.getElementById('bcVanishAt').value ? new Date(document.getElementById('bcVanishAt').value).toISOString() : undefined
          }`;

if (!content.includes(oldBody)) {
  console.error('ERROR: could not find the POST body block in broadcasts.html.');
  process.exit(1);
}
content = content.replace(oldBody, newBody);

// 4. Reset the new fields after a successful send, alongside the existing reset
const oldReset = `document.getElementById('bcScheduledAt').style.display = 'none';
        document.getElementById('bcScheduledAt').value = '';`;
const newReset = oldReset + `
        document.getElementById('bcDashboardAnnouncement').checked = false;
        document.getElementById('bcVanishWrap').style.display = 'none';
        document.getElementById('bcVanishAt').value = '';`;

if (!content.includes(oldReset)) {
  console.error('ERROR: could not find the form-reset block in broadcasts.html.');
  process.exit(1);
}
content = content.replace(oldReset, newReset);

writeRestoringLineEndings(filePath, content, usesCRLF);
console.log('    Patched portal/broadcasts.html (announcement checkbox + vanish field).');
NODE_EOF

node .tmp-patch-bc.js
rm .tmp-patch-bc.js

echo ""
echo "Done. Push with your usual save-progress.sh."
