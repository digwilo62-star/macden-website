#!/usr/bin/env bash
# Creates the /server backend folder structure for the MACDEN Accounting tool.
# Run this from the ROOT of your macden-website repo, in Git Bash.
set -e

mkdir -p server/config server/routes server/middleware server/scripts

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
    "express-session": "^1.18.0"
  }
}

EOF_SERVER_PACKAGE_JSON

cat > server/.env.example << 'EOF_SERVER__ENV_EXAMPLE'
# Supabase — Project Settings > API
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key-here

# Session secret — any long random string, generate one and never reuse across projects
SESSION_SECRET=replace-this-with-a-long-random-string

# Port Render will inject automatically — this is just the local dev fallback
PORT=3000

EOF_SERVER__ENV_EXAMPLE

cat > server/server.js << 'EOF_SERVER_SERVER_JS'
require('dotenv').config();

const express = require('express');
const session = require('express-session');
const cors = require('cors');

const authRoutes = require('./routes/auth');
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

app.get('/api/accounting/dashboard-check', (req, res) => {
  // Simple proof that requireAuth is working — returns the logged-in staff's info
  res.json({ message: `Welcome, ${req.session.staff.fullName}`, staff: req.session.staff });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Accounting backend running on port ${PORT}`);
});

EOF_SERVER_SERVER_JS

cat > server/config/supabaseClient.js << 'EOF_SERVER_CONFIG_SUPABASECLIENT_JS'
const { createClient } = require('@supabase/supabase-js');

// IMPORTANT: this uses the service_role key, never the anon key.
// This file only ever runs server-side — it must never be imported
// into anything that ships to the browser.
const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY,
  {
    auth: {
      autoRefreshToken: false,
      persistSession: false
    }
  }
);

module.exports = supabase;

EOF_SERVER_CONFIG_SUPABASECLIENT_JS

cat > server/routes/auth.js << 'EOF_SERVER_ROUTES_AUTH_JS'
const express = require('express');
const bcrypt = require('bcrypt');
const supabase = require('../config/supabaseClient');

const router = express.Router();

// POST /api/accounting/auth/login
router.post('/login', async (req, res) => {
  const { username, password } = req.body;

  if (!username || !password) {
    return res.status(400).json({ error: 'Username and password are required.' });
  }

  const { data: staffMember, error } = await supabase
    .from('staff')
    .select('id, full_name, username, password_hash, role, can_edit_prices, is_active, department_id')
    .eq('username', username)
    .single();

  if (error || !staffMember) {
    // Same generic message whether username doesn't exist or password is wrong —
    // don't reveal which one, that's a basic login-security habit worth keeping
    // even though we're deferring the bigger security work.
    return res.status(401).json({ error: 'Invalid username or password.' });
  }

  if (!staffMember.is_active) {
    return res.status(403).json({ error: 'This account has been disabled.' });
  }

  const passwordMatches = await bcrypt.compare(password, staffMember.password_hash);

  if (!passwordMatches) {
    return res.status(401).json({ error: 'Invalid username or password.' });
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

cat > server/middleware/requireAuth.js << 'EOF_SERVER_MIDDLEWARE_REQUIREAUTH_JS'
// Blocks any route from running unless there's an active staff session.
// Use this on every accounting API route except /auth/login.
function requireAuth(req, res, next) {
  if (!req.session || !req.session.staff) {
    return res.status(401).json({ error: 'Please log in to continue.' });
  }
  next();
}

module.exports = requireAuth;

EOF_SERVER_MIDDLEWARE_REQUIREAUTH_JS

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

  rl.close();

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

echo "All server files created successfully."
echo "Next: cd server && npm install"