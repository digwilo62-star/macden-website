// Adds diagnostic logging specifically around the email-sending step --
// the first attempt at this used a fragile multi-line match that failed
// against your real file's exact formatting. This targets a single,
// distinctive line instead, much less likely to mismatch.
//
//   node add-email-step-logging.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'server', 'routes', 'admin.js');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');

if (content.includes('sendWelcomeEmail() completed with NO error thrown')) {
  console.log('Already added, skipping.');
  process.exit(0);
}

const emailLine = "await sendWelcomeEmail(data.email, data.full_name, data.username, tempPassword);";

if (!content.includes(emailLine)) {
  console.log('WARNING: could not find the email-send line at all. Nothing changed -- paste back your current admin.js.');
  process.exit(1);
}

const replacement = "console.log('[APPROVE-DEBUG] About to call sendWelcomeEmail() for:', data.email);\n      " + emailLine + "\n      console.log('[APPROVE-DEBUG] sendWelcomeEmail() completed with NO error thrown.');";

content = content.replace(emailLine, replacement);
fs.writeFileSync(filePath, content, 'utf8');
console.log('Email-step diagnostic logging added successfully.');

