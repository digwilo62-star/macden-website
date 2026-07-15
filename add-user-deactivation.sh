#!/usr/bin/env bash
# Adds admin-only 'remove user' from inbox: deactivates the account (soft-
# disable, preserves history) and clears the shared chat. Regular staff
# don't see this option at all.
# Run this from the ROOT of your macden-website repo, in Git Bash.
set -e

mkdir -p server/routes accounting

cat > server/routes/admin.js << 'EOF_SERVER_ROUTES_ADMIN_JS'
const express = require('express');
const supabase = require('../config/supabaseClient');

const router = express.Router();

// Only staff with role = 'admin' can reach these routes.
function requireAdmin(req, res, next) {
  if (req.session.staff.role !== 'admin') {
    return res.status(403).json({ error: 'Admin access only.' });
  }
  next();
}

router.use(requireAdmin);

// GET /api/accounting/admin/pending-staff
// Lists everyone who has verified their email but is still waiting on approval.
router.get('/pending-staff', async (req, res) => {
  const { data, error } = await supabase
    .from('staff')
    .select('id, full_name, username, email, created_at')
    .eq('email_verified', true)
    .eq('is_active', false)
    .order('created_at', { ascending: true });

  if (error) {
    return res.status(500).json({ error: 'Could not load pending accounts.' });
  }

  res.json({ pending: data });
});

// POST /api/accounting/admin/approve-staff/:id
router.post('/approve-staff/:id', async (req, res) => {
  const { id } = req.params;

  const { data, error } = await supabase
    .from('staff')
    .update({ is_active: true })
    .eq('id', id)
    .select()
    .single();

  if (error || !data) {
    return res.status(400).json({ error: 'Could not approve this account.' });
  }

  res.json({ success: true, message: `${data.full_name} has been approved and can now log in.` });
});

// DELETE /api/accounting/admin/staff/:id
// Deactivates a staff member (soft-disable, not a hard delete — their past
// messages and price edits stay intact) and clears any shared conversation
// with the admin performing this action.
router.delete('/staff/:id', async (req, res) => {
  const { id } = req.params;
  const adminId = req.session.staff.id;

  if (id === adminId) {
    return res.status(400).json({ error: 'You cannot deactivate your own account.' });
  }

  const { data: targetMemberships } = await supabase
    .from('conversation_members')
    .select('conversation_id')
    .eq('staff_id', id);

  const { data: adminMemberships } = await supabase
    .from('conversation_members')
    .select('conversation_id')
    .eq('staff_id', adminId);

  const targetIds = new Set((targetMemberships || []).map(m => m.conversation_id));
  const sharedConversationIds = (adminMemberships || [])
    .map(m => m.conversation_id)
    .filter(convId => targetIds.has(convId));

  if (sharedConversationIds.length > 0) {
    // Cascade delete handles conversation_members, messages, and message_reads automatically
    await supabase.from('conversations').delete().in('id', sharedConversationIds);
  }

  const { error } = await supabase
    .from('staff')
    .update({ is_active: false })
    .eq('id', id);

  if (error) {
    return res.status(500).json({ error: 'Could not deactivate this account.' });
  }

  res.json({ success: true });
});

module.exports = router;

EOF_SERVER_ROUTES_ADMIN_JS

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
          const deleteBtn = (isAdmin && p) ? '<button onclick="event.stopPropagation(); deleteUser(\'' + p.id + '\', \'' + c.displayName.replace(/'/g, "\\'") + '\')" aria-label="Remove user" style="background:none;border:none;color:var(--text-muted);cursor:pointer;font-size:14px;padding:4px;flex-shrink:0;">🗑</button>' : '';
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

    async function deleteUser(staffId, displayName) {
      const confirmed = confirm(
        'Remove ' + displayName + '?\n\n' +
        'This deactivates their account (they will no longer be able to log in) ' +
        'and permanently clears your chat with them. This cannot be undone.'
      );
      if (!confirmed) return;

      const deletedConversation = conversationsCache.find(c => c.participants.some(p => p.id === staffId));
      const wasOpen = deletedConversation && deletedConversation.id === currentConversationId;

      try {
        await apiRequest('/admin/staff/' + staffId, { method: 'DELETE' });

        if (wasOpen) {
          document.getElementById('emptyState').style.display = 'flex';
          document.getElementById('activeChat').style.display = 'none';
          currentConversationId = null;
          history.replaceState(null, '', 'inbox.html');
        }

        loadSidebar();
      } catch (err) {
        alert(err.message);
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

echo "Admin-only user removal added to inbox."
echo "Push to deploy: bash save-progress.sh \"Add admin-only user deactivation from inbox\""