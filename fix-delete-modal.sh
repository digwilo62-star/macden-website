#!/usr/bin/env bash
# Replaces the native browser confirm() popup with a proper styled modal
# card, and surfaces real error messages if delete genuinely fails instead
# of failing silently.
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

/* ---------- Two-panel chat shell ---------- */

.chat-shell {
  display: flex;
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  overflow: hidden;
  height: calc(100vh - 220px);
  min-height: 420px;
}

.chat-sidebar {
  width: 300px;
  flex-shrink: 0;
  border-right: 1px solid var(--border);
  display: flex;
  flex-direction: column;
  background: var(--surface);
}

.chat-sidebar-search {
  padding: 14px;
  border-bottom: 1px solid var(--border);
}

.chat-sidebar-search input {
  width: 100%;
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  padding: 8px 12px;
  font-size: 13px;
  color: var(--text-primary);
  font-family: var(--font-ui);
}

.chat-sidebar-list { flex: 1; overflow-y: auto; }

.chat-sidebar-row {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 12px 14px;
  cursor: pointer;
  border-bottom: 1px solid var(--border);
}

.chat-sidebar-row:hover, .chat-sidebar-row.active { background: var(--surface-raised); }
.chat-sidebar-row.unread .chat-row-name { font-weight: 700; }

.chat-panel {
  flex: 1;
  display: flex;
  flex-direction: column;
  background: var(--bg);
  min-width: 0;
}

.chat-panel-header {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 14px 18px;
  border-bottom: 1px solid var(--border);
  background: var(--surface);
}

.chat-panel-messages {
  flex: 1;
  overflow-y: auto;
  padding: 18px;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.chat-panel-composer {
  padding: 14px 18px;
  border-top: 1px solid var(--border);
  background: var(--surface);
  display: flex;
  gap: 8px;
  align-items: flex-end;
}

.chat-panel-composer textarea {
  flex: 1;
  min-height: 40px;
  max-height: 120px;
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 20px;
  padding: 10px 16px;
  color: var(--text-primary);
  font-size: 13.5px;
  font-family: var(--font-ui);
  resize: none;
}

.chat-panel-composer textarea:focus {
  outline: none;
  border-color: var(--accent-green);
}

.chat-empty-state {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-muted);
  font-size: 13px;
}

/* ---------- Shared modal (confirmations, forms) ---------- */

.modal-backdrop {
  display: none;
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.45);
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

.modal h3 { margin: 0 0 8px; font-size: 15px; color: var(--text-primary); }
.modal p { margin: 0 0 4px; font-size: 13px; color: var(--text-secondary); line-height: 1.5; }

.modal-actions {
  display: flex;
  gap: 8px;
  margin-top: 20px;
  justify-content: flex-end;
}

.modal-actions .btn { width: auto; padding: 8px 16px; }

EOF_ACCOUNTING_ASSETS_STYLE_CSS

cat > accounting/inbox.html << 'EOF_ACCOUNTING_INBOX_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <script>if(localStorage.getItem("accounting-theme")==="dark"){document.documentElement.setAttribute("data-theme","dark")}</script>
  <meta charset="UTF-8">
  <title>Inbox — MACDEN Accounting</title>
  <link rel="stylesheet" href="assets/style.css">
  <style>
    .search-results { position: absolute; top: 100%; left: 0; right: 0; background: var(--surface-raised); border: 1px solid var(--border); border-radius: var(--radius-sm); margin-top: 4px; max-height: 240px; overflow-y: auto; z-index: 5; display: none; }
    .search-result-item { padding: 10px 12px; cursor: pointer; font-size: 13px; display: flex; align-items: center; gap: 8px; }
    .search-result-item:hover { background: var(--surface); }
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
              </div>
    </div>

    <div class="app-main" id="appMain">
      <h1 class="page-title">Inbox</h1>
      <p class="page-subtitle"><a href="dashboard.html" style="color: var(--accent-green);">← Back to dashboard</a></p>

      <div class="chat-shell">
        <div class="chat-sidebar">
          <div class="chat-sidebar-search" style="position: relative;">
            <input type="text" id="userSearch" placeholder="Search by name or username…">
            <div class="search-results" id="userSearchResults"></div>
          </div>
          <div class="chat-sidebar-list" id="chatList">
            <div style="padding: 40px 16px; text-align: center; color: var(--text-muted); font-size: 13px;">Loading…</div>
          </div>
        </div>

        <div class="chat-panel">
          <div id="emptyState" class="chat-empty-state">Select a chat to get started</div>

          <div id="activeChat" style="display: none; flex-direction: column; flex: 1;">
            <div class="chat-panel-header">
              <div class="chat-avatar" id="threadAvatar" style="position: relative;">
                <span id="threadInitials">—</span>
                <span class="presence-dot" id="threadDot"></span>
              </div>
              <div>
                <p class="chat-header-name" id="threadName">—</p>
                <p class="chat-header-status" id="threadStatus">—</p>
              </div>
            </div>

            <div class="chat-panel-messages" id="messagesContainer"></div>

            <div class="chat-panel-composer">
              <textarea id="replyBody" placeholder="Type a message…" rows="1"></textarea>
              <button class="chat-send-btn" id="sendReplyBtn" aria-label="Send">→</button>
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
    let isAdmin = false;
    let currentConversationId = null;
    let conversationsCache = [];
    const params = new URLSearchParams(window.location.search);
    const initialConversationId = params.get('id');

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
        isAdmin = result.staff.role === 'admin';
      } catch (err) {
        window.location.href = 'login.html';
        return;
      }

      await loadSidebar();

      if (initialConversationId) {
        selectChat(initialConversationId);
      }
    }

    async function loadSidebar() {
      const list = document.getElementById('chatList');
      try {
        const result = await apiRequest('/messages/conversations');
        conversationsCache = result.conversations;

        if (result.conversations.length === 0) {
          list.innerHTML = '<div style="padding: 40px 16px; text-align: center; color: var(--text-muted); font-size: 13px;">No chats yet. Search above to start one.</div>';
          return;
        }

        list.innerHTML = result.conversations.map(c => {
          const p = c.participants[0];
          const online = p && p.isOnline;
          const active = c.id === currentConversationId ? 'active' : '';
          const unread = c.isUnread ? 'unread' : '';
          const deleteBtn = '<button onclick="event.stopPropagation(); deleteConversation(\'' + c.id + '\', \'' + c.displayName.replace(/'/g, "\\'") + '\')" aria-label="Delete conversation" style="background:none;border:none;color:var(--text-muted);cursor:pointer;font-size:14px;padding:4px;flex-shrink:0;">🗑</button>';
          return '<div class="chat-sidebar-row ' + active + ' ' + unread + '" data-id="' + c.id + '" onclick="selectChat(\'' + c.id + '\')">' +
            '<div class="chat-avatar">' + initials(c.displayName) + '<span class="presence-dot ' + (online ? 'online' : '') + '"></span></div>' +
            '<div class="chat-row-text"><p class="chat-row-name">' + c.displayName + '</p><p class="chat-row-preview">' + (c.lastMessagePreview || 'No messages yet') + '</p></div>' +
            deleteBtn +
            '</div>';
        }).join('');
      } catch (err) {
        list.innerHTML = '<div style="padding: 40px 16px; text-align: center; color: var(--text-muted); font-size: 13px;">Could not load chats.</div>';
      }
    }

    async function selectChat(id) {
      currentConversationId = id;
      history.replaceState(null, '', 'inbox.html?id=' + id);

      document.querySelectorAll('.chat-sidebar-row').forEach(row => {
        row.classList.toggle('active', row.dataset.id === id);
      });

      document.getElementById('emptyState').style.display = 'none';
      document.getElementById('activeChat').style.display = 'flex';

      try {
        const result = await apiRequest('/messages/conversations/' + id);
        const participant = result.participants[0];

        document.getElementById('threadInitials').textContent = initials(participant ? participant.fullName : '?');
        document.getElementById('threadName').textContent = participant ? participant.fullName : 'Conversation';
        document.getElementById('threadStatus').textContent = participant && participant.isOnline ? 'Online' : 'Offline';
        document.getElementById('threadDot').className = 'presence-dot' + (participant && participant.isOnline ? ' online' : '');

        const container = document.getElementById('messagesContainer');
        container.innerHTML = result.messages.map(m => {
          const sent = m.sender_id === currentStaffId;
          return '<div class="bubble-row ' + (sent ? 'sent' : 'received') + '">' +
            '<div class="bubble">' + m.body + (m.status === 'draft' ? ' (draft)' : '') + '</div>' +
            '<div class="bubble-time">' + (m.sent_at ? new Date(m.sent_at).toLocaleTimeString([], {hour: '2-digit', minute: '2-digit'}) : '') + '</div>' +
            '</div>';
        }).join('');
        container.scrollTop = container.scrollHeight;

        loadUnreadBadge();
        loadSidebar();
      } catch (err) {
        document.getElementById('messagesContainer').innerHTML = '<div style="color: var(--text-muted); font-size: 13px;">' + err.message + '</div>';
      }
    }

    let pendingDeleteId = null;

    function deleteConversation(conversationId, displayName) {
      pendingDeleteId = conversationId;
      document.getElementById('deleteModalText').textContent =
        'This will permanently delete your conversation with ' + displayName + '. This cannot be undone.';
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
      const confirmBtn = document.getElementById('deleteModalConfirm');
      hideAlert(alertEl);
      confirmBtn.disabled = true;
      confirmBtn.textContent = 'Deleting…';

      try {
        await apiRequest('/messages/conversations/' + pendingDeleteId, { method: 'DELETE' });

        if (pendingDeleteId === currentConversationId) {
          document.getElementById('emptyState').style.display = 'flex';
          document.getElementById('activeChat').style.display = 'none';
          currentConversationId = null;
          history.replaceState(null, '', 'inbox.html');
        }

        document.getElementById('deleteModalBackdrop').classList.remove('visible');
        pendingDeleteId = null;
        await loadSidebar();
      } catch (err) {
        showAlert(alertEl, err.message);
      } finally {
        confirmBtn.disabled = false;
        confirmBtn.textContent = 'Delete';
      }
    });

    document.getElementById('sendReplyBtn').addEventListener('click', async () => {
      const textarea = document.getElementById('replyBody');
      const body = textarea.value.trim();
      if (!body || !currentConversationId) return;

      try {
        await apiRequest('/messages/conversations/' + currentConversationId + '/reply', {
          method: 'POST',
          body: { body: body, status: 'sent' }
        });
        textarea.value = '';
        selectChat(currentConversationId);
      } catch (err) {
        alert(err.message);
      }
    });

    document.getElementById('replyBody').addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        document.getElementById('sendReplyBtn').click();
      }
    });

    const userSearchInput = document.getElementById('userSearch');
    const userSearchResults = document.getElementById('userSearchResults');
    let userSearchTimeout = null;

    userSearchInput.addEventListener('input', () => {
      clearTimeout(userSearchTimeout);
      const query = userSearchInput.value.trim();
      if (!query) {
        userSearchResults.style.display = 'none';
        return;
      }
      userSearchTimeout = setTimeout(() => searchUsers(query), 250);
    });

    async function searchUsers(query) {
      try {
        const result = await apiRequest('/staff?search=' + encodeURIComponent(query));
        if (result.staff.length === 0) {
          userSearchResults.innerHTML = '<div class="search-result-item" style="color: var(--text-muted);">No matches.</div>';
        } else {
          userSearchResults.innerHTML = result.staff.map(s => {
            return '<div class="search-result-item" onclick=\'startOrOpenChat(' + JSON.stringify(s) + ')\'>' +
              '<span class="presence-dot ' + (s.isOnline ? 'online' : '') + '"></span>' +
              '<span>' + s.full_name + ' · ' + s.username + '</span></div>';
          }).join('');
        }
        userSearchResults.style.display = 'block';
      } catch (err) {
        userSearchResults.style.display = 'none';
      }
    }

    async function startOrOpenChat(staff) {
      userSearchResults.style.display = 'none';
      userSearchInput.value = '';

      const match = conversationsCache.find(c => c.participants.length === 1 && c.participants[0].id === staff.id);
      if (match) {
        selectChat(match.id);
        return;
      }

      try {
        const result = await apiRequest('/messages/compose', {
          method: 'POST',
          body: { recipientIds: [staff.id], body: '', status: 'draft' }
        });
        await loadSidebar();
        selectChat(result.conversationId);
      } catch (err) {
        alert(err.message);
      }
    }

    document.addEventListener('click', (e) => {
      if (!e.target.closest('#userSearch') && !e.target.closest('#userSearchResults')) {
        userSearchResults.style.display = 'none';
      }
    });

    setInterval(loadSidebar, 20000);
    setInterval(() => {
      if (currentConversationId) selectChat(currentConversationId);
    }, 20000);

    init();
    loadUnreadBadge();
  </script>
</body>
</html>

EOF_ACCOUNTING_INBOX_HTML

echo "Delete now uses a proper card modal instead of the browser popup."
echo "Push to deploy: bash save-progress.sh \"Replace native confirm with modal for delete\""