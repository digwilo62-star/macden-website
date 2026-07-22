#!/usr/bin/env bash
# Fixes emoji icons -> proper consistent line-icon set (Tabler Icons),
# matching the clean mockup style instead of OS-dependent emoji.
# Run this from the ROOT of your macden-website repo, in Git Bash.
set -e

mkdir -p accounting/assets

cat > accounting/assets/portal-style.css << 'EOF_ACCOUNTING_ASSETS_PORTAL-STYLE_CSS'
/* ============================================================
   MACDEN Portal — Design Tokens
   Matches the confirmed mockup direction: deep green primary,
   gold accent, Montserrat headings + Inter body.
   Desktop-first, company-wide (not accounting-only).
   ============================================================ */

@import url('https://fonts.googleapis.com/css2?family=Montserrat:wght@600;700;800&family=Inter:wght@400;500;600;700&display=swap');
@import url('https://cdn.jsdelivr.net/npm/@tabler/icons-webfont@2.44.0/tabler-icons.min.css');

:root {
  --primary: #0d5c2f;
  --primary-light: #1e7a3e;
  --primary-dim: rgba(13, 92, 47, 0.08);
  --gold: #f2c94c;
  --gold-dim: rgba(242, 201, 76, 0.15);

  --bg: #f7f8fa;
  --surface: #ffffff;
  --surface-raised: #f2f3f5;
  --border: #e5e7eb;
  --border-hover: #d1d5db;

  --text-primary: #2b2d31;
  --text-secondary: #6b7280;
  --text-muted: #9ca3af;

  --success: #1e7a3e;
  --success-dim: rgba(30, 122, 62, 0.1);
  --warning: #f2c94c;
  --warning-dim: rgba(242, 201, 76, 0.15);
  --error: #dc2626;
  --error-dim: rgba(220, 38, 38, 0.08);

  --radius-sm: 8px;
  --radius-md: 12px;
  --radius-lg: 16px;

  --font-heading: 'Montserrat', -apple-system, sans-serif;
  --font-body: 'Inter', -apple-system, sans-serif;
}

* { box-sizing: border-box; }

body {
  margin: 0;
  background: var(--bg);
  color: var(--text-primary);
  font-family: var(--font-body);
  font-size: 14px;
  line-height: 1.5;
  min-width: 1024px; /* desktop-first */
}

h1, h2, h3 { font-family: var(--font-heading); font-weight: 700; margin: 0; }

/* ---------- Split-panel login shell ---------- */

.login-shell {
  min-height: 100vh;
  display: flex;
}

.login-brand-panel {
  width: 42%;
  background: var(--primary);
  background-image:
    radial-gradient(circle at 15% 85%, rgba(255,255,255,0.06), transparent 45%),
    radial-gradient(circle at 85% 15%, rgba(242,201,76,0.10), transparent 40%);
  color: #ffffff;
  display: flex;
  flex-direction: column;
  justify-content: center;
  padding: 60px 56px;
  position: relative;
  overflow: hidden;
}

.login-brand-panel::after {
  content: '';
  position: absolute;
  inset: 0;
  background: linear-gradient(180deg, rgba(0,0,0,0) 60%, rgba(0,0,0,0.25) 100%);
  pointer-events: none;
}

.login-brand-logo {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 48px;
}

.login-brand-logo img {
  width: 44px;
  height: 44px;
  border-radius: 10px;
  object-fit: cover;
  background: #fff;
}

.login-brand-logo span {
  font-family: var(--font-heading);
  font-weight: 800;
  font-size: 18px;
  letter-spacing: 0.02em;
}

.login-brand-logo small {
  display: block;
  font-family: var(--font-body);
  font-weight: 500;
  font-size: 10.5px;
  letter-spacing: 0.08em;
  opacity: 0.75;
  margin-top: 1px;
}

.login-tagline {
  font-size: 32px;
  font-weight: 800;
  line-height: 1.25;
  max-width: 340px;
  position: relative;
  z-index: 1;
}

.login-tagline .gold { color: var(--gold); }

/* ---------- Right side form panel ---------- */

.login-form-panel {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--surface);
  padding: 40px;
}

.login-form-inner { width: 100%; max-width: 380px; }

.login-form-inner h1 {
  font-size: 26px;
  margin-bottom: 6px;
}

.login-form-subtitle {
  color: var(--text-secondary);
  font-size: 13.5px;
  margin-bottom: 32px;
}

.field { margin-bottom: 18px; }

.field label {
  display: block;
  font-size: 12.5px;
  font-weight: 600;
  color: var(--text-primary);
  margin-bottom: 7px;
}

.field input {
  width: 100%;
  background: var(--surface);
  border: 1.5px solid var(--border);
  border-radius: var(--radius-sm);
  padding: 11px 14px;
  color: var(--text-primary);
  font-size: 13.5px;
  font-family: var(--font-body);
  transition: border-color 0.15s ease;
}

.field input:focus {
  outline: none;
  border-color: var(--primary);
}

.field input::placeholder { color: var(--text-muted); }

.login-row-between {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 24px;
  font-size: 12.5px;
}

.login-row-between label {
  display: flex;
  align-items: center;
  gap: 6px;
  color: var(--text-secondary);
  cursor: pointer;
}

.login-row-between a {
  color: var(--primary);
  text-decoration: none;
  font-weight: 600;
}

.btn {
  width: 100%;
  padding: 12px 16px;
  border-radius: var(--radius-sm);
  border: none;
  font-size: 14px;
  font-weight: 700;
  font-family: var(--font-body);
  cursor: pointer;
  transition: background 0.15s ease, opacity 0.15s ease;
}

.btn-primary { background: var(--primary); color: #ffffff; }
.btn-primary:hover { background: var(--primary-light); }
.btn-primary:disabled { opacity: 0.55; cursor: not-allowed; }

.login-footer-link {
  text-align: center;
  margin-top: 24px;
  font-size: 12.5px;
  color: var(--text-muted);
}

.login-footer-link a { color: var(--primary); text-decoration: none; font-weight: 600; }

/* ---------- Alerts ---------- */

.alert {
  padding: 11px 14px;
  border-radius: var(--radius-sm);
  font-size: 12.5px;
  margin-bottom: 18px;
  display: none;
}

.alert-error { background: var(--error-dim); color: var(--error); border: 1px solid rgba(220,38,38,0.2); }
.alert-success { background: var(--success-dim); color: var(--success); border: 1px solid rgba(30,122,62,0.2); }
.alert.visible { display: block; }

EOF_ACCOUNTING_ASSETS_PORTAL-STYLE_CSS

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

EOF_ACCOUNTING_ASSETS_PORTAL-SHELL_CSS

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
        <a href="#" class="sidebar-link"><i class="ti ti-pencil"></i> Compose</a>
        <a href="#" class="sidebar-link"><i class="ti ti-speakerphone"></i> Broadcasts</a>
        <a href="#" class="sidebar-link"><i class="ti ti-users"></i> Directory</a>
        <a href="#" class="sidebar-link"><i class="ti ti-calendar-event"></i> Leave &amp; Requests</a>
        <a href="#" class="sidebar-link"><i class="ti ti-file-text"></i> Documents</a>
        <a href="#" class="sidebar-link"><i class="ti ti-book"></i> Policies</a>
        <a href="#" class="sidebar-link"><i class="ti ti-settings"></i> Settings</a>
      </nav>
      <div class="sidebar-logout">
        <button id="logoutBtn"><i class="ti ti-logout"></i> Logout</button>
      </div>
    </div>

    <div class="main-content">
      <div class="topbar">
        <div class="topbar-search"><input type="text" placeholder="Search messages, people, documents…"></div>
        <button class="topbar-bell"><i class="ti ti-bell"></i><span class="dot" id="notifDot" style="display:none;">0</span></button>
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
            <a href="#" class="quick-action" style="opacity:0.5; cursor:not-allowed;"><i class="ti ti-calendar-event"></i> Request Leave (coming soon)</a>
            <a href="#" class="quick-action" style="opacity:0.5; cursor:not-allowed;"><i class="ti ti-users"></i> Staff Directory (coming soon)</a>
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

echo "Icons fixed. Reload the page after restarting the server."