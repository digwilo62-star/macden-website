#!/usr/bin/env bash
# Rebuilds messaging as a real chat interface: contact list, live online
# presence, chat bubbles, no subject line. Run the SQL migration FIRST,
# in Supabase, before running this script.
# Run this from the ROOT of your macden-website repo, in Git Bash.
set -e

mkdir -p server/routes accounting/assets

cat > server/routes/presence.js << 'EOF_SERVER_ROUTES_PRESENCE_JS'
const express = require('express');
const supabase = require('../config/supabaseClient');

const router = express.Router();

// POST /api/accounting/presence/heartbeat
// Called every ~20 seconds by the frontend while a page is open.
// Anyone whose last_seen is within the last 40 seconds counts as online.
router.post('/heartbeat', async (req, res) => {
  await supabase
    .from('staff')
    .update({ last_seen: new Date().toISOString() })
    .eq('id', req.session.staff.id);

  res.json({ success: true });
});

module.exports = router;

EOF_SERVER_ROUTES_PRESENCE_JS

cat > server/routes/staff.js << 'EOF_SERVER_ROUTES_STAFF_JS'
const express = require('express');
const supabase = require('../config/supabaseClient');

const router = express.Router();

const ONLINE_THRESHOLD_MS = 40 * 1000; // last_seen within 40s counts as online

function isOnline(lastSeen) {
  if (!lastSeen) return false;
  return Date.now() - new Date(lastSeen).getTime() < ONLINE_THRESHOLD_MS;
}

// GET /api/accounting/staff?search=amara — searchable directory, excludes yourself
router.get('/', async (req, res) => {
  const search = (req.query.search || '').trim();

  let query = supabase
    .from('staff')
    .select('id, full_name, username, last_seen')
    .eq('is_active', true)
    .neq('id', req.session.staff.id)
    .order('full_name', { ascending: true });

  if (search) {
    query = query.or(`full_name.ilike.%${search}%,username.ilike.%${search}%`);
  }

  const { data, error } = await query;

  if (error) {
    return res.status(500).json({ error: 'Could not load staff directory.' });
  }

  const staff = data.map(s => ({
    id: s.id,
    full_name: s.full_name,
    username: s.username,
    isOnline: isOnline(s.last_seen)
  }));

  res.json({ staff });
});

module.exports = router;
module.exports.isOnline = isOnline;

EOF_SERVER_ROUTES_STAFF_JS

cat > server/routes/messages.js << 'EOF_SERVER_ROUTES_MESSAGES_JS'
const express = require('express');
const supabase = require('../config/supabaseClient');
const { isOnline } = require('./staff');

const router = express.Router();

async function createReadRowsForRecipients(conversationId, messageId, senderId) {
  const { data: members } = await supabase
    .from('conversation_members')
    .select('staff_id')
    .eq('conversation_id', conversationId)
    .neq('staff_id', senderId);

  if (!members || members.length === 0) return;

  const rows = members.map(m => ({ message_id: messageId, staff_id: m.staff_id, read_at: null }));
  await supabase.from('message_reads').insert(rows);
}

async function getOtherParticipants(conversationId, excludeStaffId) {
  const { data: memberRows } = await supabase
    .from('conversation_members')
    .select('staff_id')
    .eq('conversation_id', conversationId)
    .neq('staff_id', excludeStaffId);

  if (!memberRows || memberRows.length === 0) return [];

  const ids = memberRows.map(m => m.staff_id);
  const { data: staffRows } = await supabase
    .from('staff')
    .select('id, full_name, last_seen')
    .in('id', ids);

  if (!staffRows) return [];

  return staffRows.map(s => ({
    id: s.id,
    fullName: s.full_name,
    isOnline: isOnline(s.last_seen)
  }));
}

router.get('/unread-count', async (req, res) => {
  const { count, error } = await supabase
    .from('message_reads')
    .select('*', { count: 'exact', head: true })
    .eq('staff_id', req.session.staff.id)
    .is('read_at', null);

  if (error) {
    return res.status(500).json({ error: 'Could not load unread count.' });
  }

  res.json({ unreadCount: count });
});

router.get('/conversations', async (req, res) => {
  const staffId = req.session.staff.id;

  const { data: memberRows, error: memberError } = await supabase
    .from('conversation_members')
    .select('conversation_id')
    .eq('staff_id', staffId);

  if (memberError) {
    return res.status(500).json({ error: 'Could not load inbox.' });
  }

  const conversationIds = memberRows.map(r => r.conversation_id);
  if (conversationIds.length === 0) {
    return res.json({ conversations: [] });
  }

  const { data: conversations, error: convError } = await supabase
    .from('conversations')
    .select('id, created_at')
    .in('id', conversationIds)
    .order('created_at', { ascending: false });

  if (convError) {
    return res.status(500).json({ error: 'Could not load inbox.' });
  }

  const enriched = await Promise.all(conversations.map(async (conv) => {
    const [lastMessageResult, participants] = await Promise.all([
      supabase
        .from('messages')
        .select('id, sender_id, body, sent_at')
        .eq('conversation_id', conv.id)
        .eq('status', 'sent')
        .order('sent_at', { ascending: false })
        .limit(1)
        .maybeSingle(),
      getOtherParticipants(conv.id, staffId)
    ]);

    const lastMessage = lastMessageResult.data;

    let isUnread = false;
    if (lastMessage) {
      const { data: readRow } = await supabase
        .from('message_reads')
        .select('read_at')
        .eq('message_id', lastMessage.id)
        .eq('staff_id', staffId)
        .maybeSingle();
      isUnread = readRow ? readRow.read_at === null : false;
    }

    return {
      id: conv.id,
      participants,
      displayName: participants.map(p => p.fullName).join(', ') || 'Conversation',
      lastMessagePreview: lastMessage ? lastMessage.body.slice(0, 60) : null,
      lastMessageAt: lastMessage ? lastMessage.sent_at : conv.created_at,
      isUnread
    };
  }));

  enriched.sort((a, b) => new Date(b.lastMessageAt) - new Date(a.lastMessageAt));

  res.json({ conversations: enriched });
});

router.get('/conversations/:id', async (req, res) => {
  const { id } = req.params;
  const staffId = req.session.staff.id;

  const { data: membership } = await supabase
    .from('conversation_members')
    .select('id')
    .eq('conversation_id', id)
    .eq('staff_id', staffId)
    .maybeSingle();

  if (!membership) {
    return res.status(403).json({ error: 'You do not have access to this conversation.' });
  }

  const participants = await getOtherParticipants(id, staffId);

  const { data: messages, error } = await supabase
    .from('messages')
    .select('id, sender_id, body, status, sent_at, created_at, attachment_url, attachment_type')
    .eq('conversation_id', id)
    .or(`status.eq.sent,and(status.eq.draft,sender_id.eq.${staffId})`)
    .order('created_at', { ascending: true });

  if (error) {
    return res.status(500).json({ error: 'Could not load conversation.' });
  }

  const sentMessageIds = messages.filter(m => m.status === 'sent').map(m => m.id);
  if (sentMessageIds.length > 0) {
    await supabase
      .from('message_reads')
      .update({ read_at: new Date().toISOString() })
      .eq('staff_id', staffId)
      .in('message_id', sentMessageIds)
      .is('read_at', null);
  }

  res.json({ participants, messages });
});

router.post('/compose', async (req, res) => {
  const { recipientIds, body, status } = req.body;
  const staffId = req.session.staff.id;

  if (!recipientIds || recipientIds.length === 0) {
    return res.status(400).json({ error: 'Add at least one recipient.' });
  }

  const { data: conversation, error: convError } = await supabase
    .from('conversations')
    .insert({
      department_id: req.session.staff.departmentId,
      subject: 'Conversation',
      is_group: recipientIds.length > 1
    })
    .select()
    .single();

  if (convError) {
    return res.status(500).json({ error: 'Could not start conversation.' });
  }

  const memberRows = [staffId, ...recipientIds].map(id => ({ conversation_id: conversation.id, staff_id: id }));
  await supabase.from('conversation_members').insert(memberRows);

  const isSent = status === 'sent';
  const { data: message, error: msgError } = await supabase
    .from('messages')
    .insert({
      conversation_id: conversation.id,
      sender_id: staffId,
      body: body || '',
      status: isSent ? 'sent' : 'draft',
      sent_at: isSent ? new Date().toISOString() : null
    })
    .select()
    .single();

  if (msgError) {
    return res.status(500).json({ error: 'Could not send message.' });
  }

  if (isSent) {
    await createReadRowsForRecipients(conversation.id, message.id, staffId);
  }

  res.json({ success: true, conversationId: conversation.id, messageId: message.id });
});

router.post('/conversations/:id/reply', async (req, res) => {
  const { id } = req.params;
  const { body, status } = req.body;
  const staffId = req.session.staff.id;

  const { data: membership } = await supabase
    .from('conversation_members')
    .select('id')
    .eq('conversation_id', id)
    .eq('staff_id', staffId)
    .maybeSingle();

  if (!membership) {
    return res.status(403).json({ error: 'You do not have access to this conversation.' });
  }

  const isSent = status === 'sent';
  const { data: message, error } = await supabase
    .from('messages')
    .insert({
      conversation_id: id,
      sender_id: staffId,
      body: body || '',
      status: isSent ? 'sent' : 'draft',
      sent_at: isSent ? new Date().toISOString() : null
    })
    .select()
    .single();

  if (error) {
    return res.status(500).json({ error: 'Could not send message.' });
  }

  if (isSent) {
    await createReadRowsForRecipients(id, message.id, staffId);
  }

  res.json({ success: true, message });
});

router.get('/drafts', async (req, res) => {
  const staffId = req.session.staff.id;

  const { data: drafts, error } = await supabase
    .from('messages')
    .select('id, conversation_id, body, created_at')
    .eq('sender_id', staffId)
    .eq('status', 'draft')
    .order('created_at', { ascending: false });

  if (error) {
    return res.status(500).json({ error: 'Could not load drafts.' });
  }

  const enriched = await Promise.all(drafts.map(async (draft) => {
    const participants = await getOtherParticipants(draft.conversation_id, staffId);
    return {
      ...draft,
      displayName: participants.map(p => p.fullName).join(', ') || 'Conversation'
    };
  }));

  res.json({ drafts: enriched });
});

router.put('/:id', async (req, res) => {
  const { id } = req.params;
  const { body, status } = req.body;
  const staffId = req.session.staff.id;

  const { data: existing, error: fetchError } = await supabase
    .from('messages')
    .select('id, conversation_id, sender_id, status')
    .eq('id', id)
    .single();

  if (fetchError || !existing) {
    return res.status(404).json({ error: 'Message not found.' });
  }

  if (existing.sender_id !== staffId) {
    return res.status(403).json({ error: 'You can only edit your own drafts.' });
  }

  if (existing.status === 'sent') {
    return res.status(400).json({ error: 'This message has already been sent and cannot be edited.' });
  }

  const isSending = status === 'sent';
  const { data: updated, error: updateError } = await supabase
    .from('messages')
    .update({
      body: body !== undefined ? body : undefined,
      status: isSending ? 'sent' : 'draft',
      sent_at: isSending ? new Date().toISOString() : null
    })
    .eq('id', id)
    .select()
    .single();

  if (updateError) {
    return res.status(500).json({ error: 'Could not update message.' });
  }

  if (isSending) {
    await createReadRowsForRecipients(existing.conversation_id, id, staffId);
  }

  res.json({ success: true, message: updated });
});

module.exports = router;

EOF_SERVER_ROUTES_MESSAGES_JS

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

  await supabase
    .from('staff')
    .update({ last_seen: new Date().toISOString() })
    .eq('id', staffMember.id);

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

cat > server/server.js << 'EOF_SERVER_SERVER_JS'
require('dotenv').config();

const path = require('path');
const express = require('express');
const session = require('express-session');
const cors = require('cors');

const authRoutes = require('./routes/auth');
const adminRoutes = require('./routes/admin');
const priceRoutes = require('./routes/prices');
const staffRoutes = require('./routes/staff');
const messageRoutes = require('./routes/messages');
const presenceRoutes = require('./routes/presence');
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

app.use(session({
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

app.get('/api/accounting/dashboard-check', (req, res) => {
  // Simple proof that requireAuth is working — returns the logged-in staff's info
  res.json({ message: `Welcome, ${req.session.staff.fullName}`, staff: req.session.staff });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Accounting backend running on port ${PORT}`);
});

EOF_SERVER_SERVER_JS

cat > accounting/assets/style.css << 'EOF_ACCOUNTING_ASSETS_STYLE_CSS'
/* ============================================================
   MACDEN Accounting — Design Tokens
   Light mode is the default. Dark mode (the original Supabase/Claude-
   inspired near-black theme) is available via [data-theme="dark"] on <html>.
   Desktop-only, corporate-internal tool.
   ============================================================ */

:root {
  --bg: #fafafa;
  --surface: #ffffff;
  --surface-raised: #f2f2f0;
  --border: #e3e2dd;
  --border-hover: #cfcec8;

  --text-primary: #1c1d1a;
  --text-secondary: #63645e;
  --text-muted: #9a9a94;

  --accent-green: #1d9e75;
  --accent-green-hover: #17835f;
  --accent-green-dim: rgba(29, 158, 117, 0.10);

  --accent-clay: #b85a38;
  --accent-clay-dim: rgba(184, 90, 56, 0.10);

  --error: #d64545;
  --error-dim: rgba(214, 69, 69, 0.10);

  --radius-sm: 6px;
  --radius-md: 10px;
  --radius-lg: 14px;

  --font-ui: -apple-system, "Inter", "Segoe UI", Helvetica, Arial, sans-serif;
  --font-mono: "SF Mono", "JetBrains Mono", Consolas, monospace;
}

html[data-theme="dark"] {
  --bg: #0d0e0f;
  --surface: #16171a;
  --surface-raised: #1c1d21;
  --border: #2a2b2f;
  --border-hover: #38393e;

  --text-primary: #edeef0;
  --text-secondary: #9a9ba1;
  --text-muted: #6b6c72;

  --accent-green: #3ecf8e;
  --accent-green-hover: #34b87d;
  --accent-green-dim: rgba(62, 207, 142, 0.12);

  --accent-clay: #d97757;
  --accent-clay-dim: rgba(217, 119, 87, 0.12);

  --error: #f87171;
  --error-dim: rgba(248, 113, 113, 0.12);
}

* { box-sizing: border-box; transition: background-color 0.15s ease, border-color 0.15s ease; }

body {
  margin: 0;
  background: var(--bg);
  color: var(--text-primary);
  font-family: var(--font-ui);
  font-size: 14px;
  line-height: 1.5;
  min-width: 1024px; /* desktop-only, by design */
}

/* ---------- Auth shell (login / register) ---------- */

.auth-shell {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  background:
    radial-gradient(circle at 20% 15%, rgba(62, 207, 142, 0.06), transparent 40%),
    radial-gradient(circle at 85% 80%, rgba(217, 119, 87, 0.05), transparent 40%),
    var(--bg);
}

.auth-card {
  width: 400px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius-lg);
  padding: 40px 36px;
}

.auth-logo-row {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 28px;
}

.auth-logo-row img {
  width: 28px;
  height: 28px;
  border-radius: 6px;
  object-fit: cover;
}

.auth-logo-row span {
  font-size: 13px;
  font-weight: 600;
  letter-spacing: 0.02em;
  color: var(--text-secondary);
}

.auth-title {
  font-size: 20px;
  font-weight: 600;
  margin: 0 0 6px;
  color: var(--text-primary);
}

.auth-subtitle {
  font-size: 13px;
  color: var(--text-secondary);
  margin: 0 0 28px;
}

/* ---------- Form elements ---------- */

.field {
  margin-bottom: 16px;
}

.field label {
  display: block;
  font-size: 12.5px;
  font-weight: 500;
  color: var(--text-secondary);
  margin-bottom: 6px;
}

.field input {
  width: 100%;
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  padding: 10px 12px;
  color: var(--text-primary);
  font-size: 13.5px;
  font-family: var(--font-ui);
  transition: border-color 0.15s ease;
}

.field input:focus {
  outline: none;
  border-color: var(--accent-green);
}

.field input::placeholder {
  color: var(--text-muted);
}

.btn {
  width: 100%;
  padding: 10px 16px;
  border-radius: var(--radius-sm);
  border: none;
  font-size: 13.5px;
  font-weight: 600;
  font-family: var(--font-ui);
  cursor: pointer;
  transition: background 0.15s ease, opacity 0.15s ease;
}

.btn-primary {
  background: var(--accent-green);
  color: #0a0f0c;
}

.btn-primary:hover { background: var(--accent-green-hover); }
.btn-primary:disabled { opacity: 0.5; cursor: not-allowed; }

.btn-ghost {
  background: transparent;
  border: 1px solid var(--border);
  color: var(--text-primary);
}

.btn-ghost:hover { border-color: var(--border-hover); }

.auth-footer-link {
  text-align: center;
  margin-top: 20px;
  font-size: 13px;
  color: var(--text-secondary);
}

.auth-footer-link a {
  color: var(--accent-green);
  text-decoration: none;
}

.auth-footer-link a:hover { text-decoration: underline; }

/* ---------- Alerts ---------- */

.alert {
  padding: 10px 12px;
  border-radius: var(--radius-sm);
  font-size: 12.5px;
  margin-bottom: 16px;
  display: none;
}

.alert-error {
  background: var(--error-dim);
  color: var(--error);
  border: 1px solid rgba(248, 113, 113, 0.25);
}

.alert-success {
  background: var(--accent-green-dim);
  color: var(--accent-green);
  border: 1px solid rgba(62, 207, 142, 0.25);
}

.alert.visible { display: block; }

/* ---------- Verification code input ---------- */

.code-input {
  letter-spacing: 8px;
  font-family: var(--font-mono);
  font-size: 18px;
  text-align: center;
}

/* ---------- App shell (dashboard) ---------- */

.app-shell {
  display: flex;
  min-height: 100vh;
}

.app-topbar {
  position: fixed;
  top: 0; left: 0; right: 0;
  height: 56px;
  background: var(--surface);
  border-bottom: 1px solid var(--border);
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 24px;
  z-index: 10;
}

.topbar-brand {
  display: flex;
  align-items: center;
  gap: 10px;
}

.topbar-brand img {
  width: 24px;
  height: 24px;
  border-radius: 5px;
  object-fit: cover;
}

.topbar-brand span {
  font-size: 13.5px;
  font-weight: 600;
  color: var(--text-primary);
}

.topbar-user {
  display: flex;
  align-items: center;
  gap: 12px;
}

.topbar-user .role-badge {
  font-size: 10.5px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  padding: 2px 8px;
  border-radius: 999px;
  background: var(--accent-clay-dim);
  color: var(--accent-clay);
}

.topbar-user .user-name {
  font-size: 13px;
  color: var(--text-primary);
}

.logout-btn {
  background: transparent;
  border: 1px solid var(--border);
  color: var(--text-secondary);
  font-size: 12px;
  padding: 6px 12px;
  border-radius: var(--radius-sm);
  cursor: pointer;
  font-family: var(--font-ui);
}

.logout-btn:hover { border-color: var(--border-hover); color: var(--text-primary); }

/* ---------- Theme toggle ---------- */

.theme-toggle {
  position: relative;
  width: 44px;
  height: 24px;
  border-radius: 999px;
  border: 1px solid var(--border-hover);
  background: var(--surface-raised);
  cursor: pointer;
  padding: 0;
  flex-shrink: 0;
}

.theme-toggle .theme-knob {
  position: absolute;
  top: 2px;
  left: 2px;
  width: 18px;
  height: 18px;
  border-radius: 50%;
  background: var(--accent-green);
  display: flex;
  align-items: center;
  justify-content: center;
  color: #fff;
  font-size: 11px;
  transition: left 0.15s ease;
}

html[data-theme="dark"] .theme-toggle .theme-knob { left: 22px; }

/* ---------- Hamburger (right side, messaging nav) ---------- */

.hamburger-nav {
  position: fixed;
  top: 56px;
  right: 0;
  height: calc(100vh - 56px);
  width: 240px;
  background: var(--surface);
  border-left: 1px solid var(--border);
  transition: width 0.2s ease;
  overflow: hidden;
  z-index: 9;
}

.hamburger-nav.collapsed { width: 56px; }

.hamburger-toggle {
  position: absolute;
  top: 12px;
  left: 12px;
  width: 32px;
  height: 32px;
  background: transparent;
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  color: var(--text-secondary);
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
}

.hamburger-toggle:hover { border-color: var(--border-hover); color: var(--text-primary); }

.hamburger-content {
  padding: 56px 16px 16px;
  white-space: nowrap;
}

.hamburger-nav.collapsed .hamburger-content { opacity: 0; pointer-events: none; }

.inbox-link {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 10px 12px;
  border-radius: var(--radius-sm);
  color: var(--text-primary);
  text-decoration: none;
  font-size: 13.5px;
  font-weight: 500;
}

.inbox-link:hover { background: var(--surface-raised); }

.unread-badge {
  background: var(--accent-green);
  color: #0a0f0c;
  font-size: 11px;
  font-weight: 700;
  min-width: 18px;
  height: 18px;
  border-radius: 999px;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 0 5px;
}

/* ---------- Main content area ---------- */

.app-main {
  margin-top: 56px;
  margin-right: 240px;
  padding: 32px 40px;
  flex: 1;
  transition: margin-right 0.2s ease;
}

.app-main.expanded { margin-right: 56px; }

.page-title {
  font-size: 20px;
  font-weight: 600;
  margin: 0 0 4px;
}

.page-subtitle {
  font-size: 13.5px;
  color: var(--text-secondary);
  margin: 0 0 28px;
}

.card-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 20px;
}

.dash-card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 12px;
  padding: 24px;
  display: flex;
  flex-direction: column;
  gap: 4px;
  transition: border-color 0.15s ease;
}

.dash-card:hover { border-color: var(--border-hover); }

.dash-card .dash-card-icon {
  width: 44px;
  height: 44px;
  border-radius: 12px;
  background: var(--accent-green-dim);
  color: var(--accent-green);
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 19px;
  font-weight: 600;
  margin-bottom: 16px;
}

.dash-card h3 {
  font-size: 15px;
  font-weight: 600;
  margin: 0 0 4px;
  color: var(--text-primary);
}

.dash-card p {
  font-size: 13px;
  color: var(--text-secondary);
  margin: 0 0 18px;
  line-height: 1.5;
}

.dash-card-btn {
  margin-top: auto;
  align-self: flex-start;
  background: transparent;
  border: 1px solid var(--border);
  color: var(--text-primary);
  font-size: 12.5px;
  font-weight: 500;
  padding: 8px 14px;
  border-radius: var(--radius-sm);
  cursor: pointer;
  font-family: var(--font-ui);
  text-decoration: none;
  display: inline-block;
  transition: border-color 0.15s ease, background 0.15s ease;
}

.dash-card-btn:hover {
  border-color: var(--accent-green);
  background: var(--accent-green-dim);
  color: var(--accent-green);
}

.pending-loading {
  color: var(--text-muted);
  font-size: 13px;
}

/* ---------- Chat interface ---------- */

.presence-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--text-muted);
  flex-shrink: 0;
  display: inline-block;
}

.presence-dot.online { background: var(--accent-green); }

.chat-list {
  display: flex;
  flex-direction: column;
  gap: 1px;
  background: var(--border);
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  overflow: hidden;
}

.chat-row {
  background: var(--surface);
  padding: 14px 18px;
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 12px;
}

.chat-row:hover { background: var(--surface-raised); }

.chat-avatar {
  width: 38px;
  height: 38px;
  border-radius: 50%;
  background: var(--accent-clay-dim);
  color: var(--accent-clay);
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 13px;
  font-weight: 600;
  flex-shrink: 0;
  position: relative;
}

.chat-avatar .presence-dot {
  position: absolute;
  bottom: -1px;
  right: -1px;
  border: 2px solid var(--surface);
}

.chat-row-text { flex: 1; min-width: 0; }

.chat-row-name {
  font-size: 13.5px;
  color: var(--text-primary);
  margin: 0 0 2px;
}

.chat-row.unread .chat-row-name { font-weight: 700; }

.chat-row-preview {
  font-size: 12.5px;
  color: var(--text-secondary);
  margin: 0;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.chat-row-time {
  font-size: 11px;
  color: var(--text-muted);
  font-family: var(--font-mono);
  flex-shrink: 0;
}

/* Thread header with participant name + presence */
.chat-header {
  display: flex;
  align-items: center;
  gap: 12px;
  padding-bottom: 16px;
  margin-bottom: 16px;
  border-bottom: 1px solid var(--border);
}

.chat-header-name {
  font-size: 15px;
  font-weight: 600;
  color: var(--text-primary);
  margin: 0;
}

.chat-header-status {
  font-size: 12px;
  color: var(--text-muted);
  margin: 0;
  display: flex;
  align-items: center;
  gap: 5px;
}

/* Message bubbles */
.chat-messages {
  display: flex;
  flex-direction: column;
  gap: 8px;
  margin-bottom: 16px;
}

.bubble-row {
  display: flex;
  flex-direction: column;
  max-width: 70%;
}

.bubble-row.sent { align-self: flex-end; align-items: flex-end; }
.bubble-row.received { align-self: flex-start; align-items: flex-start; }

.bubble {
  padding: 9px 13px;
  border-radius: 14px;
  font-size: 13.5px;
  line-height: 1.45;
  white-space: pre-wrap;
}

.bubble-row.sent .bubble {
  background: var(--accent-green);
  color: #ffffff;
  border-bottom-right-radius: 4px;
}

.bubble-row.received .bubble {
  background: var(--surface-raised);
  color: var(--text-primary);
  border-bottom-left-radius: 4px;
}

.bubble-time {
  font-size: 10.5px;
  color: var(--text-muted);
  font-family: var(--font-mono);
  margin-top: 3px;
  padding: 0 4px;
}

/* Chat composer */
.chat-composer {
  display: flex;
  gap: 8px;
  align-items: flex-end;
}

.chat-composer textarea {
  flex: 1;
  min-height: 40px;
  max-height: 120px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 20px;
  padding: 10px 16px;
  color: var(--text-primary);
  font-size: 13.5px;
  font-family: var(--font-ui);
  resize: none;
}

.chat-composer textarea:focus { outline: none; border-color: var(--accent-green); }

.chat-send-btn {
  width: 40px;
  height: 40px;
  border-radius: 50%;
  background: var(--accent-green);
  color: #ffffff;
  border: none;
  cursor: pointer;
  font-size: 16px;
  flex-shrink: 0;
}

.chat-send-btn:hover { background: var(--accent-green-hover); }
.chat-send-btn:disabled { opacity: 0.5; cursor: not-allowed; }

EOF_ACCOUNTING_ASSETS_STYLE_CSS

cat > accounting/assets/presence.js << 'EOF_ACCOUNTING_ASSETS_PRESENCE_JS'
// Pings the server every 20 seconds while any accounting page is open,
// keeping this person's online status live for everyone else.
async function sendHeartbeat() {
  try {
    await apiRequest('/presence/heartbeat', { method: 'POST' });
  } catch (err) {
    // Not logged in, or a network blip — fail silently, next heartbeat will retry
  }
}

document.addEventListener('DOMContentLoaded', () => {
  sendHeartbeat();
  setInterval(sendHeartbeat, 20000);
});

EOF_ACCOUNTING_ASSETS_PRESENCE_JS

cat > accounting/inbox.html << 'EOF_ACCOUNTING_INBOX_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <script>if(localStorage.getItem("accounting-theme")==="dark"){document.documentElement.setAttribute("data-theme","dark")}</script>
  <meta charset="UTF-8">
  <title>Inbox — MACDEN Accounting</title>
  <link rel="stylesheet" href="assets/style.css">
</head>
<body>
  <div class="app-shell">
    <div class="app-topbar">
      <a href="dashboard.html" class="topbar-brand" style="text-decoration: none;">
        <img src="assets/logo.jpeg" alt="MACDEN">
        <span>MACDEN Accounting</span>
      </a>
      <div class="topbar-user">
        <span class="role-badge" id="roleBadge">—</span>
        <span class="user-name" id="userName">Loading…</span>
        <button class="theme-toggle" id="themeToggle" aria-label="Toggle dark mode">
          <span class="theme-knob"></span>
        </button>
        <button class="logout-btn" id="logoutBtn">Log out</button>
      </div>
    </div>

    <div class="hamburger-nav" id="hamburgerNav">
      <button class="hamburger-toggle" id="hamburgerToggle" aria-label="Toggle menu">☰</button>
      <div class="hamburger-content">
        <a href="inbox.html" class="inbox-link">
          <span>Inbox</span>
          <span class="unread-badge" id="unreadBadge">0</span>
        </a>
        <a href="drafts.html" class="inbox-link"><span>Drafts</span></a>
      </div>
    </div>

    <div class="app-main" id="appMain">

      <div id="listView">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px;">
          <div>
            <h1 class="page-title">Inbox</h1>
            <p class="page-subtitle"><a href="dashboard.html" style="color: var(--accent-green);">← Back to dashboard</a></p>
          </div>
          <button class="btn btn-primary" style="width: auto; padding: 9px 18px;" onclick="window.location.href='compose.html'">+ New chat</button>
        </div>
        <div class="chat-list" id="chatList">
          <div style="padding: 40px 20px; text-align: center; color: var(--text-muted); font-size: 13px;">Loading…</div>
        </div>
      </div>

      <div id="threadView" style="display: none;">
        <a href="inbox.html" style="color: var(--accent-green); text-decoration: none; font-size: 13px; display: inline-block; margin-bottom: 16px;">← Back to inbox</a>

        <div class="chat-header">
          <div class="chat-avatar" id="threadAvatar" style="position: relative;">
            <span id="threadInitials">—</span>
            <span class="presence-dot" id="threadDot"></span>
          </div>
          <div>
            <p class="chat-header-name" id="threadName">—</p>
            <p class="chat-header-status" id="threadStatus">—</p>
          </div>
        </div>

        <div class="chat-messages" id="messagesContainer"></div>

        <div id="replyAlert" class="alert alert-error"></div>
        <div class="chat-composer">
          <textarea id="replyBody" placeholder="Type a message…" rows="1"></textarea>
          <button class="chat-send-btn" id="sendReplyBtn" aria-label="Send">→</button>
        </div>
      </div>

    </div>
  </div>

  <script src="assets/api.js"></script>
  <script src="assets/presence.js"></script>
  <script src="assets/theme.js"></script>
  <script>
    const hamburgerNav = document.getElementById('hamburgerNav');
    const hamburgerToggle = document.getElementById('hamburgerToggle');
    const appMain = document.getElementById('appMain');
    hamburgerToggle.addEventListener('click', () => {
      hamburgerNav.classList.toggle('collapsed');
      appMain.classList.toggle('expanded');
    });

    document.getElementById('logoutBtn').addEventListener('click', async () => {
      await apiRequest('/auth/logout', { method: 'POST' });
      window.location.href = 'login.html';
    });

    let currentStaffId = null;
    let currentConversationId = null;
    const params = new URLSearchParams(window.location.search);
    const openConversationId = params.get('id');

    function initials(name) {
      if (!name) return '?';
      return name.split(' ').map(p => p[0]).join('').slice(0, 2).toUpperCase();
    }

    async function init() {
      try {
        const result = await apiRequest('/dashboard-check');
        document.getElementById('userName').textContent = result.staff.fullName;
        document.getElementById('roleBadge').textContent = result.staff.role;
        currentStaffId = result.staff.id;
      } catch (err) {
        window.location.href = 'login.html';
        return;
      }

      if (openConversationId) {
        openThread(openConversationId);
      } else {
        loadInbox();
      }
    }

    async function loadInbox() {
      const list = document.getElementById('chatList');
      try {
        const result = await apiRequest('/messages/conversations');
        if (result.conversations.length === 0) {
          list.innerHTML = '<div style="padding: 40px 20px; text-align: center; color: var(--text-muted); font-size: 13px;">No chats yet. Start one with New chat.</div>';
          return;
        }
        list.innerHTML = result.conversations.map(c => {
          const firstParticipant = c.participants[0];
          const online = firstParticipant && firstParticipant.isOnline;
          return `
            <div class="chat-row ${c.isUnread ? 'unread' : ''}" onclick="window.location.href='inbox.html?id=${c.id}'">
              <div class="chat-avatar">
                ${initials(c.displayName)}
                <span class="presence-dot ${online ? 'online' : ''}"></span>
              </div>
              <div class="chat-row-text">
                <p class="chat-row-name">${c.displayName}</p>
                <p class="chat-row-preview">${c.lastMessagePreview || 'No messages yet'}</p>
              </div>
              <span class="chat-row-time">${c.lastMessageAt ? new Date(c.lastMessageAt).toLocaleDateString() : ''}</span>
            </div>
          `;
        }).join('');
      } catch (err) {
        list.innerHTML = '<div style="padding: 40px 20px; text-align: center; color: var(--text-muted); font-size: 13px;">Could not load inbox.</div>';
      }
    }

    async function openThread(id) {
      currentConversationId = id;
      document.getElementById('listView').style.display = 'none';
      document.getElementById('threadView').style.display = 'block';

      try {
        const result = await apiRequest(`/messages/conversations/${id}`);
        const participant = result.participants[0];

        document.getElementById('threadInitials').textContent = initials(participant ? participant.fullName : '?');
        document.getElementById('threadName').textContent = participant ? participant.fullName : 'Conversation';
        document.getElementById('threadStatus').textContent = participant && participant.isOnline ? 'Online' : 'Offline';
        document.getElementById('threadDot').className = 'presence-dot' + (participant && participant.isOnline ? ' online' : '');

        const container = document.getElementById('messagesContainer');
        container.innerHTML = result.messages.map(m => {
          const sent = m.sender_id === currentStaffId;
          return `
            <div class="bubble-row ${sent ? 'sent' : 'received'}">
              <div class="bubble">${m.body}${m.status === 'draft' ? ' (draft)' : ''}</div>
              <div class="bubble-time">${m.sent_at ? new Date(m.sent_at).toLocaleTimeString([], {hour: '2-digit', minute: '2-digit'}) : ''}</div>
            </div>
          `;
        }).join('');
        container.scrollTop = container.scrollHeight;

        loadUnreadBadge();
      } catch (err) {
        document.getElementById('messagesContainer').innerHTML = `<div style="color: var(--text-muted); font-size: 13px;">${err.message}</div>`;
      }
    }

    document.getElementById('sendReplyBtn').addEventListener('click', async () => {
      const alertEl = document.getElementById('replyAlert');
      const textarea = document.getElementById('replyBody');
      const body = textarea.value.trim();
      hideAlert(alertEl);

      if (!body || !currentConversationId) return;

      try {
        await apiRequest(`/messages/conversations/${currentConversationId}/reply`, {
          method: 'POST',
          body: { body, status: 'sent' }
        });
        textarea.value = '';
        openThread(currentConversationId);
      } catch (err) {
        showAlert(alertEl, err.message);
      }
    });

    document.getElementById('replyBody').addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        document.getElementById('sendReplyBtn').click();
      }
    });

    // Lightweight presence + new-message refresh while a thread is open
    setInterval(() => {
      if (currentConversationId && document.getElementById('threadView').style.display !== 'none') {
        openThread(currentConversationId);
      }
    }, 20000);

    init();
    loadUnreadBadge();
  </script>
</body>
</html>

EOF_ACCOUNTING_INBOX_HTML

cat > accounting/compose.html << 'EOF_ACCOUNTING_COMPOSE_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <script>if(localStorage.getItem("accounting-theme")==="dark"){document.documentElement.setAttribute("data-theme","dark")}</script>
  <meta charset="UTF-8">
  <title>Compose — MACDEN Accounting</title>
  <link rel="stylesheet" href="assets/style.css">
  <style>
    .compose-card { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-md); padding: 24px; max-width: 640px; }
    .recipient-search-wrap { position: relative; }
    .recipient-chips { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 8px; }
    .chip { background: var(--accent-green-dim); color: var(--accent-green); font-size: 12.5px; padding: 5px 10px; border-radius: 999px; display: flex; align-items: center; gap: 6px; }
    .chip button { background: none; border: none; color: var(--accent-green); cursor: pointer; font-size: 13px; padding: 0; line-height: 1; }
    .search-results { position: absolute; top: 100%; left: 0; right: 0; background: var(--surface-raised); border: 1px solid var(--border); border-radius: var(--radius-sm); margin-top: 4px; max-height: 200px; overflow-y: auto; z-index: 5; display: none; }
    .search-results.visible { display: block; }
    .search-result-item { padding: 10px 12px; cursor: pointer; font-size: 13px; }
    .search-result-item:hover { background: var(--surface); }
    .compose-textarea { width: 100%; min-height: 160px; background: var(--bg); border: 1px solid var(--border); border-radius: var(--radius-sm); padding: 10px 12px; color: var(--text-primary); font-size: 13.5px; font-family: var(--font-ui); resize: vertical; }
    .compose-actions { display: flex; gap: 8px; margin-top: 20px; }
    .compose-actions .btn { width: auto; padding: 10px 20px; }
  </style>
</head>
<body>
  <div class="app-shell">
    <div class="app-topbar">
      <a href="dashboard.html" class="topbar-brand" style="text-decoration: none;">
        <img src="assets/logo.jpeg" alt="MACDEN">
        <span>MACDEN Accounting</span>
      </a>
      <div class="topbar-user">
        <span class="role-badge" id="roleBadge">—</span>
        <span class="user-name" id="userName">Loading…</span>
        <button class="theme-toggle" id="themeToggle" aria-label="Toggle dark mode">
          <span class="theme-knob"></span>
        </button>
        <button class="logout-btn" id="logoutBtn">Log out</button>
      </div>
    </div>

    <div class="hamburger-nav" id="hamburgerNav">
      <button class="hamburger-toggle" id="hamburgerToggle" aria-label="Toggle menu">☰</button>
      <div class="hamburger-content">
        <a href="inbox.html" class="inbox-link">
          <span>Inbox</span>
          <span class="unread-badge" id="unreadBadge">0</span>
        </a>
        <a href="drafts.html" class="inbox-link"><span>Drafts</span></a>
      </div>
    </div>

    <div class="app-main" id="appMain">
      <h1 class="page-title">Compose</h1>
      <p class="page-subtitle"><a href="inbox.html" style="color: var(--accent-green);">← Back to inbox</a></p>

      <div id="alert" class="alert alert-error"></div>

      <div class="compose-card">
        <div class="field">
          <label>To</label>
          <div class="recipient-chips" id="recipientChips"></div>
          <div class="recipient-search-wrap">
            <input type="text" id="recipientSearch" placeholder="Search staff by name or username…">
            <div class="search-results" id="searchResults"></div>
          </div>
        </div>
        <div class="field">
          <label>Message</label>
          <textarea class="compose-textarea" id="body" placeholder="Write your message…"></textarea>
        </div>
        <div class="compose-actions">
          <button class="btn btn-ghost" id="saveDraftBtn">Save as draft</button>
          <button class="btn btn-primary" id="sendBtn">Send</button>
        </div>
      </div>
    </div>
  </div>

  <script src="assets/api.js"></script>
  <script src="assets/presence.js"></script>
  <script src="assets/theme.js"></script>
  <script>
    const hamburgerNav = document.getElementById('hamburgerNav');
    const hamburgerToggle = document.getElementById('hamburgerToggle');
    const appMain = document.getElementById('appMain');
    hamburgerToggle.addEventListener('click', () => {
      hamburgerNav.classList.toggle('collapsed');
      appMain.classList.toggle('expanded');
    });

    document.getElementById('logoutBtn').addEventListener('click', async () => {
      await apiRequest('/auth/logout', { method: 'POST' });
      window.location.href = 'login.html';
    });

    let selectedRecipients = []; // [{id, full_name}]
    let searchTimeout = null;

    async function init() {
      try {
        const result = await apiRequest('/dashboard-check');
        document.getElementById('userName').textContent = result.staff.fullName;
        document.getElementById('roleBadge').textContent = result.staff.role;
      } catch (err) {
        window.location.href = 'login.html';
      }
    }

    const searchInput = document.getElementById('recipientSearch');
    const searchResults = document.getElementById('searchResults');

    searchInput.addEventListener('input', () => {
      clearTimeout(searchTimeout);
      const query = searchInput.value.trim();
      if (!query) {
        searchResults.classList.remove('visible');
        return;
      }
      searchTimeout = setTimeout(() => searchStaff(query), 250);
    });

    async function searchStaff(query) {
      try {
        const result = await apiRequest(`/staff?search=${encodeURIComponent(query)}`);
        const available = result.staff.filter(s => !selectedRecipients.find(r => r.id === s.id));

        if (available.length === 0) {
          searchResults.innerHTML = '<div class="search-result-item" style="color: var(--text-muted);">No matches.</div>';
        } else {
          searchResults.innerHTML = available.map(s => `
            <div class="search-result-item" style="display: flex; align-items: center; gap: 8px;" onclick='selectRecipient(${JSON.stringify(s)})'>
              <span class="presence-dot ${s.isOnline ? 'online' : ''}"></span>
              <span>${s.full_name} · ${s.username}</span>
            </div>
          `).join('');
        }
        searchResults.classList.add('visible');
      } catch (err) {
        searchResults.classList.remove('visible');
      }
    }

    function selectRecipient(staff) {
      selectedRecipients.push(staff);
      renderChips();
      searchInput.value = '';
      searchResults.classList.remove('visible');
    }

    function removeRecipient(id) {
      selectedRecipients = selectedRecipients.filter(r => r.id !== id);
      renderChips();
    }

    function renderChips() {
      document.getElementById('recipientChips').innerHTML = selectedRecipients.map(r => `
        <span class="chip">${r.full_name} <button onclick="removeRecipient('${r.id}')">×</button></span>
      `).join('');
    }

    document.getElementById('sendBtn').addEventListener('click', () => submitCompose('sent'));
    document.getElementById('saveDraftBtn').addEventListener('click', () => submitCompose('draft'));

    async function submitCompose(status) {
      const alertEl = document.getElementById('alert');
      hideAlert(alertEl);

      const body = document.getElementById('body').value.trim();

      if (selectedRecipients.length === 0) {
        showAlert(alertEl, 'Add at least one recipient.');
        return;
      }
      if (!body) {
        showAlert(alertEl, 'Write a message.');
        return;
      }

      try {
        const result = await apiRequest('/messages/compose', {
          method: 'POST',
          body: {
            recipientIds: selectedRecipients.map(r => r.id),
            body,
            status
          }
        });

        if (status === 'sent') {
          window.location.href = `inbox.html?id=${result.conversationId}`;
        } else {
          window.location.href = 'drafts.html';
        }
      } catch (err) {
        showAlert(alertEl, err.message);
      }
    }

    // Close search dropdown when clicking elsewhere
    document.addEventListener('click', (e) => {
      if (!e.target.closest('.recipient-search-wrap')) {
        searchResults.classList.remove('visible');
      }
    });

    init();
    loadUnreadBadge();
  </script>
</body>
</html>

EOF_ACCOUNTING_COMPOSE_HTML

cat > accounting/drafts.html << 'EOF_ACCOUNTING_DRAFTS_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <script>if(localStorage.getItem("accounting-theme")==="dark"){document.documentElement.setAttribute("data-theme","dark")}</script>
  <meta charset="UTF-8">
  <title>Drafts — MACDEN Accounting</title>
  <link rel="stylesheet" href="assets/style.css">
  <style>
    .conv-list { display: flex; flex-direction: column; gap: 1px; background: var(--border); border: 1px solid var(--border); border-radius: var(--radius-md); overflow: hidden; }
    .conv-row { background: var(--surface); padding: 16px 20px; cursor: pointer; display: flex; justify-content: space-between; align-items: flex-start; }
    .conv-row:hover { background: var(--surface-raised); }
    .conv-subject { font-size: 13.5px; color: var(--text-primary); margin: 0 0 3px; font-weight: 600; }
    .conv-preview { font-size: 12.5px; color: var(--text-secondary); margin: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 480px; }
    .conv-time { font-size: 11.5px; color: var(--text-muted); font-family: var(--font-mono); white-space: nowrap; margin-left: 16px; }
    .empty-inbox { padding: 40px 20px; text-align: center; color: var(--text-muted); font-size: 13px; }
  </style>
</head>
<body>
  <div class="app-shell">
    <div class="app-topbar">
      <a href="dashboard.html" class="topbar-brand" style="text-decoration: none;">
        <img src="assets/logo.jpeg" alt="MACDEN">
        <span>MACDEN Accounting</span>
      </a>
      <div class="topbar-user">
        <span class="role-badge" id="roleBadge">—</span>
        <span class="user-name" id="userName">Loading…</span>
        <button class="theme-toggle" id="themeToggle" aria-label="Toggle dark mode">
          <span class="theme-knob"></span>
        </button>
        <button class="logout-btn" id="logoutBtn">Log out</button>
      </div>
    </div>

    <div class="hamburger-nav" id="hamburgerNav">
      <button class="hamburger-toggle" id="hamburgerToggle" aria-label="Toggle menu">☰</button>
      <div class="hamburger-content">
        <a href="inbox.html" class="inbox-link">
          <span>Inbox</span>
          <span class="unread-badge" id="unreadBadge">0</span>
        </a>
        <a href="drafts.html" class="inbox-link"><span>Drafts</span></a>
      </div>
    </div>

    <div class="app-main" id="appMain">
      <h1 class="page-title">Drafts</h1>
      <p class="page-subtitle"><a href="inbox.html" style="color: var(--accent-green);">← Back to inbox</a></p>

      <div class="conv-list" id="draftList">
        <div class="empty-inbox">Loading…</div>
      </div>
    </div>
  </div>

  <script src="assets/api.js"></script>
  <script src="assets/presence.js"></script>
  <script src="assets/theme.js"></script>
  <script>
    const hamburgerNav = document.getElementById('hamburgerNav');
    const hamburgerToggle = document.getElementById('hamburgerToggle');
    const appMain = document.getElementById('appMain');
    hamburgerToggle.addEventListener('click', () => {
      hamburgerNav.classList.toggle('collapsed');
      appMain.classList.toggle('expanded');
    });

    document.getElementById('logoutBtn').addEventListener('click', async () => {
      await apiRequest('/auth/logout', { method: 'POST' });
      window.location.href = 'login.html';
    });

    async function init() {
      try {
        const result = await apiRequest('/dashboard-check');
        document.getElementById('userName').textContent = result.staff.fullName;
        document.getElementById('roleBadge').textContent = result.staff.role;
      } catch (err) {
        window.location.href = 'login.html';
        return;
      }
      loadDrafts();
    }

    async function loadDrafts() {
      const list = document.getElementById('draftList');
      try {
        const result = await apiRequest('/messages/drafts');
        if (result.drafts.length === 0) {
          list.innerHTML = '<div class="empty-inbox">No drafts. Start one from Compose.</div>';
          return;
        }
        list.innerHTML = result.drafts.map(d => `
          <div class="conv-row" onclick="window.location.href='inbox.html?id=${d.conversation_id}'">
            <div>
              <p class="conv-subject">${d.displayName}</p>
              <p class="conv-preview">${d.body || '(empty draft)'}</p>
            </div>
            <span class="conv-time">${new Date(d.created_at).toLocaleDateString()}</span>
          </div>
        `).join('');
      } catch (err) {
        list.innerHTML = '<div class="empty-inbox">Could not load drafts.</div>';
      }
    }

    init();
    loadUnreadBadge();
  </script>
</body>
</html>

EOF_ACCOUNTING_DRAFTS_HTML

cat > accounting/dashboard.html << 'EOF_ACCOUNTING_DASHBOARD_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <script>if(localStorage.getItem("accounting-theme")==="dark"){document.documentElement.setAttribute("data-theme","dark")}</script>
  <meta charset="UTF-8">
  <title>Dashboard — MACDEN Accounting</title>
  <link rel="stylesheet" href="assets/style.css">
</head>
<body>
  <div class="app-shell">

    <div class="app-topbar">
      <a href="dashboard.html" class="topbar-brand" style="text-decoration: none;">
        <img src="assets/logo.jpeg" alt="MACDEN">
        <span>MACDEN Accounting</span>
      </a>
      <div class="topbar-user">
        <span class="role-badge" id="roleBadge">—</span>
        <span class="user-name" id="userName">Loading…</span>
        <button class="theme-toggle" id="themeToggle" aria-label="Toggle dark mode">
          <span class="theme-knob"></span>
        </button>
        <button class="logout-btn" id="logoutBtn">Log out</button>
      </div>
    </div>

    <div class="hamburger-nav" id="hamburgerNav">
      <button class="hamburger-toggle" id="hamburgerToggle" aria-label="Toggle menu">☰</button>
      <div class="hamburger-content">
        <a href="inbox.html" class="inbox-link">
          <span>Inbox</span>
          <span class="unread-badge" id="unreadBadge">0</span>
        </a>
        <a href="drafts.html" class="inbox-link"><span>Drafts</span></a>
      </div>
    </div>

    <div class="app-main" id="appMain">
      <h1 class="page-title" id="welcomeTitle">Welcome</h1>
      <p class="page-subtitle">Accounting department — internal tools.</p>

      <div class="card-grid">
        <div class="dash-card">
          <div class="dash-card-icon">₦</div>
          <h3>Price check</h3>
          <p>Look up current product pricing.</p>
          <a href="prices.html" class="dash-card-btn">Open →</a>
        </div>
        <div class="dash-card">
          <div class="dash-card-icon">↺</div>
          <h3>Price history</h3>
          <p>View prices from last week or last month.</p>
          <a href="prices-history.html" class="dash-card-btn">Open →</a>
        </div>
        <div class="dash-card">
          <div class="dash-card-icon">✉</div>
          <h3>Messages</h3>
          <p>Message other accounting staff.</p>
          <a href="inbox.html" class="dash-card-btn">Open →</a>
        </div>
      </div>

      <div id="adminSection" style="display: none; margin-top: 32px;">
        <h2 class="page-title" style="font-size: 16px;">Pending approvals</h2>
        <p class="page-subtitle">New staff accounts waiting for activation.</p>
        <div id="pendingList" class="pending-loading">Loading…</div>
      </div>
    </div>

  </div>

  <script src="assets/api.js"></script>
  <script src="assets/presence.js"></script>
  <script src="assets/theme.js"></script>
  <script>
    const hamburgerNav = document.getElementById('hamburgerNav');
    const hamburgerToggle = document.getElementById('hamburgerToggle');
    const appMain = document.getElementById('appMain');

    // Hamburger: default open, collapses on click
    hamburgerToggle.addEventListener('click', () => {
      hamburgerNav.classList.toggle('collapsed');
      appMain.classList.toggle('expanded');
    });

    document.getElementById('logoutBtn').addEventListener('click', async () => {
      await apiRequest('/auth/logout', { method: 'POST' });
      window.location.href = 'login.html';
    });

    async function loadDashboard() {
      try {
        const result = await apiRequest('/dashboard-check');
        const staff = result.staff;

        document.getElementById('userName').textContent = staff.fullName;
        document.getElementById('roleBadge').textContent = staff.role;
        document.getElementById('welcomeTitle').textContent = `Welcome, ${staff.fullName.split(' ')[0]}`;

        if (staff.role === 'admin') {
          loadPendingStaff();
        }
      } catch (err) {
        // Not logged in, or session expired — send back to login
        window.location.href = 'login.html';
      }
    }

    async function loadPendingStaff() {
      const adminSection = document.getElementById('adminSection');
      const pendingList = document.getElementById('pendingList');
      adminSection.style.display = 'block';

      try {
        const result = await apiRequest('/admin/pending-staff');

        if (result.pending.length === 0) {
          pendingList.innerHTML = '<p class="pending-loading">No accounts waiting for approval.</p>';
          return;
        }

        pendingList.innerHTML = result.pending.map(person => `
          <div class="dash-card" style="margin-bottom: 8px; display: flex; align-items: center; justify-content: space-between;">
            <div>
              <h3>${person.full_name}</h3>
              <p>${person.username} · ${person.email}</p>
            </div>
            <button class="btn btn-primary" style="width: auto; padding: 8px 16px;" onclick="approveStaff('${person.id}', this)">Approve</button>
          </div>
        `).join('');
      } catch (err) {
        pendingList.innerHTML = `<p class="pending-loading">Could not load pending accounts.</p>`;
      }
    }

    async function approveStaff(id, btn) {
      btn.disabled = true;
      btn.textContent = 'Approving…';
      try {
        await apiRequest(`/admin/approve-staff/${id}`, { method: 'POST' });
        loadPendingStaff();
      } catch (err) {
        btn.textContent = 'Failed — retry';
        btn.disabled = false;
      }
    }

    loadDashboard();
    loadUnreadBadge();
  </script>
</body>
</html>

EOF_ACCOUNTING_DASHBOARD_HTML

cat > accounting/prices.html << 'EOF_ACCOUNTING_PRICES_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <script>if(localStorage.getItem("accounting-theme")==="dark"){document.documentElement.setAttribute("data-theme","dark")}</script>
  <meta charset="UTF-8">
  <title>Price check — MACDEN Accounting</title>
  <link rel="stylesheet" href="assets/style.css">
  <style>
    .price-table {
      width: 100%;
      border-collapse: collapse;
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: var(--radius-md);
      overflow: hidden;
    }
    .price-table th {
      text-align: left;
      font-size: 11.5px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.03em;
      color: var(--text-secondary);
      padding: 12px 16px;
      border-bottom: 1px solid var(--border);
      background: var(--surface-raised);
    }
    .price-table td {
      padding: 12px 16px;
      border-bottom: 1px solid var(--border);
      font-size: 13.5px;
    }
    .price-table tr:last-child td { border-bottom: none; }
    .price-table .mono { font-family: var(--font-mono); color: var(--text-secondary); font-size: 12.5px; }
    .edit-inline-btn {
      background: transparent;
      border: 1px solid var(--border);
      color: var(--text-secondary);
      font-size: 12px;
      padding: 5px 10px;
      border-radius: var(--radius-sm);
      cursor: pointer;
      font-family: var(--font-ui);
    }
    .edit-inline-btn:hover { border-color: var(--accent-green); color: var(--accent-green); }
    .toolbar {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 16px;
    }
    .add-btn {
      width: auto;
      padding: 9px 16px;
    }
    /* Simple modal */
    .modal-backdrop {
      display: none;
      position: fixed;
      inset: 0;
      background: rgba(0,0,0,0.6);
      align-items: center;
      justify-content: center;
      z-index: 100;
    }
    .modal-backdrop.visible { display: flex; }
    .modal {
      width: 360px;
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: var(--radius-lg);
      padding: 24px;
    }
    .modal h3 { margin: 0 0 16px; font-size: 15px; }
    .modal-actions { display: flex; gap: 8px; margin-top: 20px; }
  </style>
</head>
<body>
  <div class="app-shell">
    <div class="app-topbar">
      <a href="dashboard.html" class="topbar-brand" style="text-decoration: none;">
        <img src="assets/logo.jpeg" alt="MACDEN">
        <span>MACDEN Accounting</span>
      </a>
      <div class="topbar-user">
        <span class="role-badge" id="roleBadge">—</span>
        <span class="user-name" id="userName">Loading…</span>
        <button class="theme-toggle" id="themeToggle" aria-label="Toggle dark mode">
          <span class="theme-knob"></span>
        </button>
        <button class="logout-btn" id="logoutBtn">Log out</button>
      </div>
    </div>

    <div class="hamburger-nav" id="hamburgerNav">
      <button class="hamburger-toggle" id="hamburgerToggle" aria-label="Toggle menu">☰</button>
      <div class="hamburger-content">
        <a href="inbox.html" class="inbox-link">
          <span>Inbox</span>
          <span class="unread-badge" id="unreadBadge">0</span>
        </a>
        <a href="drafts.html" class="inbox-link"><span>Drafts</span></a>
      </div>
    </div>

    <div class="app-main" id="appMain">
      <div class="toolbar">
        <div>
          <h1 class="page-title">Price check</h1>
          <p class="page-subtitle">Current product pricing. <a href="prices-history.html" style="color: var(--accent-green);">View history →</a></p>
        </div>
        <button class="btn btn-primary add-btn" id="addBtn" style="display: none;">+ Add product</button>
      </div>

      <div id="alert" class="alert alert-error"></div>

      <table class="price-table">
        <thead>
          <tr>
            <th>Product</th>
            <th>Cost price</th>
            <th>Margin</th>
            <th>Last updated</th>
            <th></th>
          </tr>
        </thead>
        <tbody id="priceTableBody">
          <tr><td colspan="5" class="pending-loading">Loading prices…</td></tr>
        </tbody>
      </table>
    </div>
  </div>

  <!-- Edit / Add modal -->
  <div class="modal-backdrop" id="modalBackdrop">
    <div class="modal">
      <h3 id="modalTitle">Edit price</h3>
      <div id="modalAlert" class="alert alert-error"></div>
      <div class="field" id="productNameField" style="display: none;">
        <label>Product name</label>
        <input type="text" id="modalProductName" placeholder="e.g. Guinness Stout 60cl">
      </div>
      <div class="field">
        <label>Cost price (₦)</label>
        <input type="number" id="modalCostPrice" step="0.01" placeholder="0.00">
      </div>
      <div class="field">
        <label>Margin (%)</label>
        <input type="number" id="modalMargin" step="0.1" placeholder="Optional">
      </div>
      <div class="modal-actions">
        <button class="btn btn-ghost" id="modalCancel">Cancel</button>
        <button class="btn btn-primary" id="modalSave">Save</button>
      </div>
    </div>
  </div>

  <script src="assets/api.js"></script>
  <script src="assets/presence.js"></script>
  <script src="assets/theme.js"></script>
  <script>
    const hamburgerNav = document.getElementById('hamburgerNav');
    const hamburgerToggle = document.getElementById('hamburgerToggle');
    const appMain = document.getElementById('appMain');
    hamburgerToggle.addEventListener('click', () => {
      hamburgerNav.classList.toggle('collapsed');
      appMain.classList.toggle('expanded');
    });

    document.getElementById('logoutBtn').addEventListener('click', async () => {
      await apiRequest('/auth/logout', { method: 'POST' });
      window.location.href = 'login.html';
    });

    let canEdit = false;
    let editingId = null;

    async function init() {
      try {
        const result = await apiRequest('/dashboard-check');
        document.getElementById('userName').textContent = result.staff.fullName;
        document.getElementById('roleBadge').textContent = result.staff.role;
        canEdit = result.staff.canEditPrices;
        if (canEdit) document.getElementById('addBtn').style.display = 'block';
        loadPrices();
      } catch (err) {
        window.location.href = 'login.html';
      }
    }

    async function loadPrices() {
      const tbody = document.getElementById('priceTableBody');
      try {
        const result = await apiRequest('/prices');
        if (result.prices.length === 0) {
          tbody.innerHTML = '<tr><td colspan="5" class="pending-loading">No products yet.</td></tr>';
          return;
        }
        tbody.innerHTML = result.prices.map(p => `
          <tr>
            <td>${p.product_name}</td>
            <td class="mono">₦${Number(p.cost_price).toLocaleString()}</td>
            <td class="mono">${p.margin_percent ? p.margin_percent + '%' : '—'}</td>
            <td class="mono">${new Date(p.updated_at).toLocaleDateString()}</td>
            <td>${canEdit ? `<button class="edit-inline-btn" onclick="openEdit('${p.id}', '${p.product_name}', ${p.cost_price}, ${p.margin_percent || 'null'})">Edit</button>` : ''}</td>
          </tr>
        `).join('');
      } catch (err) {
        tbody.innerHTML = `<tr><td colspan="5" class="pending-loading">Could not load prices.</td></tr>`;
      }
    }

    const modalBackdrop = document.getElementById('modalBackdrop');
    const modalAlert = document.getElementById('modalAlert');

    function openEdit(id, name, cost, margin) {
      editingId = id;
      document.getElementById('modalTitle').textContent = `Edit — ${name}`;
      document.getElementById('productNameField').style.display = 'none';
      document.getElementById('modalCostPrice').value = cost;
      document.getElementById('modalMargin').value = margin || '';
      hideAlert(modalAlert);
      modalBackdrop.classList.add('visible');
    }

    document.getElementById('addBtn').addEventListener('click', () => {
      editingId = null;
      document.getElementById('modalTitle').textContent = 'Add product';
      document.getElementById('productNameField').style.display = 'block';
      document.getElementById('modalProductName').value = '';
      document.getElementById('modalCostPrice').value = '';
      document.getElementById('modalMargin').value = '';
      hideAlert(modalAlert);
      modalBackdrop.classList.add('visible');
    });

    document.getElementById('modalCancel').addEventListener('click', () => {
      modalBackdrop.classList.remove('visible');
    });

    document.getElementById('modalSave').addEventListener('click', async () => {
      const costPrice = parseFloat(document.getElementById('modalCostPrice').value);
      const marginPercent = document.getElementById('modalMargin').value
        ? parseFloat(document.getElementById('modalMargin').value)
        : null;

      if (isNaN(costPrice)) {
        showAlert(modalAlert, 'Enter a valid cost price.');
        return;
      }

      try {
        if (editingId) {
          await apiRequest(`/prices/${editingId}`, {
            method: 'PUT',
            body: { costPrice, marginPercent }
          });
        } else {
          const productName = document.getElementById('modalProductName').value.trim();
          if (!productName) {
            showAlert(modalAlert, 'Enter a product name.');
            return;
          }
          await apiRequest('/prices', {
            method: 'POST',
            body: { productName, costPrice, marginPercent }
          });
        }
        modalBackdrop.classList.remove('visible');
        loadPrices();
      } catch (err) {
        showAlert(modalAlert, err.message);
      }
    });

    init();
    loadUnreadBadge();
  </script>
</body>
</html>

EOF_ACCOUNTING_PRICES_HTML

cat > accounting/prices-history.html << 'EOF_ACCOUNTING_PRICES-HISTORY_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <script>if(localStorage.getItem("accounting-theme")==="dark"){document.documentElement.setAttribute("data-theme","dark")}</script>
  <meta charset="UTF-8">
  <title>Price history — MACDEN Accounting</title>
  <link rel="stylesheet" href="assets/style.css">
  <style>
    .price-table {
      width: 100%;
      border-collapse: collapse;
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: var(--radius-md);
      overflow: hidden;
    }
    .price-table th {
      text-align: left;
      font-size: 11.5px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.03em;
      color: var(--text-secondary);
      padding: 12px 16px;
      border-bottom: 1px solid var(--border);
      background: var(--surface-raised);
    }
    .price-table td {
      padding: 12px 16px;
      border-bottom: 1px solid var(--border);
      font-size: 13.5px;
    }
    .price-table tr:last-child td { border-bottom: none; }
    .price-table .mono { font-family: var(--font-mono); color: var(--text-secondary); font-size: 12.5px; }

    .controls-row {
      display: flex;
      gap: 12px;
      align-items: flex-end;
      margin-bottom: 20px;
    }
    .controls-row .field { margin-bottom: 0; flex: 1; }
    .controls-row select {
      width: 100%;
      background: var(--bg);
      border: 1px solid var(--border);
      border-radius: var(--radius-sm);
      padding: 10px 12px;
      color: var(--text-primary);
      font-size: 13.5px;
      font-family: var(--font-ui);
    }
    .range-toggle {
      display: flex;
      gap: 6px;
    }
    .range-btn {
      background: transparent;
      border: 1px solid var(--border);
      color: var(--text-secondary);
      font-size: 12.5px;
      padding: 9px 14px;
      border-radius: var(--radius-sm);
      cursor: pointer;
      font-family: var(--font-ui);
    }
    .range-btn.active {
      background: var(--accent-green-dim);
      border-color: var(--accent-green);
      color: var(--accent-green);
    }
  </style>
</head>
<body>
  <div class="app-shell">
    <div class="app-topbar">
      <a href="dashboard.html" class="topbar-brand" style="text-decoration: none;">
        <img src="assets/logo.jpeg" alt="MACDEN">
        <span>MACDEN Accounting</span>
      </a>
      <div class="topbar-user">
        <span class="role-badge" id="roleBadge">—</span>
        <span class="user-name" id="userName">Loading…</span>
        <button class="theme-toggle" id="themeToggle" aria-label="Toggle dark mode">
          <span class="theme-knob"></span>
        </button>
        <button class="logout-btn" id="logoutBtn">Log out</button>
      </div>
    </div>

    <div class="hamburger-nav" id="hamburgerNav">
      <button class="hamburger-toggle" id="hamburgerToggle" aria-label="Toggle menu">☰</button>
      <div class="hamburger-content">
        <a href="inbox.html" class="inbox-link">
          <span>Inbox</span>
          <span class="unread-badge" id="unreadBadge">0</span>
        </a>
        <a href="drafts.html" class="inbox-link"><span>Drafts</span></a>
      </div>
    </div>

    <div class="app-main" id="appMain">
      <h1 class="page-title">Price history</h1>
      <p class="page-subtitle"><a href="prices.html" style="color: var(--accent-green);">← Back to current prices</a></p>

      <div class="controls-row">
        <div class="field">
          <label>Product</label>
          <select id="productSelect">
            <option value="">Select a product…</option>
          </select>
        </div>
        <div class="range-toggle">
          <button class="range-btn active" data-range="week" id="rangeWeek">Last week</button>
          <button class="range-btn" data-range="month" id="rangeMonth">Last month</button>
        </div>
      </div>

      <table class="price-table">
        <thead>
          <tr>
            <th>Cost price</th>
            <th>Margin</th>
            <th>Recorded</th>
          </tr>
        </thead>
        <tbody id="historyTableBody">
          <tr><td colspan="3" class="pending-loading">Select a product to view its price history.</td></tr>
        </tbody>
      </table>
    </div>
  </div>

  <script src="assets/api.js"></script>
  <script src="assets/presence.js"></script>
  <script src="assets/theme.js"></script>
  <script>
    const hamburgerNav = document.getElementById('hamburgerNav');
    const hamburgerToggle = document.getElementById('hamburgerToggle');
    const appMain = document.getElementById('appMain');
    hamburgerToggle.addEventListener('click', () => {
      hamburgerNav.classList.toggle('collapsed');
      appMain.classList.toggle('expanded');
    });

    document.getElementById('logoutBtn').addEventListener('click', async () => {
      await apiRequest('/auth/logout', { method: 'POST' });
      window.location.href = 'login.html';
    });

    let currentRange = 'week';

    async function init() {
      try {
        const result = await apiRequest('/dashboard-check');
        document.getElementById('userName').textContent = result.staff.fullName;
        document.getElementById('roleBadge').textContent = result.staff.role;
        loadProductList();
      } catch (err) {
        window.location.href = 'login.html';
      }
    }

    async function loadProductList() {
      const select = document.getElementById('productSelect');
      try {
        const result = await apiRequest('/prices');
        select.innerHTML = '<option value="">Select a product…</option>' +
          result.prices.map(p => `<option value="${p.id}">${p.product_name}</option>`).join('');
      } catch (err) {
        select.innerHTML = '<option value="">Could not load products</option>';
      }
    }

    document.getElementById('productSelect').addEventListener('change', loadHistory);

    document.getElementById('rangeWeek').addEventListener('click', () => setRange('week'));
    document.getElementById('rangeMonth').addEventListener('click', () => setRange('month'));

    function setRange(range) {
      currentRange = range;
      document.getElementById('rangeWeek').classList.toggle('active', range === 'week');
      document.getElementById('rangeMonth').classList.toggle('active', range === 'month');
      loadHistory();
    }

    async function loadHistory() {
      const productId = document.getElementById('productSelect').value;
      const tbody = document.getElementById('historyTableBody');

      if (!productId) {
        tbody.innerHTML = '<tr><td colspan="3" class="pending-loading">Select a product to view its price history.</td></tr>';
        return;
      }

      tbody.innerHTML = '<tr><td colspan="3" class="pending-loading">Loading…</td></tr>';

      try {
        const result = await apiRequest(`/prices/${productId}/history?range=${currentRange}`);
        if (result.history.length === 0) {
          tbody.innerHTML = `<tr><td colspan="3" class="pending-loading">No price changes in the last ${currentRange}.</td></tr>`;
          return;
        }
        tbody.innerHTML = result.history.map(h => `
          <tr>
            <td class="mono">₦${Number(h.cost_price).toLocaleString()}</td>
            <td class="mono">${h.margin_percent ? h.margin_percent + '%' : '—'}</td>
            <td class="mono">${new Date(h.recorded_at).toLocaleString()}</td>
          </tr>
        `).join('');
      } catch (err) {
        tbody.innerHTML = `<tr><td colspan="3" class="pending-loading">Could not load history.</td></tr>`;
      }
    }

    init();
    loadUnreadBadge();
  </script>
</body>
</html>

EOF_ACCOUNTING_PRICES-HISTORY_HTML

echo "Chat interface with live presence installed."
echo "Push to deploy: bash save-progress.sh \"Rebuild messaging as chat with online presence\""