#!/usr/bin/env bash
# Adds a light/dark theme toggle to the accounting tool. Light mode is now the default.
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

cat > accounting/assets/theme.js << 'EOF_ACCOUNTING_ASSETS_THEME_JS'
// Default is light mode. Dark mode only activates if the person explicitly
// chose it before — checked via the inline anti-flicker script in <head>,
// this file just wires up the actual toggle button click.
function initThemeToggle() {
  const toggleBtn = document.getElementById('themeToggle');
  if (!toggleBtn) return;

  toggleBtn.addEventListener('click', () => {
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
    if (isDark) {
      document.documentElement.removeAttribute('data-theme');
      localStorage.setItem('accounting-theme', 'light');
    } else {
      document.documentElement.setAttribute('data-theme', 'dark');
      localStorage.setItem('accounting-theme', 'dark');
    }
  });
}

document.addEventListener('DOMContentLoaded', initThemeToggle);

EOF_ACCOUNTING_ASSETS_THEME_JS

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

cat > accounting/inbox.html << 'EOF_ACCOUNTING_INBOX_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <script>if(localStorage.getItem("accounting-theme")==="dark"){document.documentElement.setAttribute("data-theme","dark")}</script>
  <meta charset="UTF-8">
  <title>Inbox — MACDEN Accounting</title>
  <link rel="stylesheet" href="assets/style.css">
  <style>
    .toolbar { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; }
    .compose-btn { width: auto; padding: 9px 18px; }

    .conv-list { display: flex; flex-direction: column; gap: 1px; background: var(--border); border: 1px solid var(--border); border-radius: var(--radius-md); overflow: hidden; }
    .conv-row { background: var(--surface); padding: 16px 20px; cursor: pointer; display: flex; justify-content: space-between; align-items: flex-start; }
    .conv-row:hover { background: var(--surface-raised); }
    .conv-row.unread .conv-subject { font-weight: 700; }
    .conv-row.unread::before { content: ''; width: 6px; height: 6px; border-radius: 50%; background: var(--accent-green); display: inline-block; margin-right: 10px; flex-shrink: 0; margin-top: 6px; }
    .conv-main { display: flex; flex: 1; min-width: 0; }
    .conv-text { min-width: 0; }
    .conv-subject { font-size: 13.5px; color: var(--text-primary); margin: 0 0 3px; }
    .conv-preview { font-size: 12.5px; color: var(--text-secondary); margin: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .conv-time { font-size: 11.5px; color: var(--text-muted); font-family: var(--font-mono); white-space: nowrap; margin-left: 16px; }

    .empty-inbox { padding: 40px 20px; text-align: center; color: var(--text-muted); font-size: 13px; }

    /* Thread view */
    .thread-header { display: flex; align-items: center; gap: 12px; margin-bottom: 20px; }
    .back-link { color: var(--accent-green); text-decoration: none; font-size: 13px; }

    .email-card { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-md); padding: 20px 24px; margin-bottom: 12px; }
    .email-meta { display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 12px; padding-bottom: 12px; border-bottom: 1px solid var(--border); }
    .email-sender { font-size: 13.5px; font-weight: 600; color: var(--text-primary); }
    .email-time { font-size: 11.5px; color: var(--text-muted); font-family: var(--font-mono); }
    .email-body { font-size: 13.5px; color: var(--text-primary); white-space: pre-wrap; line-height: 1.6; }

    .reply-box { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-md); padding: 16px; margin-top: 8px; }
    .reply-box textarea { width: 100%; min-height: 90px; background: var(--bg); border: 1px solid var(--border); border-radius: var(--radius-sm); padding: 10px 12px; color: var(--text-primary); font-size: 13.5px; font-family: var(--font-ui); resize: vertical; }
    .reply-actions { display: flex; gap: 8px; margin-top: 10px; justify-content: flex-end; }
    .reply-actions .btn { width: auto; padding: 8px 16px; }
  </style>
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
        <a href="drafts.html" class="inbox-link">
          <span>Drafts</span>
        </a>
      </div>
    </div>

    <div class="app-main" id="appMain">

      <!-- LIST VIEW -->
      <div id="listView">
        <div class="toolbar">
          <div>
            <h1 class="page-title">Inbox</h1>
            <p class="page-subtitle">Messages between accounting staff.</p>
          </div>
          <button class="btn btn-primary compose-btn" onclick="window.location.href='compose.html'">+ Compose</button>
        </div>
        <div class="conv-list" id="convList">
          <div class="empty-inbox">Loading…</div>
        </div>
      </div>

      <!-- THREAD VIEW -->
      <div id="threadView" style="display: none;">
        <div class="thread-header">
          <a href="inbox.html" class="back-link">← Back to inbox</a>
        </div>
        <h1 class="page-title" id="threadSubject">—</h1>
        <p class="page-subtitle">&nbsp;</p>
        <div id="messagesContainer"></div>

        <div class="reply-box">
          <div id="replyAlert" class="alert alert-error"></div>
          <textarea id="replyBody" placeholder="Write a reply…"></textarea>
          <div class="reply-actions">
            <button class="btn btn-ghost" id="saveDraftBtn">Save as draft</button>
            <button class="btn btn-primary" id="sendReplyBtn">Send</button>
          </div>
        </div>
      </div>

    </div>
  </div>

  <script src="assets/api.js"></script>
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
    const params = new URLSearchParams(window.location.search);
    const openConversationId = params.get('id');

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
      const list = document.getElementById('convList');
      try {
        const result = await apiRequest('/messages/conversations');
        if (result.conversations.length === 0) {
          list.innerHTML = '<div class="empty-inbox">No messages yet. Start a conversation with Compose.</div>';
          return;
        }
        list.innerHTML = result.conversations.map(c => `
          <div class="conv-row ${c.isUnread ? 'unread' : ''}" onclick="window.location.href='inbox.html?id=${c.id}'">
            <div class="conv-main">
              <div class="conv-text">
                <p class="conv-subject">${c.subject}</p>
                <p class="conv-preview">${c.lastMessagePreview || '(no messages)'}</p>
              </div>
            </div>
            <span class="conv-time">${c.lastMessageAt ? new Date(c.lastMessageAt).toLocaleDateString() : ''}</span>
          </div>
        `).join('');
      } catch (err) {
        list.innerHTML = '<div class="empty-inbox">Could not load inbox.</div>';
      }
    }

    async function openThread(id) {
      document.getElementById('listView').style.display = 'none';
      document.getElementById('threadView').style.display = 'block';

      try {
        const result = await apiRequest(`/messages/conversations/${id}`);
        document.getElementById('threadSubject').textContent = result.conversation.subject;

        const container = document.getElementById('messagesContainer');
        container.innerHTML = result.messages.map(m => `
          <div class="email-card">
            <div class="email-meta">
              <span class="email-sender">${m.sender_id === currentStaffId ? 'You' : 'Staff member'}${m.status === 'draft' ? ' (draft)' : ''}</span>
              <span class="email-time">${m.sent_at ? new Date(m.sent_at).toLocaleString() : 'not sent'}</span>
            </div>
            <div class="email-body">${m.body}</div>
          </div>
        `).join('');

        document.getElementById('sendReplyBtn').onclick = () => submitReply(id, 'sent');
        document.getElementById('saveDraftBtn').onclick = () => submitReply(id, 'draft');

        loadUnreadBadge(); // opening the thread just marked messages read server-side
      } catch (err) {
        document.getElementById('messagesContainer').innerHTML = `<div class="empty-inbox">${err.message}</div>`;
      }
    }

    async function submitReply(conversationId, status) {
      const alertEl = document.getElementById('replyAlert');
      const body = document.getElementById('replyBody').value.trim();
      hideAlert(alertEl);

      if (!body) {
        showAlert(alertEl, 'Write something before sending.');
        return;
      }

      try {
        await apiRequest(`/messages/conversations/${conversationId}/reply`, {
          method: 'POST',
          body: { body, status }
        });
        if (status === 'sent') {
          openThread(conversationId); // refresh thread to show the new message
          document.getElementById('replyBody').value = '';
        } else {
          window.location.href = 'drafts.html';
        }
      } catch (err) {
        showAlert(alertEl, err.message);
      }
    }

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
          <label>Subject</label>
          <input type="text" id="subject" placeholder="What's this about?">
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
            <div class="search-result-item" onclick='selectRecipient(${JSON.stringify(s)})'>${s.full_name} · ${s.username}</div>
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
            subject,
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
      <h1 class="page-title">Drafts</h1>
      <p class="page-subtitle"><a href="inbox.html" style="color: var(--accent-green);">← Back to inbox</a></p>

      <div class="conv-list" id="draftList">
        <div class="empty-inbox">Loading…</div>
      </div>
    </div>
  </div>

  <script src="assets/api.js"></script>
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
              <p class="conv-subject">${d.subject}</p>
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

echo "Light/dark toggle added. Light mode is now default."
echo "Push to deploy: bash save-progress.sh \"Add light/dark mode toggle\""