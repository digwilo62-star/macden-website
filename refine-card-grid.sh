#!/usr/bin/env bash
# Refines the dashboard card grid: bigger rounded icon tiles, more breathing
# room, and explicit buttons instead of whole-card links.
# Run this from the ROOT of your macden-website repo, in Git Bash.
set -e

mkdir -p accounting/assets

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

EOF_ACCOUNTING_ASSETS_STYLE_CSS

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
      <div class="topbar-brand">
        <img src="assets/logo.jpeg" alt="MACDEN">
        <span>MACDEN Accounting</span>
      </div>
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

echo "Card grid refined."
echo "Push to deploy: bash save-progress.sh \"Refine dashboard card grid styling\""