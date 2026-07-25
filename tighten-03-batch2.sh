#!/usr/bin/env bash
# TIGHTENING BATCH 3: Dependabot config, admin action audit logging (a
# real bug was caught here - the deactivate route had NO error handling
# at all despite an earlier audit claiming it did), 'log out of all
# devices', and deactivated-staff flagging on pending leave requests.
# RUN THE SQL MIGRATION FIRST in Supabase before running this script.
# Run this from the ROOT of your macden-website repo, in Git Bash.
set -e

mkdir -p .github server/config server/routes accounting

cat > .github/dependabot.yml << 'EOF__GITHUB_DEPENDABOT_YML'
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/server"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 5

EOF__GITHUB_DEPENDABOT_YML

cat > server/server.js << 'EOF_SERVER_SERVER_JS'
require('dotenv').config();

const path = require('path');
const express = require('express');
const session = require('express-session');
const pgSession = require('connect-pg-simple')(session);
const cors = require('cors');
const helmet = require('helmet');

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
// If the accounting pages are served from the same domain (macden.com.ng/accounting),
// this can be tightened further. Update the origin below to match your real domain.
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
    secure: process.env.NODE_ENV === 'production', // HTTPS required only in production
    sameSite: 'lax',
    maxAge: 1000 * 60 * 60 * 8   // 8-hour session, adjust as needed
  }
}));

// Serve the accounting frontend pages (login, register, dashboard, etc.)
// Lives in a sibling folder: macden-website/accounting
app.use('/accounting', express.static(path.join(__dirname, '../accounting')));

// SECURITY: block direct access to the backend source folder and git internals
// before the general static server below, which would otherwise happily serve
// server.js, .env, and everything else in /server to anyone who requests it.
app.use('/server', (req, res) => res.status(404).send('Not found'));
app.use('/.git', (req, res) => res.status(404).send('Not found'));

// Serve the main storefront (index.html, about.html, products.html, etc.)
// Lives at the repo root, one level up from /server
app.use(express.static(path.join(__dirname, '..'), {
  dotfiles: 'deny' // extra safety net: never serve any dotfile (.env, .git, .gitignore, etc.)
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
app.use('/api/accounting/prices', priceRoutes);
app.use('/api/accounting/staff', staffRoutes);
app.use('/api/accounting/messages', messageRoutes);
app.use('/api/accounting/presence', presenceRoutes);
app.use('/api/accounting/leave', leaveRoutes);
app.use('/api/accounting/documents', documentsRoutes);
app.use('/api/accounting/policies', policiesRoutes);
app.use('/api/accounting/settings', settingsRoutes);
app.use('/api/accounting/notifications', notificationsRoutes);

app.get('/api/accounting/dashboard-check', (req, res) => {
  // Simple proof that requireAuth is working — returns the logged-in staff's info
  res.json({ message: `Welcome, ${req.session.staff.fullName}`, staff: req.session.staff });
});

// Safety net: if anything else throws unexpectedly, always send JSON back —
// never Express's default HTML error page, which is what breaks the frontend
// (it expects to parse every API response as JSON).
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ error: 'Something went wrong on the server.' });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Accounting backend running on port ${PORT}`);
});

EOF_SERVER_SERVER_JS

cat > server/config/pgPool.js << 'EOF_SERVER_CONFIG_PGPOOL_JS'
const { Pool } = require('pg');

// Shared Postgres connection pool -- used by the session store (server.js)
// and anywhere else that needs a direct query against the sessions table,
// like "log out of all devices" in settings.js.
const pgPool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false } // required for Supabase's connection pooler
});

module.exports = pgPool;

EOF_SERVER_CONFIG_PGPOOL_JS

cat > server/routes/admin.js << 'EOF_SERVER_ROUTES_ADMIN_JS'
const express = require('express');
const bcrypt = require('bcrypt');
const crypto = require('crypto');
const supabase = require('../config/supabaseClient');
const { sendWelcomeEmail } = require('../utils/email');

const router = express.Router();

// Only staff with role = 'admin' can reach these routes.
function requireAdmin(req, res, next) {
  if (req.session.staff.role !== 'admin') {
    return res.status(403).json({ error: 'Admin access only.' });
  }
  next();
}

// Logs sensitive admin actions (who did what, when, from where) — closes the
// "who touched HR data" gap flagged when NIN/address fields were first added.
// Fire-and-forget: a logging failure should never block the actual action.
function logAdminAction(req, action, targetId, details) {
  supabase
    .from('admin_audit_log')
    .insert({
      staff_id: req.session.staff.id,
      action,
      target_id: targetId ? String(targetId) : null,
      details: details || null,
      ip_address: req.ip || req.headers['x-forwarded-for'] || null
    })
    .then(({ error }) => {
      if (error) console.error('Audit log insert failed:', error);
    });
}

router.use(requireAdmin);

// GET /api/accounting/admin/departments — for the onboarding Work Info dropdown
router.get('/departments', async (req, res) => {
  try {
    const { data, error } = await supabase.from('departments').select('id, name').order('name');
    if (error) {
      return res.status(500).json({ error: 'Could not load departments.' });
    }
    res.json({ departments: data });
  } catch (err) {
    console.error('Departments fetch error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// GET /api/accounting/admin/all-staff — everyone including inactive, for Manage Staff
router.get('/all-staff', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('staff')
      .select('id, full_name, username, email, role, phone, branch, is_active, created_at, departments(name)')
      .order('full_name');

    if (error) {
      console.error('All-staff fetch error:', error);
      return res.status(500).json({ error: 'Could not load staff.' });
    }

    const staff = data.map(s => ({
      id: s.id,
      fullName: s.full_name,
      username: s.username,
      email: s.email,
      role: s.role,
      phone: s.phone,
      branch: s.branch,
      department: s.departments ? s.departments.name : null,
      isActive: s.is_active,
      dateStarted: s.created_at
    }));

    res.json({ staff });
  } catch (err) {
    console.error('All-staff unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading staff.' });
  }
});

// POST /api/accounting/admin/onboard-staff — HR-initiated account creation
router.post('/onboard-staff', async (req, res) => {
  try {
    const { fullName, email, phone, nin, address, role, departmentId, branch, dateStarted, reportsTo } = req.body;

    if (!fullName || !email || !role || !departmentId) {
      return res.status(400).json({ error: 'Full name, email, role, and department are required.' });
    }

    // Generate a username from the name, and a random temporary password
    const baseUsername = fullName.toLowerCase().replace(/[^a-z]+/g, '.').replace(/^\.|\.$/g, '');
    const username = baseUsername + '.' + crypto.randomInt(100, 999);
    // Longer temp password (was 10 chars, now 14) — generate extra bytes
    // since base64/alphanumeric stripping shrinks the usable length.
    const tempPassword = crypto.randomBytes(14).toString('base64').replace(/[^a-zA-Z0-9]/g, '').slice(0, 14);
    const passwordHash = await bcrypt.hash(tempPassword, 10);

    const { data, error } = await supabase
      .from('staff')
      .insert({
        full_name: fullName,
        username: username,
        email: email,
        password_hash: passwordHash,
        role: role,
        department_id: departmentId,
        phone: phone || null,
        nin: nin || null,
        address: address || null,
        branch: branch || null,
        reports_to: reportsTo || null,
        email_verified: true,  // HR-created accounts are trusted, skip the self-signup flow
        is_active: true,
        must_change_password: true
      })
      .select()
      .single();

    if (error) {
      console.error('Onboard staff insert error:', error);
      return res.status(400).json({ error: 'Could not create account. Email may already be in use.' });
    }

    try {
      await sendWelcomeEmail(email, fullName, username, tempPassword);
    } catch (emailErr) {
      console.error('Welcome email failed:', emailErr);
      // Account was created successfully even if the email failed — tell the admin so they can share credentials manually
      return res.json({
        success: true,
        staff: data,
        warning: 'Account created, but the welcome email failed to send. Username: ' + username + ', temporary password: ' + tempPassword
      });
    }

    logAdminAction(req, 'onboard_staff', data.id, `Created account for ${fullName} (${email})`);
    res.json({ success: true, staff: data });
  } catch (err) {
    console.error('Onboard staff unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong creating this account.' });
  }
});

// PUT /api/accounting/admin/staff/:id — edit an existing staff member
router.put('/staff/:id', async (req, res) => {
  try {
    const { fullName, role, departmentId, phone, branch } = req.body;

    const { error } = await supabase
      .from('staff')
      .update({
        full_name: fullName,
        role: role,
        department_id: departmentId,
        phone: phone || null,
        branch: branch || null
      })
      .eq('id', req.params.id);

    if (error) {
      return res.status(500).json({ error: 'Could not update this account.' });
    }
    logAdminAction(req, 'edit_staff', req.params.id, `Updated profile fields (role/department/phone/branch)`);
    res.json({ success: true });
  } catch (err) {
    console.error('Staff edit unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// POST /api/accounting/admin/staff/:id/reactivate
router.post('/staff/:id/reactivate', async (req, res) => {
  try {
    const { error } = await supabase.from('staff').update({ is_active: true }).eq('id', req.params.id);
    if (error) {
      return res.status(500).json({ error: 'Could not reactivate this account.' });
    }
    logAdminAction(req, 'reactivate_staff', req.params.id, 'Reactivated account');
    res.json({ success: true });
  } catch (err) {
    console.error('Reactivate unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// GET /api/accounting/admin/pending-staff
// Lists everyone who has verified their email but is still waiting on approval.
router.get('/pending-staff', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('staff')
      .select('id, full_name, username, email, created_at')
      .eq('email_verified', true)
      .eq('is_active', false)
      .order('created_at', { ascending: true });

    if (error) {
      console.error('Pending staff fetch error:', error);
      return res.status(500).json({ error: 'Could not load pending accounts.' });
    }

    res.json({ pending: data });
  } catch (err) {
    console.error('Pending staff unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// POST /api/accounting/admin/approve-staff/:id
router.post('/approve-staff/:id', async (req, res) => {
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

    logAdminAction(req, 'approve_staff', id, `Approved ${data.full_name}`);
    res.json({ success: true, message: `${data.full_name} has been approved and can now log in.` });
  } catch (err) {
    console.error('Approve staff unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong approving this account.' });
  }
});

// DELETE /api/accounting/admin/staff/:id
// Deactivates a staff member (soft-disable, not a hard delete — their past
// messages and price edits stay intact) and clears any shared conversation
// with the admin performing this action.
router.delete('/staff/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const adminId = req.session.staff.id;

    if (id === adminId) {
      return res.status(400).json({ error: 'You cannot deactivate your own account.' });
    }

    const { data: targetMemberships } = await supabase
      .from('conversation_members')
      .select('conversation_id')
      .eq('staff_id', id);

    const { data: adminMemberships } = await supabase
      .from('conversation_members')
      .select('conversation_id')
      .eq('staff_id', adminId);

    const targetIds = new Set((targetMemberships || []).map(m => m.conversation_id));
    const sharedConversationIds = (adminMemberships || [])
      .map(m => m.conversation_id)
      .filter(convId => targetIds.has(convId));

    if (sharedConversationIds.length > 0) {
      // Cascade delete handles conversation_members, messages, and message_reads automatically
      await supabase.from('conversations').delete().in('id', sharedConversationIds);
    }

    const { error } = await supabase
      .from('staff')
      .update({ is_active: false })
      .eq('id', id);

    if (error) {
      console.error('Deactivate staff error:', error);
      return res.status(500).json({ error: 'Could not deactivate this account.' });
    }

    logAdminAction(req, 'deactivate_staff', id, 'Deactivated account');
    res.json({ success: true });
  } catch (err) {
    console.error('Deactivate staff unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong deactivating this account.' });
  }
});

module.exports = router;

EOF_SERVER_ROUTES_ADMIN_JS

cat > server/routes/settings.js << 'EOF_SERVER_ROUTES_SETTINGS_JS'
const express = require('express');
const bcrypt = require('bcrypt');
const supabase = require('../config/supabaseClient');
const pgPool = require('../config/pgPool');

const router = express.Router();

// GET /api/accounting/settings/me — full profile for the Settings page
router.get('/me', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('staff')
      .select('id, full_name, username, email, role, bio, created_at, departments(name), notify_email_broadcasts, notify_email_messages, notify_desktop')
      .eq('id', req.session.staff.id)
      .single();

    if (error) {
      console.error('Settings fetch error:', error);
      return res.status(500).json({ error: 'Could not load your profile.' });
    }

    res.json({
      profile: {
        fullName: data.full_name,
        username: data.username,
        email: data.email,
        role: data.role,
        department: data.departments ? data.departments.name : null,
        bio: data.bio,
        dateJoined: data.created_at,
        notifyEmailBroadcasts: data.notify_email_broadcasts,
        notifyEmailMessages: data.notify_email_messages,
        notifyDesktop: data.notify_desktop
      }
    });
  } catch (err) {
    console.error('Settings fetch unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading your profile.' });
  }
});

// PUT /api/accounting/settings/profile — only bio is editable by the staff member themselves
router.put('/profile', async (req, res) => {
  try {
    const { bio } = req.body;

    const { error } = await supabase
      .from('staff')
      .update({ bio: bio || null })
      .eq('id', req.session.staff.id);

    if (error) {
      return res.status(500).json({ error: 'Could not update your profile.' });
    }
    res.json({ success: true });
  } catch (err) {
    console.error('Profile update unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong updating your profile.' });
  }
});

// PUT /api/accounting/settings/notifications
router.put('/notifications', async (req, res) => {
  try {
    const { notifyEmailBroadcasts, notifyEmailMessages, notifyDesktop } = req.body;

    const { error } = await supabase
      .from('staff')
      .update({
        notify_email_broadcasts: !!notifyEmailBroadcasts,
        notify_email_messages: !!notifyEmailMessages,
        notify_desktop: !!notifyDesktop
      })
      .eq('id', req.session.staff.id);

    if (error) {
      return res.status(500).json({ error: 'Could not update notification preferences.' });
    }
    res.json({ success: true });
  } catch (err) {
    console.error('Notifications update unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// PUT /api/accounting/settings/password — real password change
router.put('/password', async (req, res) => {
  try {
    const { currentPassword, newPassword } = req.body;

    if (!currentPassword || !newPassword) {
      return res.status(400).json({ error: 'Current and new password are required.' });
    }
    if (newPassword.length < 8) {
      return res.status(400).json({ error: 'New password must be at least 8 characters.' });
    }

    const { data: staffMember, error: fetchError } = await supabase
      .from('staff')
      .select('password_hash')
      .eq('id', req.session.staff.id)
      .single();

    if (fetchError || !staffMember) {
      return res.status(500).json({ error: 'Could not verify your account.' });
    }

    const matches = await bcrypt.compare(currentPassword, staffMember.password_hash);
    if (!matches) {
      return res.status(401).json({ error: 'Current password is incorrect.' });
    }

    const newHash = await bcrypt.hash(newPassword, 10);
    const { error: updateError } = await supabase
      .from('staff')
      .update({ password_hash: newHash, must_change_password: false })
      .eq('id', req.session.staff.id);

    if (updateError) {
      return res.status(500).json({ error: 'Could not update your password.' });
    }

    // Clear the forced-change flag in the session too, so the frontend
    // stops redirecting immediately without needing a fresh login.
    req.session.staff.mustChangePassword = false;

    res.json({ success: true });
  } catch (err) {
    console.error('Password change unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong changing your password.' });
  }
});

// POST /api/accounting/settings/logout-all-devices
// Deletes every session row belonging to this person from the Postgres
// session store, forcing every logged-in device/browser to be signed out.
// Their CURRENT session is deleted too, so they'll need to log back in here as well.
router.post('/logout-all-devices', async (req, res) => {
  try {
    const staffId = req.session.staff.id;

    await pgPool.query(
      `DELETE FROM user_sessions WHERE sess::jsonb -> 'staff' ->> 'id' = $1`,
      [staffId]
    );

    res.json({ success: true });
  } catch (err) {
    console.error('Logout-all-devices unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong logging out other devices.' });
  }
});

module.exports = router;

EOF_SERVER_ROUTES_SETTINGS_JS

cat > server/routes/leave.js << 'EOF_SERVER_ROUTES_LEAVE_JS'
const express = require('express');
const supabase = require('../config/supabaseClient');

const router = express.Router();

function daysBetween(startDate, endDate) {
  const start = new Date(startDate);
  const end = new Date(endDate);
  const diffMs = end - start;
  return Math.round(diffMs / (1000 * 60 * 60 * 24)) + 1; // inclusive of both days
}

// POST /api/accounting/leave — submit a new leave request
router.post('/', async (req, res) => {
  try {
    const { leaveType, startDate, endDate, reason } = req.body;
    const staffId = req.session.staff.id;

    if (!leaveType || !startDate || !endDate) {
      return res.status(400).json({ error: 'Leave type, start date, and end date are required.' });
    }

    if (new Date(endDate) < new Date(startDate)) {
      return res.status(400).json({ error: 'End date cannot be before start date.' });
    }

    const { data, error } = await supabase
      .from('leave_requests')
      .insert({
        staff_id: staffId,
        leave_type: leaveType,
        start_date: startDate,
        end_date: endDate,
        reason: reason || null
      })
      .select()
      .single();

    if (error) {
      console.error('Leave request insert error:', error);
      return res.status(500).json({ error: 'Could not submit leave request.' });
    }

    res.json({ success: true, request: data });
  } catch (err) {
    console.error('Leave submit unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong submitting your request.' });
  }
});

// GET /api/accounting/leave/mine — this staff member's own requests
router.get('/mine', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('leave_requests')
      .select('id, leave_type, start_date, end_date, reason, status, requested_at')
      .eq('staff_id', req.session.staff.id)
      .order('requested_at', { ascending: false });

    if (error) {
      console.error('Leave mine fetch error:', error);
      return res.status(500).json({ error: 'Could not load your requests.' });
    }

    const withDays = data.map(r => ({ ...r, days: daysBetween(r.start_date, r.end_date) }));
    res.json({ requests: withDays });
  } catch (err) {
    console.error('Leave mine unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading your requests.' });
  }
});

// GET /api/accounting/leave/pending — admin-only, everyone's pending requests
router.get('/pending', async (req, res) => {
  try {
    if (req.session.staff.role !== 'admin') {
      return res.status(403).json({ error: 'Only admins can view pending approvals.' });
    }

    const { data, error } = await supabase
      .from('leave_requests')
      .select('id, staff_id, leave_type, start_date, end_date, reason, status, requested_at')
      .eq('status', 'pending')
      .order('requested_at', { ascending: true });

    if (error) {
      console.error('Leave pending fetch error:', error);
      return res.status(500).json({ error: 'Could not load pending requests.' });
    }

    const staffIds = [...new Set(data.map(r => r.staff_id))];
    const { data: staffRows } = await supabase
      .from('staff')
      .select('id, full_name, username, is_active')
      .in('id', staffIds.length > 0 ? staffIds : ['00000000-0000-0000-0000-000000000000']);
    const staffById = {};
    (staffRows || []).forEach(s => { staffById[s.id] = s; });

    const enriched = data.map(r => ({
      ...r,
      days: daysBetween(r.start_date, r.end_date),
      staffName: staffById[r.staff_id] ? staffById[r.staff_id].full_name : 'Unknown',
      staffUsername: staffById[r.staff_id] ? staffById[r.staff_id].username : '',
      staffIsActive: staffById[r.staff_id] ? staffById[r.staff_id].is_active : true
    }));

    res.json({ requests: enriched });
  } catch (err) {
    console.error('Leave pending unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading pending requests.' });
  }
});

// POST /api/accounting/leave/:id/approve — admin-only
router.post('/:id/approve', async (req, res) => {
  try {
    if (req.session.staff.role !== 'admin') {
      return res.status(403).json({ error: 'Only admins can approve requests.' });
    }

    const { error } = await supabase
      .from('leave_requests')
      .update({ status: 'approved', reviewed_by: req.session.staff.id, reviewed_at: new Date().toISOString() })
      .eq('id', req.params.id);

    if (error) {
      return res.status(500).json({ error: 'Could not approve this request.' });
    }
    res.json({ success: true });
  } catch (err) {
    console.error('Leave approve unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// POST /api/accounting/leave/:id/reject — admin-only
router.post('/:id/reject', async (req, res) => {
  try {
    if (req.session.staff.role !== 'admin') {
      return res.status(403).json({ error: 'Only admins can reject requests.' });
    }

    const { error } = await supabase
      .from('leave_requests')
      .update({ status: 'rejected', reviewed_by: req.session.staff.id, reviewed_at: new Date().toISOString() })
      .eq('id', req.params.id);

    if (error) {
      return res.status(500).json({ error: 'Could not reject this request.' });
    }
    res.json({ success: true });
  } catch (err) {
    console.error('Leave reject unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

module.exports = router;

EOF_SERVER_ROUTES_LEAVE_JS

cat > accounting/settings.html << 'EOF_ACCOUNTING_SETTINGS_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Settings — MACDEN Portal</title>
  <link rel="stylesheet" href="assets/portal-style.css">
  <link rel="stylesheet" href="assets/portal-shell.css">
  <link rel="stylesheet" href="assets/portal-inbox.css">
  <style>
    .set-panel { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-md); padding: 24px; margin-bottom: 20px; max-width: 640px; }
    .set-panel h2 { font-size: 15px; margin-bottom: 4px; }
    .set-panel .sub { font-size: 12.5px; color: var(--text-secondary); margin-bottom: 18px; }

    .set-avatar-row { display: flex; align-items: center; gap: 16px; margin-bottom: 20px; }
    .set-avatar { width: 64px; height: 64px; border-radius: 50%; background: var(--gold-dim); color: #a17a00; display: flex; align-items: center; justify-content: center; font-size: 22px; font-weight: 700; }

    .set-field-row { display: flex; justify-content: space-between; padding: 10px 0; border-bottom: 1px solid var(--border); font-size: 13px; }
    .set-field-row:last-child { border-bottom: none; }
    .set-field-label { color: var(--text-secondary); }
    .set-field-value { color: var(--text-primary); font-weight: 500; }

    .set-locked-note { background: var(--gold-dim); color: #8a6d00; padding: 10px 14px; border-radius: var(--radius-sm); font-size: 12px; margin-top: 14px; }

    .set-toggle-row { display: flex; justify-content: space-between; align-items: center; padding: 12px 0; border-bottom: 1px solid var(--border); }
    .set-toggle-row:last-child { border-bottom: none; }
    .set-toggle-row .label { font-size: 13px; font-weight: 500; color: var(--text-primary); }
    .set-toggle-row .desc { font-size: 11.5px; color: var(--text-muted); }
    .set-toggle { position: relative; width: 40px; height: 22px; border-radius: 999px; border: none; cursor: pointer; background: var(--border); flex-shrink: 0; }
    .set-toggle.on { background: var(--primary); }
    .set-toggle .knob { position: absolute; top: 2px; left: 2px; width: 18px; height: 18px; border-radius: 50%; background: #fff; transition: left 0.15s ease; }
    .set-toggle.on .knob { left: 20px; }

    .set-appearance-row { display: flex; gap: 10px; }
    .set-appearance-btn { flex: 1; padding: 12px; border-radius: var(--radius-sm); border: 1.5px solid var(--border); text-align: center; font-size: 12.5px; font-weight: 600; cursor: pointer; background: var(--surface); color: var(--text-primary); }
    .set-appearance-btn.active { border-color: var(--primary); background: var(--primary-dim); color: var(--primary); }
    .set-appearance-btn.disabled { opacity: 0.5; cursor: not-allowed; }
  </style>
</head>
<body>
  <div class="app-shell">
    <div class="sidebar">
      <div class="sidebar-brand">
        <img src="assets/logo.jpeg" alt="MACDEN">
        <span>MACDEN</span>
      </div>
      <nav class="sidebar-nav">
        <a href="dashboard.html" class="sidebar-link"><i class="ti ti-layout-dashboard"></i> Dashboard</a>
        <a href="inbox.html" class="sidebar-link"><i class="ti ti-mail"></i> Inbox <span class="badge" id="unreadBadge" style="display:none;">0</span></a>
        <a href="compose.html" class="sidebar-link"><i class="ti ti-pencil"></i> Compose</a>
        <a href="broadcasts.html" class="sidebar-link"><i class="ti ti-speakerphone"></i> Broadcasts</a>
        <a href="directory.html" class="sidebar-link"><i class="ti ti-users"></i> Directory</a>
        <a href="leave.html" class="sidebar-link"><i class="ti ti-calendar-event"></i> Leave &amp; Requests</a>
        <a href="documents.html" class="sidebar-link"><i class="ti ti-file-text"></i> Documents</a>
        <a href="policies.html" class="sidebar-link"><i class="ti ti-book"></i> Policies</a>
        <a href="settings.html" class="sidebar-link active"><i class="ti ti-settings"></i> Settings</a>
      </nav>
      <div class="sidebar-logout">
        <button id="logoutBtn"><i class="ti ti-logout"></i> Logout</button>
      </div>
    </div>

    <div class="main-content">
      <div class="topbar">
        <div class="topbar-search"><input type="text" placeholder="Search messages, people, documents…"></div>
        <div class="notif-wrap">
          <button class="topbar-bell" id="notifBell" aria-label="Notifications"><i class="ti ti-bell"></i><span class="dot" id="notifDot" style="display:none;">0</span></button>
          <div class="notif-dropdown" id="notifDropdown"></div>
        </div>
        <img class="topbar-avatar" src="assets/logo.jpeg" alt="You">
      </div>

      <div class="page-body">
        <h1 class="page-greeting" style="font-size: 22px;">Settings</h1>
        <p class="page-greeting-sub"><a href="dashboard.html" style="color: var(--primary); text-decoration:none; font-weight:600;">← Back to dashboard</a></p>

        <div id="forceChangeBanner" class="set-locked-note" style="display:none; max-width:640px; margin-bottom:20px;">
          <i class="ti ti-alert-triangle"></i> Your account was just created by HR — please set a new password below before continuing.
        </div>

        <!-- Profile -->
        <div class="set-panel">
          <h2>Profile</h2>
          <p class="sub">View and update your personal information.</p>

          <div class="set-avatar-row">
            <div class="set-avatar" id="profileAvatar">—</div>
            <div>
              <div style="font-weight:700; font-size:15px;" id="profileName">—</div>
              <div style="font-size:12.5px; color:var(--text-secondary);" id="profileRoleDept">—</div>
            </div>
          </div>

          <div class="set-field-row"><span class="set-field-label">Username</span><span class="set-field-value" id="profileUsername">—</span></div>
          <div class="set-field-row"><span class="set-field-label">Email</span><span class="set-field-value" id="profileEmail">—</span></div>
          <div class="set-field-row"><span class="set-field-label">Date Joined</span><span class="set-field-value" id="profileDate">—</span></div>

          <div class="set-locked-note"><i class="ti ti-info-circle"></i> Your name, role, department, and join date are managed by HR and can't be changed here.</div>

          <div style="margin-top:16px;">
            <label style="display:block; font-size:12.5px; font-weight:600; margin-bottom:6px;">Status / Bio</label>
            <textarea id="bioInput" placeholder="A short status or bio…" style="width:100%; min-height:70px; background:var(--surface-raised); border:1px solid var(--border); border-radius:var(--radius-sm); padding:10px 12px; font-size:13px; font-family:var(--font-body); color:var(--text-primary); resize:vertical;"></textarea>
            <div id="profileAlert" class="alert alert-error" style="margin-top:10px;"></div>
            <button class="btn btn-primary" id="saveBioBtn" style="width:auto; padding:9px 20px; margin-top:10px;">Save</button>
          </div>
        </div>

        <!-- Notifications -->
        <div class="set-panel">
          <h2>Notifications</h2>
          <p class="sub">Choose how and when you want to be notified.</p>
          <div class="set-toggle-row">
            <div><div class="label">Email me for new broadcasts</div><div class="desc">Receive an email when a new broadcast is sent.</div></div>
            <button class="set-toggle" id="toggleBroadcasts" onclick="toggleSwitch(this)"><span class="knob"></span></button>
          </div>
          <div class="set-toggle-row">
            <div><div class="label">Email me for direct messages</div><div class="desc">Receive an email when someone sends you a message.</div></div>
            <button class="set-toggle" id="toggleMessages" onclick="toggleSwitch(this)"><span class="knob"></span></button>
          </div>
          <div class="set-toggle-row">
            <div><div class="label">Desktop notifications</div><div class="desc">Show desktop notifications for new activity.</div></div>
            <button class="set-toggle" id="toggleDesktop" onclick="toggleSwitch(this)"><span class="knob"></span></button>
          </div>
          <div class="set-locked-note" style="margin-top:14px;"><i class="ti ti-check"></i> These preferences are fully active — turn any of them off if you don't want that email.</div>
        </div>

        <!-- Security -->
        <div class="set-panel">
          <h2>Security</h2>
          <p class="sub">Keep your account secure.</p>
          <div id="passwordAlert" class="alert alert-error"></div>
          <div id="passwordSuccess" class="alert alert-success"></div>
          <div style="margin-bottom:12px;">
            <label style="display:block; font-size:12.5px; font-weight:600; margin-bottom:6px;">Current Password</label>
            <input type="password" id="currentPassword" style="width:100%; padding:9px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); font-family:var(--font-body);">
          </div>
          <div style="margin-bottom:12px;">
            <label style="display:block; font-size:12.5px; font-weight:600; margin-bottom:6px;">New Password</label>
            <input type="password" id="newPassword" style="width:100%; padding:9px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); font-family:var(--font-body);">
          </div>
          <div style="margin-bottom:16px;">
            <label style="display:block; font-size:12.5px; font-weight:600; margin-bottom:6px;">Confirm New Password</label>
            <input type="password" id="confirmPassword" style="width:100%; padding:9px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); font-family:var(--font-body);">
          </div>
          <button class="btn btn-primary" id="changePasswordBtn" style="width:auto; padding:9px 20px;">Update Password</button>

          <div style="margin-top:20px; padding-top:20px; border-top:1px solid var(--border);">
            <p style="font-size:12.5px; color:var(--text-secondary); margin-bottom:10px;">Signed in somewhere you don't recognize? Sign out everywhere at once.</p>
            <button class="btn btn-ghost" id="logoutAllBtn" style="width:auto; padding:9px 20px; color:var(--error); border-color:var(--error);">Log out of all devices</button>
          </div>
        </div>

        <!-- Appearance -->
        <div class="set-panel">
          <h2>Appearance</h2>
          <p class="sub">Customize how the app looks.</p>
          <div class="set-appearance-row">
            <div class="set-appearance-btn active"><i class="ti ti-sun"></i> Light</div>
            <div class="set-appearance-btn disabled" title="Coming soon"><i class="ti ti-moon"></i> Dark (coming soon)</div>
          </div>
        </div>

      </div>
    </div>
  </div>

  <script src="assets/api.js"></script>
  <script src="assets/notifications.js"></script>
  <script src="assets/presence.js"></script>
  <script>
    document.getElementById('logoutBtn').addEventListener('click', async () => {
      await apiRequest('/auth/logout', { method: 'POST' });
      window.location.href = 'login.html';
    });

    function initials(name) {
      if (!name) return '?';
      return name.split(' ').map(p => p[0]).join('').slice(0, 2).toUpperCase();
    }

    function toggleSwitch(btn) {
      btn.classList.toggle('on');
    }

    async function init() {
      const params = new URLSearchParams(window.location.search);
      if (params.get('forcePasswordChange') === '1') {
        document.getElementById('forceChangeBanner').style.display = 'block';
        setTimeout(() => document.getElementById('currentPassword').scrollIntoView({ behavior: 'smooth', block: 'center' }), 300);
      }

      try {
        const result = await apiRequest('/settings/me');
        const p = result.profile;

        document.getElementById('profileAvatar').textContent = initials(p.fullName);
        document.getElementById('profileName').textContent = p.fullName;
        document.getElementById('profileRoleDept').textContent = p.role + (p.department ? ' · ' + p.department : '');
        document.getElementById('profileUsername').textContent = p.username;
        document.getElementById('profileEmail').textContent = p.email;
        document.getElementById('profileDate').textContent = new Date(p.dateJoined).toLocaleDateString();
        document.getElementById('bioInput').value = p.bio || '';

        if (p.notifyEmailBroadcasts) document.getElementById('toggleBroadcasts').classList.add('on');
        if (p.notifyEmailMessages) document.getElementById('toggleMessages').classList.add('on');
        if (p.notifyDesktop) document.getElementById('toggleDesktop').classList.add('on');
      } catch (err) {
        window.location.href = 'login.html';
        return;
      }
      loadUnreadBadge();
    }

    document.getElementById('saveBioBtn').addEventListener('click', async () => {
      const alertEl = document.getElementById('profileAlert');
      hideAlert(alertEl);
      try {
        await apiRequest('/settings/profile', { method: 'PUT', body: { bio: document.getElementById('bioInput').value.trim() } });
      } catch (err) {
        showAlert(alertEl, err.message);
      }
    });

    ['toggleBroadcasts', 'toggleMessages', 'toggleDesktop'].forEach(id => {
      document.getElementById(id).addEventListener('click', async () => {
        try {
          await apiRequest('/settings/notifications', {
            method: 'PUT',
            body: {
              notifyEmailBroadcasts: document.getElementById('toggleBroadcasts').classList.contains('on'),
              notifyEmailMessages: document.getElementById('toggleMessages').classList.contains('on'),
              notifyDesktop: document.getElementById('toggleDesktop').classList.contains('on')
            }
          });
        } catch (err) {
          alert(err.message);
        }
      });
    });

    document.getElementById('changePasswordBtn').addEventListener('click', async () => {
      const alertEl = document.getElementById('passwordAlert');
      const successEl = document.getElementById('passwordSuccess');
      hideAlert(alertEl);
      hideAlert(successEl);

      const currentPassword = document.getElementById('currentPassword').value;
      const newPassword = document.getElementById('newPassword').value;
      const confirmPassword = document.getElementById('confirmPassword').value;

      if (newPassword !== confirmPassword) {
        showAlert(alertEl, 'New password and confirmation do not match.');
        return;
      }

      const btn = document.getElementById('changePasswordBtn');
      btn.disabled = true;

      try {
        await apiRequest('/settings/password', { method: 'PUT', body: { currentPassword, newPassword } });
        showAlert(successEl, 'Password updated successfully.', 'success');
        document.getElementById('currentPassword').value = '';
        document.getElementById('newPassword').value = '';
        document.getElementById('confirmPassword').value = '';
      } catch (err) {
        showAlert(alertEl, err.message);
      } finally {
        btn.disabled = false;
      }
    });

    document.getElementById('logoutAllBtn').addEventListener('click', async () => {
      if (!confirm('This will sign you out on every device, including this one. Continue?')) return;
      try {
        await apiRequest('/settings/logout-all-devices', { method: 'POST' });
      } catch (err) {
        // Even if this errors, the safest move is still to send them to login
      }
      window.location.href = 'login.html';
    });

    init();
  </script>
</body>
</html>

EOF_ACCOUNTING_SETTINGS_HTML

cat > accounting/leave.html << 'EOF_ACCOUNTING_LEAVE_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Leave & Requests — MACDEN Portal</title>
  <link rel="stylesheet" href="assets/portal-style.css">
  <link rel="stylesheet" href="assets/portal-shell.css">
  <link rel="stylesheet" href="assets/portal-inbox.css">
  <style>
    .lv-grid { display: grid; grid-template-columns: 380px 1fr; gap: 20px; margin-bottom: 24px; }
    .lv-form-field { margin-bottom: 16px; }
    .lv-form-field label { display: block; font-size: 12.5px; font-weight: 600; color: var(--text-primary); margin-bottom: 6px; }
    .lv-form-field input, .lv-form-field select, .lv-form-field textarea {
      width: 100%; background: var(--surface-raised); border: 1px solid var(--border); border-radius: var(--radius-sm);
      padding: 10px 12px; font-size: 13px; font-family: var(--font-body); color: var(--text-primary);
    }
    .lv-form-field textarea { min-height: 80px; resize: vertical; }
    .lv-form-row { display: flex; gap: 10px; }
    .lv-form-row .lv-form-field { flex: 1; }

    .lv-table { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-md); overflow: hidden; }
    .lv-header-row { display: grid; grid-template-columns: 100px 100px 100px 1fr 100px 130px; gap: 12px; padding: 12px 18px; font-size: 10.5px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.04em; color: var(--text-muted); border-bottom: 1px solid var(--border); }
    .lv-row { display: grid; grid-template-columns: 100px 100px 100px 1fr 100px 130px; gap: 12px; align-items: center; padding: 12px 18px; border-bottom: 1px solid var(--border); font-size: 12.5px; }
    .lv-row:last-child { border-bottom: none; }
    .lv-empty { padding: 40px 18px; text-align: center; color: var(--text-muted); font-size: 13px; }

    .status-badge { display: inline-block; padding: 2px 9px; border-radius: 999px; font-size: 10.5px; font-weight: 700; }
    .status-pending { background: var(--gold-dim); color: #8a6d00; }
    .status-approved { background: var(--success-dim); color: var(--success); }
    .status-rejected { background: var(--error-dim); color: var(--error); }

    .approve-btn, .reject-btn { border: none; border-radius: var(--radius-sm); padding: 5px 12px; font-size: 11.5px; font-weight: 700; cursor: pointer; font-family: var(--font-body); }
    .approve-btn { background: var(--success-dim); color: var(--success); }
    .reject-btn { background: var(--error-dim); color: var(--error); margin-left: 6px; }

    .admin-section-divider { margin: 32px 0 18px; padding-top: 20px; border-top: 1px solid var(--border); }
  </style>
</head>
<body>
  <div class="app-shell">
    <div class="sidebar">
      <div class="sidebar-brand">
        <img src="assets/logo.jpeg" alt="MACDEN">
        <span>MACDEN</span>
      </div>
      <nav class="sidebar-nav">
        <a href="dashboard.html" class="sidebar-link"><i class="ti ti-layout-dashboard"></i> Dashboard</a>
        <a href="inbox.html" class="sidebar-link"><i class="ti ti-mail"></i> Inbox <span class="badge" id="unreadBadge" style="display:none;">0</span></a>
        <a href="compose.html" class="sidebar-link"><i class="ti ti-pencil"></i> Compose</a>
        <a href="broadcasts.html" class="sidebar-link"><i class="ti ti-speakerphone"></i> Broadcasts</a>
        <a href="directory.html" class="sidebar-link"><i class="ti ti-users"></i> Directory</a>
        <a href="leave.html" class="sidebar-link active"><i class="ti ti-calendar-event"></i> Leave &amp; Requests</a>
        <a href="documents.html" class="sidebar-link"><i class="ti ti-file-text"></i> Documents</a>
        <a href="policies.html" class="sidebar-link"><i class="ti ti-book"></i> Policies</a>
        <a href="settings.html" class="sidebar-link"><i class="ti ti-settings"></i> Settings</a>
      </nav>
      <div class="sidebar-logout">
        <button id="logoutBtn"><i class="ti ti-logout"></i> Logout</button>
      </div>
    </div>

    <div class="main-content">
      <div class="topbar">
        <div class="topbar-search"><input type="text" placeholder="Search messages, people, documents…"></div>
        <div class="notif-wrap">
          <button class="topbar-bell" id="notifBell" aria-label="Notifications"><i class="ti ti-bell"></i><span class="dot" id="notifDot" style="display:none;">0</span></button>
          <div class="notif-dropdown" id="notifDropdown"></div>
        </div>
        <img class="topbar-avatar" src="assets/logo.jpeg" alt="You">
      </div>

      <div class="page-body">
        <h1 class="page-greeting" style="font-size: 22px;">Leave &amp; Requests</h1>
        <p class="page-greeting-sub"><a href="dashboard.html" style="color: var(--primary); text-decoration:none; font-weight:600;">← Back to dashboard</a></p>

        <div class="lv-grid">
          <div class="compose-card" style="max-width:none;">
            <h3 style="margin-bottom:14px; font-size:14.5px;">Submit New Leave Request</h3>
            <div id="alert" class="alert alert-error"></div>

            <div class="lv-form-field">
              <label>Leave Type</label>
              <select id="leaveType">
                <option>Annual Leave</option>
                <option>Sick Leave</option>
                <option>Emergency Leave</option>
                <option>Study Leave</option>
              </select>
            </div>
            <div class="lv-form-row">
              <div class="lv-form-field">
                <label>Start Date</label>
                <input type="date" id="startDate">
              </div>
              <div class="lv-form-field">
                <label>End Date</label>
                <input type="date" id="endDate">
              </div>
            </div>
            <div class="lv-form-field">
              <label>Reason</label>
              <textarea id="reason" placeholder="Briefly explain the reason for this leave…"></textarea>
            </div>
            <button class="btn btn-primary" id="submitBtn" style="width:auto; padding:10px 24px;">Submit Request</button>
          </div>

          <div>
            <h3 style="margin-bottom:14px; font-size:14.5px;">My Requests</h3>
            <div class="lv-table">
              <div class="lv-header-row"><div>Type</div><div>Start</div><div>End</div><div>Reason</div><div>Days</div><div>Status</div></div>
              <div id="myRequestsRows"><div class="lv-empty">Loading…</div></div>
            </div>
          </div>
        </div>

        <div id="adminSection" style="display:none;">
          <div class="admin-section-divider">
            <h2 class="page-greeting" style="font-size: 17px;">Pending Approvals</h2>
            <p class="page-greeting-sub">Requests from all staff awaiting your review.</p>
          </div>
          <div class="lv-table">
            <div class="lv-header-row" style="grid-template-columns: 160px 100px 100px 100px 1fr 160px;">
              <div>Staff Member</div><div>Type</div><div>Start</div><div>End</div><div>Reason</div><div>Actions</div>
            </div>
            <div id="pendingRows"><div class="lv-empty">Loading…</div></div>
          </div>
        </div>

      </div>
    </div>
  </div>

  <script src="assets/api.js"></script>
  <script src="assets/notifications.js"></script>
  <script src="assets/presence.js"></script>
  <script>
    document.getElementById('logoutBtn').addEventListener('click', async () => {
      await apiRequest('/auth/logout', { method: 'POST' });
      window.location.href = 'login.html';
    });

    async function init() {
      let staff;
      try {
        const result = await apiRequest('/dashboard-check');
        staff = result.staff;
      } catch (err) {
        window.location.href = 'login.html';
        return;
      }
      loadUnreadBadge();
      loadMyRequests();

      if (staff.role === 'admin') {
        document.getElementById('adminSection').style.display = 'block';
        loadPending();
      }
    }

    function statusBadge(status) {
      return '<span class="status-badge status-' + status + '">' + status.charAt(0).toUpperCase() + status.slice(1) + '</span>';
    }

    async function loadMyRequests() {
      const rows = document.getElementById('myRequestsRows');
      try {
        const result = await apiRequest('/leave/mine');
        if (result.requests.length === 0) {
          rows.innerHTML = '<div class="lv-empty">No requests yet.</div>';
          return;
        }
        rows.innerHTML = result.requests.map(r =>
          '<div class="lv-row">' +
          '<div>' + r.leave_type + '</div>' +
          '<div>' + new Date(r.start_date).toLocaleDateString() + '</div>' +
          '<div>' + new Date(r.end_date).toLocaleDateString() + '</div>' +
          '<div style="overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">' + (r.reason || '—') + '</div>' +
          '<div>' + r.days + '</div>' +
          '<div>' + statusBadge(r.status) + '</div>' +
          '</div>'
        ).join('');
      } catch (err) {
        rows.innerHTML = '<div class="lv-empty">Could not load your requests.</div>';
      }
    }

    async function loadPending() {
      const rows = document.getElementById('pendingRows');
      try {
        const result = await apiRequest('/leave/pending');
        if (result.requests.length === 0) {
          rows.innerHTML = '<div class="lv-empty">No pending requests.</div>';
          return;
        }
        rows.innerHTML = result.requests.map(r =>
          '<div class="lv-row" style="grid-template-columns: 160px 100px 100px 100px 1fr 160px;">' +
          '<div>' + r.staffName + (r.staffIsActive === false ? ' <span class="status-badge status-rejected" style="margin-left:4px;">Deactivated</span>' : '') + '</div>' +
          '<div>' + r.leave_type + '</div>' +
          '<div>' + new Date(r.start_date).toLocaleDateString() + '</div>' +
          '<div>' + new Date(r.end_date).toLocaleDateString() + '</div>' +
          '<div style="overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">' + (r.reason || '—') + '</div>' +
          '<div><button class="approve-btn" onclick="reviewRequest(\'' + r.id + '\', \'approve\')">Approve</button><button class="reject-btn" onclick="reviewRequest(\'' + r.id + '\', \'reject\')">Reject</button></div>' +
          '</div>'
        ).join('');
      } catch (err) {
        rows.innerHTML = '<div class="lv-empty">Could not load pending requests.</div>';
      }
    }

    async function reviewRequest(id, action) {
      try {
        await apiRequest('/leave/' + id + '/' + action, { method: 'POST' });
        loadPending();
      } catch (err) {
        alert(err.message);
      }
    }

    document.getElementById('submitBtn').addEventListener('click', async () => {
      const alertEl = document.getElementById('alert');
      hideAlert(alertEl);

      const leaveType = document.getElementById('leaveType').value;
      const startDate = document.getElementById('startDate').value;
      const endDate = document.getElementById('endDate').value;
      const reason = document.getElementById('reason').value.trim();

      if (!startDate || !endDate) {
        showAlert(alertEl, 'Select a start and end date.');
        return;
      }

      const btn = document.getElementById('submitBtn');
      btn.disabled = true;
      btn.textContent = 'Submitting…';

      try {
        await apiRequest('/leave', {
          method: 'POST',
          body: { leaveType, startDate, endDate, reason }
        });
        document.getElementById('reason').value = '';
        loadMyRequests();
      } catch (err) {
        showAlert(alertEl, err.message);
      } finally {
        btn.disabled = false;
        btn.textContent = 'Submit Request';
      }
    });

    init();
  </script>
</body>
</html>

EOF_ACCOUNTING_LEAVE_HTML

echo "Tightening batch 3 complete: 5 more items (12 of 40 total now done)."