// When admin approves a self-registered account, this now generates a
// fresh random password (overwriting whatever they originally set),
// forces a password change on first login, and emails them the new
// username/password/login link -- reusing the exact same email function
// already built for HR-onboarded accounts, no new email template needed.
//
//   node fix-approve-generates-password.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'server', 'routes', 'admin.js');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');

if (content.includes('tempPassword') && content.includes('approve-staff')) {
  console.log('Already updated, skipping.');
  process.exit(0);
}

const oldRoute = `router.post('/approve-staff/:id', async (req, res) => {
  try {
    const { id } = req.params;

    const { data, error } = await supabase
      .from('staff')
      .update({ is_active: true })
      .eq('id', id)
      .select()
      .single();

    if (error || !data) {
      return res.status(400).json({ error: 'Could not approve this account.' });
    }

    logAdminAction(req, 'approve_staff', id, \`Approved \${data.full_name}\`);
    res.json({ success: true, message: \`\${data.full_name} has been approved and can now log in.\` });
  } catch (err) {
    console.error('Approve staff unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong approving this account.' });
  }
});`;

const newRoute = `router.post('/approve-staff/:id', async (req, res) => {
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

    try {
      await sendWelcomeEmail(data.email, data.full_name, data.username, tempPassword);
    } catch (emailErr) {
      console.error('Approval welcome email failed:', emailErr);
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
});`;

if (content.includes(oldRoute)) {
  content = content.replace(oldRoute, newRoute);
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('Approve now generates a real password, forces a change, and emails the login details.');
} else {
  console.log('WARNING: could not find the expected approve-staff route. Nothing changed -- paste back admin.js again if this persists.');
  process.exit(1);
}

