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

