#!/usr/bin/env bash
# Fixes the Approve button staying stuck forever even when the backend
# approval genuinely succeeds (confirmed by refreshing showing the
# account WAS approved). The button now gets immediate, guaranteed
# feedback the moment the request succeeds, instead of depending
# entirely on a second re-fetch to make it disappear.
set -e
cat > fix-approve-button-stuck.js << 'EOF_FIXER_JS'
// Fixes the Approve button staying stuck forever even when the backend
// approval genuinely succeeds. Root cause: on success, the old code just
// called loadPendingStaff() to re-fetch and re-render the whole list --
// if that re-fetch has ANY timing hiccup, the old button (still showing
// "Approving..." and disabled) never gets replaced, looking permanently
// frozen even though the real work already completed.
//
// Fix: give the button immediate, guaranteed feedback the moment the
// request succeeds -- remove that row directly, not dependent on a second
// round-trip succeeding too.
//
//   node fix-approve-button-stuck.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'accounting', 'dashboard.html');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');

if (content.includes('btn.closest')) {
  console.log('Already fixed, skipping.');
  process.exit(0);
}

const oldFn = `async function approveStaff(id, btn) {
      btn.disabled = true;
      btn.textContent = 'Approving…';
      try {
        await apiRequest('/admin/approve-staff/' + id, { method: 'POST' });
        loadPendingStaff();
      } catch (err) {
        alert(err.message);
        btn.disabled = false;
        btn.textContent = 'Approve';
      }
    }`;

const newFn = `async function approveStaff(id, btn) {
      btn.disabled = true;
      btn.textContent = 'Approving…';
      try {
        await apiRequest('/admin/approve-staff/' + id, { method: 'POST' });
        // Give the button immediate, guaranteed feedback instead of relying
        // entirely on a second re-fetch (loadPendingStaff) to make it
        // disappear -- if that re-fetch has ANY timing hiccup, the old
        // button used to just sit there stuck forever even though the
        // approval itself had already genuinely succeeded.
        btn.textContent = 'Approved ✓';
        const row = btn.closest('div');
        if (row && row.parentElement) {
          setTimeout(() => row.remove(), 600);
        }
        loadPendingStaff(); // still refresh in the background, for accuracy
      } catch (err) {
        alert(err.message);
        btn.disabled = false;
        btn.textContent = 'Approve';
      }
    }`;

if (content.includes(oldFn)) {
  content = content.replace(oldFn, newFn);
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('Fixed: Approve button now updates immediately on success, no longer dependent on a second re-fetch.');
} else {
  console.log('WARNING: could not find the expected approveStaff function. Nothing changed -- paste back dashboard.html again if this persists.');
  process.exit(1);
}

EOF_FIXER_JS
echo "Running the fix..."
node fix-approve-button-stuck.js
echo "Done. Restart your server and hard-refresh (Ctrl+F5)."