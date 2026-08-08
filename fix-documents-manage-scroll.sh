#!/usr/bin/env bash
# Fixes the same horizontal scroll root cause (rigid fixed-pixel table
# columns) in Documents and Manage Staff -- same pattern already fixed
# in Directory and Leave & Requests. Note: Policies didn't need this
# fix (already uses fully flexible repeat(3, 1fr) columns). Inbox
# needs a separate fix -- its layout comes entirely from the shared
# portal-inbox.css file, not seen yet.
set -e
cat > fix-documents-manage-scroll.js << 'EOF_FIXER_JS'
// Fixes the same horizontal scroll root cause (rigid fixed-pixel table
// columns) in Documents and Manage Staff -- same pattern already fixed in
// Directory and Leave & Requests.
//
//   node fix-documents-manage-scroll.js

const fs = require('fs');
const path = require('path');
let totalChanged = 0;

function fixFile(filename, replacements) {
  const filePath = path.join(__dirname, 'portal', filename);
  if (!fs.existsSync(filePath)) {
    console.log(filename + ': not found, skipping.');
    return;
  }
  let content = fs.readFileSync(filePath, 'utf8');
  content = content.replace(/\r\n/g, '\n');
  let changed = false;

  replacements.forEach(({ old, new: newStr, label }) => {
    const count = content.split(old).length - 1;
    if (count > 0) {
      content = content.split(old).join(newStr);
      changed = true;
      console.log(filename + ': fixed ' + label + ' (' + count + ' occurrence(s)).');
    } else if (!content.includes(newStr)) {
      console.log(filename + ': WARNING could not find ' + label + '.');
    } else {
      console.log(filename + ': ' + label + ' already fixed, skipping.');
    }
  });

  if (changed) {
    fs.writeFileSync(filePath, content, 'utf8');
    totalChanged++;
  }
}

// ---- Documents ----
fixFile('documents.html', [
  {
    old: '.doc-header-row { display: grid; grid-template-columns: 1fr 140px 110px 90px 90px;',
    new: '.doc-header-row { display: grid; min-width: 600px; grid-template-columns: minmax(160px, 1fr) minmax(100px, 140px) minmax(80px, 110px) minmax(70px, 90px) minmax(70px, 90px);',
    label: 'header row columns'
  },
  {
    old: '.doc-row { display: grid; grid-template-columns: 1fr 140px 110px 90px 90px;',
    new: '.doc-row { display: grid; min-width: 600px; grid-template-columns: minmax(160px, 1fr) minmax(100px, 140px) minmax(80px, 110px) minmax(70px, 90px) minmax(70px, 90px);',
    label: 'body row columns'
  },
  {
    old: '.doc-list { background: var(--surface);border: 1px solid var(--border); border-radius: var(--radius-md); overflow: hidden; }',
    new: '.doc-list { background: var(--surface);border: 1px solid var(--border); border-radius: var(--radius-md); overflow-x: auto; overflow-y: hidden; }',
    label: 'scroll containment'
  }
]);

// ---- Manage Staff ----
fixFile('manage-staff.html', [
  {
    old: '.ms-header-row { display: grid; grid-template-columns: 200px 130px 130px 1fr 90px 90px;',
    new: '.ms-header-row { display: grid; min-width: 650px; grid-template-columns: minmax(140px, 200px) minmax(90px, 130px) minmax(90px, 130px) minmax(120px, 1fr) minmax(70px, 90px) minmax(70px, 90px);',
    label: 'header row columns'
  },
  {
    old: '.ms-row { display: grid; grid-template-columns: 200px 130px 130px 1fr 90px 90px;',
    new: '.ms-row { display: grid; min-width: 650px; grid-template-columns: minmax(140px, 200px) minmax(90px, 130px) minmax(90px, 130px) minmax(120px, 1fr) minmax(70px, 90px) minmax(70px, 90px);',
    label: 'body row columns'
  },
  {
    old: '.ms-list { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-md); overflow: hidden; }',
    new: '.ms-list { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-md); overflow-x: auto; overflow-y: hidden; }',
    label: 'scroll containment'
  }
]);

console.log('\n' + totalChanged + ' file(s) patched.');

EOF_FIXER_JS
echo "Running the fix..."
node fix-documents-manage-scroll.js
echo "Done. Hard-refresh (Ctrl+F5) -- CSS only, no server restart needed."