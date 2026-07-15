#!/usr/bin/env bash
# Corrects the delete feature: any user can delete a conversation (like
# deleting an email), no account changes involved. Replaces the previous
# admin-only account-deactivation approach.
# Run this from the ROOT of your macden-website repo, in Git Bash.
set -e

mkdir -p server/routes accounting

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

router.delete('/:id', async (req, res) => {
  const { id } = req.params;
  const staffId = req.session.staff.id;

  const { data: existing, error: fetchError } = await supabase
    .from('messages')
    .select('id, sender_id')
    .eq('id', id)
    .single();

  if (fetchError || !existing) {
    return res.status(404).json({ error: 'Message not found.' });
  }

  if (existing.sender_id !== staffId) {
    return res.status(403).json({ error: 'You can only delete your own messages.' });
  }

  const { error: deleteError } = await supabase
    .from('messages')
    .delete()
    .eq('id', id);

  if (deleteError) {
    return res.status(500).json({ error: 'Could not delete message.' });
  }

  res.json({ success: true });
});

// DELETE /api/accounting/messages/conversations/:id
// Deletes the whole conversation — cascade cleans up its messages and read
// records automatically. Any participant can do this, same as deleting an
// email thread. No account or login access is affected by this at all.
router.delete('/conversations/:id', async (req, res) => {
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

  const { error } = await supabase.from('conversations').delete().eq('id', id);

  if (error) {
    return res.status(500).json({ error: 'Could not delete conversation.' });
  }

  res.json({ success: true });
});

module.exports = router;

EOF_SERVER_ROUTES_MESSAGES_JS

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

    async function deleteConversation(conversationId, displayName) {
      const confirmed = confirm('Delete the conversation with ' + displayName + '? This cannot be undone.');
      if (!confirmed) return;

      try {
        await apiRequest('/messages/conversations/' + conversationId, { method: 'DELETE' });

        if (conversationId === currentConversationId) {
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

echo "Simple conversation delete added for everyone."
echo "Push to deploy: bash save-progress.sh \"Simplify to conversation delete for all users\""