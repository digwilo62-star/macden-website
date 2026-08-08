// Fixes Inbox's horizontal scroll issue -- same root cause as everywhere
// else: rigid fixed-pixel columns (220px 1fr 110px 36px), with a 220px
// minimum just for the sender column alone. This is in the SHARED
// portal-inbox.css file, but the specific rule being fixed (.email-row)
// is only actually used by Inbox's list view, so this is a targeted,
// safe change.
//
//   node fix-inbox-scroll.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'portal', 'assets', 'portal-inbox.css');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');
let changed = false;

const oldRow = '.email-row { display: grid; grid-template-columns: 220px 1fr 110px 36px; align-items: center; gap: 16px; padding: 14px 20px; border-bottom: 1px solid var(--border); cursor: pointer; }';
const newRow = '.email-row { display: grid; min-width: 500px; grid-template-columns: minmax(140px, 220px) minmax(160px, 1fr) minmax(80px, 110px) 36px; align-items: center; gap: 16px; padding: 14px 20px; border-bottom: 1px solid var(--border); cursor: pointer; }';

if (content.includes(oldRow)) {
  content = content.replace(oldRow, newRow);
  changed = true;
  console.log('Fixed: Inbox row columns made flexible.');
} else if (content.includes('min-width: 500px')) {
  console.log('Already fixed, skipping that part.');
} else {
  console.log('WARNING: could not find the expected .email-row rule. Nothing changed for that part.');
}

const oldList = '.email-list { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-md); overflow: hidden; }';
const newList = '.email-list { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-md); overflow-x: auto; overflow-y: hidden; }';

if (content.includes(oldList)) {
  content = content.replace(oldList, newList);
  changed = true;
  console.log('Contained horizontal scroll to the list itself, not the whole page.');
} else if (content.includes('overflow-x: auto; overflow-y: hidden;')) {
  console.log('Scroll containment already present, skipping that part.');
}

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\nportal-inbox.css patched successfully.');
} else {
  console.log('\nNo changes made.');
}

