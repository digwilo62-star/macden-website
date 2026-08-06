#!/usr/bin/env bash
# Fixes Directory's horizontal scroll/movement issue. Root cause: the
# table used rigid fixed-pixel columns totaling a fairly wide minimum
# -- on a narrower window, this forced the whole PAGE wider than the
# viewport, not just the table, making everything feel like it slides
# around. Fixed two ways: columns now shrink proportionally with
# minmax() instead of staying rigid, and any scrolling still needed on
# very narrow screens is now contained to just the table itself, never
# the whole page/sidebar.
set -e
cat > fix-directory-scroll.js << 'EOF_FIXER_JS'
// Fixes the Directory page's horizontal scroll/movement issue. Root
// cause: the table used fixed pixel-width columns (220px 160px 160px 1fr
// 130px) totaling a fairly wide minimum -- on a narrower window, this
// forced the table (and the whole page along with it) wider than the
// viewport, making the entire page horizontally scrollable in a way that
// feels like content sliding around. Fixed two ways: the table can now
// shrink its columns proportionally instead of forcing a rigid minimum,
// and any scrolling that IS still needed is contained to just the table
// itself, never the whole page/sidebar.
//
//   node fix-directory-scroll.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'portal', 'directory.html');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');
let changed = false;

// ---- 1. Make columns flexible (minmax) instead of rigid fixed widths ----
const oldColumns = 'grid-template-columns: 220px 160px 160px 1fr 130px;';
const newColumns = 'grid-template-columns: minmax(140px, 220px) minmax(100px, 160px) minmax(100px, 160px) minmax(120px, 1fr) minmax(90px, 130px);';

const count = (content.match(new RegExp(oldColumns.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g')) || []).length;

if (count > 0) {
  content = content.split(oldColumns).join(newColumns);
  changed = true;
  console.log('Made table columns flexible instead of rigid (updated ' + count + ' occurrence(s)).');
} else if (content.includes('minmax(140px, 220px)')) {
  console.log('Columns already flexible, skipping that part.');
}

// ---- 2. Contain any remaining necessary scroll to just the table, never the whole page ----
const oldListStyle = '.dir-list { background: var(--surface);border: 1px solid var(--border); border-radius: var(--radius-md); overflow: hidden; }';
const newListStyle = '.dir-list { background: var(--surface);border: 1px solid var(--border); border-radius: var(--radius-md); overflow-x: auto; overflow-y: hidden; }';

if (content.includes(oldListStyle)) {
  content = content.replace(oldListStyle, newListStyle);
  changed = true;
  console.log('Contained horizontal scroll to the table itself (not the whole page).');
} else if (content.includes('overflow-x: auto; overflow-y: hidden;')) {
  console.log('Scroll containment already present, skipping that part.');
}

// ---- 3. Give the header/body rows a sensible min-width so columns don't
// crush illegibly small, while still allowing the table to scroll within
// itself rather than the page ----
const oldHeaderRow = '.dir-header-row { display: grid;';
const newHeaderRow = '.dir-header-row { display: grid; min-width: 700px;';
if (content.includes(oldHeaderRow) && !content.includes('.dir-header-row { display: grid; min-width: 700px;')) {
  content = content.replace(oldHeaderRow, newHeaderRow);
  changed = true;
}

const oldBodyRow = '.dir-row { display: grid;';
const newBodyRow = '.dir-row { display: grid; min-width: 700px;';
if (content.includes(oldBodyRow) && !content.includes('.dir-row { display: grid; min-width: 700px;')) {
  content = content.replace(oldBodyRow, newBodyRow);
  changed = true;
  console.log('Added a sensible minimum width so columns stay readable on any screen size.');
}

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\ndirectory.html patched successfully.');
} else {
  console.log('\nNo changes made -- nothing matched. Paste back your current directory.html if the issue persists.');
}

EOF_FIXER_JS
echo "Running the fix..."
node fix-directory-scroll.js
echo "Done. Hard-refresh (Ctrl+F5) -- CSS only, no server restart needed."