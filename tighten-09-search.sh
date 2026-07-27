#!/usr/bin/env bash
# BACKEND ITEM #23: Company-wide search. New GET /api/accounting/search?q=
# searches messages (only conversations you're actually part of), current
# documents, and policies. BACKEND ONLY - actually wiring the topbar
# search input to call this and show results is frontend work.
# NO SQL MIGRATION NEEDED for this one.
# Run this from the ROOT of your macden-website repo, in Git Bash.
set -e

mkdir -p server/routes

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
const searchRoutes = require('./routes/search');
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
app.use('/api/accounting/search', searchRoutes);

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

cat > server/routes/search.js << 'EOF_SERVER_ROUTES_SEARCH_JS'
const express = require('express');
const supabase = require('../config/supabaseClient');

const router = express.Router();

function snippet(text, maxLen) {
  if (!text) return '';
  return text.length > maxLen ? text.slice(0, maxLen) + '…' : text;
}

// GET /api/accounting/search?q=... — searches across messages (only ones
// you're actually a participant in), documents, and policies. This is the
// search bar that's been sitting in every topbar unwired since the portal
// rebuild started.
router.get('/', async (req, res) => {
  try {
    const q = (req.query.q || '').trim();
    if (!q || q.length < 2) {
      return res.json({ messages: [], documents: [], policies: [] });
    }

    const staffId = req.session.staff.id;

    // ---- Messages: only within conversations this person is actually part of ----
    const { data: memberRows } = await supabase
      .from('conversation_members')
      .select('conversation_id')
      .eq('staff_id', staffId);
    const myConversationIds = (memberRows || []).map(m => m.conversation_id);

    let messageResults = [];
    if (myConversationIds.length > 0) {
      const { data: convMatches } = await supabase
        .from('conversations')
        .select('id, subject')
        .in('id', myConversationIds)
        .ilike('subject', `%${q}%`)
        .limit(8);

      const { data: bodyMatches } = await supabase
        .from('messages')
        .select('id, conversation_id, body')
        .in('conversation_id', myConversationIds)
        .eq('status', 'sent')
        .ilike('body', `%${q}%`)
        .limit(8);

      const subjectIdsFound = new Set((convMatches || []).map(c => c.id));
      const bodyMatchConvos = (bodyMatches || []).filter(m => !subjectIdsFound.has(m.conversation_id));

      const subjectById = {};
      (convMatches || []).forEach(c => { subjectById[c.id] = c.subject; });

      messageResults = [
        ...(convMatches || []).map(c => ({
          conversationId: c.id,
          subject: c.subject,
          matchedOn: 'subject'
        })),
        ...bodyMatchConvos.map(m => ({
          conversationId: m.conversation_id,
          subject: subjectById[m.conversation_id] || '(no subject)',
          snippet: snippet(m.body, 80),
          matchedOn: 'body'
        }))
      ].slice(0, 8);
    }

    // ---- Documents (current versions only) ----
    const { data: docMatches } = await supabase
      .from('documents')
      .select('id, file_name, category')
      .eq('is_current', true)
      .ilike('file_name', `%${q}%`)
      .limit(8);

    // ---- Policies ----
    const { data: policyMatches } = await supabase
      .from('policies')
      .select('id, title, body')
      .or(`title.ilike.%${q}%,body.ilike.%${q}%`)
      .limit(8);

    res.json({
      messages: messageResults,
      documents: (docMatches || []).map(d => ({ id: d.id, fileName: d.file_name, category: d.category })),
      policies: (policyMatches || []).map(p => ({ id: p.id, title: p.title, snippet: snippet(p.body, 80) }))
    });
  } catch (err) {
    console.error('Search unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong searching.' });
  }
});

module.exports = router;

EOF_SERVER_ROUTES_SEARCH_JS

echo "Company-wide search backend complete (#23). 22 of 40 items now done."