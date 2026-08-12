#!/bin/bash
# fix-managestaff-generate-idcard.sh
#
# Adds a one-click "ID Card" button next to Deactivate/Reactivate on
# Manage Staff. Lets an admin generate a card directly for any staff
# member -- no login, no request, no approval step needed on their end.
# Auto-assigns a random staff_id behind the scenes if they don't have
# one yet, then opens the rendered card in a new tab.

set -e

if grep -q "generateIdCard" portal/manage-staff.html; then
  echo "==> Already applied -- skipping (safe to re-run)."
  exit 0
fi

cat > .tmp-patch-generate.js << 'NODE_EOF'
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

const filePath = 'portal/manage-staff.html';
let { normalized: content, usesCRLF } = readNormalized(filePath);

// 1. Add the button next to the existing action button
const oldRow = `            '<div>' + actionBtn + '</div>' +`;
const newRow = `            '<div>' + actionBtn + ' <button class="ms-action-btn" onclick="generateIdCard(\\'' + s.id + '\\')">ID Card</button>' + '</div>' +`;

if (!content.includes(oldRow)) {
  console.error('ERROR: could not find the action button row in manage-staff.html.');
  process.exit(1);
}
content = content.replace(oldRow, newRow);

// 2. Add the generateIdCard() function, right after reactivate()
const oldReactivate = `    async function reactivate(id) {
      try {
        await apiRequest('/admin/staff/' + id + '/reactivate', { method: 'POST' });
        loadStaff();
      } catch (err) {
        alert(err.message);
      }
    }`;

const newReactivate = `    async function reactivate(id) {
      try {
        await apiRequest('/admin/staff/' + id + '/reactivate', { method: 'POST' });
        loadStaff();
      } catch (err) {
        alert(err.message);
      }
    }

    // Uses raw fetch (not apiRequest) because this route lives at
    // /api/id-card/... , not under the /api/accounting prefix apiRequest adds.
    async function generateIdCard(id) {
      try {
        const res = await fetch('/api/id-card/admin-generate/' + id, { method: 'POST', credentials: 'include' });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Could not generate ID card.');
        window.open('id-card-view.html?requestId=' + data.requestId, '_blank');
      } catch (err) {
        alert(err.message);
      }
    }`;

if (!content.includes(oldReactivate)) {
  console.error('ERROR: could not find the reactivate() function in manage-staff.html.');
  process.exit(1);
}
content = content.replace(oldReactivate, newReactivate);

writeRestoringLineEndings(filePath, content, usesCRLF);
console.log('    Patched portal/manage-staff.html (ID Card button + generateIdCard()).');
NODE_EOF

node .tmp-patch-generate.js
rm .tmp-patch-generate.js

echo ""
echo "Done. Push with your usual save-progress.sh."
