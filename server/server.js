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

// TEMPORARY diagnostic: logs every single request that reaches this
// server, before any routing. Remove once the approve-staff mystery is solved.
app.use((req, res, next) => {
  console.log('[GLOBAL-REQUEST-LOG]', req.method, req.originalUrl);
  next();
});

app.use(helmet({ contentSecurityPolicy: false }));

// Any request that hangs for more than 15 seconds (a stuck database
// connection, an unresolved promise, etc.) now fails with a real, visible
// JSON error instead of hanging forever with no error at all -- which is
// exactly what a frozen button with zero console errors looks like.
const REQUEST_TIMEOUT_MS = 15000;
app.use((req, res, next) => {
  res.setTimeout(REQUEST_TIMEOUT_MS, () => {
    if (!res.headersSent) {
      console.error('Request timed out after ' + REQUEST_TIMEOUT_MS + 'ms:', req.method, req.originalUrl);
      res.status(504).json({ error: 'This is taking too long. Please try again.' });
    }
  });
  next();
});
app.set('trust proxy', 1);
app.use(express.json());

app.use(cors({
  origin: 'https://macden.com.ng',
  credentials: true
}));

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

// Portal pages now live at /portal instead of /accounting -- "accounting"
// was just the working name from when this started as a single-department
// tool; the project outgrew that name. The actual files stay in the
// "accounting" folder on disk (renaming every file wasn't necessary, only
// the public-facing URL needed to change).
// [PORTAL-ROOT-FIX] Explicit routes for the bare /portal and /portal/ paths --
// express.static's "index" option should handle serving login.html here
// automatically, but doesn't reliably in this Express version. This
// sidesteps that entirely with a direct, guaranteed route.
// [PORTAL-TRAILING-SLASH-FIX-V2] Single handler, checking req.path itself
// -- Express's default routing treats '/portal' and '/portal/' as the SAME
// route (non-strict routing), so two separate app.get() calls for each
// collided with each other. This checks the actual path directly instead,
// redirecting only when the trailing slash is genuinely missing. Matters
// because every page's CSS/JS uses relative paths (assets/portal-style.css)
// which only resolve correctly when the browser's address bar has the slash.
app.get(['/portal', '/portal/'], (req, res) => {
  if (req.path === '/portal') {
    return res.redirect(301, '/portal/');
  }
  res.sendFile(path.join(__dirname, '../portal/login.html'));
});

app.use('/portal', express.static(path.join(__dirname, '../portal'), {
  index: 'login.html'
}));

// Old /accounting links (if anyone already bookmarked one) quietly redirect
// to the new /portal path instead of breaking.
app.use('/accounting', (req, res) => res.redirect('/portal' + req.path));

app.use('/server', (req, res) => res.status(404).send('Not found'));
app.use('/.git', (req, res) => res.status(404).send('Not found'));

app.use(express.static(path.join(__dirname, '..'), {
  dotfiles: 'deny'
}));

app.get('/api/accounting/health', (req, res) => {
  res.json({ status: 'ok' });
});

app.use('/api/accounting/auth', authRoutes);
app.use('/api/accounting/public', publicRegisterRoutes);

// --- MACDEN Staff Verification (public, no auth) ---
const verifyRoutes = require('./routes/verify');
app.use(verifyRoutes);
// --- end staff verification block ---

// --- MACDEN ID Card Requests (auth required, checked inside the route file) ---
const idCardRoutes = require('./routes/idCardRequests');
app.use(idCardRoutes);
// --- end ID card requests block ---

// --- MACDEN Field Staff (auth required, checked inside the route file) ---
const fieldStaffRoutes = require('./routes/fieldStaff');
app.use(fieldStaffRoutes);
// --- end field staff block ---

// --- MACDEN Attendance (auth required, checked inside the route file) ---
const attendanceRoutes = require('./routes/attendance');
app.use(attendanceRoutes);
// --- end attendance block ---

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

app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ error: 'Something went wrong on the server.' });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Accounting backend running on port ${PORT}`);
});

cron.schedule('* * * * *', () => {
  messageRoutes.publishDueScheduledBroadcasts();
});

