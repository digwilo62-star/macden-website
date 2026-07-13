#!/usr/bin/env bash
# Updates the /server backend with self-signup + email verification + admin approval.
# Run this from the ROOT of your macden-website repo, in Git Bash.
# Safe to run even if some files already exist — it overwrites them cleanly.
set -e

mkdir -p server/config server/routes server/middleware server/scripts server/utils

cat > server/package.json << 'EOF_SERVER_PACKAGE_JSON'
{
  "name": "macden-accounting-server",
  "version": "1.0.0",
  "description": "Backend for MACDEN Accounting Department tool",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "create-staff": "node scripts/createStaff.js"
  },
  "dependencies": {
    "@supabase/supabase-js": "^2.45.0",
    "bcrypt": "^5.1.1",
    "cors": "^2.8.5",
    "dotenv": "^16.4.5",
    "express": "^4.19.2",
    "express-session": "^1.18.0",
    "nodemailer": "^6.9.14",
    "nodemailer": "^9.0.3"
  }
}

EOF_SERVER_PACKAGE_JSON

cat > server/.env.example << 'EOF_SERVER__ENV_EXAMPLE'
# Supabase — Project Settings > API
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key-here

# Session secret — any long random string, generate one and never reuse across projects
SESSION_SECRET=replace-this-with-a-long-random-string

# Email (SMTP) — used to send verification codes at signup
# FREE option: Gmail SMTP using an App Password (not your real Gmail password)
# Setup: Google Account > Security > turn on 2-Step Verification > search "App Passwords" > generate one for "Mail"
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=youraccount@gmail.com
SMTP_PASS=your-16-character-app-password
SMTP_FROM="MACDEN Accounting" <youraccount@gmail.com>

# Port Render will inject automatically — this is just the local dev fallback
PORT=3000

EOF_SERVER__ENV_EXAMPLE

cat > server/server.js << 'EOF_SERVER_SERVER_JS'
require('dotenv').config();

const express = require('express');
const session = require('express-session');
const cors = require('cors');

const authRoutes = require('./routes/auth');
const adminRoutes = require('./routes/admin');
const requireAuth = require('./middleware/requireAuth');

const app = express();

app.use(express.json());

// CORS — allow requests from your actual site only.
// If the accounting pages are served from the same domain (macden.com.ng/accounting),
// this can be tightened further. Update the origin below to match your real domain.
app.use(cors({
  origin: 'https://macden.com.ng',
  credentials: true
}));

app.use(session({
  secret: process.env.SESSION_SECRET,
  resave: false,
  saveUninitialized: false,
  cookie: {
    httpOnly: true,
    secure: true,       // requires HTTPS — Render gives you this by default
    sameSite: 'lax',
    maxAge: 1000 * 60 * 60 * 8   // 8-hour session, adjust as needed
  }
}));

// Health check — useful for confirming Render deploy is alive
app.get('/api/accounting/health', (req, res) => {
  res.json({ status: 'ok' });
});

// Auth routes (login/logout/me) — not behind requireAuth, obviously
app.use('/api/accounting/auth', authRoutes);

// Everything below this line will require a logged-in session.
// Placeholder for now — Phase 3 (prices) and Phase 4 (messaging)
// routes will be added here as we build them.
app.use('/api/accounting', requireAuth);
app.use('/api/accounting/admin', adminRoutes);

app.get('/api/accounting/dashboard-check', (req, res) => {
  // Simple proof that requireAuth is working — returns the logged-in staff's info
  res.json({ message: `Welcome, ${req.session.staff.fullName}`, staff: req.session.staff });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Accounting backend running on port ${PORT}`);
});

EOF_SERVER_SERVER_JS

cat > server/routes/auth.js << 'EOF_SERVER_ROUTES_AUTH_JS'
const express = require('express');
const bcrypt = require('bcrypt');
const crypto = require('crypto');
const supabase = require('../config/supabaseClient');
const { sendVerificationEmail } = require('../utils/email');

const router = express.Router();

function generateCode() {
  // 6-digit numeric code, e.g. 483920
  return crypto.randomInt(100000, 999999).toString();
}

// POST /api/accounting/auth/register
router.post('/register', async (req, res) => {
  const { fullName, username, email, password } = req.body;

  if (!fullName || !username || !email || !password) {
    return res.status(400).json({ error: 'All fields are required.' });
  }

  if (password.length < 8) {
    return res.status(400).json({ error: 'Password must be at least 8 characters.' });
  }

  const { data: dept, error: deptError } = await supabase
    .from('departments')
    .select('id')
    .eq('slug', 'accounting')
    .single();

  if (deptError || !dept) {
    return res.status(500).json({ error: 'Setup error — accounting department not found.' });
  }

  const passwordHash = await bcrypt.hash(password, 10);
  const code = generateCode();
  const expiresAt = new Date(Date.now() + 15 * 60 * 1000); // 15 minutes from now

  const { data: newStaff, error } = await supabase
    .from('staff')
    .insert({
      department_id: dept.id,
      full_name: fullName,
      username: username,
      email: email,
      password_hash: passwordHash,
      email_verified: false,
      is_active: false, // stays inactive until you manually approve
      verification_code: code,
      verification_code_expires_at: expiresAt.toISOString()
    })
    .select()
    .single();

  if (error) {
    // Most likely cause: username or email already taken (unique constraint)
    return res.status(400).json({ error: 'Could not create account. Username or email may already be in use.' });
  }

  try {
    await sendVerificationEmail(email, fullName, code);
  } catch (emailError) {
    console.error('Failed to send verification email:', emailError.message);
    return res.status(500).json({ error: 'Account created but the verification email failed to send. Contact your admin.' });
  }

  res.json({ success: true, message: 'Account created. Check your email for a verification code.' });
});

// POST /api/accounting/auth/verify-email
router.post('/verify-email', async (req, res) => {
  const { email, code } = req.body;

  if (!email || !code) {
    return res.status(400).json({ error: 'Email and code are required.' });
  }

  const { data: staffMember, error } = await supabase
    .from('staff')
    .select('id, verification_code, verification_code_expires_at, email_verified')
    .eq('email', email)
    .single();

  if (error || !staffMember) {
    return res.status(400).json({ error: 'Invalid email or code.' });
  }

  if (staffMember.email_verified) {
    return res.status(400).json({ error: 'This email is already verified.' });
  }

  if (staffMember.verification_code !== code) {
    return res.status(400).json({ error: 'Incorrect code.' });
  }

  if (new Date(staffMember.verification_code_expires_at) < new Date()) {
    return res.status(400).json({ error: 'This code has expired. Please request a new one.' });
  }

  await supabase
    .from('staff')
    .update({ email_verified: true, verification_code: null, verification_code_expires_at: null })
    .eq('id', staffMember.id);

  res.json({ success: true, message: 'Email verified. Your account is now waiting for admin approval.' });
});

// POST /api/accounting/auth/login
router.post('/login', async (req, res) => {
  const { username, password } = req.body;

  if (!username || !password) {
    return res.status(400).json({ error: 'Username and password are required.' });
  }

  const { data: staffMember, error } = await supabase
    .from('staff')
    .select('id, full_name, username, password_hash, role, can_edit_prices, is_active, email_verified, department_id')
    .eq('username', username)
    .single();

  if (error || !staffMember) {
    return res.status(401).json({ error: 'Invalid username or password.' });
  }

  const passwordMatches = await bcrypt.compare(password, staffMember.password_hash);

  if (!passwordMatches) {
    return res.status(401).json({ error: 'Invalid username or password.' });
  }

  if (!staffMember.email_verified) {
    return res.status(403).json({ error: 'Please verify your email before logging in.' });
  }

  if (!staffMember.is_active) {
    return res.status(403).json({ error: 'Your account is awaiting admin approval.' });
  }

  // Store only what we need in the session — never the password hash
  req.session.staff = {
    id: staffMember.id,
    fullName: staffMember.full_name,
    username: staffMember.username,
    role: staffMember.role,
    canEditPrices: staffMember.can_edit_prices,
    departmentId: staffMember.department_id
  };

  res.json({ success: true, staff: req.session.staff });
});

// POST /api/accounting/auth/logout
router.post('/logout', (req, res) => {
  req.session.destroy((err) => {
    if (err) {
      return res.status(500).json({ error: 'Could not log out. Try again.' });
    }
    res.clearCookie('connect.sid');
    res.json({ success: true });
  });
});

// GET /api/accounting/auth/me — used by frontend to check if a session is active
router.get('/me', (req, res) => {
  if (!req.session.staff) {
    return res.status(401).json({ error: 'Not logged in.' });
  }
  res.json({ staff: req.session.staff });
});

module.exports = router;

EOF_SERVER_ROUTES_AUTH_JS

cat > server/routes/admin.js << 'EOF_SERVER_ROUTES_ADMIN_JS'
const express = require('express');
const supabase = require('../config/supabaseClient');

const router = express.Router();

// Only staff with role = 'admin' can reach these routes.
function requireAdmin(req, res, next) {
  if (req.session.staff.role !== 'admin') {
    return res.status(403).json({ error: 'Admin access only.' });
  }
  next();
}

router.use(requireAdmin);

// GET /api/accounting/admin/pending-staff
// Lists everyone who has verified their email but is still waiting on approval.
router.get('/pending-staff', async (req, res) => {
  const { data, error } = await supabase
    .from('staff')
    .select('id, full_name, username, email, created_at')
    .eq('email_verified', true)
    .eq('is_active', false)
    .order('created_at', { ascending: true });

  if (error) {
    return res.status(500).json({ error: 'Could not load pending accounts.' });
  }

  res.json({ pending: data });
});

// POST /api/accounting/admin/approve-staff/:id
router.post('/approve-staff/:id', async (req, res) => {
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

  res.json({ success: true, message: `${data.full_name} has been approved and can now log in.` });
});

module.exports = router;

EOF_SERVER_ROUTES_ADMIN_JS

cat > server/utils/email.js << 'EOF_SERVER_UTILS_EMAIL_JS'
const nodemailer = require('nodemailer');

const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST,
  port: process.env.SMTP_PORT,
  secure: process.env.SMTP_PORT === '465', // true for port 465, false for 587/others
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS
  }
});

async function sendVerificationEmail(toEmail, fullName, code) {
  await transporter.sendMail({
    from: process.env.SMTP_FROM || '"MACDEN Accounting" <no-reply@macden.com.ng>',
    to: toEmail,
    subject: 'Verify your MACDEN Accounting account',
    text: `Hi ${fullName},\n\nYour verification code is: ${code}\n\nThis code expires in 15 minutes.\n\nAfter verifying, your account will still need admin approval before you can log in.`,
    html: `
      <p>Hi ${fullName},</p>
      <p>Your verification code is:</p>
      <p style="font-size: 24px; font-weight: bold; letter-spacing: 4px;">${code}</p>
      <p>This code expires in 15 minutes.</p>
      <p>After verifying, your account will still need admin approval before you can log in.</p>
    `
  });
}

module.exports = { sendVerificationEmail };

EOF_SERVER_UTILS_EMAIL_JS

cat > server/scripts/createStaff.js << 'EOF_SERVER_SCRIPTS_CREATESTAFF_JS'
// Run this from the server folder to add a staff member.
// Usage:  node scripts/createStaff.js
// You'll be prompted for each field — no arguments needed.

require('dotenv').config();
const readline = require('readline');
const bcrypt = require('bcrypt');
const supabase = require('../config/supabaseClient');

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });

function ask(question) {
  return new Promise((resolve) => rl.question(question, resolve));
}

async function main() {
  console.log('--- Add a new accounting staff member ---\n');

  const fullName = await ask('Full name: ');
  const username = await ask('Username: ');
  const email = await ask('Email: ');
  const password = await ask('Temporary password (staff should change this later): ');
  const canEditPricesInput = await ask('Can this person edit prices? (y/N): ');
  const roleInput = await ask('Role — "staff" or "admin" (default: staff): ');

  rl.close();

  const role = roleInput.trim().toLowerCase() === 'admin' ? 'admin' : 'staff';

  const { data: dept, error: deptError } = await supabase
    .from('departments')
    .select('id')
    .eq('slug', 'accounting')
    .single();

  if (deptError || !dept) {
    console.error('Could not find the Accounting department row. Did the schema script run correctly?');
    process.exit(1);
  }

  const passwordHash = await bcrypt.hash(password, 10);

  const { data, error } = await supabase
    .from('staff')
    .insert({
      department_id: dept.id,
      full_name: fullName,
      username: username,
      email: email,
      password_hash: passwordHash,
      role: role,
      email_verified: true,   // trusted, created directly by an admin — skips the signup flow
      is_active: true,        // no approval step needed for admin-created accounts
      can_edit_prices: canEditPricesInput.trim().toLowerCase() === 'y'
    })
    .select()
    .single();

  if (error) {
    console.error('Failed to create staff member:', error.message);
    process.exit(1);
  }

  console.log(`\nStaff member created: ${data.full_name} (${data.username})`);
}

main();

EOF_SERVER_SCRIPTS_CREATESTAFF_JS

echo "All files updated successfully."
echo "Next: cd server && npm install"
echo "Then: fill in the new SMTP_* values in .env (see .env.example)"