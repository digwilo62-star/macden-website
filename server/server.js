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
app.use('/portal', express.static(path.join(__dirname, '../accounting'), {
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

