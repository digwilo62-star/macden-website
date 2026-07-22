#!/usr/bin/env bash
# Rebuilds Inbox (screen 3 of 15) with the new portal shell and icon set.
# All backend logic (search, presence, attachments, delete) unchanged.
# Run this from the ROOT of your macden-website repo, in Git Bash.
set -e

mkdir -p accounting/assets

cat > accounting/assets/portal-inbox.css << 'EOF_ACCOUNTING_ASSETS_PORTAL-INBOX_CSS'
/* ---------- Alerts & modal (shared) ---------- */

.alert { padding: 11px 14px; border-radius: var(--radius-sm); font-size: 12.5px; margin-bottom: 18px; display: none; }
.alert-error { background: var(--error-dim); color: var(--error); border: 1px solid rgba(220,38,38,0.2); }
.alert.visible { display: block; }

.modal-backdrop { display: none; position: fixed; inset: 0; background: rgba(0,0,0,0.45); align-items: center; justify-content: center; z-index: 100; }
.modal-backdrop.visible { display: flex; }
.modal { width: 360px; background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-lg); padding: 24px; }
.modal h3 { margin: 0 0 8px; font-size: 15px; }
.modal p { margin: 0 0 4px; font-size: 13px; color: var(--text-secondary); line-height: 1.5; }
.modal-actions { display: flex; gap: 8px; margin-top: 20px; justify-content: flex-end; }
.modal-actions .btn { width: auto; padding: 8px 16px; }
.btn-ghost { background: transparent; border: 1px solid var(--border); color: var(--text-primary); }
.btn-ghost:hover { border-color: var(--border-hover); }

/* ---------- Presence ---------- */

.presence-dot { width: 8px; height: 8px; border-radius: 50%; background: var(--text-muted); flex-shrink: 0; display: inline-block; }
.presence-dot.online { background: var(--primary-light); }

/* ---------- Two-panel inbox ---------- */

.chat-shell {
  display: flex;
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  overflow: hidden;
  height: calc(100vh - 220px);
  min-height: 420px;
  background: var(--surface);
}

.chat-sidebar { width: 320px; flex-shrink: 0; border-right: 1px solid var(--border); display: flex; flex-direction: column; }

.chat-sidebar-search { padding: 14px; border-bottom: 1px solid var(--border); }
.chat-sidebar-search input {
  width: 100%; background: var(--surface-raised); border: 1px solid var(--border);
  border-radius: var(--radius-sm); padding: 9px 12px; font-size: 13px;
  font-family: var(--font-body); color: var(--text-primary);
}

.chat-sidebar-list { flex: 1; overflow-y: auto; }

.chat-sidebar-row { display: flex; align-items: center; gap: 10px; padding: 13px 14px; cursor: pointer; border-bottom: 1px solid var(--border); }
.chat-sidebar-row:hover, .chat-sidebar-row.active { background: var(--surface-raised); }
.chat-sidebar-row.unread .chat-row-name { font-weight: 700; }

.chat-avatar {
  width: 38px; height: 38px; border-radius: 50%;
  background: var(--gold-dim); color: #a17a00;
  display: flex; align-items: center; justify-content: center;
  font-size: 13px; font-weight: 700; flex-shrink: 0; position: relative;
}
.chat-avatar .presence-dot { position: absolute; bottom: -1px; right: -1px; border: 2px solid var(--surface); }

.chat-row-text { flex: 1; min-width: 0; }
.chat-row-name { font-size: 13.5px; color: var(--text-primary); margin: 0 0 2px; }
.chat-row-preview { font-size: 12.5px; color: var(--text-secondary); margin: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }

.chat-panel { flex: 1; display: flex; flex-direction: column; background: var(--bg); min-width: 0; }
.chat-empty-state { flex: 1; display: flex; align-items: center; justify-content: center; color: var(--text-muted); font-size: 13px; }

.chat-panel-header { display: flex; align-items: center; gap: 10px; padding: 15px 20px; border-bottom: 1px solid var(--border); background: var(--surface); }
.chat-header-name { font-size: 15px; font-weight: 700; color: var(--text-primary); margin: 0; font-family: var(--font-heading); }
.chat-header-status { font-size: 12px; color: var(--text-muted); margin: 0; }

.chat-panel-messages { flex: 1; overflow-y: auto; padding: 20px; display: flex; flex-direction: column; gap: 8px; }

.bubble-row { display: flex; flex-direction: column; max-width: 65%; }
.bubble-row.sent { align-self: flex-end; align-items: flex-end; }
.bubble-row.received { align-self: flex-start; align-items: flex-start; }
.bubble { padding: 10px 14px; border-radius: 14px; font-size: 13.5px; line-height: 1.45; white-space: pre-wrap; }
.bubble-row.sent .bubble { background: var(--primary); color: #fff; border-bottom-right-radius: 4px; }
.bubble-row.received .bubble { background: var(--surface); border: 1px solid var(--border); color: var(--text-primary); border-bottom-left-radius: 4px; }
.bubble-time { font-size: 10.5px; color: var(--text-muted); margin-top: 3px; padding: 0 4px; }

.chat-panel-composer { padding: 15px 20px; border-top: 1px solid var(--border); background: var(--surface); display: flex; gap: 8px; align-items: flex-end; }
.chat-panel-composer textarea {
  flex: 1; min-height: 42px; max-height: 120px; background: var(--surface-raised);
  border: 1px solid var(--border); border-radius: 20px; padding: 11px 16px;
  color: var(--text-primary); font-size: 13.5px; font-family: var(--font-body); resize: none;
}
.chat-panel-composer textarea:focus { outline: none; border-color: var(--primary); }

.chat-send-btn { width: 42px; height: 42px; border-radius: 50%; background: var(--primary); color: #fff; border: none; cursor: pointer; font-size: 16px; flex-shrink: 0; }
.chat-send-btn:hover { background: var(--primary-light); }
.chat-send-btn:disabled { opacity: 0.5; cursor: not-allowed; }

.search-results { position: absolute; top: 100%; left: 0; right: 0; background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-sm); margin-top: 4px; max-height: 240px; overflow-y: auto; z-index: 5; display: none; box-shadow: 0 4px 12px rgba(0,0,0,0.08); }
.search-result-item { padding: 10px 12px; cursor: pointer; font-size: 13px; display: flex; align-items: center; gap: 8px; }
.search-result-item:hover { background: var(--surface-raised); }

EOF_ACCOUNTING_ASSETS_PORTAL-INBOX_CSS

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
        <button class="topbar-bell"><i class="ti ti-bell"></i></button>
        <img class="topbar-avatar" src="assets/logo.jpeg" alt="You">
      </div>

      <div class="page-body">
        <h1 class="page-greeting" style="font-size: 22px;">Inbox</h1>
        <p class="page-greeting-sub"><a href="dashboard.html" style="color: var(--primary); text-decoration: none; font-weight: 600;">← Back to dashboard</a></p>

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

              <div id="attachmentPreview" style="display: none; padding: 8px 20px; font-size: 12.5px; color: var(--text-secondary); border-top: 1px solid var(--border); background: var(--surface);">
                <i class="ti ti-paperclip"></i> <span id="attachmentName"></span>
                <button onclick="clearAttachment()" style="background: none; border: none; color: var(--error); cursor: pointer; margin-left: 8px; font-size: 12px; font-family: var(--font-body);">Remove</button>
              </div>
              <div id="attachmentAlert" class="alert alert-error" style="margin: 8px 20px 0; display: none; align-items: center; justify-content: space-between;">
                <span id="attachmentAlertText"></span>
                <button onclick="hideAlert(document.getElementById('attachmentAlert'))" style="background: none; border: none; color: inherit; cursor: pointer; font-size: 13px; padding: 0 0 0 12px;"><i class="ti ti-x"></i></button>
              </div>

              <div class="chat-panel-composer">
                <button id="attachBtn" aria-label="Attach file" style="background: transparent; border: 1px solid var(--border); color: var(--text-secondary); width: 42px; height: 42px; border-radius: 50%; cursor: pointer; font-size: 16px; flex-shrink: 0;"><i class="ti ti-paperclip"></i></button>
                <input type="file" id="fileInput" accept=".pdf,.xlsx" style="display: none;">
                <textarea id="replyBody" placeholder="Type a message…" rows="1"></textarea>
                <button class="chat-send-btn" id="sendReplyBtn" aria-label="Send"><i class="ti ti-send"></i></button>
              </div>
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
  <script>
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
          const deleteBtn = '<button onclick="event.stopPropagation(); deleteConversation(\'' + c.id + '\', \'' + c.displayName.replace(/'/g, "\\'") + '\')" aria-label="Delete conversation" style="background:none;border:none;color:var(--text-muted);cursor:pointer;font-size:14px;padding:4px;flex-shrink:0;"><i class="ti ti-trash"></i></button>';
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

    function renderBubble(m) {
      const sent = m.sender_id === currentStaffId;
      const deleteBtn = sent ? '<button onclick="deleteMessage(\'' + m.id + '\', this)" aria-label="Delete message" style="background:none;border:none;color:inherit;opacity:0.65;cursor:pointer;font-size:11px;margin-left:8px;padding:0;"><i class="ti ti-x"></i></button>' : '';
      let attachmentHtml = '';
      if (m.attachment_url) {
        const icon = m.attachment_type === 'pdf' ? 'ti-file-type-pdf' : 'ti-file-spreadsheet';
        attachmentHtml = '<div style="margin-top:6px;"><a href="' + m.attachment_url + '" target="_blank" rel="noopener" style="color: inherit; text-decoration: underline; font-size: 12.5px;"><i class="ti ' + icon + '"></i> Download attachment</a></div>';
      }
      return '<div class="bubble-row ' + (sent ? 'sent' : 'received') + '" data-message-id="' + m.id + '">' +
        '<div class="bubble">' + (m.body || '') + (m.status === 'draft' ? ' (draft)' : '') + deleteBtn + attachmentHtml + '</div>' +
        '<div class="bubble-time">' + (m.sent_at ? new Date(m.sent_at).toLocaleTimeString([], {hour: '2-digit', minute: '2-digit'}) : '') + '</div>' +
        '</div>';
    }

    async function selectChat(id) {
      currentConversationId = id;
      history.replaceState(null, '', 'inbox.html?id=' + id);

      document.querySelectorAll('.chat-sidebar-row').forEach(row => {
        row.classList.toggle('active', row.dataset.id === id);
      });

      document.getElementById('emptyState').style.display = 'none';
      document.getElementById('activeChat').style.display = 'flex';
      hideAttachmentError();
      clearAttachment();

      try {
        const result = await apiRequest('/messages/conversations/' + id);
        const participant = result.participants[0];

        document.getElementById('threadInitials').textContent = initials(participant ? participant.fullName : '?');
        document.getElementById('threadName').textContent = participant ? participant.fullName : 'Conversation';
        document.getElementById('threadStatus').textContent = participant && participant.isOnline ? 'Online' : 'Offline';
        document.getElementById('threadDot').className = 'presence-dot' + (participant && participant.isOnline ? ' online' : '');

        const container = document.getElementById('messagesContainer');
        container.innerHTML = result.messages.map(renderBubble).join('');
        container.scrollTop = container.scrollHeight;

        loadUnreadBadge();
      } catch (err) {
        document.getElementById('messagesContainer').innerHTML = '<div style="color: var(--text-muted); font-size: 13px;">' + err.message + '</div>';
      }
    }

    async function deleteMessage(id, btn) {
      const bubbleRow = btn.closest('.bubble-row');
      try {
        await apiRequest('/messages/' + id, { method: 'DELETE' });
        if (bubbleRow) bubbleRow.remove();
        loadSidebar();
      } catch (err) {
        alert(err.message);
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

    function showAttachmentError(message) {
      const alertEl = document.getElementById('attachmentAlert');
      document.getElementById('attachmentAlertText').textContent = message;
      alertEl.style.display = 'flex';
    }

    function hideAttachmentError() {
      document.getElementById('attachmentAlert').style.display = 'none';
    }

    let pendingAttachment = null;

    document.getElementById('attachBtn').addEventListener('click', () => {
      document.getElementById('fileInput').click();
    });

    document.getElementById('fileInput').addEventListener('change', async (e) => {
      const file = e.target.files[0];
      if (!file) return;

      hideAttachmentError();

      const formData = new FormData();
      formData.append('attachment', file);

      try {
        const res = await fetch('/api/accounting/messages/upload', {
          method: 'POST',
          credentials: 'include',
          body: formData
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Upload failed.');

        pendingAttachment = data;
        document.getElementById('attachmentName').textContent = data.name;
        document.getElementById('attachmentPreview').style.display = 'block';
      } catch (err) {
        showAttachmentError(err.message);
      }
      e.target.value = '';
    });

    function clearAttachment() {
      pendingAttachment = null;
      document.getElementById('attachmentPreview').style.display = 'none';
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
        const result = await apiRequest('/messages/conversations/' + currentConversationId + '/reply', {
          method: 'POST',
          body: {
            body: savedBody,
            status: 'sent',
            attachmentUrl: savedAttachment ? savedAttachment.url : undefined,
            attachmentType: savedAttachment ? savedAttachment.type : undefined
          }
        });

        const container = document.getElementById('messagesContainer');
        container.insertAdjacentHTML('beforeend', renderBubble(result.message));
        container.scrollTop = container.scrollHeight;
        hideAttachmentError();

        loadSidebar();
      } catch (err) {
        alert(err.message);
        textarea.value = savedBody;
        pendingAttachment = savedAttachment;
      } finally {
        sendBtn.disabled = false;
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

echo "Inbox rebuilt with new portal design (screen 3 of 15)."