// The REAL fix this time. Root cause of every prior failure: an earlier
// script's "is this already fixed?" check searched for the word
// "tempPassword" anywhere in the whole file -- but onboard-staff already
// uses a variable with that exact name for something unrelated, so the
// check always found a false match and silently skipped the real fix,
// every single time, from the very start. This uses a check scoped
// specifically to the approve-staff route's own body instead.
//
//   node fix-approve-for-real.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'server', 'routes', 'admin.js');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');

const startMarker = "router.post('/approve-staff/:id', async (req, res) => {";
const endMarker = "// DELETE /api/accounting/admin/staff/:id";

const startIdx = content.indexOf(startMarker);
const endIdx = content.indexOf(endMarker);

if (startIdx === -1 || endIdx === -1) {
  console.log('WARNING: could not find the approve-staff route boundaries. Nothing changed.');
  process.exit(1);
}

const currentRouteBlock = content.slice(startIdx, endIdx);

// Scoped check: does the APPROVE-STAFF route specifically already send an
// email? (not just "does this word appear anywhere in the whole file")
if (currentRouteBlock.includes('sendWelcomeEmail')) {
  console.log('The approve-staff route specifically already sends an email -- genuinely already fixed, skipping.');
  process.exit(0);
}

const newRoute = `router.post('/approve-staff/:id', async (req, res) => {
  console.log('[APPROVE-DEBUG] Request received for id:', req.params.id);
  try {
    const { id } = req.params;

    // Generate a fresh password (overwriting whatever they set during
    // self-registration) and force them to change it on first login --
    // same pattern already used for HR-onboarded accounts.
    const tempPassword = crypto.randomBytes(14).toString('base64').replace(/[^a-zA-Z0-9]/g, '').slice(0, 14);
    const newPasswordHash = await bcrypt.hash(tempPassword, 10);

    const { data, error } = await supabase
      .from('staff')
      .update({ is_active: true, password_hash: newPasswordHash, must_change_password: true })
      .eq('id', id)
      .select()
      .single();

    if (error || !data) {
      return res.status(400).json({ error: 'Could not approve this account.' });
    }

    logAdminAction(req, 'approve_staff', id, \`Approved \${data.full_name}\`);
    console.log('[APPROVE-DEBUG] Account approved in database. About to email:', data.email);

    try {
      await sendWelcomeEmail(data.email, data.full_name, data.username, tempPassword);
      console.log('[APPROVE-DEBUG] sendWelcomeEmail() completed with NO error thrown.');
    } catch (emailErr) {
      console.error('[APPROVE-DEBUG] Approval welcome email FAILED:', emailErr);
      return res.json({
        success: true,
        message: \`\${data.full_name} has been approved, but the email failed to send.\`,
        warning: 'Email failed. Username: ' + data.username + ', temporary password: ' + tempPassword
      });
    }

    res.json({ success: true, message: \`\${data.full_name} has been approved and emailed their login details.\` });
  } catch (err) {
    console.error('Approve staff unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong approving this account.' });
  }
});

`;

content = content.slice(0, startIdx) + newRoute + content.slice(endIdx);
fs.writeFileSync(filePath, content, 'utf8');
console.log('Approve-staff route genuinely fixed this time: real password generation, real email attempt, full diagnostic logging throughout.');

