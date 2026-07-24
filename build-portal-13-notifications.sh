#!/usr/bin/env bash
# Adds the notification bell dropdown - the LAST item from the original
# 15-screen mockup set. No new table - aggregates real activity from
# unread messages, your own reviewed leave requests, and new hires.
# Wired into all 11 portal pages.
# Run this from the ROOT of your macden-website repo, in Git Bash.
set -e

mkdir -p server/routes accounting/assets

cat > server/server.js << 'EOF_SERVER_SERVER_JS'
require('dotenv').config();

const path = require('path');
const express = require('express');
const session = require('express-session');
const pgSession = require('connect-pg-simple')(session);
const { Pool } = require('pg');
const cors = require('cors');

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
const pgPool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false } // required for Supabase's connection pooler
});

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

cat > server/routes/notifications.js << 'EOF_SERVER_ROUTES_NOTIFICATIONS_JS'
const express = require('express');
const supabase = require('../config/supabaseClient');

const router = express.Router();

function timeAgo(dateStr) {
  const diffMs = Date.now() - new Date(dateStr).getTime();
  const mins = Math.floor(diffMs / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return mins + 'm ago';
  const hours = Math.floor(mins / 60);
  if (hours < 24) return hours + 'h ago';
  const days = Math.floor(hours / 24);
  return days + 'd ago';
}

// GET /api/accounting/notifications — aggregates real recent activity for this
// person: unread messages, their own reviewed leave requests, and new hires.
// No separate notifications table — this reads directly from data that
// already exists, so everything shown is genuinely real.
router.get('/', async (req, res) => {
  try {
    const staffId = req.session.staff.id;
    const items = [];

    // Get the TRUE unread count separately from the 5-row sample used for display below
    const { count: trueUnreadCount } = await supabase
      .from('message_reads')
      .select('*', { count: 'exact', head: true })
      .eq('staff_id', staffId)
      .is('read_at', null);

    // Unread messages (up to 5 most recent, for display)
    const { data: unreadRows } = await supabase
      .from('message_reads')
      .select('message_id, read_at')
      .eq('staff_id', staffId)
      .is('read_at', null)
      .limit(5);

    if (unreadRows && unreadRows.length > 0) {
      const messageIds = unreadRows.map(r => r.message_id);
      const { data: messages } = await supabase
        .from('messages')
        .select('id, sender_id, body, sent_at, conversation_id')
        .in('id', messageIds);

      if (messages) {
        const senderIds = [...new Set(messages.map(m => m.sender_id))];
        const { data: senders } = await supabase.from('staff').select('id, full_name').in('id', senderIds);
        const nameById = {};
        (senders || []).forEach(s => { nameById[s.id] = s.full_name; });

        messages.forEach(m => {
          items.push({
            type: 'message',
            icon: 'ti-mail',
            title: (nameById[m.sender_id] || 'Someone') + ' sent you a message',
            detail: (m.body || '').slice(0, 60),
            time: m.sent_at,
            link: 'inbox.html?id=' + m.conversation_id
          });
        });
      }
    }

    // Own leave requests reviewed in the last 7 days
    const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
    const { data: reviewedLeave } = await supabase
      .from('leave_requests')
      .select('id, status, leave_type, reviewed_at')
      .eq('staff_id', staffId)
      .not('reviewed_at', 'is', null)
      .gte('reviewed_at', sevenDaysAgo)
      .order('reviewed_at', { ascending: false })
      .limit(3);

    (reviewedLeave || []).forEach(r => {
      items.push({
        type: 'leave',
        icon: r.status === 'approved' ? 'ti-circle-check' : 'ti-circle-x',
        title: 'Your leave request was ' + r.status,
        detail: r.leave_type,
        time: r.reviewed_at,
        link: 'leave.html'
      });
    });

    // New staff joined in the last 3 days (everyone sees this)
    const threeDaysAgo = new Date(Date.now() - 3 * 24 * 60 * 60 * 1000).toISOString();
    const { data: newStaff } = await supabase
      .from('staff')
      .select('id, full_name, created_at')
      .neq('id', staffId)
      .gte('created_at', threeDaysAgo)
      .order('created_at', { ascending: false })
      .limit(3);

    (newStaff || []).forEach(s => {
      items.push({
        type: 'staff',
        icon: 'ti-user-plus',
        title: s.full_name + ' joined the company',
        detail: 'Welcome to MACDEN!',
        time: s.created_at,
        link: 'directory.html'
      });
    });

    // Sort everything by recency, cap at 8
    items.sort((a, b) => new Date(b.time) - new Date(a.time));
    const limited = items.slice(0, 8).map(i => ({ ...i, timeAgo: timeAgo(i.time) }));

    res.json({ notifications: limited, unreadCount: trueUnreadCount || 0 });
  } catch (err) {
    console.error('Notifications fetch error:', err);
    res.status(500).json({ error: 'Something went wrong loading notifications.' });
  }
});

module.exports = router;

EOF_SERVER_ROUTES_NOTIFICATIONS_JS

cat > accounting/assets/portal-shell.css << 'EOF_ACCOUNTING_ASSETS_PORTAL-SHELL_CSS'
/* ---------- App shell ---------- */

.app-shell { display: flex; min-height: 100vh; }

.sidebar {
  width: 240px;
  flex-shrink: 0;
  background: var(--primary);
  color: #fff;
  display: flex;
  flex-direction: column;
  padding: 20px 0;
  position: fixed;
  top: 0; left: 0; bottom: 0;
}

.sidebar-brand {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 0 20px 24px;
}

.sidebar-brand img { width: 34px; height: 34px; border-radius: 8px; background: #fff; }
.sidebar-brand span { font-family: var(--font-heading); font-weight: 800; font-size: 14.5px; }

.sidebar-nav { flex: 1; padding: 0 12px; }

.sidebar-link {
  display: flex;
  align-items: center;
  gap: 11px;
  padding: 10px 12px;
  border-radius: var(--radius-sm);
  color: rgba(255,255,255,0.82);
  text-decoration: none;
  font-size: 13.5px;
  font-weight: 500;
  margin-bottom: 2px;
}

.sidebar-link:hover { background: rgba(255,255,255,0.08); color: #fff; }
.sidebar-link.active { background: rgba(255,255,255,0.14); color: #fff; font-weight: 600; }
.sidebar-link i, .quick-action i, .topbar-bell i { font-size: 17px; line-height: 1; flex-shrink: 0; }
.topbar-bell i { font-size: 20px; }

.sidebar-link .badge {
  margin-left: auto;
  background: var(--gold);
  color: var(--primary);
  font-size: 10.5px;
  font-weight: 700;
  padding: 1px 7px;
  border-radius: 999px;
}

.sidebar-logout {
  padding: 12px 20px 0;
  border-top: 1px solid rgba(255,255,255,0.12);
  margin-top: 12px;
}

.sidebar-logout a {
  display: flex; align-items: center; gap: 10px;
  color: rgba(255,255,255,0.75); text-decoration: none; font-size: 13px; padding: 8px 0;
  background: none; border: none; cursor: pointer; font-family: var(--font-body);
}

/* ---------- Topbar ---------- */

.topbar {
  height: 68px;
  background: var(--surface);
  border-bottom: 1px solid var(--border);
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 18px;
  padding: 0 32px;
  position: sticky;
  top: 0;
  z-index: 10;
}

.topbar-search {
  flex: 1;
  max-width: 420px;
  margin-right: auto;
}

.topbar-search input {
  width: 100%;
  background: var(--surface-raised);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  padding: 9px 14px;
  font-size: 13px;
  font-family: var(--font-body);
  color: var(--text-primary);
}

.topbar-bell {
  position: relative;
  background: none;
  border: none;
  cursor: pointer;
  color: var(--text-secondary);
  font-size: 18px;
}

.topbar-bell .dot {
  position: absolute;
  top: -2px; right: -2px;
  background: var(--error);
  color: #fff;
  font-size: 9.5px;
  font-weight: 700;
  min-width: 15px;
  height: 15px;
  border-radius: 999px;
  display: flex; align-items: center; justify-content: center;
}

.topbar-avatar { width: 36px; height: 36px; border-radius: 50%; object-fit: cover; background: var(--surface-raised); }

/* ---------- Main content ---------- */

.main-content { margin-left: 240px; flex: 1; }
.page-body { padding: 28px 32px; }

.page-greeting { font-size: 24px; margin-bottom: 3px; }
.page-greeting-sub { color: var(--text-secondary); font-size: 13px; margin-bottom: 26px; }

.dash-grid { display: grid; grid-template-columns: 1.4fr 1fr; gap: 20px; margin-bottom: 24px; }

.panel {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  padding: 22px;
}

.panel-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 16px; }
.panel-header h2 { font-size: 15.5px; }
.panel-header a { font-size: 12px; color: var(--primary); text-decoration: none; font-weight: 600; }

.announcement-item { padding: 13px 0; border-bottom: 1px solid var(--border); }
.announcement-item:last-child { border-bottom: none; }
.announcement-item .subj { font-weight: 600; font-size: 13.5px; margin-bottom: 2px; }
.announcement-item .meta { font-size: 12px; color: var(--text-muted); }

.quick-action {
  display: flex; align-items: center; gap: 10px;
  padding: 11px 12px;
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  text-decoration: none;
  color: var(--text-primary);
  font-size: 13px;
  font-weight: 500;
  margin-bottom: 8px;
}
.quick-action:hover { border-color: var(--primary); background: var(--primary-dim); }

.stat-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; }

.stat-card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  padding: 18px;
}

.stat-card .num { font-family: var(--font-heading); font-size: 26px; font-weight: 800; color: var(--primary); }
.stat-card .lbl { font-size: 12px; color: var(--text-secondary); margin-top: 2px; }

.empty-note {
  font-size: 12.5px;
  color: var(--text-muted);
  padding: 16px 0;
  text-align: center;
}

/* ---------- Notification bell dropdown ---------- */

.notif-wrap { position: relative; }

.notif-dropdown {
  display: none;
  position: absolute;
  top: calc(100% + 10px);
  right: 0;
  width: 340px;
  max-height: 420px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  box-shadow: 0 8px 24px rgba(0,0,0,0.12);
  z-index: 50;
  overflow: hidden;
  display: none;
  flex-direction: column;
}

.notif-dropdown.visible { display: flex; }

.notif-header {
  padding: 14px 18px;
  font-size: 13px;
  font-weight: 700;
  border-bottom: 1px solid var(--border);
  color: var(--text-primary);
}

.notif-list { overflow-y: auto; }

.notif-item {
  display: flex;
  gap: 12px;
  padding: 13px 18px;
  border-bottom: 1px solid var(--border);
  text-decoration: none;
  color: inherit;
}

.notif-item:last-child { border-bottom: none; }
.notif-item:hover { background: var(--surface-raised); }

.notif-icon {
  width: 32px;
  height: 32px;
  border-radius: 50%;
  background: var(--primary-dim);
  color: var(--primary);
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 14px;
  flex-shrink: 0;
}

.notif-text { min-width: 0; }
.notif-title { font-size: 12.5px; font-weight: 600; color: var(--text-primary); }
.notif-detail { font-size: 11.5px; color: var(--text-secondary); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.notif-time { font-size: 10.5px; color: var(--text-muted); margin-top: 2px; }

.notif-empty { padding: 30px 18px; text-align: center; color: var(--text-muted); font-size: 12.5px; }

EOF_ACCOUNTING_ASSETS_PORTAL-SHELL_CSS

cat > accounting/assets/notifications.js << 'EOF_ACCOUNTING_ASSETS_NOTIFICATIONS_JS'
// Shared notification bell dropdown — loaded on every portal page.
// Requires this markup to exist in the topbar:
// <div class="notif-wrap">
//   <button class="topbar-bell" id="notifBell"><i class="ti ti-bell"></i><span class="dot" id="notifDot" style="display:none;">0</span></button>
//   <div class="notif-dropdown" id="notifDropdown">...</div>
// </div>

async function initNotificationBell() {
  const bell = document.getElementById('notifBell');
  const dropdown = document.getElementById('notifDropdown');
  if (!bell || !dropdown) return;

  await refreshNotifBadge();

  bell.addEventListener('click', async (e) => {
    e.stopPropagation();
    const isOpen = dropdown.classList.contains('visible');
    if (isOpen) {
      dropdown.classList.remove('visible');
      return;
    }
    dropdown.classList.add('visible');
    await loadNotifDropdown();
  });

  document.addEventListener('click', (e) => {
    if (!e.target.closest('.notif-wrap')) {
      dropdown.classList.remove('visible');
    }
  });
}

async function refreshNotifBadge() {
  try {
    const result = await apiRequest('/notifications');
    const dot = document.getElementById('notifDot');
    if (result.unreadCount > 0) {
      dot.textContent = result.unreadCount;
      dot.style.display = 'flex';
    } else {
      dot.style.display = 'none';
    }
  } catch (err) {}
}

async function loadNotifDropdown() {
  const dropdown = document.getElementById('notifDropdown');
  dropdown.innerHTML = '<div class="notif-empty">Loading…</div>';

  try {
    const result = await apiRequest('/notifications');

    if (result.notifications.length === 0) {
      dropdown.innerHTML = '<div class="notif-header">Notifications</div><div class="notif-empty">Nothing new right now.</div>';
      return;
    }

    const items = result.notifications.map(n =>
      '<a href="' + n.link + '" class="notif-item">' +
        '<div class="notif-icon"><i class="ti ' + n.icon + '"></i></div>' +
        '<div class="notif-text">' +
          '<div class="notif-title">' + n.title + '</div>' +
          '<div class="notif-detail">' + n.detail + '</div>' +
          '<div class="notif-time">' + n.timeAgo + '</div>' +
        '</div>' +
      '</a>'
    ).join('');

    dropdown.innerHTML = '<div class="notif-header">Notifications</div><div class="notif-list">' + items + '</div>';
  } catch (err) {
    dropdown.innerHTML = '<div class="notif-header">Notifications</div><div class="notif-empty">Could not load notifications.</div>';
  }
}

document.addEventListener('DOMContentLoaded', initNotificationBell);

EOF_ACCOUNTING_ASSETS_NOTIFICATIONS_JS

cat > accounting/broadcasts.html << 'EOF_ACCOUNTING_BROADCASTS_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Broadcasts — MACDEN Portal</title>
  <link rel="stylesheet" href="assets/portal-style.css">
  <link rel="stylesheet" href="assets/portal-shell.css">
  <link rel="stylesheet" href="assets/portal-inbox.css">
  <style>
    .bc-list { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-md); overflow: hidden; }
    .bc-row { display: grid; grid-template-columns: 1fr 140px 140px 160px; align-items: center; gap: 14px; padding: 14px 20px; border-bottom: 1px solid var(--border); cursor: pointer; }
    .bc-row:last-child { border-bottom: none; }
    .bc-row:hover { background: var(--surface-raised); }
    .bc-subject { font-size: 13.5px; font-weight: 600; color: var(--text-primary); }
    .bc-date { font-size: 12px; color: var(--text-muted); }
    .bc-count { font-size: 12.5px; color: var(--text-secondary); }
    .bc-opened { font-size: 12.5px; color: var(--primary); font-weight: 600; }
    .bc-empty { padding: 60px 20px; text-align: center; color: var(--text-muted); font-size: 13px; }
    .bc-compose-note { background: var(--gold-dim); color: #8a6d00; padding: 10px 14px; border-radius: var(--radius-sm); font-size: 12.5px; margin-bottom: 16px; }
    .bc-recipient-count { font-family: var(--font-heading); font-size: 22px; font-weight: 800; color: var(--primary); }
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
        <a href="broadcasts.html" class="sidebar-link active"><i class="ti ti-speakerphone"></i> Broadcasts</a>
        <a href="directory.html" class="sidebar-link"><i class="ti ti-users"></i> Directory</a>
        <a href="leave.html" class="sidebar-link"><i class="ti ti-calendar-event"></i> Leave &amp; Requests</a>
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
          <button class="topbar-bell" id="notifBell"><i class="ti ti-bell"></i><span class="dot" id="notifDot" style="display:none;">0</span></button>
          <div class="notif-dropdown" id="notifDropdown"></div>
        </div>
        <img class="topbar-avatar" src="assets/logo.jpeg" alt="You">
      </div>

      <div class="page-body">

        <div id="notAdminView" style="display:none;">
          <h1 class="page-greeting" style="font-size: 22px;">Broadcasts</h1>
          <div class="bc-empty" style="margin-top:20px;">Only admins (HR/Auditor) can send or view company-wide broadcasts.</div>
        </div>

        <div id="adminView" style="display:none;">

          <div id="listView">
            <div class="email-toolbar">
              <div>
                <h1 class="page-greeting" style="font-size: 22px;">Broadcasts — Sent History</h1>
                <p class="page-greeting-sub" style="margin:0;"><a href="dashboard.html" style="color: var(--primary); text-decoration:none; font-weight:600;">← Back to dashboard</a></p>
              </div>
              <button class="btn btn-primary" id="newBroadcastBtn" style="width:auto; padding:10px 20px; display:inline-flex; align-items:center; gap:8px;"><i class="ti ti-speakerphone"></i> New Broadcast</button>
            </div>

            <div class="bc-list" id="bcList">
              <div class="bc-empty">Loading…</div>
            </div>
          </div>

          <div id="composeView" style="display:none;">
            <h1 class="page-greeting" style="font-size: 22px;">New Broadcast</h1>
            <p class="page-greeting-sub"><a href="#" id="cancelComposeLink" style="color: var(--primary); text-decoration:none; font-weight:600;">← Back to broadcasts</a></p>

            <div class="bc-compose-note"><i class="ti ti-info-circle"></i> This message will be sent to all active staff.</div>
            <div id="alert" class="alert alert-error"></div>

            <div style="display:grid; grid-template-columns: 1fr 220px; gap: 20px;">
              <div class="compose-card" style="max-width:none;">
                <div class="compose-field">
                  <label>Subject</label>
                  <input type="text" id="bcSubject" placeholder="Important company update">
                </div>
                <div class="compose-body-area">
                  <textarea id="bcBody" placeholder="Write your announcement…"></textarea>
                </div>
                <div class="compose-footer">
                  <span></span>
                  <button class="btn btn-primary" id="sendBroadcastBtn" style="width:auto; padding:10px 24px; display:inline-flex; align-items:center; gap:8px;"><i class="ti ti-send"></i> Send to All</button>
                </div>
              </div>
              <div class="email-card" style="text-align:center;">
                <div class="bc-recipient-count" id="recipientCountDisplay">—</div>
                <div style="font-size:12px; color:var(--text-secondary); margin-top:4px;">Active Staff</div>
              </div>
            </div>
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

      if (staff.role !== 'admin') {
        document.getElementById('notAdminView').style.display = 'block';
        return;
      }

      document.getElementById('adminView').style.display = 'block';
      loadBroadcasts();
      loadUnreadBadge();
    }

    async function loadBroadcasts() {
      const list = document.getElementById('bcList');
      try {
        const result = await apiRequest('/messages/broadcasts');
        if (result.broadcasts.length === 0) {
          list.innerHTML = '<div class="bc-empty">No broadcasts sent yet. Click New Broadcast to send your first one.</div>';
          return;
        }
        list.innerHTML =
          '<div class="bc-row" style="font-size:11px; font-weight:700; text-transform:uppercase; letter-spacing:0.04em; color:var(--text-muted); cursor:default;">' +
            '<div>Subject</div><div>Date Sent</div><div>Recipients</div><div>Opened</div>' +
          '</div>' +
          result.broadcasts.map(b => {
            const pct = b.recipientCount > 0 ? Math.round((b.openedCount / b.recipientCount) * 100) : 0;
            return '<div class="bc-row" onclick="window.location.href=\'inbox.html?id=' + b.id + '\'">' +
              '<div class="bc-subject">' + b.subject + '</div>' +
              '<div class="bc-date">' + new Date(b.sentAt).toLocaleString() + '</div>' +
              '<div class="bc-count">' + b.recipientCount + ' sent</div>' +
              '<div class="bc-opened">' + b.openedCount + ' opened (' + pct + '%)</div>' +
              '</div>';
          }).join('');
      } catch (err) {
        list.innerHTML = '<div class="bc-empty">' + err.message + '</div>';
      }
    }

    document.getElementById('newBroadcastBtn').addEventListener('click', async () => {
      document.getElementById('listView').style.display = 'none';
      document.getElementById('composeView').style.display = 'block';
      try {
        const result = await apiRequest('/staff?search=');
        document.getElementById('recipientCountDisplay').textContent = result.staff.length;
      } catch (err) {
        document.getElementById('recipientCountDisplay').textContent = '—';
      }
    });

    document.getElementById('cancelComposeLink').addEventListener('click', (e) => {
      e.preventDefault();
      document.getElementById('composeView').style.display = 'none';
      document.getElementById('listView').style.display = 'block';
      loadBroadcasts();
    });

    document.getElementById('sendBroadcastBtn').addEventListener('click', async () => {
      const alertEl = document.getElementById('alert');
      hideAlert(alertEl);

      const subject = document.getElementById('bcSubject').value.trim();
      const body = document.getElementById('bcBody').value.trim();

      if (!subject) { showAlert(alertEl, 'Add a subject.'); return; }
      if (!body) { showAlert(alertEl, 'Write a message.'); return; }

      const btn = document.getElementById('sendBroadcastBtn');
      btn.disabled = true;
      btn.textContent = 'Sending…';

      try {
        await apiRequest('/messages/broadcast', {
          method: 'POST',
          body: { subject, body }
        });
        document.getElementById('bcSubject').value = '';
        document.getElementById('bcBody').value = '';
        document.getElementById('composeView').style.display = 'none';
        document.getElementById('listView').style.display = 'block';
        loadBroadcasts();
      } catch (err) {
        showAlert(alertEl, err.message);
      } finally {
        btn.disabled = false;
        btn.innerHTML = '<i class="ti ti-send"></i> Send to All';
      }
    });

    init();
  </script>
</body>
</html>

EOF_ACCOUNTING_BROADCASTS_HTML

cat > accounting/compose.html << 'EOF_ACCOUNTING_COMPOSE_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Compose — MACDEN Portal</title>
  <link rel="stylesheet" href="assets/portal-style.css">
  <link rel="stylesheet" href="assets/portal-shell.css">
  <link rel="stylesheet" href="assets/portal-inbox.css">
  <style>
    .search-results { position: absolute; top: 100%; left: 0; right: 0; background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-sm); margin-top: 4px; max-height: 220px; overflow-y: auto; z-index: 5; display: none; box-shadow: 0 4px 12px rgba(0,0,0,0.08); }
    .search-result-item { padding: 9px 12px; cursor: pointer; font-size: 13px; display: flex; align-items: center; gap: 8px; }
    .search-result-item:hover { background: var(--surface-raised); }
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
        <a href="compose.html" class="sidebar-link active"><i class="ti ti-pencil"></i> Compose</a>
        <a href="broadcasts.html" class="sidebar-link"><i class="ti ti-speakerphone"></i> Broadcasts</a>
        <a href="directory.html" class="sidebar-link"><i class="ti ti-users"></i> Directory</a>
        <a href="leave.html" class="sidebar-link"><i class="ti ti-calendar-event"></i> Leave &amp; Requests</a>
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
          <button class="topbar-bell" id="notifBell"><i class="ti ti-bell"></i><span class="dot" id="notifDot" style="display:none;">0</span></button>
          <div class="notif-dropdown" id="notifDropdown"></div>
        </div>
        <img class="topbar-avatar" src="assets/logo.jpeg" alt="You">
      </div>

      <div class="page-body">
        <h1 class="page-greeting" style="font-size: 22px;">Compose</h1>
        <p class="page-greeting-sub"><a href="inbox.html" style="color: var(--primary); text-decoration:none; font-weight:600;">← Back to inbox</a></p>

        <div id="alert" class="alert alert-error"></div>

        <div class="compose-card">
          <div class="compose-field">
            <label>To</label>
            <div class="compose-recipients" id="recipientChips">
              <input type="text" class="compose-recipient-input" id="recipientSearch" placeholder="Search staff by name or username…">
              <div class="search-results" id="searchResults"></div>
            </div>
          </div>
          <div class="compose-field">
            <label>Subject</label>
            <input type="text" id="subject" placeholder="What's this about?">
          </div>
          <div class="compose-body-area">
            <textarea id="body" placeholder="Write your message…"></textarea>
          </div>

          <div id="attachmentPreview" style="display:none; font-size:12.5px; color:var(--text-secondary); margin-top:10px;">
            <i class="ti ti-paperclip"></i> <span id="attachmentName"></span>
            <button onclick="clearAttachment()" style="background:none;border:none;color:var(--error);cursor:pointer;margin-left:8px;font-size:12px;">Remove</button>
          </div>

          <div class="compose-footer">
            <button id="attachBtn" style="background:none;border:1px solid var(--border);border-radius:50%;width:38px;height:38px;color:var(--text-secondary);cursor:pointer;font-size:15px;"><i class="ti ti-paperclip"></i></button>
            <input type="file" id="fileInput" accept=".pdf,.xlsx" style="display:none;">
            <div style="display:flex; gap:8px;">
              <button class="btn btn-ghost" id="saveDraftBtn" style="width:auto; padding:10px 20px;">Save as Draft</button>
              <button class="btn btn-primary" id="sendBtn" style="width:auto; padding:10px 24px;">Send</button>
            </div>
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

    let selectedRecipients = [];
    let pendingAttachment = null;
    let searchTimeout = null;

    async function init() {
      try {
        await apiRequest('/dashboard-check');
      } catch (err) {
        window.location.href = 'login.html';
        return;
      }
      loadUnreadBadge();

      const params = new URLSearchParams(window.location.search);
      const prefillId = params.get('to');
      const prefillName = params.get('name');
      if (prefillId && prefillName) {
        selectedRecipients.push({ id: prefillId, full_name: decodeURIComponent(prefillName) });
        renderChips();
      }
    }

    const searchInput = document.getElementById('recipientSearch');
    const searchResults = document.getElementById('searchResults');

    searchInput.addEventListener('input', () => {
      clearTimeout(searchTimeout);
      const q = searchInput.value.trim();
      if (!q) { searchResults.style.display = 'none'; return; }
      searchTimeout = setTimeout(() => searchStaff(q), 250);
    });

    async function searchStaff(query) {
      try {
        const result = await apiRequest('/staff?search=' + encodeURIComponent(query));
        const available = result.staff.filter(s => !selectedRecipients.find(r => r.id === s.id));
        if (available.length === 0) {
          searchResults.innerHTML = '<div class="search-result-item" style="color:var(--text-muted);">No matches.</div>';
        } else {
          searchResults.innerHTML = available.map(s =>
            '<div class="search-result-item" onclick=\'selectRecipient(' + JSON.stringify(s) + ')\'>' +
            '<span class="presence-dot ' + (s.isOnline ? 'online' : '') + '"></span>' +
            '<span>' + s.full_name + ' · ' + s.username + '</span></div>'
          ).join('');
        }
        searchResults.style.display = 'block';
      } catch (err) {
        searchResults.style.display = 'none';
      }
    }

    function selectRecipient(staff) {
      selectedRecipients.push(staff);
      renderChips();
      searchInput.value = '';
      searchResults.style.display = 'none';
    }

    function removeRecipient(id) {
      selectedRecipients = selectedRecipients.filter(r => r.id !== id);
      renderChips();
    }

    function renderChips() {
      const chipsHtml = selectedRecipients.map(r =>
        '<span class="compose-chip">' + r.full_name + ' <button onclick="removeRecipient(\'' + r.id + '\')">×</button></span>'
      ).join('');
      const container = document.getElementById('recipientChips');
      const inputWrap = container.querySelector('#recipientSearch');
      container.innerHTML = chipsHtml + '<input type="text" class="compose-recipient-input" id="recipientSearch" placeholder="Search staff by name or username…"><div class="search-results" id="searchResults"></div>';
      document.getElementById('recipientSearch').addEventListener('input', searchInputHandler);
    }

    function searchInputHandler() {
      clearTimeout(searchTimeout);
      const q = document.getElementById('recipientSearch').value.trim();
      const sr = document.getElementById('searchResults');
      if (!q) { sr.style.display = 'none'; return; }
      searchTimeout = setTimeout(() => searchStaff(q), 250);
    }

    document.getElementById('attachBtn').addEventListener('click', () => {
      document.getElementById('fileInput').click();
    });

    document.getElementById('fileInput').addEventListener('change', async (e) => {
      const file = e.target.files[0];
      if (!file) return;
      const alertEl = document.getElementById('alert');
      hideAlert(alertEl);

      const formData = new FormData();
      formData.append('attachment', file);

      try {
        const res = await fetch('/api/accounting/messages/upload', {
          method: 'POST', credentials: 'include', body: formData
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Upload failed.');
        pendingAttachment = data;
        document.getElementById('attachmentName').textContent = data.name;
        document.getElementById('attachmentPreview').style.display = 'block';
      } catch (err) {
        showAlert(alertEl, err.message);
      }
      e.target.value = '';
    });

    function clearAttachment() {
      pendingAttachment = null;
      document.getElementById('attachmentPreview').style.display = 'none';
    }

    document.getElementById('sendBtn').addEventListener('click', () => submitCompose('sent'));
    document.getElementById('saveDraftBtn').addEventListener('click', () => submitCompose('draft'));

    async function submitCompose(status) {
      const alertEl = document.getElementById('alert');
      hideAlert(alertEl);

      const subject = document.getElementById('subject').value.trim();
      const body = document.getElementById('body').value.trim();

      if (selectedRecipients.length === 0) {
        showAlert(alertEl, 'Add at least one recipient.');
        return;
      }
      if (!subject) {
        showAlert(alertEl, 'Add a subject.');
        return;
      }

      try {
        const result = await apiRequest('/messages/compose', {
          method: 'POST',
          body: {
            recipientIds: selectedRecipients.map(r => r.id),
            subject: subject,
            body: body,
            status: status,
            attachmentUrl: pendingAttachment ? pendingAttachment.url : undefined,
            attachmentType: pendingAttachment ? pendingAttachment.type : undefined
          }
        });
        window.location.href = 'inbox.html?id=' + result.conversationId;
      } catch (err) {
        showAlert(alertEl, err.message);
      }
    }

    document.addEventListener('click', (e) => {
      if (!e.target.closest('.compose-recipients')) {
        const sr = document.getElementById('searchResults');
        if (sr) sr.style.display = 'none';
      }
    });

    init();
  </script>
</body>
</html>

EOF_ACCOUNTING_COMPOSE_HTML

cat > accounting/dashboard.html << 'EOF_ACCOUNTING_DASHBOARD_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Dashboard — MACDEN Portal</title>
  <link rel="stylesheet" href="assets/portal-style.css">
  <link rel="stylesheet" href="assets/portal-shell.css">
</head>
<body>
  <div class="app-shell">
    <div class="sidebar">
      <div class="sidebar-brand">
        <img src="assets/logo.jpeg" alt="MACDEN">
        <span>MACDEN</span>
      </div>
      <nav class="sidebar-nav">
        <a href="dashboard.html" class="sidebar-link active"><i class="ti ti-layout-dashboard"></i> Dashboard</a>
        <a href="inbox.html" class="sidebar-link"><i class="ti ti-mail"></i> Inbox <span class="badge" id="unreadBadge" style="display:none;">0</span></a>
        <a href="compose.html" class="sidebar-link"><i class="ti ti-pencil"></i> Compose</a>
        <a href="broadcasts.html" class="sidebar-link"><i class="ti ti-speakerphone"></i> Broadcasts</a>
        <a href="directory.html" class="sidebar-link"><i class="ti ti-users"></i> Directory</a>
        <a href="leave.html" class="sidebar-link"><i class="ti ti-calendar-event"></i> Leave &amp; Requests</a>
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
          <button class="topbar-bell" id="notifBell"><i class="ti ti-bell"></i><span class="dot" id="notifDot" style="display:none;">0</span></button>
          <div class="notif-dropdown" id="notifDropdown"></div>
        </div>
        <img class="topbar-avatar" src="assets/logo.jpeg" alt="You">
      </div>

      <div class="page-body">
        <h1 class="page-greeting" id="greeting">Hello,</h1>
        <p class="page-greeting-sub" id="greetingSub">—</p>

        <div class="dash-grid">
          <div class="panel">
            <div class="panel-header">
              <h2>Announcements</h2>
              <a href="#">View all</a>
            </div>
            <div class="empty-note">Company-wide broadcasts aren't built yet — this fills in once the Broadcasts feature is live.</div>
          </div>

          <div class="panel">
            <div class="panel-header"><h2>Quick Actions</h2></div>
            <a href="inbox.html" class="quick-action"><i class="ti ti-mail"></i> Open Inbox</a>
            <a href="leave.html" class="quick-action"><i class="ti ti-calendar-event"></i> Request Leave</a>
            <a href="directory.html" class="quick-action"><i class="ti ti-users"></i> Staff Directory</a>
          </div>
        </div>

        <div class="stat-grid">
          <div class="stat-card">
            <div class="num" id="statUnread">—</div>
            <div class="lbl">Unread Messages</div>
          </div>
          <div class="stat-card">
            <div class="num">—</div>
            <div class="lbl">Pending Requests (coming soon)</div>
          </div>
          <div class="stat-card">
            <div class="num">—</div>
            <div class="lbl">Tasks Assigned (coming soon)</div>
          </div>
          <div class="stat-card">
            <div class="num">—</div>
            <div class="lbl">Approvals (coming soon)</div>
          </div>
        </div>
      </div>
    </div>
  </div>

  <script src="assets/api.js"></script>
  <script src="assets/notifications.js"></script>
  <script>
    async function init() {
      try {
        const result = await apiRequest('/dashboard-check');
        const staff = result.staff;
        document.getElementById('greeting').textContent = `Hello, ${staff.fullName.split(' ')[0]} 👋`;
        document.getElementById('greetingSub').textContent = `${staff.role} · MACDEN`;
      } catch (err) {
        window.location.href = 'login.html';
        return;
      }

      try {
        const unread = await apiRequest('/messages/unread-count');
        document.getElementById('statUnread').textContent = unread.unreadCount;
        if (unread.unreadCount > 0) {
          const badge = document.getElementById('unreadBadge');
          badge.textContent = unread.unreadCount;
          badge.style.display = 'inline-block';
          const dot = document.getElementById('notifDot');
          dot.textContent = unread.unreadCount;
          dot.style.display = 'flex';
        }
      } catch (err) {
        document.getElementById('statUnread').textContent = '0';
      }
    }

    document.getElementById('logoutBtn').addEventListener('click', async () => {
      await apiRequest('/auth/logout', { method: 'POST' });
      window.location.href = 'login.html';
    });

    init();
  </script>
</body>
</html>

EOF_ACCOUNTING_DASHBOARD_HTML

cat > accounting/directory.html << 'EOF_ACCOUNTING_DIRECTORY_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Staff Directory — MACDEN Portal</title>
  <link rel="stylesheet" href="assets/portal-style.css">
  <link rel="stylesheet" href="assets/portal-shell.css">
  <link rel="stylesheet" href="assets/portal-inbox.css">
  <style>
    .dir-toolbar { display: flex; gap: 12px; margin-bottom: 18px; }
    .dir-toolbar input {
      flex: 1; max-width: 380px; background: var(--surface); border: 1px solid var(--border);
      border-radius: var(--radius-sm); padding: 10px 14px; font-size: 13px; font-family: var(--font-body);
      color: var(--text-primary);
    }
    .dir-list { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-md); overflow: hidden; }
    .dir-header-row { display: grid; grid-template-columns: 220px 160px 160px 1fr 130px; gap: 14px; padding: 12px 20px; font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.04em; color: var(--text-muted); border-bottom: 1px solid var(--border); }
    .dir-row { display: grid; grid-template-columns: 220px 160px 160px 1fr 130px; gap: 14px; align-items: center; padding: 13px 20px; border-bottom: 1px solid var(--border); cursor: pointer; }
    .dir-row:last-child { border-bottom: none; }
    .dir-row:hover { background: var(--surface-raised); }
    .dir-name-cell { display: flex; align-items: center; gap: 10px; font-size: 13.5px; font-weight: 600; color: var(--text-primary); }
    .dir-avatar { width: 32px; height: 32px; border-radius: 50%; background: var(--gold-dim); color: #a17a00; display: flex; align-items: center; justify-content: center; font-size: 11.5px; font-weight: 700; flex-shrink: 0; position: relative; }
    .dir-cell { font-size: 12.5px; color: var(--text-secondary); }
    .dir-role-badge { display: inline-block; padding: 2px 9px; border-radius: 999px; font-size: 10.5px; font-weight: 700; text-transform: uppercase; background: var(--primary-dim); color: var(--primary); }
    .dir-empty { padding: 60px 20px; text-align: center; color: var(--text-muted); font-size: 13px; }

    .profile-field-row { display: flex; justify-content: space-between; padding: 10px 0; border-bottom: 1px solid var(--border); font-size: 13px; }
    .profile-field-row:last-child { border-bottom: none; }
    .profile-field-label { color: var(--text-secondary); }
    .profile-field-value { color: var(--text-primary); font-weight: 500; }
    .profile-field-value.muted { color: var(--text-muted); font-style: italic; font-weight: 400; }
    .profile-avatar-large { width: 72px; height: 72px; border-radius: 50%; background: var(--gold-dim); color: #a17a00; display: flex; align-items: center; justify-content: center; font-size: 24px; font-weight: 700; margin: 0 auto 14px; }
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
        <a href="directory.html" class="sidebar-link active"><i class="ti ti-users"></i> Directory</a>
        <a href="leave.html" class="sidebar-link"><i class="ti ti-calendar-event"></i> Leave &amp; Requests</a>
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
          <button class="topbar-bell" id="notifBell"><i class="ti ti-bell"></i><span class="dot" id="notifDot" style="display:none;">0</span></button>
          <div class="notif-dropdown" id="notifDropdown"></div>
        </div>
        <img class="topbar-avatar" src="assets/logo.jpeg" alt="You">
      </div>

      <div class="page-body">
        <h1 class="page-greeting" style="font-size: 22px;">Staff Directory</h1>
        <p class="page-greeting-sub"><a href="dashboard.html" style="color: var(--primary); text-decoration:none; font-weight:600;">← Back to dashboard</a></p>

        <div class="dir-toolbar">
          <input type="text" id="dirSearch" placeholder="Search by name or username…">
          <a href="manage-staff.html" class="btn btn-primary" id="manageStaffLink" style="width:auto; padding:10px 18px; text-decoration:none; display:none; align-items:center; gap:8px; margin-left:auto;"><i class="ti ti-settings"></i> Manage Staff</a>
        </div>

        <div class="dir-list">
          <div class="dir-header-row">
            <div>Staff Member</div><div>Role</div><div>Department</div><div>Email</div><div>Status</div>
          </div>
          <div id="dirRows">
            <div class="dir-empty">Loading…</div>
          </div>
        </div>
      </div>
    </div>
  </div>

  <div class="modal-backdrop" id="profileModalBackdrop">
    <div class="modal" style="width: 380px; text-align: center;">
      <button onclick="closeProfileModal()" style="float:right; background:none; border:none; cursor:pointer; color:var(--text-muted); font-size:16px;"><i class="ti ti-x"></i></button>
      <div class="profile-avatar-large" id="profileAvatar">—</div>
      <h3 id="profileName" style="text-align:center; font-size:17px;">—</h3>
      <p id="profileRole" style="text-align:center; color:var(--text-secondary); font-size:12.5px; margin-top:-6px;">—</p>

      <div style="text-align:left; margin-top:18px;">
        <div class="profile-field-row"><span class="profile-field-label">Department</span><span class="profile-field-value" id="profileDept">—</span></div>
        <div class="profile-field-row"><span class="profile-field-label">Username</span><span class="profile-field-value" id="profileUsername">—</span></div>
        <div class="profile-field-row"><span class="profile-field-label">Email</span><span class="profile-field-value" id="profileEmail">—</span></div>
        <div class="profile-field-row"><span class="profile-field-label">Date Joined</span><span class="profile-field-value" id="profileDate">—</span></div>
        <div class="profile-field-row"><span class="profile-field-label">Phone</span><span class="profile-field-value muted">Not yet added</span></div>
        <div class="profile-field-row"><span class="profile-field-label">Branch</span><span class="profile-field-value muted">Not yet added</span></div>
      </div>

      <button class="btn btn-primary" id="messageProfileBtn" style="margin-top:18px; display:inline-flex; align-items:center; justify-content:center; gap:8px; width:auto; padding:10px 24px;">
        <i class="ti ti-mail"></i> Message
      </button>
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

    let staffCache = [];
    let searchTimeout = null;

    async function init() {
      try {
        const result = await apiRequest('/dashboard-check');
        if (result.staff.role === 'admin') {
          document.getElementById('manageStaffLink').style.display = 'inline-flex';
        }
      } catch (err) {
        window.location.href = 'login.html';
        return;
      }
      loadUnreadBadge();
      loadDirectory('');
    }

    async function loadDirectory(query) {
      const rows = document.getElementById('dirRows');
      try {
        const result = await apiRequest('/staff?search=' + encodeURIComponent(query));
        staffCache = result.staff;

        if (result.staff.length === 0) {
          rows.innerHTML = '<div class="dir-empty">No staff found.</div>';
          return;
        }

        rows.innerHTML = result.staff.map(s => {
          const statusDot = s.isOnline ? '<span style="color:var(--primary-light); font-size:11px;">● Online</span>' : '<span style="color:var(--text-muted); font-size:11px;">○ Offline</span>';
          return '<div class="dir-row" onclick="openProfile(\'' + s.id + '\')">' +
            '<div class="dir-name-cell"><span class="dir-avatar">' + initials(s.full_name) + '</span>' + s.full_name + '</div>' +
            '<div class="dir-cell"><span class="dir-role-badge">' + s.role + '</span></div>' +
            '<div class="dir-cell">' + (s.department || '—') + '</div>' +
            '<div class="dir-cell">' + s.email + '</div>' +
            '<div class="dir-cell">' + statusDot + '</div>' +
            '</div>';
        }).join('');
      } catch (err) {
        rows.innerHTML = '<div class="dir-empty">Could not load directory.</div>';
      }
    }

    document.getElementById('dirSearch').addEventListener('input', (e) => {
      clearTimeout(searchTimeout);
      searchTimeout = setTimeout(() => loadDirectory(e.target.value.trim()), 250);
    });

    function openProfile(id) {
      const person = staffCache.find(s => s.id === id);
      if (!person) return;

      document.getElementById('profileAvatar').textContent = initials(person.full_name);
      document.getElementById('profileName').textContent = person.full_name;
      document.getElementById('profileRole').textContent = person.role + (person.department ? ' · ' + person.department : '');
      document.getElementById('profileDept').textContent = person.department || '—';
      document.getElementById('profileUsername').textContent = person.username;
      document.getElementById('profileEmail').textContent = person.email;
      document.getElementById('profileDate').textContent = person.dateStarted ? new Date(person.dateStarted).toLocaleDateString() : '—';

      document.getElementById('messageProfileBtn').onclick = () => {
        window.location.href = 'compose.html?to=' + person.id + '&name=' + encodeURIComponent(person.full_name);
      };

      document.getElementById('profileModalBackdrop').classList.add('visible');
    }

    function closeProfileModal() {
      document.getElementById('profileModalBackdrop').classList.remove('visible');
    }

    init();
  </script>
</body>
</html>

EOF_ACCOUNTING_DIRECTORY_HTML

cat > accounting/documents.html << 'EOF_ACCOUNTING_DOCUMENTS_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Documents — MACDEN Portal</title>
  <link rel="stylesheet" href="assets/portal-style.css">
  <link rel="stylesheet" href="assets/portal-shell.css">
  <link rel="stylesheet" href="assets/portal-inbox.css">
  <style>
    .doc-grid { display: grid; grid-template-columns: 220px 1fr; gap: 20px; }
    .doc-categories { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-md); padding: 10px; height: fit-content; }
    .doc-cat-item { display: flex; justify-content: space-between; padding: 9px 12px; border-radius: var(--radius-sm); font-size: 13px; cursor: pointer; color: var(--text-primary); }
    .doc-cat-item:hover { background: var(--surface-raised); }
    .doc-cat-item.active { background: var(--primary-dim); color: var(--primary); font-weight: 600; }
    .doc-cat-count { color: var(--text-muted); font-size: 11.5px; }

    .doc-toolbar { display: flex; justify-content: space-between; align-items: center; margin-bottom: 14px; }
    .doc-list { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-md); overflow: hidden; }
    .doc-header-row { display: grid; grid-template-columns: 1fr 140px 110px 90px 90px; gap: 14px; padding: 12px 18px; font-size: 10.5px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.04em; color: var(--text-muted); border-bottom: 1px solid var(--border); }
    .doc-row { display: grid; grid-template-columns: 1fr 140px 110px 90px 90px; gap: 14px; align-items: center; padding: 13px 18px; border-bottom: 1px solid var(--border); font-size: 13px; }
    .doc-row:last-child { border-bottom: none; }
    .doc-name-cell { display: flex; align-items: center; gap: 10px; font-weight: 500; color: var(--text-primary); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .doc-icon { font-size: 17px; flex-shrink: 0; }
    .doc-empty { padding: 50px 18px; text-align: center; color: var(--text-muted); font-size: 13px; }
    .doc-download-btn { border: 1px solid var(--border); border-radius: var(--radius-sm); padding: 6px 12px; font-size: 11.5px; font-weight: 600; color: var(--text-primary); text-decoration: none; display: inline-flex; align-items: center; gap: 6px; }
    .doc-download-btn:hover { border-color: var(--primary); color: var(--primary); }
    .doc-delete-btn { background: none; border: none; color: var(--text-muted); cursor: pointer; font-size: 14px; }
    .doc-delete-btn:hover { color: var(--error); }
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
        <a href="documents.html" class="sidebar-link active"><i class="ti ti-file-text"></i> Documents</a>
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
          <button class="topbar-bell" id="notifBell"><i class="ti ti-bell"></i><span class="dot" id="notifDot" style="display:none;">0</span></button>
          <div class="notif-dropdown" id="notifDropdown"></div>
        </div>
        <img class="topbar-avatar" src="assets/logo.jpeg" alt="You">
      </div>

      <div class="page-body">
        <div class="doc-toolbar">
          <div>
            <h1 class="page-greeting" style="font-size: 22px;">Documents</h1>
            <p class="page-greeting-sub" style="margin:0;"><a href="dashboard.html" style="color: var(--primary); text-decoration:none; font-weight:600;">← Back to dashboard</a></p>
          </div>
          <div>
            <button class="btn btn-primary" id="uploadBtn" style="width:auto; padding:10px 20px; display:none; align-items:center; gap:8px;"><i class="ti ti-upload"></i> Upload</button>
            <input type="file" id="fileInput" accept=".pdf,.xlsx,.docx,.doc,.xls" style="display:none;">
          </div>
        </div>

        <div id="alert" class="alert alert-error"></div>

        <div class="doc-grid">
          <div class="doc-categories" id="categoryList">
            <div class="doc-cat-item active" data-cat="All Documents" onclick="selectCategory('All Documents')">
              <span>All Documents</span><span class="doc-cat-count" id="catCountAll">—</span>
            </div>
            <div class="doc-cat-item" data-cat="HR Forms" onclick="selectCategory('HR Forms')"><span>HR Forms</span></div>
            <div class="doc-cat-item" data-cat="Company Policies" onclick="selectCategory('Company Policies')"><span>Company Policies</span></div>
            <div class="doc-cat-item" data-cat="Branch Reports" onclick="selectCategory('Branch Reports')"><span>Branch Reports</span></div>
            <div class="doc-cat-item" data-cat="Templates" onclick="selectCategory('Templates')"><span>Templates</span></div>
            <div class="doc-cat-item" data-cat="Finance & Accounting" onclick="selectCategory('Finance & Accounting')"><span>Finance &amp; Accounting</span></div>
          </div>

          <div class="doc-list">
            <div class="doc-header-row"><div>File Name</div><div>Uploaded By</div><div>Date</div><div>Size</div><div></div></div>
            <div id="docRows"><div class="doc-empty">Loading…</div></div>
          </div>
        </div>
      </div>
    </div>
  </div>

  <div class="modal-backdrop" id="uploadModalBackdrop">
    <div class="modal">
      <h3>Upload Document</h3>
      <div id="uploadAlert" class="alert alert-error"></div>
      <div class="lv-form-field" style="margin-bottom:14px;">
        <label style="display:block; font-size:12.5px; font-weight:600; margin-bottom:6px;">Category</label>
        <select id="uploadCategory" style="width:100%; padding:9px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); font-family:var(--font-body);">
          <option>HR Forms</option>
          <option>Company Policies</option>
          <option>Branch Reports</option>
          <option>Templates</option>
          <option>Finance & Accounting</option>
        </select>
      </div>
      <button class="btn btn-ghost" id="chooseFileBtn" style="width:100%;">Choose file…</button>
      <p id="chosenFileName" style="font-size:12px; color:var(--text-secondary); margin-top:8px;"></p>
      <div class="modal-actions">
        <button class="btn btn-ghost" id="uploadCancelBtn">Cancel</button>
        <button class="btn btn-primary" id="uploadConfirmBtn" disabled>Upload</button>
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

    let isAdmin = false;
    let currentCategory = 'All Documents';
    let selectedFile = null;

    async function init() {
      try {
        const result = await apiRequest('/dashboard-check');
        isAdmin = result.staff.role === 'admin';
        if (isAdmin) document.getElementById('uploadBtn').style.display = 'inline-flex';
      } catch (err) {
        window.location.href = 'login.html';
        return;
      }
      loadUnreadBadge();
      loadDocuments();
    }

    function selectCategory(cat) {
      currentCategory = cat;
      document.querySelectorAll('.doc-cat-item').forEach(el => el.classList.toggle('active', el.dataset.cat === cat));
      loadDocuments();
    }

    function iconFor(mimeType) {
      if (mimeType && mimeType.includes('pdf')) return '<i class="ti ti-file-type-pdf" style="color:#dc2626;"></i>';
      if (mimeType && (mimeType.includes('spreadsheet') || mimeType.includes('excel'))) return '<i class="ti ti-file-spreadsheet" style="color:#1e7a3e;"></i>';
      return '<i class="ti ti-file-word" style="color:#2563eb;"></i>';
    }

    async function loadDocuments() {
      const rows = document.getElementById('docRows');
      try {
        const result = await apiRequest('/documents?category=' + encodeURIComponent(currentCategory));
        document.getElementById('catCountAll').textContent = currentCategory === 'All Documents' ? result.documents.length : '';

        if (result.documents.length === 0) {
          rows.innerHTML = '<div class="doc-empty">No documents in this category yet.</div>';
          return;
        }

        rows.innerHTML = result.documents.map(d => {
          const deleteBtn = isAdmin ? '<button class="doc-delete-btn" onclick="deleteDocument(\'' + d.id + '\')" aria-label="Delete"><i class="ti ti-trash"></i></button>' : '';
          return '<div class="doc-row">' +
            '<div class="doc-name-cell"><span class="doc-icon">' + iconFor(d.mimeType) + '</span>' + d.fileName + '</div>' +
            '<div>' + d.uploadedBy + '</div>' +
            '<div>' + new Date(d.createdAt).toLocaleDateString() + '</div>' +
            '<div>' + d.fileSize + '</div>' +
            '<div style="display:flex; gap:8px; align-items:center;"><a class="doc-download-btn" href="' + d.fileUrl + '" target="_blank" rel="noopener"><i class="ti ti-download"></i> Download</a>' + deleteBtn + '</div>' +
            '</div>';
        }).join('');
      } catch (err) {
        rows.innerHTML = '<div class="doc-empty">' + err.message + '</div>';
      }
    }

    async function deleteDocument(id) {
      if (!confirm('Delete this document? This cannot be undone.')) return;
      try {
        await apiRequest('/documents/' + id, { method: 'DELETE' });
        loadDocuments();
      } catch (err) {
        alert(err.message);
      }
    }

    document.getElementById('uploadBtn').addEventListener('click', () => {
      selectedFile = null;
      document.getElementById('chosenFileName').textContent = '';
      document.getElementById('uploadConfirmBtn').disabled = true;
      hideAlert(document.getElementById('uploadAlert'));
      document.getElementById('uploadModalBackdrop').classList.add('visible');
    });

    document.getElementById('uploadCancelBtn').addEventListener('click', () => {
      document.getElementById('uploadModalBackdrop').classList.remove('visible');
    });

    document.getElementById('chooseFileBtn').addEventListener('click', () => {
      document.getElementById('fileInput').click();
    });

    document.getElementById('fileInput').addEventListener('change', (e) => {
      const file = e.target.files[0];
      if (!file) return;
      selectedFile = file;
      document.getElementById('chosenFileName').textContent = file.name;
      document.getElementById('uploadConfirmBtn').disabled = false;
    });

    document.getElementById('uploadConfirmBtn').addEventListener('click', async () => {
      if (!selectedFile) return;
      const alertEl = document.getElementById('uploadAlert');
      hideAlert(alertEl);
      const btn = document.getElementById('uploadConfirmBtn');
      btn.disabled = true;
      btn.textContent = 'Uploading…';

      const formData = new FormData();
      formData.append('file', selectedFile);
      formData.append('category', document.getElementById('uploadCategory').value);

      try {
        const res = await fetch('/api/accounting/documents/upload', {
          method: 'POST', credentials: 'include', body: formData
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Upload failed.');

        document.getElementById('uploadModalBackdrop').classList.remove('visible');
        loadDocuments();
      } catch (err) {
        showAlert(alertEl, err.message);
      } finally {
        btn.disabled = false;
        btn.textContent = 'Upload';
      }
    });

    init();
  </script>
</body>
</html>

EOF_ACCOUNTING_DOCUMENTS_HTML

cat > accounting/inbox.html << 'EOF_ACCOUNTING_INBOX_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Inbox — MACDEN Portal</title>
  <link rel="stylesheet" href="assets/portal-style.css">
  <link rel="stylesheet" href="assets/portal-shell.css">
  <link rel="stylesheet" href="assets/portal-inbox.css">
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
        <a href="inbox.html" class="sidebar-link active"><i class="ti ti-mail"></i> Inbox <span class="badge" id="unreadBadge" style="display:none;">0</span></a>
        <a href="compose.html" class="sidebar-link"><i class="ti ti-pencil"></i> Compose</a>
        <a href="broadcasts.html" class="sidebar-link"><i class="ti ti-speakerphone"></i> Broadcasts</a>
        <a href="directory.html" class="sidebar-link"><i class="ti ti-users"></i> Directory</a>
        <a href="leave.html" class="sidebar-link"><i class="ti ti-calendar-event"></i> Leave &amp; Requests</a>
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
          <button class="topbar-bell" id="notifBell"><i class="ti ti-bell"></i><span class="dot" id="notifDot" style="display:none;">0</span></button>
          <div class="notif-dropdown" id="notifDropdown"></div>
        </div>
        <img class="topbar-avatar" src="assets/logo.jpeg" alt="You">
      </div>

      <div class="page-body">

        <!-- LIST VIEW -->
        <div id="listView">
          <div class="email-toolbar">
            <div>
              <h1 class="page-greeting" style="font-size: 22px;">Inbox</h1>
              <p class="page-greeting-sub" style="margin:0;"><a href="dashboard.html" style="color: var(--primary); text-decoration:none; font-weight:600;">← Back to dashboard</a></p>
            </div>
            <a href="compose.html" class="btn btn-primary" style="width:auto; padding:10px 20px; text-decoration:none; display:inline-flex; align-items:center; gap:8px;"><i class="ti ti-pencil"></i> New Message</a>
          </div>

          <div class="email-list" id="emailList">
            <div class="email-empty">Loading…</div>
          </div>
        </div>

        <!-- DETAIL VIEW -->
        <div id="detailView" style="display:none;">
          <div class="email-detail-toolbar">
            <a href="inbox.html" class="email-back"><i class="ti ti-arrow-left"></i> Back to Inbox</a>
          </div>

          <div class="email-card">
            <h2 class="email-detail-subject" id="detailSubject">—</h2>
            <div id="messagesContainer"></div>
            <div class="email-action-row">
              <button class="email-action-btn" onclick="document.getElementById('replyBody').focus()"><i class="ti ti-arrow-back-up"></i> Reply</button>
              <button class="email-action-btn" onclick="document.getElementById('replyBody').focus()"><i class="ti ti-arrow-back-up-double"></i> Reply All</button>
              <button class="email-action-btn" disabled title="Coming soon" style="opacity:0.5; cursor:not-allowed;"><i class="ti ti-arrow-forward-up"></i> Forward</button>
              <button class="email-action-btn danger" onclick="deleteConversation(currentConversationId, document.getElementById('detailSubject').textContent)"><i class="ti ti-trash"></i> Delete</button>
            </div>
          </div>

          <div class="reply-box visible" id="replyBox">
            <div class="reply-box-label" id="replyLabel">Reply</div>
            <div id="attachmentPreview" style="display:none; font-size:12.5px; color:var(--text-secondary); margin-bottom:8px;">
              <i class="ti ti-paperclip"></i> <span id="attachmentName"></span>
              <button onclick="clearAttachment()" style="background:none;border:none;color:var(--error);cursor:pointer;margin-left:8px;font-size:12px;">Remove</button>
            </div>
            <div id="attachmentAlert" class="alert alert-error" style="display:none;"></div>
            <textarea id="replyBody" placeholder="Write your reply…"></textarea>
            <div class="reply-box-footer">
              <button class="reply-attach-btn" id="attachBtn" aria-label="Attach file"><i class="ti ti-paperclip"></i></button>
              <input type="file" id="fileInput" accept=".pdf,.xlsx" style="display:none;">
              <button class="btn btn-primary" id="sendReplyBtn" style="width:auto; padding:10px 22px;">Send</button>
            </div>
          </div>
        </div>

      </div>
    </div>
  </div>

  <div class="modal-backdrop" id="deleteModalBackdrop">
    <div class="modal">
      <h3>Delete conversation?</h3>
      <p id="deleteModalText">This will permanently delete this conversation.</p>
      <div id="deleteModalAlert" class="alert alert-error"></div>
      <div class="modal-actions">
        <button class="btn btn-ghost" id="deleteModalCancel">Cancel</button>
        <button class="btn btn-primary" id="deleteModalConfirm" style="background: var(--error); color: #fff;">Delete</button>
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

    let currentStaffId = null;
    let currentConversationId = null;
    const params = new URLSearchParams(window.location.search);
    const openId = params.get('id');

    function initials(name) {
      if (!name) return '?';
      return name.split(' ').map(p => p[0]).join('').slice(0, 2).toUpperCase();
    }

    async function init() {
      try {
        const result = await apiRequest('/dashboard-check');
        currentStaffId = result.staff.id;
      } catch (err) {
        window.location.href = 'login.html';
        return;
      }

      if (openId) {
        openMessage(openId);
      } else {
        loadList();
      }
      loadUnreadBadge();
    }

    async function loadList() {
      const list = document.getElementById('emailList');
      try {
        const result = await apiRequest('/messages/conversations');
        if (result.conversations.length === 0) {
          list.innerHTML = '<div class="email-empty">No messages yet. Click New Message to start one.</div>';
          return;
        }
        list.innerHTML = result.conversations.map(c => {
          const senderName = c.displayName || 'Unknown';
          const unread = c.isUnread ? 'unread' : '';
          return '<div class="email-row ' + unread + '" onclick="window.location.href=\'inbox.html?id=' + c.id + '\'">' +
            '<div class="email-sender"><span class="email-sender-avatar">' + initials(senderName) + '</span>' + senderName + '</div>' +
            '<div class="email-subject">' + (c.subject || '(no subject)') + ' <span class="preview">— ' + (c.lastMessagePreview || 'No messages yet') + '</span></div>' +
            '<div class="email-date">' + (c.lastMessageAt ? new Date(c.lastMessageAt).toLocaleDateString() : '') + '</div>' +
            '<button class="email-row-delete" onclick="event.stopPropagation(); deleteConversation(\'' + c.id + '\', \'' + (c.subject || 'this message').replace(/'/g, "\\'") + '\')" aria-label="Delete"><i class="ti ti-trash"></i></button>' +
            '</div>';
        }).join('');
      } catch (err) {
        list.innerHTML = '<div class="email-empty">Could not load inbox.</div>';
      }
    }

    async function openMessage(id) {
      currentConversationId = id;
      document.getElementById('listView').style.display = 'none';
      document.getElementById('detailView').style.display = 'block';

      try {
        const result = await apiRequest('/messages/conversations/' + id);
        document.getElementById('detailSubject').textContent = result.subject || '(no subject)';
        document.getElementById('replyLabel').textContent = 'Replying to: ' + result.toLine;

        const container = document.getElementById('messagesContainer');
        container.innerHTML = result.messages.map(m => {
          let attachmentHtml = '';
          if (m.attachment_url) {
            const icon = m.attachment_type === 'pdf' ? 'ti-file-type-pdf' : 'ti-file-spreadsheet';
            attachmentHtml = '<a href="' + m.attachment_url + '" target="_blank" rel="noopener" class="email-attachment"><i class="ti ' + icon + '"></i> Download attachment</a>';
          }
          return '<div class="email-meta-row">' +
            '<div class="email-meta-avatar">' + initials(m.senderName) + '</div>' +
            '<div class="email-meta-text">' +
              '<div class="email-meta-from">' + m.senderName + (m.status === 'draft' ? ' (draft)' : '') + '</div>' +
              '<div class="email-meta-to">To: ' + result.toLine + '</div>' +
              '<div class="email-body-text">' + (m.body || '') + '</div>' +
              attachmentHtml +
            '</div>' +
            '<div class="email-meta-date">' + (m.sent_at ? new Date(m.sent_at).toLocaleString() : '') + '</div>' +
            '</div>';
        }).join('<hr style="border:none;border-top:1px solid var(--border);margin:16px 0;">');

        loadUnreadBadge();
      } catch (err) {
        document.getElementById('messagesContainer').innerHTML = '<div style="color:var(--text-muted);font-size:13px;">' + err.message + '</div>';
      }
    }

    document.getElementById('sendReplyBtn').addEventListener('click', async () => {
      const textarea = document.getElementById('replyBody');
      const body = textarea.value.trim();
      if ((!body && !pendingAttachment) || !currentConversationId) return;

      const sendBtn = document.getElementById('sendReplyBtn');
      sendBtn.disabled = true;
      const savedBody = body;
      const savedAttachment = pendingAttachment;
      textarea.value = '';
      clearAttachment();

      try {
        await apiRequest('/messages/conversations/' + currentConversationId + '/reply', {
          method: 'POST',
          body: {
            body: savedBody,
            status: 'sent',
            attachmentUrl: savedAttachment ? savedAttachment.url : undefined,
            attachmentType: savedAttachment ? savedAttachment.type : undefined
          }
        });
        openMessage(currentConversationId);
      } catch (err) {
        alert(err.message);
        textarea.value = savedBody;
        pendingAttachment = savedAttachment;
      } finally {
        sendBtn.disabled = false;
      }
    });

    let pendingAttachment = null;

    document.getElementById('attachBtn').addEventListener('click', () => {
      document.getElementById('fileInput').click();
    });

    document.getElementById('fileInput').addEventListener('change', async (e) => {
      const file = e.target.files[0];
      if (!file) return;
      const alertEl = document.getElementById('attachmentAlert');
      hideAlert(alertEl);

      const formData = new FormData();
      formData.append('attachment', file);

      try {
        const res = await fetch('/api/accounting/messages/upload', {
          method: 'POST', credentials: 'include', body: formData
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Upload failed.');
        pendingAttachment = data;
        document.getElementById('attachmentName').textContent = data.name;
        document.getElementById('attachmentPreview').style.display = 'block';
      } catch (err) {
        showAlert(alertEl, err.message);
      }
      e.target.value = '';
    });

    function clearAttachment() {
      pendingAttachment = null;
      document.getElementById('attachmentPreview').style.display = 'none';
    }

    let pendingDeleteId = null;

    function deleteConversation(id, subject) {
      pendingDeleteId = id;
      document.getElementById('deleteModalText').textContent = 'This will permanently delete "' + subject + '". This cannot be undone.';
      hideAlert(document.getElementById('deleteModalAlert'));
      document.getElementById('deleteModalBackdrop').classList.add('visible');
    }

    document.getElementById('deleteModalCancel').addEventListener('click', () => {
      document.getElementById('deleteModalBackdrop').classList.remove('visible');
      pendingDeleteId = null;
    });

    document.getElementById('deleteModalConfirm').addEventListener('click', async () => {
      if (!pendingDeleteId) return;
      const alertEl = document.getElementById('deleteModalAlert');
      const btn = document.getElementById('deleteModalConfirm');
      hideAlert(alertEl);
      btn.disabled = true;
      btn.textContent = 'Deleting…';
      try {
        await apiRequest('/messages/conversations/' + pendingDeleteId, { method: 'DELETE' });
        document.getElementById('deleteModalBackdrop').classList.remove('visible');
        pendingDeleteId = null;
        window.location.href = 'inbox.html';
      } catch (err) {
        showAlert(alertEl, err.message);
      } finally {
        btn.disabled = false;
        btn.textContent = 'Delete';
      }
    });

    init();
  </script>
</body>
</html>

EOF_ACCOUNTING_INBOX_HTML

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
          <button class="topbar-bell" id="notifBell"><i class="ti ti-bell"></i><span class="dot" id="notifDot" style="display:none;">0</span></button>
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
          '<div>' + r.staffName + '</div>' +
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

cat > accounting/manage-staff.html << 'EOF_ACCOUNTING_MANAGE-STAFF_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Manage Staff — MACDEN Portal</title>
  <link rel="stylesheet" href="assets/portal-style.css">
  <link rel="stylesheet" href="assets/portal-shell.css">
  <link rel="stylesheet" href="assets/portal-inbox.css">
  <style>
    .ms-toolbar { display: flex; justify-content: space-between; align-items: center; margin-bottom: 18px; }
    .ms-list { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-md); overflow: hidden; }
    .ms-header-row { display: grid; grid-template-columns: 200px 130px 130px 1fr 90px 90px; gap: 12px; padding: 12px 18px; font-size: 10.5px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.04em; color: var(--text-muted); border-bottom: 1px solid var(--border); }
    .ms-row { display: grid; grid-template-columns: 200px 130px 130px 1fr 90px 90px; gap: 12px; align-items: center; padding: 12px 18px; border-bottom: 1px solid var(--border); font-size: 12.5px; }
    .ms-row:last-child { border-bottom: none; }
    .ms-empty { padding: 50px 18px; text-align: center; color: var(--text-muted); font-size: 13px; }
    .ms-status { display: inline-block; padding: 2px 9px; border-radius: 999px; font-size: 10.5px; font-weight: 700; }
    .ms-status.active { background: var(--success-dim); color: var(--success); }
    .ms-status.inactive { background: var(--error-dim); color: var(--error); }
    .ms-action-btn { border: 1px solid var(--border); background: var(--surface); border-radius: var(--radius-sm); padding: 5px 11px; font-size: 11px; font-weight: 600; cursor: pointer; font-family: var(--font-body); color: var(--text-primary); }
    .ms-action-btn:hover { border-color: var(--error); color: var(--error); background: var(--error-dim); }
    .ms-action-btn.reactivate { background: var(--success-dim); color: var(--success); border-color: transparent; }
    .ms-action-btn.reactivate:hover { background: var(--success); color: #fff; }
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
        <a href="directory.html" class="sidebar-link"><i class="ti ti-users"></i> Directory</a>
        <a href="leave.html" class="sidebar-link"><i class="ti ti-calendar-event"></i> Leave &amp; Requests</a>
        <a href="documents.html" class="sidebar-link"><i class="ti ti-file-text"></i> Documents</a>
        <a href="policies.html" class="sidebar-link"><i class="ti ti-book"></i> Policies</a>
        <a href="settings.html" class="sidebar-link"><i class="ti ti-settings"></i> Settings</a>
      </nav>
      <div class="sidebar-logout"><button id="logoutBtn"><i class="ti ti-logout"></i> Logout</button></div>
    </div>

    <div class="main-content">
      <div class="topbar">
        <div class="topbar-search"><input type="text" placeholder="Search messages, people, documents…"></div>
        <div class="notif-wrap">
          <button class="topbar-bell" id="notifBell"><i class="ti ti-bell"></i><span class="dot" id="notifDot" style="display:none;">0</span></button>
          <div class="notif-dropdown" id="notifDropdown"></div>
        </div>
        <img class="topbar-avatar" src="assets/logo.jpeg" alt="You">
      </div>

      <div class="page-body">
        <div class="ms-toolbar">
          <div>
            <h1 class="page-greeting" style="font-size: 22px;">Manage Staff</h1>
            <p class="page-greeting-sub" style="margin:0;"><a href="directory.html" style="color: var(--primary); text-decoration:none; font-weight:600;">← Back to Directory</a></p>
          </div>
          <a href="onboard.html" class="btn btn-primary" style="width:auto; padding:10px 20px; text-decoration:none; display:inline-flex; align-items:center; gap:8px;"><i class="ti ti-user-plus"></i> Add New Staff</a>
        </div>

        <div class="ms-list">
          <div class="ms-header-row"><div>Staff Member</div><div>Role</div><div>Department</div><div>Email</div><div>Status</div><div>Actions</div></div>
          <div id="msRows"><div class="ms-empty">Loading…</div></div>
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
      try {
        const result = await apiRequest('/dashboard-check');
        if (result.staff.role !== 'admin') {
          document.body.innerHTML = '<div style="padding:40px; font-family:sans-serif;">Admin access only.</div>';
          return;
        }
      } catch (err) {
        window.location.href = 'login.html';
        return;
      }
      loadUnreadBadge();
      loadStaff();
    }

    async function loadStaff() {
      const rows = document.getElementById('msRows');
      try {
        const result = await apiRequest('/admin/all-staff');
        if (result.staff.length === 0) {
          rows.innerHTML = '<div class="ms-empty">No staff yet.</div>';
          return;
        }
        rows.innerHTML = result.staff.map(s => {
          const statusHtml = s.isActive ? '<span class="ms-status active">Active</span>' : '<span class="ms-status inactive">Deactivated</span>';
          const actionBtn = s.isActive
            ? '<button class="ms-action-btn" onclick="deactivate(\'' + s.id + '\')">Deactivate</button>'
            : '<button class="ms-action-btn reactivate" onclick="reactivate(\'' + s.id + '\')">Reactivate</button>';
          return '<div class="ms-row">' +
            '<div>' + s.fullName + '</div>' +
            '<div>' + s.role + '</div>' +
            '<div>' + (s.department || '—') + '</div>' +
            '<div style="overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">' + s.email + '</div>' +
            '<div>' + statusHtml + '</div>' +
            '<div>' + actionBtn + '</div>' +
            '</div>';
        }).join('');
      } catch (err) {
        rows.innerHTML = '<div class="ms-empty">Could not load staff.</div>';
      }
    }

    async function deactivate(id) {
      if (!confirm('Deactivate this staff member? They will no longer be able to log in.')) return;
      try {
        await apiRequest('/admin/staff/' + id, { method: 'DELETE' });
        loadStaff();
      } catch (err) {
        alert(err.message);
      }
    }

    async function reactivate(id) {
      try {
        await apiRequest('/admin/staff/' + id + '/reactivate', { method: 'POST' });
        loadStaff();
      } catch (err) {
        alert(err.message);
      }
    }

    init();
  </script>
</body>
</html>

EOF_ACCOUNTING_MANAGE-STAFF_HTML

cat > accounting/onboard.html << 'EOF_ACCOUNTING_ONBOARD_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Add New Staff — MACDEN Portal</title>
  <link rel="stylesheet" href="assets/portal-style.css">
  <link rel="stylesheet" href="assets/portal-shell.css">
  <link rel="stylesheet" href="assets/portal-inbox.css">
  <style>
    .step-indicator { display: flex; align-items: center; gap: 10px; margin-bottom: 24px; }
    .step-item { display: flex; align-items: center; gap: 8px; font-size: 12.5px; color: var(--text-muted); }
    .step-item.active, .step-item.done { color: var(--text-primary); font-weight: 600; }
    .step-num { width: 22px; height: 22px; border-radius: 50%; background: var(--border); color: var(--text-muted); display: flex; align-items: center; justify-content: center; font-size: 11px; font-weight: 700; }
    .step-item.active .step-num { background: var(--primary); color: #fff; }
    .step-item.done .step-num { background: var(--success); color: #fff; }
    .step-arrow { color: var(--border); }

    .onb-grid { display: grid; grid-template-columns: 1fr 260px; gap: 20px; }
    .onb-card { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-md); padding: 26px; }
    .onb-field-row { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; margin-bottom: 14px; }
    .onb-field label { display: block; font-size: 12.5px; font-weight: 600; margin-bottom: 6px; }
    .onb-field input, .onb-field select, .onb-field textarea {
      width: 100%; background: var(--surface-raised); border: 1px solid var(--border); border-radius: var(--radius-sm);
      padding: 9px 12px; font-size: 13px; font-family: var(--font-body); color: var(--text-primary);
    }
    .onb-note { background: var(--gold-dim); color: #8a6d00; padding: 12px 16px; border-radius: var(--radius-sm); font-size: 12px; }

    .review-section { margin-bottom: 16px; }
    .review-section h4 { font-size: 12.5px; text-transform: uppercase; letter-spacing: 0.04em; color: var(--text-muted); margin-bottom: 8px; }
    .review-row { display: flex; justify-content: space-between; padding: 6px 0; font-size: 13px; border-bottom: 1px solid var(--border); }

    .search-results { position: absolute; top: 100%; left: 0; right: 0; background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-sm); margin-top: 4px; max-height: 180px; overflow-y: auto; z-index: 5; display: none; box-shadow: 0 4px 12px rgba(0,0,0,0.08); }
    .search-result-item { padding: 8px 12px; cursor: pointer; font-size: 12.5px; }
    .search-result-item:hover { background: var(--surface-raised); }
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
        <a href="directory.html" class="sidebar-link"><i class="ti ti-users"></i> Directory</a>
        <a href="leave.html" class="sidebar-link"><i class="ti ti-calendar-event"></i> Leave &amp; Requests</a>
        <a href="documents.html" class="sidebar-link"><i class="ti ti-file-text"></i> Documents</a>
        <a href="policies.html" class="sidebar-link"><i class="ti ti-book"></i> Policies</a>
        <a href="settings.html" class="sidebar-link"><i class="ti ti-settings"></i> Settings</a>
      </nav>
      <div class="sidebar-logout"><button id="logoutBtn"><i class="ti ti-logout"></i> Logout</button></div>
    </div>

    <div class="main-content">
      <div class="topbar">
        <div class="topbar-search"><input type="text" placeholder="Search messages, people, documents…"></div>
        <div class="notif-wrap">
          <button class="topbar-bell" id="notifBell"><i class="ti ti-bell"></i><span class="dot" id="notifDot" style="display:none;">0</span></button>
          <div class="notif-dropdown" id="notifDropdown"></div>
        </div>
        <img class="topbar-avatar" src="assets/logo.jpeg" alt="You">
      </div>

      <div class="page-body">
        <h1 class="page-greeting" style="font-size: 22px;">Add New Staff Member</h1>
        <p class="page-greeting-sub"><a href="manage-staff.html" style="color: var(--primary); text-decoration:none; font-weight:600;">← Back to Manage Staff</a></p>

        <div class="step-indicator">
          <div class="step-item active" id="stepInd1"><span class="step-num">1</span> Personal Information</div>
          <span class="step-arrow">→</span>
          <div class="step-item" id="stepInd2"><span class="step-num">2</span> Work Information</div>
          <span class="step-arrow">→</span>
          <div class="step-item" id="stepInd3"><span class="step-num">3</span> Review &amp; Create</div>
        </div>

        <div id="alert" class="alert alert-error"></div>

        <!-- Step 1 -->
        <div id="step1" class="onb-grid">
          <div class="onb-card">
            <div class="onb-field-row">
              <div class="onb-field"><label>Full Name *</label><input type="text" id="fullName"></div>
              <div class="onb-field"><label>Email Address *</label><input type="text" id="email"></div>
            </div>
            <div class="onb-field-row">
              <div class="onb-field"><label>Phone Number</label><input type="text" id="phone"></div>
              <div class="onb-field"><label>NIN</label><input type="text" id="nin"></div>
            </div>
            <div class="onb-field"><label>Residential Address</label><textarea id="address" style="min-height:70px;"></textarea></div>
            <div style="text-align:right; margin-top:16px;"><button class="btn btn-primary" style="width:auto; padding:9px 22px;" onclick="goToStep(2)">Next: Work Information →</button></div>
          </div>
          <div class="onb-note"><i class="ti ti-info-circle"></i> Photo upload isn't supported yet — staff records don't have a photo field in the database yet.</div>
        </div>

        <!-- Step 2 -->
        <div id="step2" class="onb-grid" style="display:none;">
          <div class="onb-card">
            <div class="onb-field-row">
              <div class="onb-field"><label>Role / Job Title *</label><input type="text" id="role"></div>
              <div class="onb-field"><label>Department *</label><select id="departmentId"></select></div>
            </div>
            <div class="onb-field-row">
              <div class="onb-field"><label>Branch</label><input type="text" id="branch" placeholder="e.g. Ikeja Branch"></div>
              <div class="onb-field"><label>Date Started</label><input type="date" id="dateStarted"></div>
            </div>
            <div class="onb-field" style="position:relative;">
              <label>Reports To (Direct Manager)</label>
              <input type="text" id="reportsToSearch" placeholder="Search staff member…">
              <div class="search-results" id="reportsToResults"></div>
              <div id="reportsToSelected" style="margin-top:6px; font-size:12.5px; color:var(--primary); display:none;"></div>
            </div>
            <div style="display:flex; justify-content:space-between; margin-top:16px;">
              <button class="btn btn-ghost" style="width:auto; padding:9px 22px;" onclick="goToStep(1)">← Back</button>
              <button class="btn btn-primary" style="width:auto; padding:9px 22px;" onclick="goToStep(3)">Next: Review &amp; Create →</button>
            </div>
          </div>
          <div class="onb-note"><i class="ti ti-info-circle"></i> Branch is a free-text field for now — no managed branch list exists yet.</div>
        </div>

        <!-- Step 3 -->
        <div id="step3" style="display:none;">
          <div class="onb-card" style="max-width:640px;">
            <div class="review-section">
              <h4>Personal Information</h4>
              <div class="review-row"><span>Full Name</span><span id="rvName"></span></div>
              <div class="review-row"><span>Email</span><span id="rvEmail"></span></div>
              <div class="review-row"><span>Phone</span><span id="rvPhone"></span></div>
              <div class="review-row"><span>NIN</span><span id="rvNin"></span></div>
            </div>
            <div class="review-section">
              <h4>Work Information</h4>
              <div class="review-row"><span>Role</span><span id="rvRole"></span></div>
              <div class="review-row"><span>Department</span><span id="rvDept"></span></div>
              <div class="review-row"><span>Branch</span><span id="rvBranch"></span></div>
              <div class="review-row"><span>Reports To</span><span id="rvReportsTo"></span></div>
            </div>
            <div class="onb-note" style="margin-top:16px;"><i class="ti ti-mail"></i> The staff member will receive an email with their login credentials.</div>
            <div style="display:flex; justify-content:space-between; margin-top:16px;">
              <button class="btn btn-ghost" style="width:auto; padding:9px 22px;" onclick="goToStep(2)">← Back</button>
              <button class="btn btn-primary" id="createAccountBtn" style="width:auto; padding:9px 22px;">Create Account</button>
            </div>
          </div>
        </div>

        <div id="successView" style="display:none;">
          <div class="onb-card" style="max-width:520px;">
            <h2 style="font-size:16px; margin-bottom:6px; color: var(--success);"><i class="ti ti-circle-check"></i> Account Created</h2>
            <p id="successNormalMsg" style="font-size:13px; color:var(--text-secondary); display:none;">A welcome email with login details has been sent.</p>
            <div id="successWarningBox" style="display:none;">
              <div class="onb-note" style="margin-bottom:14px;">
                <i class="ti ti-alert-triangle"></i> The welcome email failed to send. Share these credentials with the new staff member directly &mdash; <strong>this is the only time they will be shown.</strong>
              </div>
              <div style="background: var(--surface-raised); border: 1px solid var(--border); border-radius: var(--radius-sm); padding: 14px; font-family: var(--font-mono); font-size: 13px;">
                <div>Username: <strong id="credUsername"></strong></div>
                <div style="margin-top:6px;">Temporary password: <strong id="credPassword"></strong></div>
              </div>
            </div>
            <button class="btn btn-primary" style="width:auto; padding:9px 22px; margin-top:16px;" onclick="window.location.href='manage-staff.html'">Go to Manage Staff</button>
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

    let selectedReportsTo = null;

    async function init() {
      try {
        const result = await apiRequest('/dashboard-check');
        if (result.staff.role !== 'admin') {
          document.body.innerHTML = '<div style="padding:40px; font-family:sans-serif;">Admin access only.</div>';
          return;
        }
      } catch (err) {
        window.location.href = 'login.html';
        return;
      }
      loadUnreadBadge();

      try {
        const result = await apiRequest('/admin/departments');
        document.getElementById('departmentId').innerHTML = result.departments.map(d => '<option value="' + d.id + '">' + d.name + '</option>').join('');
      } catch (err) {}
    }

    function goToStep(n) {
      [1,2,3].forEach(i => {
        document.getElementById('step' + i).style.display = i === n ? (i === 3 ? 'block' : 'grid') : 'none';
        const ind = document.getElementById('stepInd' + i);
        ind.classList.remove('active', 'done');
        if (i < n) ind.classList.add('done');
        if (i === n) ind.classList.add('active');
      });
      if (n === 3) populateReview();
    }

    function populateReview() {
      document.getElementById('rvName').textContent = document.getElementById('fullName').value;
      document.getElementById('rvEmail').textContent = document.getElementById('email').value;
      document.getElementById('rvPhone').textContent = document.getElementById('phone').value || '—';
      document.getElementById('rvNin').textContent = document.getElementById('nin').value || '—';
      document.getElementById('rvRole').textContent = document.getElementById('role').value;
      document.getElementById('rvDept').textContent = document.getElementById('departmentId').selectedOptions[0]?.textContent || '—';
      document.getElementById('rvBranch').textContent = document.getElementById('branch').value || '—';
      document.getElementById('rvReportsTo').textContent = selectedReportsTo ? selectedReportsTo.full_name : '—';
    }

    let searchTimeout = null;
    document.getElementById('reportsToSearch').addEventListener('input', (e) => {
      clearTimeout(searchTimeout);
      const q = e.target.value.trim();
      const results = document.getElementById('reportsToResults');
      if (!q) { results.style.display = 'none'; return; }
      searchTimeout = setTimeout(async () => {
        try {
          const result = await apiRequest('/staff?search=' + encodeURIComponent(q));
          results.innerHTML = result.staff.map(s => '<div class="search-result-item" onclick=\'selectReportsTo(' + JSON.stringify(s) + ')\'>' + s.full_name + ' · ' + (s.department || '') + '</div>').join('');
          results.style.display = 'block';
        } catch (err) {}
      }, 250);
    });

    function selectReportsTo(staff) {
      selectedReportsTo = staff;
      document.getElementById('reportsToSearch').value = '';
      document.getElementById('reportsToResults').style.display = 'none';
      const el = document.getElementById('reportsToSelected');
      el.textContent = '✓ ' + staff.full_name;
      el.style.display = 'block';
    }

    document.getElementById('createAccountBtn').addEventListener('click', async () => {
      const alertEl = document.getElementById('alert');
      hideAlert(alertEl);

      const fullName = document.getElementById('fullName').value.trim();
      const email = document.getElementById('email').value.trim();
      const role = document.getElementById('role').value.trim();
      const departmentId = document.getElementById('departmentId').value;

      if (!fullName || !email || !role || !departmentId) {
        showAlert(alertEl, 'Full name, email, role, and department are required.');
        goToStep(1);
        return;
      }

      const btn = document.getElementById('createAccountBtn');
      btn.disabled = true;
      btn.textContent = 'Creating…';

      try {
        const result = await apiRequest('/admin/onboard-staff', {
          method: 'POST',
          body: {
            fullName, email,
            phone: document.getElementById('phone').value.trim(),
            nin: document.getElementById('nin').value.trim(),
            address: document.getElementById('address').value.trim(),
            role,
            departmentId,
            branch: document.getElementById('branch').value.trim(),
            dateStarted: document.getElementById('dateStarted').value,
            reportsTo: selectedReportsTo ? selectedReportsTo.id : null
          }
        });

        document.getElementById('step3').style.display = 'none';
        document.getElementById('successView').style.display = 'block';

        if (result.warning) {
          // Extract username/password from the warning message for clean display
          const match = result.warning.match(/Username:\s*([^\s,]+),\s*temporary password:\s*(\S+)/);
          document.getElementById('successWarningBox').style.display = 'block';
          document.getElementById('credUsername').textContent = match ? match[1] : '(check server logs)';
          document.getElementById('credPassword').textContent = match ? match[2] : '(check server logs)';
        } else {
          document.getElementById('successNormalMsg').style.display = 'block';
        }
      } catch (err) {
        showAlert(alertEl, err.message);
        btn.disabled = false;
        btn.textContent = 'Create Account';
      }
    });

    init();
  </script>
</body>
</html>

EOF_ACCOUNTING_ONBOARD_HTML

cat > accounting/policies.html << 'EOF_ACCOUNTING_POLICIES_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Policies — MACDEN Portal</title>
  <link rel="stylesheet" href="assets/portal-style.css">
  <link rel="stylesheet" href="assets/portal-shell.css">
  <link rel="stylesheet" href="assets/portal-inbox.css">
  <style>
    .pol-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; }
    .pol-card { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-md); padding: 20px; }
    .pol-card h3 { font-size: 14.5px; margin: 0 0 8px; }
    .pol-card p { font-size: 12.5px; color: var(--text-secondary); margin: 0 0 14px; line-height: 1.5; }
    .pol-card .updated { font-size: 11.5px; color: var(--text-muted); margin-bottom: 12px; }
    .pol-card-actions { display: flex; gap: 8px; }
    .pol-read-btn { border: 1px solid var(--border); border-radius: var(--radius-sm); padding: 7px 14px; font-size: 12px; font-weight: 600; color: var(--text-primary); background: none; cursor: pointer; font-family: var(--font-body); }
    .pol-read-btn:hover { border-color: var(--primary); color: var(--primary); }
    .pol-empty { padding: 60px 20px; text-align: center; color: var(--text-muted); font-size: 13px; grid-column: 1 / -1; }

    #detailView .email-card { max-width: 720px; }
    #detailView .email-body-text { font-size: 13.5px; line-height: 1.75; }

    .pol-form-field { margin-bottom: 14px; }
    .pol-form-field label { display: block; font-size: 12.5px; font-weight: 600; margin-bottom: 6px; }
    .pol-form-field input, .pol-form-field textarea {
      width: 100%; background: var(--surface-raised); border: 1px solid var(--border); border-radius: var(--radius-sm);
      padding: 10px 12px; font-size: 13px; font-family: var(--font-body); color: var(--text-primary);
    }
    .pol-form-field textarea { min-height: 200px; resize: vertical; }
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
        <a href="policies.html" class="sidebar-link active"><i class="ti ti-book"></i> Policies</a>
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
          <button class="topbar-bell" id="notifBell"><i class="ti ti-bell"></i><span class="dot" id="notifDot" style="display:none;">0</span></button>
          <div class="notif-dropdown" id="notifDropdown"></div>
        </div>
        <img class="topbar-avatar" src="assets/logo.jpeg" alt="You">
      </div>

      <div class="page-body">

        <div id="listView">
          <div class="email-toolbar">
            <div>
              <h1 class="page-greeting" style="font-size: 22px;">Policies</h1>
              <p class="page-greeting-sub" style="margin:0;"><a href="dashboard.html" style="color: var(--primary); text-decoration:none; font-weight:600;">← Back to dashboard</a></p>
            </div>
            <button class="btn btn-primary" id="addPolicyBtn" style="width:auto; padding:10px 20px; display:none; align-items:center; gap:8px;"><i class="ti ti-plus"></i> Add Policy</button>
          </div>

          <div class="pol-grid" id="polGrid">
            <div class="pol-empty">Loading…</div>
          </div>
        </div>

        <div id="detailView" style="display:none;">
          <a href="policies.html" class="email-back" style="display:inline-flex; align-items:center; gap:5px; margin-bottom:16px;"><i class="ti ti-arrow-left"></i> Back to Policies</a>
          <div class="email-card">
            <h2 class="email-detail-subject" id="detailTitle">—</h2>
            <p class="pol-card .updated" style="font-size:12px; color:var(--text-muted); margin-bottom:14px;" id="detailUpdated"></p>
            <div class="email-body-text" id="detailBody"></div>
            <div class="email-action-row" id="detailAdminActions" style="display:none;">
              <button class="email-action-btn" id="editPolicyBtn"><i class="ti ti-pencil"></i> Edit</button>
              <button class="email-action-btn danger" id="deletePolicyBtn"><i class="ti ti-trash"></i> Delete</button>
            </div>
          </div>
        </div>

      </div>
    </div>
  </div>

  <div class="modal-backdrop" id="policyModalBackdrop">
    <div class="modal" style="width: 480px;">
      <h3 id="policyModalTitle">Add Policy</h3>
      <div id="policyModalAlert" class="alert alert-error"></div>
      <div class="pol-form-field">
        <label>Title</label>
        <input type="text" id="policyTitleInput" placeholder="e.g. Remote Work Policy">
      </div>
      <div class="pol-form-field">
        <label>Content</label>
        <textarea id="policyBodyInput" placeholder="Write the full policy text…"></textarea>
      </div>
      <div class="modal-actions">
        <button class="btn btn-ghost" id="policyModalCancel">Cancel</button>
        <button class="btn btn-primary" id="policyModalSave">Save</button>
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

    let isAdmin = false;
    let policiesCache = [];
    let editingPolicyId = null;
    const params = new URLSearchParams(window.location.search);
    const openId = params.get('id');

    async function init() {
      try {
        const result = await apiRequest('/dashboard-check');
        isAdmin = result.staff.role === 'admin';
        if (isAdmin) document.getElementById('addPolicyBtn').style.display = 'inline-flex';
      } catch (err) {
        window.location.href = 'login.html';
        return;
      }
      loadUnreadBadge();
      await loadPolicies();

      if (openId) openDetail(openId);
    }

    async function loadPolicies() {
      const grid = document.getElementById('polGrid');
      try {
        const result = await apiRequest('/policies');
        policiesCache = result.policies;

        if (result.policies.length === 0) {
          grid.innerHTML = '<div class="pol-empty">No policies added yet.' + (isAdmin ? ' Click Add Policy to create one.' : '') + '</div>';
          return;
        }

        grid.innerHTML = result.policies.map(p => {
          const excerpt = p.body.length > 90 ? p.body.slice(0, 90) + '…' : p.body;
          return '<div class="pol-card">' +
            '<h3>' + p.title + '</h3>' +
            '<p>' + excerpt + '</p>' +
            '<div class="updated">Last updated: ' + new Date(p.updated_at).toLocaleDateString() + '</div>' +
            '<div class="pol-card-actions"><button class="pol-read-btn" onclick="window.location.href=\'policies.html?id=' + p.id + '\'"><i class="ti ti-book"></i> Read Policy</button></div>' +
            '</div>';
        }).join('');
      } catch (err) {
        grid.innerHTML = '<div class="pol-empty">Could not load policies.</div>';
      }
    }

    function openDetail(id) {
      const policy = policiesCache.find(p => p.id === id);
      if (!policy) return;

      document.getElementById('listView').style.display = 'none';
      document.getElementById('detailView').style.display = 'block';
      document.getElementById('detailTitle').textContent = policy.title;
      document.getElementById('detailUpdated').textContent = 'Last updated: ' + new Date(policy.updated_at).toLocaleDateString();
      document.getElementById('detailBody').textContent = policy.body;

      if (isAdmin) {
        document.getElementById('detailAdminActions').style.display = 'flex';
        document.getElementById('editPolicyBtn').onclick = () => openPolicyModal(policy);
        document.getElementById('deletePolicyBtn').onclick = () => deletePolicy(policy.id);
      }
    }

    function openPolicyModal(policy) {
      editingPolicyId = policy ? policy.id : null;
      document.getElementById('policyModalTitle').textContent = policy ? 'Edit Policy' : 'Add Policy';
      document.getElementById('policyTitleInput').value = policy ? policy.title : '';
      document.getElementById('policyBodyInput').value = policy ? policy.body : '';
      hideAlert(document.getElementById('policyModalAlert'));
      document.getElementById('policyModalBackdrop').classList.add('visible');
    }

    document.getElementById('addPolicyBtn').addEventListener('click', () => openPolicyModal(null));
    document.getElementById('policyModalCancel').addEventListener('click', () => {
      document.getElementById('policyModalBackdrop').classList.remove('visible');
    });

    document.getElementById('policyModalSave').addEventListener('click', async () => {
      const alertEl = document.getElementById('policyModalAlert');
      hideAlert(alertEl);
      const title = document.getElementById('policyTitleInput').value.trim();
      const body = document.getElementById('policyBodyInput').value.trim();

      if (!title || !body) { showAlert(alertEl, 'Title and content are required.'); return; }

      const btn = document.getElementById('policyModalSave');
      btn.disabled = true;

      try {
        if (editingPolicyId) {
          await apiRequest('/policies/' + editingPolicyId, { method: 'PUT', body: { title, body } });
        } else {
          await apiRequest('/policies', { method: 'POST', body: { title, body } });
        }
        document.getElementById('policyModalBackdrop').classList.remove('visible');
        window.location.href = 'policies.html';
      } catch (err) {
        showAlert(alertEl, err.message);
      } finally {
        btn.disabled = false;
      }
    });

    async function deletePolicy(id) {
      if (!confirm('Delete this policy? This cannot be undone.')) return;
      try {
        await apiRequest('/policies/' + id, { method: 'DELETE' });
        window.location.href = 'policies.html';
      } catch (err) {
        alert(err.message);
      }
    }

    init();
  </script>
</body>
</html>

EOF_ACCOUNTING_POLICIES_HTML

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
          <button class="topbar-bell" id="notifBell"><i class="ti ti-bell"></i><span class="dot" id="notifDot" style="display:none;">0</span></button>
          <div class="notif-dropdown" id="notifDropdown"></div>
        </div>
        <img class="topbar-avatar" src="assets/logo.jpeg" alt="You">
      </div>

      <div class="page-body">
        <h1 class="page-greeting" style="font-size: 22px;">Settings</h1>
        <p class="page-greeting-sub"><a href="dashboard.html" style="color: var(--primary); text-decoration:none; font-weight:600;">← Back to dashboard</a></p>

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
          <div class="set-locked-note" style="margin-top:14px;"><i class="ti ti-info-circle"></i> Your preferences are saved, but no feature sends email notifications yet — this becomes active once that's built.</div>
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

    init();
  </script>
</body>
</html>

EOF_ACCOUNTING_SETTINGS_HTML

echo "Notification bell added. This completes the FULL 15-screen mockup set."