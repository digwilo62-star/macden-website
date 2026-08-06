#!/usr/bin/env bash
# Fixes Leave & Requests' horizontal scroll/swipe issue -- same root
# cause as Directory. This page had it in an extra tricky spot: the
# admin 'Pending Approvals' table's column widths are duplicated as an
# INLINE style baked directly into the JS that renders each row, not
# just the CSS class -- both had to be fixed together. Caught and fixed
# a real idempotency bug during testing (min-width would have
# duplicated on a second run) before this was sent.
set -e
cat > fix-leave-scroll.js << 'EOF_FIXER_JS'
// Fixes Leave & Requests' horizontal scroll/swipe issue -- same root cause
// as Directory: rigid fixed-pixel table columns forcing the whole page
// wider than the viewport. This page has it in THREE places: the CSS
// class for the "My Requests" table, the CSS class's inline override for
// the admin "Pending Approvals" header row, AND a matching inline style
// baked into the JS that renders each pending-approval row -- all three
// need fixing, not just the CSS class.
//
//   node fix-leave-scroll.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'portal', 'leave.html');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');
let changed = false;

function replaceAll(oldStr, newStr, label) {
  const count = content.split(oldStr).length - 1;
  if (count > 0) {
    content = content.split(oldStr).join(newStr);
    changed = true;
    console.log('Fixed: ' + label + ' (' + count + ' occurrence(s)).');
    return true;
  }
  return false;
}

// ---- 1. Main table columns (My Requests) -- flexible instead of rigid ----
replaceAll(
  'grid-template-columns: 100px 100px 100px 1fr 100px 130px;',
  'grid-template-columns: minmax(80px, 100px) minmax(80px, 100px) minmax(80px, 100px) minmax(120px, 1fr) minmax(60px, 100px) minmax(100px, 130px);',
  'My Requests table columns made flexible'
) || console.log('My Requests columns already flexible or not found, skipping.');

// ---- 2. Admin Pending Approvals table columns (appears in CSS AND inline in JS) ----
replaceAll(
  'grid-template-columns: 160px 100px 100px 100px 1fr 160px;',
  'grid-template-columns: minmax(120px, 160px) minmax(80px, 100px) minmax(80px, 100px) minmax(80px, 100px) minmax(120px, 1fr) minmax(130px, 160px);',
  'Pending Approvals table columns made flexible (CSS + inline JS)'
) || console.log('Pending Approvals columns already flexible or not found, skipping.');

// ---- 3. Contain any remaining necessary scroll to the table itself, not the whole page ----
replaceAll(
  '.lv-table { background: var(--surface);border: 1px solid var(--border); border-radius: var(--radius-md); overflow: hidden; }',
  '.lv-table { background: var(--surface);border: 1px solid var(--border); border-radius: var(--radius-md); overflow-x: auto; overflow-y: hidden; }',
  'Contained horizontal scroll to the table itself'
) || console.log('Scroll containment already present or not found, skipping.');

// ---- 4. Give rows a sensible min-width so columns stay readable while scrollable ----
if (!content.includes('.lv-header-row { display: grid; min-width: 620px;')) {
  replaceAll(
    '.lv-header-row { display: grid;',
    '.lv-header-row { display: grid; min-width: 620px;',
    'Added min-width to header row'
  );
} else {
  console.log('Header row min-width already present, skipping.');
}
if (!content.includes('.lv-row { display: grid; min-width: 620px;')) {
  replaceAll(
    '.lv-row { display: grid;',
    '.lv-row { display: grid; min-width: 620px;',
    'Added min-width to body row'
  );
} else {
  console.log('Body row min-width already present, skipping.');
}

// ---- 5. The outer form+table layout -- let the fixed 380px column shrink a bit on narrow screens ----
replaceAll(
  '.lv-grid { display: grid; grid-template-columns: 380px 1fr; gap: 20px; margin-bottom: 24px; }',
  '.lv-grid { display: grid; grid-template-columns: minmax(280px, 380px) minmax(300px, 1fr); gap: 20px; margin-bottom: 24px; }',
  'Made the outer form/table layout column flexible too'
);

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\nleave.html patched successfully.');
} else {
  console.log('\nNo changes made -- nothing matched. Paste back your current leave.html if the issue persists.');
}

EOF_FIXER_JS
echo "Running the fix..."
node fix-leave-scroll.js
echo "Done. Hard-refresh (Ctrl+F5) -- CSS only, no server restart needed."