#!/usr/bin/env bash
# Adds the accounting frontend pages + updates server.js to serve them.
# Run this from the ROOT of your macden-website repo, in Git Bash.
set -e

mkdir -p accounting/assets

cat > accounting/login.html << 'EOF_ACCOUNTING_LOGIN_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Log in — MACDEN Accounting</title>
  <link rel="stylesheet" href="assets/style.css">
</head>
<body>
  <div class="auth-shell">
    <div class="auth-card">
      <div class="auth-logo-row">
        <img src="assets/logo.jpeg" alt="MACDEN">
        <span>MACDEN ACCOUNTING</span>
      </div>

      <h1 class="auth-title">Log in</h1>
      <p class="auth-subtitle">Internal access for the accounting department.</p>

      <div id="alert" class="alert alert-error"></div>

      <form id="loginForm">
        <div class="field">
          <label for="username">Username</label>
          <input type="text" id="username" name="username" placeholder="e.g. daniel.accounts" required>
        </div>
        <div class="field">
          <label for="password">Password</label>
          <input type="password" id="password" name="password" placeholder="••••••••" required>
        </div>
        <button type="submit" class="btn btn-primary" id="submitBtn">Log in</button>
      </form>

      <div class="auth-footer-link">
        Don't have an account? <a href="register.html">Sign up</a>
      </div>
    </div>
  </div>

  <script src="assets/api.js"></script>
  <script>
    const form = document.getElementById('loginForm');
    const alertEl = document.getElementById('alert');
    const submitBtn = document.getElementById('submitBtn');

    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      hideAlert(alertEl);
      submitBtn.disabled = true;
      submitBtn.textContent = 'Logging in…';

      try {
        await apiRequest('/auth/login', {
          method: 'POST',
          body: {
            username: document.getElementById('username').value.trim(),
            password: document.getElementById('password').value
          }
        });
        window.location.href = 'dashboard.html';
      } catch (err) {
        showAlert(alertEl, err.message);
        submitBtn.disabled = false;
        submitBtn.textContent = 'Log in';
      }
    });
  </script>
</body>
</html>

EOF_ACCOUNTING_LOGIN_HTML

cat > accounting/register.html << 'EOF_ACCOUNTING_REGISTER_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Sign up — MACDEN Accounting</title>
  <link rel="stylesheet" href="assets/style.css">
</head>
<body>
  <div class="auth-shell">
    <div class="auth-card">
      <div class="auth-logo-row">
        <img src="assets/logo.jpeg" alt="MACDEN">
        <span>MACDEN ACCOUNTING</span>
      </div>

      <!-- Step 1: registration form -->
      <div id="registerStep">
        <h1 class="auth-title">Create account</h1>
        <p class="auth-subtitle">For accounting department staff only.</p>

        <div id="registerAlert" class="alert alert-error"></div>

        <form id="registerForm">
          <div class="field">
            <label for="fullName">Full name</label>
            <input type="text" id="fullName" placeholder="e.g. Amara Okoye" required>
          </div>
          <div class="field">
            <label for="username">Username</label>
            <input type="text" id="username" placeholder="e.g. amara.accounts" required>
          </div>
          <div class="field">
            <label for="email">Email</label>
            <input type="email" id="email" placeholder="you@macden.com.ng" required>
          </div>
          <div class="field">
            <label for="password">Password</label>
            <input type="password" id="password" placeholder="At least 8 characters" required minlength="8">
          </div>
          <button type="submit" class="btn btn-primary" id="registerBtn">Create account</button>
        </form>
      </div>

      <!-- Step 2: verify code (hidden until registration succeeds) -->
      <div id="verifyStep" style="display: none;">
        <h1 class="auth-title">Check your email</h1>
        <p class="auth-subtitle">Enter the 6-digit code we just sent you.</p>

        <div id="verifyAlert" class="alert alert-error"></div>
        <div id="verifySuccess" class="alert alert-success"></div>

        <form id="verifyForm">
          <div class="field">
            <label for="code">Verification code</label>
            <input type="text" id="code" class="code-input" maxlength="6" placeholder="000000" required>
          </div>
          <button type="submit" class="btn btn-primary" id="verifyBtn">Verify</button>
        </form>
      </div>

      <div class="auth-footer-link">
        Already have an account? <a href="login.html">Log in</a>
      </div>
    </div>
  </div>

  <script src="assets/api.js"></script>
  <script>
    const registerStep = document.getElementById('registerStep');
    const verifyStep = document.getElementById('verifyStep');
    const registerForm = document.getElementById('registerForm');
    const verifyForm = document.getElementById('verifyForm');
    const registerAlert = document.getElementById('registerAlert');
    const verifyAlert = document.getElementById('verifyAlert');
    const verifySuccess = document.getElementById('verifySuccess');
    const registerBtn = document.getElementById('registerBtn');
    const verifyBtn = document.getElementById('verifyBtn');

    let pendingEmail = '';

    registerForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      hideAlert(registerAlert);
      registerBtn.disabled = true;
      registerBtn.textContent = 'Creating account…';

      const email = document.getElementById('email').value.trim();

      try {
        await apiRequest('/auth/register', {
          method: 'POST',
          body: {
            fullName: document.getElementById('fullName').value.trim(),
            username: document.getElementById('username').value.trim(),
            email: email,
            password: document.getElementById('password').value
          }
        });

        pendingEmail = email;
        registerStep.style.display = 'none';
        verifyStep.style.display = 'block';
      } catch (err) {
        showAlert(registerAlert, err.message);
        registerBtn.disabled = false;
        registerBtn.textContent = 'Create account';
      }
    });

    verifyForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      hideAlert(verifyAlert);
      verifyBtn.disabled = true;
      verifyBtn.textContent = 'Verifying…';

      try {
        const result = await apiRequest('/auth/verify-email', {
          method: 'POST',
          body: {
            email: pendingEmail,
            code: document.getElementById('code').value.trim()
          }
        });

        showAlert(verifySuccess, result.message, 'success');
        verifyForm.style.display = 'none';
      } catch (err) {
        showAlert(verifyAlert, err.message);
        verifyBtn.disabled = false;
        verifyBtn.textContent = 'Verify';
      }
    });
  </script>
</body>
</html>

EOF_ACCOUNTING_REGISTER_HTML

cat > accounting/dashboard.html << 'EOF_ACCOUNTING_DASHBOARD_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Dashboard — MACDEN Accounting</title>
  <link rel="stylesheet" href="assets/style.css">
</head>
<body>
  <div class="app-shell">

    <div class="app-topbar">
      <div class="topbar-brand">
        <img src="assets/logo.jpeg" alt="MACDEN">
        <span>MACDEN Accounting</span>
      </div>
      <div class="topbar-user">
        <span class="role-badge" id="roleBadge">—</span>
        <span class="user-name" id="userName">Loading…</span>
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
      </div>
    </div>

    <div class="app-main" id="appMain">
      <h1 class="page-title" id="welcomeTitle">Welcome</h1>
      <p class="page-subtitle">Accounting department — internal tools.</p>

      <div class="card-grid">
        <a href="prices.html" class="dash-card">
          <div class="dash-card-icon">₦</div>
          <h3>Price check</h3>
          <p>Look up current product pricing.</p>
        </a>
        <a href="prices-history.html" class="dash-card">
          <div class="dash-card-icon">↺</div>
          <h3>Price history</h3>
          <p>View prices from last week or last month.</p>
        </a>
        <a href="inbox.html" class="dash-card">
          <div class="dash-card-icon">✉</div>
          <h3>Messages</h3>
          <p>Message other accounting staff.</p>
        </a>
      </div>

      <div id="adminSection" style="display: none; margin-top: 32px;">
        <h2 class="page-title" style="font-size: 16px;">Pending approvals</h2>
        <p class="page-subtitle">New staff accounts waiting for activation.</p>
        <div id="pendingList" class="pending-loading">Loading…</div>
      </div>
    </div>

  </div>

  <script src="assets/api.js"></script>
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
  </script>
</body>
</html>

EOF_ACCOUNTING_DASHBOARD_HTML

cat > accounting/assets/style.css << 'EOF_ACCOUNTING_ASSETS_STYLE_CSS'
/* ============================================================
   MACDEN Accounting — Design Tokens
   Dark, near-black surface (Supabase-style) with a Supabase-green
   primary accent and a warm terracotta secondary accent (Claude-style).
   Desktop-only, corporate-internal tool.
   ============================================================ */

:root {
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

  --radius-sm: 6px;
  --radius-md: 10px;
  --radius-lg: 14px;

  --font-ui: -apple-system, "Inter", "Segoe UI", Helvetica, Arial, sans-serif;
  --font-mono: "SF Mono", "JetBrains Mono", Consolas, monospace;
}

* { box-sizing: border-box; }

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
  gap: 16px;
}

.dash-card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  padding: 20px;
  text-decoration: none;
  display: block;
  transition: border-color 0.15s ease;
}

.dash-card:hover { border-color: var(--border-hover); }

.dash-card .dash-card-icon {
  width: 32px;
  height: 32px;
  border-radius: var(--radius-sm);
  background: var(--accent-green-dim);
  color: var(--accent-green);
  display: flex;
  align-items: center;
  justify-content: center;
  margin-bottom: 12px;
}

.dash-card h3 {
  font-size: 14px;
  font-weight: 600;
  margin: 0 0 4px;
  color: var(--text-primary);
}

.dash-card p {
  font-size: 12.5px;
  color: var(--text-secondary);
  margin: 0;
}

.pending-loading {
  color: var(--text-muted);
  font-size: 13px;
}

EOF_ACCOUNTING_ASSETS_STYLE_CSS

cat > accounting/assets/api.js << 'EOF_ACCOUNTING_ASSETS_API_JS'
// Shared fetch helper — always sends cookies, always parses JSON,
// throws a readable error message so pages can show it directly.
async function apiRequest(path, options = {}) {
  const res = await fetch(`/api/accounting${path}`, {
    method: options.method || 'GET',
    headers: { 'Content-Type': 'application/json' },
    credentials: 'include',
    body: options.body ? JSON.stringify(options.body) : undefined
  });

  const data = await res.json();

  if (!res.ok) {
    throw new Error(data.error || 'Something went wrong.');
  }

  return data;
}

function showAlert(el, message, type = 'error') {
  el.textContent = message;
  el.className = `alert alert-${type} visible`;
}

function hideAlert(el) {
  el.className = 'alert';
}

EOF_ACCOUNTING_ASSETS_API_JS

cat > server/server.js << 'EOF_SERVER_SERVER_JS'
require('dotenv').config();

const path = require('path');
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

// Serve the accounting frontend pages (login, register, dashboard, etc.)
// Lives in a sibling folder: macden-website/accounting
app.use('/accounting', express.static(path.join(__dirname, '../accounting')));

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

echo "Frontend pages created and server.js updated."

# Copy the existing logo from your images folder into the accounting assets folder
if [ -f "images/logo.jpeg" ]; then
  cp images/logo.jpeg accounting/assets/logo.jpeg
  echo "Logo copied into accounting/assets/logo.jpeg"
else
  echo "WARNING: images/logo.jpeg not found — copy your logo into accounting/assets/logo.jpeg manually."
fi