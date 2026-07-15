#!/usr/bin/env bash
# Removes the separate Drafts nav link - only Inbox remains, for everyone.
# Run this from the ROOT of your macden-website repo, in Git Bash.
set -e

mkdir -p accounting

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
          return '<div class="chat-sidebar-row ' + active + ' ' + unread + '" data-id="' + c.id + '" onclick="selectChat(\'' + c.id + '\')">' +
            '<div class="chat-avatar">' + initials(c.displayName) + '<span class="presence-dot ' + (online ? 'online' : '') + '"></span></div>' +
            '<div class="chat-row-text"><p class="chat-row-name">' + c.displayName + '</p><p class="chat-row-preview">' + (c.lastMessagePreview || 'No messages yet') + '</p></div>' +
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

echo "Drafts nav link removed everywhere. Only Inbox remains."
echo "Push to deploy: bash save-progress.sh \"Remove Drafts nav, keep only Inbox\""