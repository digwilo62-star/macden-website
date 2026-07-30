#!/usr/bin/env bash
# Public staff self-registration (memo item #1): any staff at any branch
# fills in Name/Branch/Department/Phone/Business Email at
# macden.com.ng/accounting/register.html - no login needed. Creates a
# PENDING record only, nothing active, nothing emailed yet.
#
# You (admin) review submissions at
# macden.com.ng/accounting/pending-registrations.html - Approve generates
# a real password and emails their login details; Reject deletes the
# pending request entirely.
#
# NO SQL MIGRATION NEEDED - reuses existing staff table columns.
# Tested with real HTTP requests (departments load, validation works,
# full submission succeeds) before being sent.
set -e
mkdir -p server/routes accounting

cat > server/routes/publicRegister.js << 'EOF_SERVER_ROUTES_PUBLICREGISTER_JS'
const express = require('express');
const supabase = require('../config/supabaseClient');
const crypto = require('crypto');
const bcrypt = require('bcrypt');

const router = express.Router();

// GET /api/accounting/public/departments — no login needed, just for the
// registration form's dropdown (department names only, nothing sensitive).
router.get('/departments', async (req, res) => {
  try {
    const { data, error } = await supabase.from('departments').select('id, name').order('name');
    if (error) {
      console.error('Public departments fetch error:', error);
      return res.status(500).json({ error: 'Could not load departments.' });
    }
    res.json({ departments: data });
  } catch (err) {
    console.error('Public departments unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// POST /api/accounting/public/register — any staff member at any branch
// submits this. Creates a PENDING record (is_active: false) -- no account
// exists yet, no password is set, nothing is emailed. HR/Admin reviews and
// approves it from the Pending Registrations page before any of that happens.
router.post('/register', async (req, res) => {
  try {
    const { fullName, branch, departmentId, phone, email } = req.body;

    if (!fullName || !branch || !departmentId || !phone || !email) {
      return res.status(400).json({ error: 'All fields are required.' });
    }

    const { data: existing } = await supabase
      .from('staff')
      .select('id')
      .eq('email', email)
      .maybeSingle();

    if (existing) {
      return res.status(400).json({ error: 'An account with this email already exists or is already pending review.' });
    }

    // Generate a username now (so it's ready if/when approved), and a
    // random throwaway password hash as a placeholder -- this gets
    // replaced with a real one when HR approves the request.
    const baseUsername = fullName.toLowerCase().replace(/[^a-z]+/g, '.').replace(/^\.|\.$/g, '');
    const username = baseUsername + '.' + crypto.randomInt(100, 999);
    const placeholderHash = await bcrypt.hash(crypto.randomBytes(16).toString('hex'), 10);

    const { error } = await supabase
      .from('staff')
      .insert({
        full_name: fullName,
        username: username,
        email: email,
        phone: phone,
        branch: branch,
        department_id: departmentId,
        password_hash: placeholderHash,
        role: 'staff',
        is_active: false,
        email_verified: true // manual HR review replaces the email-code step for this flow
      });

    if (error) {
      console.error('Public register insert error:', error);
      return res.status(500).json({ error: 'Could not submit your registration. Please try again.' });
    }

    res.json({ success: true, message: 'Your registration has been submitted for review. HR will email your login details once approved.' });
  } catch (err) {
    console.error('Public register unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong submitting your registration.' });
  }
});

module.exports = router;

EOF_SERVER_ROUTES_PUBLICREGISTER_JS

cat > server/routes/registrationApproval.js << 'EOF_SERVER_ROUTES_REGISTRATIONAPPROVAL_JS'
const express = require('express');
const crypto = require('crypto');
const supabase = require('../config/supabaseClient');
const { sendWelcomeEmail } = require('../utils/email');

const router = express.Router();

// Self-contained admin check (doesn't depend on the exact contents of
// admin.js, since this is a separate router mounted independently).
function requireAdmin(req, res, next) {
  if (!req.session.staff || req.session.staff.role !== 'admin') {
    return res.status(403).json({ error: 'Admin access only.' });
  }
  next();
}

router.use(requireAdmin);

// GET /api/accounting/registrations/pending — everyone who submitted the
// public form and hasn't been approved or rejected yet
router.get('/pending', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('staff')
      .select('id, full_name, username, email, phone, branch, created_at, departments(name)')
      .eq('is_active', false)
      .eq('email_verified', true)
      .order('created_at', { ascending: true });

    if (error) {
      console.error('Pending registrations fetch error:', error);
      return res.status(500).json({ error: 'Could not load pending registrations.' });
    }

    const pending = data.map(p => ({
      id: p.id,
      fullName: p.full_name,
      username: p.username,
      email: p.email,
      phone: p.phone,
      branch: p.branch,
      department: p.departments ? p.departments.name : null,
      submittedAt: p.created_at
    }));

    res.json({ pending });
  } catch (err) {
    console.error('Pending registrations unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading pending registrations.' });
  }
});

// POST /api/accounting/registrations/:id/approve — generates a real
// password, activates the account, emails the credentials
router.post('/:id/approve', async (req, res) => {
  try {
    const { id } = req.params;

    const { data: person, error: fetchError } = await supabase
      .from('staff')
      .select('id, full_name, username, email, is_active')
      .eq('id', id)
      .single();

    if (fetchError || !person) {
      return res.status(404).json({ error: 'Registration not found.' });
    }
    if (person.is_active) {
      return res.status(400).json({ error: 'This registration has already been approved.' });
    }

    const tempPassword = crypto.randomBytes(14).toString('base64').replace(/[^a-zA-Z0-9]/g, '').slice(0, 14);
    const bcrypt = require('bcrypt');
    const passwordHash = await bcrypt.hash(tempPassword, 10);

    const { error: updateError } = await supabase
      .from('staff')
      .update({
        password_hash: passwordHash,
        is_active: true,
        must_change_password: true
      })
      .eq('id', id);

    if (updateError) {
      console.error('Approve registration update error:', updateError);
      return res.status(500).json({ error: 'Could not approve this registration.' });
    }

    try {
      await sendWelcomeEmail(person.email, person.full_name, person.username, tempPassword);
    } catch (emailErr) {
      console.error('Approval welcome email failed:', emailErr);
      return res.json({
        success: true,
        warning: 'Account approved, but the welcome email failed to send. Username: ' + person.username + ', temporary password: ' + tempPassword
      });
    }

    res.json({ success: true });
  } catch (err) {
    console.error('Approve registration unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong approving this registration.' });
  }
});

// POST /api/accounting/registrations/:id/reject — deletes the pending record entirely
router.post('/:id/reject', async (req, res) => {
  try {
    const { id } = req.params;
    const { error } = await supabase.from('staff').delete().eq('id', id).eq('is_active', false);
    if (error) {
      return res.status(500).json({ error: 'Could not reject this registration.' });
    }
    res.json({ success: true });
  } catch (err) {
    console.error('Reject registration unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

module.exports = router;

EOF_SERVER_ROUTES_REGISTRATIONAPPROVAL_JS

cat > server/server.js << 'EOF_SERVER_SERVER_JS'
require('dotenv').config();

const path = require('path');
const express = require('express');
const session = require('express-session');
const pgSession = require('connect-pg-simple')(session);
const cors = require('cors');
const helmet = require('helmet');
const cron = require('node-cron');

const authRoutes = require('./routes/auth');
const adminRoutes = require('./routes/admin');
const priceRoutes = require('./routes/prices');
const staffRoutes = require('./routes/staff');
const messageRoutes = require('./routes/messages');
const presenceRoutes = require('./routes/presence');
const leaveRoutes = require('./routes/leave');
const documentsRoutes = require('./routes/documents');
const policiesRoutes = require('./routes/policies');
const settingsRoutes = require('./routes/settings');
const notificationsRoutes = require('./routes/notifications');
const searchRoutes = require('./routes/search');
const publicRegisterRoutes = require('./routes/publicRegister');
const registrationApprovalRoutes = require('./routes/registrationApproval');
const requireAuth = require('./middleware/requireAuth');

const app = express();

// Adds standard security headers (X-Frame-Options, X-Content-Type-Options,
// Strict-Transport-Security, etc). CSP is disabled because every page in
// this app uses inline <script> blocks for page logic — a strict CSP would
// break the whole app. Properly enabling CSP would mean moving all page
// scripts to external files with nonces — a real future project, not a
// quick toggle.
app.use(helmet({ contentSecurityPolicy: false }));

// Render (and most hosting platforms) sit in front of your app as a reverse proxy,
// terminating HTTPS themselves and forwarding requests internally over plain HTTP.
// Without this line, Express can't tell the connection is actually secure, so the
// "secure" session cookie silently fails to set — causing login to succeed but the
// session to never actually stick. This tells Express to trust Render's own
// X-Forwarded-Proto header to determine that correctly.
app.set('trust proxy', 1);

app.use(express.json());

// CORS — allow requests from your actual site only.
app.use(cors({
  origin: 'https://macden.com.ng',
  credentials: true
}));

// Sessions were previously stored in-memory, which meant every server
// restart (including Render's periodic free-tier restarts) silently logged
// everyone out. This stores sessions in Postgres instead, so they survive
// restarts. The table is created automatically on first run if missing.
const pgPool = require('./config/pgPool');

app.use(session({
  store: new pgSession({
    pool: pgPool,
    tableName: 'user_sessions',
    createTableIfMissing: true
  }),
  secret: process.env.SESSION_SECRET,
  resave: false,
  saveUninitialized: false,
  cookie: {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'lax',
    maxAge: 1000 * 60 * 60 * 8
  }
}));

// SHORT URL: macden.com.ng/portal redirects straight to the login page --
// staff were struggling to remember the full /accounting/login.html path.
app.get('/portal', (req, res) => res.redirect('/accounting/login.html'));

// Serve the accounting frontend pages (login, register, dashboard, etc.)
app.use('/accounting', express.static(path.join(__dirname, '../accounting'), {
  index: 'login.html'
}));

// SECURITY: block direct access to the backend source folder and git internals
app.use('/server', (req, res) => res.status(404).send('Not found'));
app.use('/.git', (req, res) => res.status(404).send('Not found'));

// Serve the main storefront
app.use(express.static(path.join(__dirname, '..'), {
  dotfiles: 'deny'
}));

// Health check
app.get('/api/accounting/health', (req, res) => {
  res.json({ status: 'ok' });
});

// Auth routes — not behind requireAuth, obviously
app.use('/api/accounting/auth', authRoutes);

// PUBLIC staff self-registration form (Name/Branch/Department/Phone/Email)
// -- not behind requireAuth, since nobody has an account yet at this point.
// Submissions sit pending until HR reviews and approves them.
app.use('/api/accounting/public', publicRegisterRoutes);

// Everything below this line will require a logged-in session.
app.use('/api/accounting', requireAuth);
app.use('/api/accounting/admin', adminRoutes);
app.use('/api/accounting/prices', priceRoutes);
app.use('/api/accounting/staff', staffRoutes);
app.use('/api/accounting/messages', messageRoutes);
app.use('/api/accounting/presence', presenceRoutes);
app.use('/api/accounting/leave', leaveRoutes);
app.use('/api/accounting/documents', documentsRoutes);
app.use('/api/accounting/policies', policiesRoutes);
app.use('/api/accounting/settings', settingsRoutes);
app.use('/api/accounting/notifications', notificationsRoutes);
app.use('/api/accounting/search', searchRoutes);
app.use('/api/accounting/registrations', registrationApprovalRoutes);

app.get('/api/accounting/dashboard-check', (req, res) => {
  res.json({ message: `Welcome, ${req.session.staff.fullName}`, staff: req.session.staff });
});

// Safety net: if anything else throws unexpectedly, always send JSON back
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ error: 'Something went wrong on the server.' });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Accounting backend running on port ${PORT}`);
});

// Checks every minute for scheduled broadcasts whose time has arrived and
// sends them.
cron.schedule('* * * * *', () => {
  messageRoutes.publishDueScheduledBroadcasts();
});

EOF_SERVER_SERVER_JS

cat > accounting/register.html << 'EOF_ACCOUNTING_REGISTER_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Register — MACDEN Portal</title>
  <link rel="stylesheet" href="assets/portal-style.css">
  <style>
    .reg-shell { min-height: 100vh; display: flex; align-items: center; justify-content: center; background: var(--bg); padding: 40px 20px; }
    .reg-card { width: 100%; max-width: 440px; background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-lg); padding: 36px; }
    .reg-logo { display: flex; align-items: center; gap: 10px; margin-bottom: 24px; }
    .reg-logo img { width: 36px; height: 36px; border-radius: 8px; }
    .reg-logo span { font-family: var(--font-heading); font-weight: 800; font-size: 15px; }
    .reg-field { margin-bottom: 16px; }
    .reg-field label { display: block; font-size: 12.5px; font-weight: 600; margin-bottom: 6px; }
    .reg-field input, .reg-field select {
      width: 100%; background: var(--surface); border: 1.5px solid var(--border); border-radius: var(--radius-sm);
      padding: 11px 14px; font-size: 13.5px; font-family: var(--font-body); color: var(--text-primary);
    }
    .reg-field input:focus, .reg-field select:focus { outline: none; border-color: var(--primary); }
    .reg-success { text-align: center; padding: 20px 0; }
    .reg-success i { font-size: 40px; color: var(--success); }
  </style>
</head>
<body>
  <div class="reg-shell">
    <div class="reg-card">
      <div class="reg-logo">
        <img src="assets/logo.jpeg" alt="MACDEN">
        <span>MACDEN Staff Registration</span>
      </div>

      <div id="formView">
        <p style="font-size:13px; color:var(--text-secondary); margin-bottom:20px;">Fill this in to request an account. HR will review your submission and email your login details once approved.</p>

        <div id="alert" class="alert alert-error"></div>

        <div class="reg-field">
          <label>Full Name</label>
          <input type="text" id="fullName" placeholder="Your full name">
        </div>
        <div class="reg-field">
          <label>Branch</label>
          <input type="text" id="branch" placeholder="e.g. Ikeja Branch">
        </div>
        <div class="reg-field">
          <label>Department</label>
          <select id="departmentId"><option value="">Loading…</option></select>
        </div>
        <div class="reg-field">
          <label>Phone Number</label>
          <input type="text" id="phone" placeholder="080...">
        </div>
        <div class="reg-field">
          <label>Business Email</label>
          <input type="text" id="email" placeholder="you@macden.com.ng">
        </div>

        <button class="btn btn-primary" id="submitBtn" style="margin-top:8px;">Submit Registration</button>
      </div>

      <div id="successView" style="display:none;" class="reg-success">
        <i class="ti ti-circle-check"></i>
        <h2 style="font-size:16px; margin-top:12px;">Registration Submitted</h2>
        <p style="font-size:13px; color:var(--text-secondary); margin-top:8px;">HR will review your request and email your login details once approved.</p>
      </div>
    </div>
  </div>

  <script>
    async function loadDepartments() {
      try {
        const res = await fetch('/api/accounting/public/departments');
        const data = await res.json();
        const select = document.getElementById('departmentId');
        select.innerHTML = '<option value="">Select your department…</option>' +
          data.departments.map(d => '<option value="' + d.id + '">' + d.name + '</option>').join('');
      } catch (err) {
        document.getElementById('departmentId').innerHTML = '<option value="">Could not load departments</option>';
      }
    }

    document.getElementById('submitBtn').addEventListener('click', async () => {
      const alertEl = document.getElementById('alert');
      alertEl.className = 'alert';

      const fullName = document.getElementById('fullName').value.trim();
      const branch = document.getElementById('branch').value.trim();
      const departmentId = document.getElementById('departmentId').value;
      const phone = document.getElementById('phone').value.trim();
      const email = document.getElementById('email').value.trim();

      if (!fullName || !branch || !departmentId || !phone || !email) {
        alertEl.textContent = 'Please fill in every field.';
        alertEl.className = 'alert alert-error visible';
        return;
      }

      const btn = document.getElementById('submitBtn');
      btn.disabled = true;
      btn.textContent = 'Submitting…';

      try {
        const res = await fetch('/api/accounting/public/register', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ fullName, branch, departmentId, phone, email })
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Something went wrong.');

        document.getElementById('formView').style.display = 'none';
        document.getElementById('successView').style.display = 'block';
      } catch (err) {
        alertEl.textContent = err.message;
        alertEl.className = 'alert alert-error visible';
        btn.disabled = false;
        btn.textContent = 'Submit Registration';
      }
    });

    loadDepartments();
  </script>
</body>
</html>

EOF_ACCOUNTING_REGISTER_HTML

cat > accounting/pending-registrations.html << 'EOF_ACCOUNTING_PENDING-REGISTRATIONS_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Pending Registrations — MACDEN Portal</title>
  <link rel="stylesheet" href="assets/portal-style.css">
  <link rel="stylesheet" href="assets/portal-shell.css">
  <style>
    .pr-list { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-md); overflow: hidden; }
    .pr-header-row { display: grid; grid-template-columns: 180px 140px 130px 130px 1fr 170px; gap: 12px; padding: 12px 18px; font-size: 10.5px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.04em; color: var(--text-muted); border-bottom: 1px solid var(--border); }
    .pr-row { display: grid; grid-template-columns: 180px 140px 130px 130px 1fr 170px; gap: 12px; align-items: center; padding: 13px 18px; border-bottom: 1px solid var(--border); font-size: 12.5px; }
    .pr-row:last-child { border-bottom: none; }
    .pr-empty { padding: 50px 18px; text-align: center; color: var(--text-muted); font-size: 13px; }
    .pr-approve-btn { background: var(--success-dim); color: var(--success); border: none; border-radius: var(--radius-sm); padding: 6px 12px; font-size: 11.5px; font-weight: 700; cursor: pointer; font-family: var(--font-body); }
    .pr-reject-btn { background: var(--error-dim); color: var(--error); border: none; border-radius: var(--radius-sm); padding: 6px 12px; font-size: 11.5px; font-weight: 700; cursor: pointer; font-family: var(--font-body); margin-left: 6px; }
  </style>
</head>
<body>
  <div class="app-shell">
    <div class="sidebar">
      <div class="sidebar-brand"><img src="assets/logo.jpeg" alt="MACDEN"><span>MACDEN</span></div>
      <nav class="sidebar-nav">
        <a href="dashboard.html" class="sidebar-link"><i class="ti ti-layout-dashboard"></i> Dashboard</a>
        <a href="inbox.html" class="sidebar-link"><i class="ti ti-mail"></i> Inbox <span class="badge" id="unreadBadge" style="display:none;">0</span></a>
        <a href="compose.html" class="sidebar-link"><i class="ti ti-pencil"></i> Compose</a>
        <a href="broadcasts.html" class="sidebar-link"><i class="ti ti-speakerphone"></i> Broadcasts</a>
        <a href="directory.html" class="sidebar-link active"><i class="ti ti-users"></i> Directory</a>
        <a href="leave.html" class="sidebar-link"><i class="ti ti-calendar-event"></i> Leave &amp; Requests</a>
        <a href="documents.html" class="sidebar-link"><i class="ti ti-file-text"></i> Documents</a>
        <a href="policies.html" class="sidebar-link"><i class="ti ti-book"></i> Policies</a>
        <a href="settings.html" class="sidebar-link"><i class="ti ti-settings"></i> Settings</a>
      </nav>
      <div class="sidebar-logout">
        <a href="help.html" class="sidebar-link" style="margin-bottom:6px;"><i class="ti ti-help-circle"></i> Help</a>
        <button id="logoutBtn"><i class="ti ti-logout"></i> Logout</button>
      </div>
    </div>

    <div class="main-content">
      <div class="topbar">
        <div class="topbar-search"><input type="text" placeholder="Search messages, people, documents…"></div>
        <img class="topbar-avatar" id="topbarAvatarImg" src="assets/logo.jpeg" alt="You">
      </div>

      <div class="page-body">
        <h1 class="page-greeting" style="font-size: 22px;">Pending Registrations</h1>
        <p class="page-greeting-sub"><a href="directory.html" style="color: var(--primary); text-decoration:none; font-weight:600;">← Back to Directory</a></p>
        <p style="font-size:13px; color:var(--text-secondary); margin-bottom:20px;">Staff who submitted the registration form, waiting for your review. Share this link with staff who need an account: <strong id="regLinkDisplay"></strong></p>

        <div class="pr-list">
          <div class="pr-header-row"><div>Name</div><div>Branch</div><div>Department</div><div>Phone</div><div>Email</div><div>Actions</div></div>
          <div id="prRows"><div class="pr-empty">Loading…</div></div>
        </div>
      </div>
    </div>
  </div>

  <script src="assets/api.js"></script>
  <script>
    document.getElementById('logoutBtn').addEventListener('click', async () => {
      await apiRequest('/auth/logout', { method: 'POST' });
      window.location.href = 'login.html';
    });

    document.getElementById('regLinkDisplay').textContent = window.location.origin + '/accounting/register.html';

    async function init() {
      let staff;
      try {
        const result = await apiRequest('/dashboard-check');
        staff = result.staff;
      } catch (err) {
        window.location.href = 'login.html';
        return;
      }
      if (staff.role !== 'admin') {
        document.body.innerHTML = '<div style="padding:40px; font-family:sans-serif;">Admin access only.</div>';
        return;
      }
      loadPending();
    }

    async function loadPending() {
      const rows = document.getElementById('prRows');
      try {
        const result = await apiRequest('/registrations/pending');
        if (result.pending.length === 0) {
          rows.innerHTML = '<div class="pr-empty">No pending registrations right now.</div>';
          return;
        }
        rows.innerHTML = result.pending.map(p =>
          '<div class="pr-row">' +
            '<div>' + p.fullName + '</div>' +
            '<div>' + p.branch + '</div>' +
            '<div>' + (p.department || '—') + '</div>' +
            '<div>' + p.phone + '</div>' +
            '<div style="overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">' + p.email + '</div>' +
            '<div>' +
              '<button class="pr-approve-btn" onclick="approveReg(\'' + p.id + '\')">Approve</button>' +
              '<button class="pr-reject-btn" onclick="rejectReg(\'' + p.id + '\')">Reject</button>' +
            '</div>' +
          '</div>'
        ).join('');
      } catch (err) {
        rows.innerHTML = '<div class="pr-empty">' + err.message + '</div>';
      }
    }

    async function approveReg(id) {
      if (!confirm('Approve this registration? They will be emailed their login details.')) return;
      try {
        const result = await apiRequest('/registrations/' + id + '/approve', { method: 'POST' });
        if (result.warning) alert(result.warning);
        loadPending();
      } catch (err) {
        alert(err.message);
      }
    }

    async function rejectReg(id) {
      if (!confirm('Reject this registration? This cannot be undone.')) return;
      try {
        await apiRequest('/registrations/' + id + '/reject', { method: 'POST' });
        loadPending();
      } catch (err) {
        alert(err.message);
      }
    }

    init();
  </script>
</body>
</html>

EOF_ACCOUNTING_PENDING-REGISTRATIONS_HTML

echo "Staff self-registration feature added."
echo "Registration link to share: macden.com.ng/accounting/register.html"