#!/usr/bin/env bash
# TEMPORARY diagnostic: adds unconditional console.log lines at every
# step of the approve process (request received, database update done,
# email attempt starting, email attempt finished with no error). This
# will show us EXACTLY where things actually stand, removing all
# ambiguity -- since even our existing error logging showed nothing at
# all when this was tested live.
set -e
cat > add-approve-diagnostic-logging.js << 'EOF_FIXER_JS'
// Adds console.log statements that fire at EVERY step of the approve
// process, unconditionally -- not just on error. This removes all
// ambiguity about whether the request reaches the server, whether the
// database update succeeds, and specifically whether the email attempt
// even starts. Temporary diagnostic tool, not a permanent fix.
//
//   node add-approve-diagnostic-logging.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'server', 'routes', 'admin.js');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');

if (content.includes('[APPROVE-DEBUG]')) {
  console.log('Diagnostic logging already added, skipping.');
  process.exit(0);
}

const oldStart = "router.post('/approve-staff/:id', async (req, res) => {\n  try {\n    const { id } = req.params;";
const newStart = "router.post('/approve-staff/:id', async (req, res) => {\n  console.log('[APPROVE-DEBUG] Request received for id:', req.params.id);\n  try {\n    const { id } = req.params;";

if (content.includes(oldStart)) {
  content = content.replace(oldStart, newStart);
} else {
  console.log('WARNING: could not find the route start. Nothing changed.');
  process.exit(1);
}

const oldBeforeEmail = "logAdminAction(req, 'approve_staff', id, `Approved ${data.full_name}`);\n\n    try {\n      await sendWelcomeEmail(data.email, data.full_name, data.username, tempPassword);";
const newBeforeEmail = "logAdminAction(req, 'approve_staff', id, `Approved ${data.full_name}`);\n    console.log('[APPROVE-DEBUG] Account approved in database. About to attempt email send to:', data.email);\n\n    try {\n      await sendWelcomeEmail(data.email, data.full_name, data.username, tempPassword);\n      console.log('[APPROVE-DEBUG] sendWelcomeEmail() completed with NO error thrown.');";

if (content.includes(oldBeforeEmail)) {
  content = content.replace(oldBeforeEmail, newBeforeEmail);
} else {
  console.log('WARNING: could not find the pre-email section. Nothing changed for that part.');
}

fs.writeFileSync(filePath, content, 'utf8');
console.log('Diagnostic logging added to approve-staff route.');

EOF_FIXER_JS
echo "Running the diagnostic patch..."
node add-approve-diagnostic-logging.js
echo "Done. Restart your server (or push + wait for Render to redeploy)."