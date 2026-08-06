// Fixes two real bugs in leave.js:
// 1. Submitting a request never explicitly set status: 'pending',
//    relying entirely on an assumed database default -- if that default
//    isn't reliably set, requests could insert with no status at all,
//    making them invisible to every admin (not just one specific account).
// 2. Approve and Reject both called newDate() instead of new Date() --
//    CONFIRMED to throw a real error, meaning these have likely never
//    actually worked. Every attempt would fail before the database update
//    even runs.
//
//   node fix-leave-request-bugs.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'server', 'routes', 'leave.js');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');
let changed = false;

// ---- 1. Explicit status on insert ----
const oldInsert = `.insert({
        staff_id: staffId,
        leave_type: leaveType,
        start_date: startDate,
        end_date: endDate,
        reason: reason || null
      })`;

const newInsert = `.insert({
        staff_id: staffId,
        leave_type: leaveType,
        start_date: startDate,
        end_date: endDate,
        reason: reason || null,
        status: 'pending'
      })`;

if (content.includes(oldInsert)) {
  content = content.replace(oldInsert, newInsert);
  changed = true;
  console.log('Fixed: new leave requests now explicitly set status to pending.');
} else if (content.includes("status: 'pending'\n      })")) {
  console.log('Insert already sets status explicitly, skipping that part.');
} else {
  console.log('WARNING: could not find the expected insert block. Nothing changed for that part.');
}

// ---- 2. newDate() -> new Date() (confirmed to actually throw) ----
const beforeCount = (content.match(/newDate\(\)/g) || []).length;
content = content.replace(/newDate\(\)/g, 'new Date()');
const afterCount = (content.match(/newDate\(\)/g) || []).length;

if (beforeCount > 0) {
  changed = true;
  console.log('Fixed ' + beforeCount + ' occurrence(s) of newDate() -> new Date() (Approve/Reject were both broken).');
} else {
  console.log('No newDate() typos found, skipping that part.');
}

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\nleave.js patched successfully.');
} else {
  console.log('\nNo changes made -- everything already correct.');
}

