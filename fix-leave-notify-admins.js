// Sends an email to ALL active admins whenever a new leave request is
// submitted, so they don't have to be actively checking the Pending
// Approvals panel to know one came in. Reuses the existing branded email
// template (sendNotificationEmail), no new template needed.
//
//   node fix-leave-notify-admins.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'server', 'routes', 'leave.js');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');

if (content.includes('notifyAdminsOfNewRequest')) {
  console.log('Already added, skipping.');
  process.exit(0);
}

// ---- 1. Import sendNotificationEmail ----
const importAnchor = "const supabase = require('../config/supabaseClient');";
const newImport = `const supabase = require('../config/supabaseClient');
const { sendNotificationEmail } = require('../utils/email');`;

if (content.includes(importAnchor)) {
  content = content.replace(importAnchor, newImport);
} else {
  console.log('WARNING: could not find the import anchor. Nothing changed.');
  process.exit(1);
}

// ---- 2. Add the notify-all-admins helper function ----
const helperAnchor = 'function daysBetween(startDate, endDate) {';
const helperFn = `// Emails every active admin when a new leave request comes in, so they
// don't have to be actively checking Pending Approvals to know about it.
// Fire-and-forget: a notification failure should never block the actual
// submission from succeeding.
async function notifyAdminsOfNewRequest(staffId, leaveType, startDate, endDate, reason) {
  try {
    const { data: staffMember } = await supabase
      .from('staff')
      .select('full_name')
      .eq('id', staffId)
      .single();

    const { data: admins } = await supabase
      .from('staff')
      .select('email, full_name')
      .eq('role', 'admin')
      .eq('is_active', true);

    if (!admins || admins.length === 0) return;

    const requesterName = staffMember ? staffMember.full_name : 'A staff member';
    const subject = 'New leave request from ' + requesterName;
    const bodyText = requesterName + ' has submitted a ' + leaveType + ' request from ' +
      new Date(startDate).toLocaleDateString() + ' to ' + new Date(endDate).toLocaleDateString() +
      (reason ? '.\\n\\nReason: ' + reason : '.') +
      '\\n\\nReview it in Leave & Requests on the portal.';

    await Promise.allSettled(
      admins.map(admin => sendNotificationEmail(admin.email, admin.full_name, subject, bodyText))
    );
  } catch (err) {
    console.error('Admin leave-notification error:', err);
  }
}

function daysBetween(startDate, endDate) {`;

if (content.includes(helperAnchor)) {
  content = content.replace(helperAnchor, helperFn);
} else {
  console.log('WARNING: could not find the helper anchor. Nothing changed.');
  process.exit(1);
}

// ---- 3. Call it after a successful submission ----
const submitAnchor = "res.json({ success: true, request: data });";
const newSubmitCall = `notifyAdminsOfNewRequest(staffId, leaveType, startDate, endDate, reason).catch(err => console.error('Leave notify error:', err));
    res.json({ success: true, request: data });`;

if (content.includes(submitAnchor)) {
  content = content.replace(submitAnchor, newSubmitCall);
} else {
  console.log('WARNING: could not find the submit-response anchor. Nothing changed for that part.');
}

fs.writeFileSync(filePath, content, 'utf8');
console.log('Admins now get emailed whenever a new leave request is submitted.');

