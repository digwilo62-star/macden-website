#!/bin/bash
# fix-managestaff-fieldlink-v1.sh
#
# Reverts the "ID Card" button/generateIdCard() added to the regular
# Manage Staff table (wrong place for it -- those staff already have
# accounts and can self-request via Settings). Adds a "Field Staff" link
# instead, pointing to the new dedicated page for no-login workers.

set -e

cat > .tmp-patch-msfieldlink.js << 'NODE_EOF'
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

// Validate the one MANDATORY anchor exists before touching anything --
// if it's missing, we bail out cleanly with nothing changed and no
// misleading "reverted" messages for steps that never actually got saved.
const anchorPattern = /<a\s+href="onboard\.html"[^>]*>[\s\S]*?<\/a>/;
const needsFieldLink = !content.includes('field-staff.html');

if (needsFieldLink && !anchorPattern.test(content)) {
  console.error('ERROR: could not find the onboard.html link to anchor the new Field Staff link to.');
  console.error('Nothing was changed.');
  process.exit(1);
}

let changed = false;

// 1. Revert the ID Card button back to the plain action row
const patchedRow = `            '<div>' + actionBtn + ' <button class="ms-action-btn" onclick="generateIdCard(\\'' + s.id + '\\')">ID Card</button>' + '</div>' +`;
const originalRow = `            '<div>' + actionBtn + '</div>' +`;

if (content.includes(patchedRow)) {
  content = content.replace(patchedRow, originalRow);
  changed = true;
  console.log('    Reverted the ID Card button from the staff table.');
} else {
  console.log('    ID Card button already absent -- nothing to revert there.');
}

// 2. Remove the generateIdCard() function block if present
const generateFnPattern = /\n\n    \/\/ Uses raw fetch \(not apiRequest\) because this route lives at\n    \/\/ \/api\/id-card\/\.\.\. , not under the \/api\/accounting prefix apiRequest adds\.\n    async function generateIdCard\(id\) \{\n      try \{\n        const res = await fetch\('\/api\/id-card\/admin-generate\/' \+ id, \{ method: 'POST', credentials: 'include' \}\);\n        const data = await res\.json\(\);\n        if \(!res\.ok\) throw new Error\(data\.error \|\| 'Could not generate ID card\.'\);\n        window\.open\('id-card-view\.html\?requestId=' \+ data\.requestId, '_blank'\);\n      \} catch \(err\) \{\n        alert\(err\.message\);\n      \}\n    \}/;

if (generateFnPattern.test(content)) {
  content = content.replace(generateFnPattern, '');
  changed = true;
  console.log('    Removed generateIdCard() function.');
} else {
  console.log('    generateIdCard() function already absent -- nothing to remove there.');
}

// 3. Add the Field Staff link next to onboard.html, if not already there
if (needsFieldLink) {
  const match = content.match(anchorPattern);
  const newLink = '<a href="field-staff.html" class="btn btn-primary" style="width:auto; padding:10px 20px; text-decoration:none; display:inline-flex; align-items:center; gap:8px; margin-right:10px; background:var(--surface); color:var(--text-primary); border:1px solid var(--border);"><i class="ti ti-id-badge-2"></i> Field Staff</a>\n          ';
  content = content.replace(match[0], newLink + match[0]);
  changed = true;
  console.log('    Added Field Staff link.');
} else {
  console.log('    Field Staff link already present -- skipping.');
}

if (changed) {
  writeRestoringLineEndings(filePath, content, usesCRLF);
  console.log('    Saved portal/manage-staff.html.');
} else {
  console.log('    No changes needed -- file already up to date.');
}
NODE_EOF

node .tmp-patch-msfieldlink.js
rm .tmp-patch-msfieldlink.js

echo ""
echo "Done. Push with your usual save-progress.sh."
