#!/usr/bin/env bash
# Adds Broadcasts (screens 6A + 7): send to all active staff, sent history
# with open-rate tracking. Reuses the existing conversation/message
# infrastructure - no separate system, just a new is_broadcast flag.
# Admin-only for now (mapped to the existing 'admin' role as HR/Auditor).
# RUN THE SQL MIGRATION FIRST in Supabase before running this script.
# Run this from the ROOT of your macden-website repo, in Git Bash.
set -e

mkdir -p server/routes accounting

cat > server/routes/messages.js << 'EOF_SERVER_ROUTES_MESSAGES_JS'
const express = require('express');
const multer = require('multer');
const supabase = require('../config/supabaseClient');
const { isOnline } = require('./staff');

const router = express.Router();

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 15 * 1024 * 1024 }, // 15MB
  fileFilter: (req, file, cb) => {
    const allowed = {
      'application/pdf': 'pdf',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx'
    };
    if (allowed[file.mimetype]) {
      cb(null, true);
    } else {
      cb(new Error('Only PDF and Excel (.xlsx) files are allowed.'));
    }
  }
});

// POST /api/accounting/messages/upload — uploads a PDF or Excel file to
// Supabase Storage and returns the URL to attach to a message.
router.post('/upload', (req, res) => {
  upload.single('attachment')(req, res, async (err) => {
    if (err) {
      return res.status(400).json({ error: err.message });
    }
    if (!req.file) {
      return res.status(400).json({ error: 'No file provided.' });
    }

    try {
      const typeMap = {
        'application/pdf': 'pdf',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx'
      };
      const attachmentType = typeMap[req.file.mimetype];
      const fileName = `${req.session.staff.id}-${Date.now()}-${req.file.originalname}`;

      const { error: uploadError } = await supabase.storage
        .from('attachments')
        .upload(fileName, req.file.buffer, { contentType: req.file.mimetype });

      if (uploadError) {
        console.error('Supabase storage upload error:', uploadError);
        // Surface the real reason (e.g. "Bucket not found") instead of a generic
        // message — this is the difference between a fixable, diagnosable error
        // and a dead end.
        return res.status(500).json({ error: 'Upload failed: ' + (uploadError.message || 'unknown error') });
      }

      const { data: publicUrlData } = supabase.storage.from('attachments').getPublicUrl(fileName);

      res.json({
        success: true,
        url: publicUrlData.publicUrl,
        type: attachmentType,
        name: req.file.originalname
      });
    } catch (err) {
      console.error('Upload error:', err);
      res.status(500).json({ error: 'Something went wrong uploading this file.' });
    }
  });
});

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
    .select('id, subject, is_broadcast, created_at')
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
      subject: conv.subject,
      isBroadcast: conv.is_broadcast,
      participants,
      displayName: participants.map(p => p.fullName).join(', ') || 'Unknown',
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

  const { data: conversation } = await supabase
    .from('conversations')
    .select('id, subject')
    .eq('id', id)
    .single();

  const participants = await getOtherParticipants(id, staffId);

  // Build a full sender-name lookup (including yourself) so every message
  // in the thread can show a real "From" name, not just the other party.
  const { data: allMemberRows } = await supabase
    .from('conversation_members')
    .select('staff_id')
    .eq('conversation_id', id);
  const allMemberIds = (allMemberRows || []).map(m => m.staff_id);
  const { data: allStaffRows } = await supabase
    .from('staff')
    .select('id, full_name')
    .in('id', allMemberIds.length > 0 ? allMemberIds : ['00000000-0000-0000-0000-000000000000']);
  const nameById = {};
  (allStaffRows || []).forEach(s => { nameById[s.id] = s.full_name; });

  const { data: messages, error } = await supabase
    .from('messages')
    .select('id, sender_id, body, status, sent_at, created_at, attachment_url, attachment_type')
    .eq('conversation_id', id)
    .or(`status.eq.sent,and(status.eq.draft,sender_id.eq.${staffId})`)
    .order('created_at', { ascending: true });

  if (error) {
    return res.status(500).json({ error: 'Could not load conversation.' });
  }

  const messagesWithSenderNames = messages.map(m => ({
    ...m,
    senderName: m.sender_id === staffId ? 'You' : (nameById[m.sender_id] || 'Unknown')
  }));

  const sentMessageIds = messages.filter(m => m.status === 'sent').map(m => m.id);
  if (sentMessageIds.length > 0) {
    await supabase
      .from('message_reads')
      .update({ read_at: new Date().toISOString() })
      .eq('staff_id', staffId)
      .in('message_id', sentMessageIds)
      .is('read_at', null);
  }

  res.json({
    subject: conversation ? conversation.subject : 'Conversation',
    participants,
    toLine: participants.map(p => p.fullName).join(', '),
    messages: messagesWithSenderNames
  });
});

router.post('/compose', async (req, res) => {
  const { recipientIds, subject, body, status, attachmentUrl, attachmentType } = req.body;
  const staffId = req.session.staff.id;

  if (!recipientIds || recipientIds.length === 0) {
    return res.status(400).json({ error: 'Add at least one recipient.' });
  }

  if (!subject || !subject.trim()) {
    return res.status(400).json({ error: 'Subject is required.' });
  }

  const { data: conversation, error: convError } = await supabase
    .from('conversations')
    .insert({
      department_id: req.session.staff.departmentId,
      subject: subject.trim(),
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
      sent_at: isSent ? new Date().toISOString() : null,
      attachment_url: attachmentUrl || null,
      attachment_type: attachmentType || null
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
  const { body, status, attachmentUrl, attachmentType } = req.body;
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
      sent_at: isSent ? new Date().toISOString() : null,
      attachment_url: attachmentUrl || null,
      attachment_type: attachmentType || null
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
  try {
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
  } catch (err) {
    console.error('Delete message error:', err);
    res.status(500).json({ error: 'Something went wrong deleting this message.' });
  }
});

// DELETE /api/accounting/messages/conversations/:id
// Deletes the whole conversation — cascade cleans up its messages and read
// records automatically. Any participant can do this, same as deleting an
// email thread. No account or login access is affected by this at all.
router.delete('/conversations/:id', async (req, res) => {
  try {
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
  } catch (err) {
    console.error('Delete conversation error:', err);
    res.status(500).json({ error: 'Something went wrong deleting this conversation.' });
  }
});

// POST /api/accounting/messages/broadcast — admin-only, sends to every active staff member
router.post('/broadcast', async (req, res) => {
  try {
    if (req.session.staff.role !== 'admin') {
      return res.status(403).json({ error: 'Only admins can send broadcasts.' });
    }

    const { subject, body } = req.body;
    const staffId = req.session.staff.id;

    if (!subject || !subject.trim()) {
      return res.status(400).json({ error: 'Subject is required.' });
    }
    if (!body || !body.trim()) {
      return res.status(400).json({ error: 'Message body is required.' });
    }

    const { data: allActiveStaff, error: staffError } = await supabase
      .from('staff')
      .select('id')
      .eq('is_active', true)
      .neq('id', staffId);

    if (staffError) {
      return res.status(500).json({ error: 'Could not load staff list.' });
    }

    const { data: conversation, error: convError } = await supabase
      .from('conversations')
      .insert({
        department_id: req.session.staff.departmentId,
        subject: subject.trim(),
        is_group: true,
        is_broadcast: true
      })
      .select()
      .single();

    if (convError) {
      return res.status(500).json({ error: 'Could not create broadcast.' });
    }

    const memberRows = [staffId, ...allActiveStaff.map(s => s.id)]
      .map(id => ({ conversation_id: conversation.id, staff_id: id }));
    await supabase.from('conversation_members').insert(memberRows);

    const { data: message, error: msgError } = await supabase
      .from('messages')
      .insert({
        conversation_id: conversation.id,
        sender_id: staffId,
        body: body.trim(),
        status: 'sent',
        sent_at: new Date().toISOString()
      })
      .select()
      .single();

    if (msgError) {
      return res.status(500).json({ error: 'Could not send broadcast.' });
    }

    await createReadRowsForRecipients(conversation.id, message.id, staffId);

    res.json({ success: true, conversationId: conversation.id, recipientCount: allActiveStaff.length });
  } catch (err) {
    console.error('Broadcast send error:', err);
    res.status(500).json({ error: 'Something went wrong sending this broadcast.' });
  }
});

// GET /api/accounting/messages/broadcasts — admin-only, sent history with open rates
router.get('/broadcasts', async (req, res) => {
  try {
    if (req.session.staff.role !== 'admin') {
      return res.status(403).json({ error: 'Only admins can view broadcast history.' });
    }

    const { data: conversations, error } = await supabase
      .from('conversations')
      .select('id, subject, created_at')
      .eq('is_broadcast', true)
      .order('created_at', { ascending: false });

    if (error) {
      return res.status(500).json({ error: 'Could not load broadcast history.' });
    }

    const enriched = await Promise.all(conversations.map(async (conv) => {
      const { data: message } = await supabase
        .from('messages')
        .select('id, body, sent_at')
        .eq('conversation_id', conv.id)
        .eq('status', 'sent')
        .limit(1)
        .maybeSingle();

      let recipientCount = 0;
      let openedCount = 0;
      if (message) {
        const { count: total } = await supabase
          .from('message_reads')
          .select('*', { count: 'exact', head: true })
          .eq('message_id', message.id);
        const { count: opened } = await supabase
          .from('message_reads')
          .select('*', { count: 'exact', head: true })
          .eq('message_id', message.id)
          .not('read_at', 'is', null);
        recipientCount = total || 0;
        openedCount = opened || 0;
      }

      return {
        id: conv.id,
        subject: conv.subject,
        sentAt: message ? message.sent_at : conv.created_at,
        recipientCount,
        openedCount
      };
    }));

    res.json({ broadcasts: enriched });
  } catch (err) {
    console.error('Broadcast history error:', err);
    res.status(500).json({ error: 'Something went wrong loading broadcast history.' });
  }
});

module.exports = router;

EOF_SERVER_ROUTES_MESSAGES_JS

cat > accounting/broadcasts.html << 'EOF_ACCOUNTING_BROADCASTS_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Broadcasts — MACDEN Portal</title>
  <link rel="stylesheet" href="assets/portal-style.css">
  <link rel="stylesheet" href="assets/portal-shell.css">
  <link rel="stylesheet" href="assets/portal-inbox.css">
  <style>
    .bc-list { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-md); overflow: hidden; }
    .bc-row { display: grid; grid-template-columns: 1fr 140px 140px 160px; align-items: center; gap: 14px; padding: 14px 20px; border-bottom: 1px solid var(--border); cursor: pointer; }
    .bc-row:last-child { border-bottom: none; }
    .bc-row:hover { background: var(--surface-raised); }
    .bc-subject { font-size: 13.5px; font-weight: 600; color: var(--text-primary); }
    .bc-date { font-size: 12px; color: var(--text-muted); }
    .bc-count { font-size: 12.5px; color: var(--text-secondary); }
    .bc-opened { font-size: 12.5px; color: var(--primary); font-weight: 600; }
    .bc-empty { padding: 60px 20px; text-align: center; color: var(--text-muted); font-size: 13px; }
    .bc-compose-note { background: var(--gold-dim); color: #8a6d00; padding: 10px 14px; border-radius: var(--radius-sm); font-size: 12.5px; margin-bottom: 16px; }
    .bc-recipient-count { font-family: var(--font-heading); font-size: 22px; font-weight: 800; color: var(--primary); }
  </style>
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
        <a href="inbox.html" class="sidebar-link"><i class="ti ti-mail"></i> Inbox <span class="badge" id="unreadBadge" style="display:none;">0</span></a>
        <a href="compose.html" class="sidebar-link"><i class="ti ti-pencil"></i> Compose</a>
        <a href="broadcasts.html" class="sidebar-link active"><i class="ti ti-speakerphone"></i> Broadcasts</a>
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

        <div id="notAdminView" style="display:none;">
          <h1 class="page-greeting" style="font-size: 22px;">Broadcasts</h1>
          <div class="bc-empty" style="margin-top:20px;">Only admins (HR/Auditor) can send or view company-wide broadcasts.</div>
        </div>

        <div id="adminView" style="display:none;">

          <div id="listView">
            <div class="email-toolbar">
              <div>
                <h1 class="page-greeting" style="font-size: 22px;">Broadcasts — Sent History</h1>
                <p class="page-greeting-sub" style="margin:0;"><a href="dashboard.html" style="color: var(--primary); text-decoration:none; font-weight:600;">← Back to dashboard</a></p>
              </div>
              <button class="btn btn-primary" id="newBroadcastBtn" style="width:auto; padding:10px 20px; display:inline-flex; align-items:center; gap:8px;"><i class="ti ti-speakerphone"></i> New Broadcast</button>
            </div>

            <div class="bc-list" id="bcList">
              <div class="bc-empty">Loading…</div>
            </div>
          </div>

          <div id="composeView" style="display:none;">
            <h1 class="page-greeting" style="font-size: 22px;">New Broadcast</h1>
            <p class="page-greeting-sub"><a href="#" id="cancelComposeLink" style="color: var(--primary); text-decoration:none; font-weight:600;">← Back to broadcasts</a></p>

            <div class="bc-compose-note"><i class="ti ti-info-circle"></i> This message will be sent to all active staff.</div>
            <div id="alert" class="alert alert-error"></div>

            <div style="display:grid; grid-template-columns: 1fr 220px; gap: 20px;">
              <div class="compose-card" style="max-width:none;">
                <div class="compose-field">
                  <label>Subject</label>
                  <input type="text" id="bcSubject" placeholder="Important company update">
                </div>
                <div class="compose-body-area">
                  <textarea id="bcBody" placeholder="Write your announcement…"></textarea>
                </div>
                <div class="compose-footer">
                  <span></span>
                  <button class="btn btn-primary" id="sendBroadcastBtn" style="width:auto; padding:10px 24px; display:inline-flex; align-items:center; gap:8px;"><i class="ti ti-send"></i> Send to All</button>
                </div>
              </div>
              <div class="email-card" style="text-align:center;">
                <div class="bc-recipient-count" id="recipientCountDisplay">—</div>
                <div style="font-size:12px; color:var(--text-secondary); margin-top:4px;">Active Staff</div>
              </div>
            </div>
          </div>

        </div>

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

    async function init() {
      let staff;
      try {
        const result = await apiRequest('/dashboard-check');
        staff = result.staff;
      } catch (err) {
        window.location.href = 'login.html';
        return;
      }

      if (staff.role !== 'admin') {
        document.getElementById('notAdminView').style.display = 'block';
        return;
      }

      document.getElementById('adminView').style.display = 'block';
      loadBroadcasts();
      loadUnreadBadge();
    }

    async function loadBroadcasts() {
      const list = document.getElementById('bcList');
      try {
        const result = await apiRequest('/messages/broadcasts');
        if (result.broadcasts.length === 0) {
          list.innerHTML = '<div class="bc-empty">No broadcasts sent yet. Click New Broadcast to send your first one.</div>';
          return;
        }
        list.innerHTML =
          '<div class="bc-row" style="font-size:11px; font-weight:700; text-transform:uppercase; letter-spacing:0.04em; color:var(--text-muted); cursor:default;">' +
            '<div>Subject</div><div>Date Sent</div><div>Recipients</div><div>Opened</div>' +
          '</div>' +
          result.broadcasts.map(b => {
            const pct = b.recipientCount > 0 ? Math.round((b.openedCount / b.recipientCount) * 100) : 0;
            return '<div class="bc-row" onclick="window.location.href=\'inbox.html?id=' + b.id + '\'">' +
              '<div class="bc-subject">' + b.subject + '</div>' +
              '<div class="bc-date">' + new Date(b.sentAt).toLocaleString() + '</div>' +
              '<div class="bc-count">' + b.recipientCount + ' sent</div>' +
              '<div class="bc-opened">' + b.openedCount + ' opened (' + pct + '%)</div>' +
              '</div>';
          }).join('');
      } catch (err) {
        list.innerHTML = '<div class="bc-empty">' + err.message + '</div>';
      }
    }

    document.getElementById('newBroadcastBtn').addEventListener('click', async () => {
      document.getElementById('listView').style.display = 'none';
      document.getElementById('composeView').style.display = 'block';
      try {
        const result = await apiRequest('/staff?search=');
        document.getElementById('recipientCountDisplay').textContent = result.staff.length;
      } catch (err) {
        document.getElementById('recipientCountDisplay').textContent = '—';
      }
    });

    document.getElementById('cancelComposeLink').addEventListener('click', (e) => {
      e.preventDefault();
      document.getElementById('composeView').style.display = 'none';
      document.getElementById('listView').style.display = 'block';
      loadBroadcasts();
    });

    document.getElementById('sendBroadcastBtn').addEventListener('click', async () => {
      const alertEl = document.getElementById('alert');
      hideAlert(alertEl);

      const subject = document.getElementById('bcSubject').value.trim();
      const body = document.getElementById('bcBody').value.trim();

      if (!subject) { showAlert(alertEl, 'Add a subject.'); return; }
      if (!body) { showAlert(alertEl, 'Write a message.'); return; }

      const btn = document.getElementById('sendBroadcastBtn');
      btn.disabled = true;
      btn.textContent = 'Sending…';

      try {
        await apiRequest('/messages/broadcast', {
          method: 'POST',
          body: { subject, body }
        });
        document.getElementById('bcSubject').value = '';
        document.getElementById('bcBody').value = '';
        document.getElementById('composeView').style.display = 'none';
        document.getElementById('listView').style.display = 'block';
        loadBroadcasts();
      } catch (err) {
        showAlert(alertEl, err.message);
      } finally {
        btn.disabled = false;
        btn.innerHTML = '<i class="ti ti-send"></i> Send to All';
      }
    });

    init();
  </script>
</body>
</html>

EOF_ACCOUNTING_BROADCASTS_HTML

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
        <a href="compose.html" class="sidebar-link"><i class="ti ti-pencil"></i> Compose</a>
        <a href="broadcasts.html" class="sidebar-link"><i class="ti ti-speakerphone"></i> Broadcasts</a>
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
        <a href="compose.html" class="sidebar-link"><i class="ti ti-pencil"></i> Compose</a>
        <a href="broadcasts.html" class="sidebar-link"><i class="ti ti-speakerphone"></i> Broadcasts</a>
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

        <!-- LIST VIEW -->
        <div id="listView">
          <div class="email-toolbar">
            <div>
              <h1 class="page-greeting" style="font-size: 22px;">Inbox</h1>
              <p class="page-greeting-sub" style="margin:0;"><a href="dashboard.html" style="color: var(--primary); text-decoration:none; font-weight:600;">← Back to dashboard</a></p>
            </div>
            <a href="compose.html" class="btn btn-primary" style="width:auto; padding:10px 20px; text-decoration:none; display:inline-flex; align-items:center; gap:8px;"><i class="ti ti-pencil"></i> New Message</a>
          </div>

          <div class="email-list" id="emailList">
            <div class="email-empty">Loading…</div>
          </div>
        </div>

        <!-- DETAIL VIEW -->
        <div id="detailView" style="display:none;">
          <div class="email-detail-toolbar">
            <a href="inbox.html" class="email-back"><i class="ti ti-arrow-left"></i> Back to Inbox</a>
          </div>

          <div class="email-card">
            <h2 class="email-detail-subject" id="detailSubject">—</h2>
            <div id="messagesContainer"></div>
            <div class="email-action-row">
              <button class="email-action-btn" onclick="document.getElementById('replyBody').focus()"><i class="ti ti-arrow-back-up"></i> Reply</button>
              <button class="email-action-btn" onclick="document.getElementById('replyBody').focus()"><i class="ti ti-arrow-back-up-double"></i> Reply All</button>
              <button class="email-action-btn" disabled title="Coming soon" style="opacity:0.5; cursor:not-allowed;"><i class="ti ti-arrow-forward-up"></i> Forward</button>
              <button class="email-action-btn danger" onclick="deleteConversation(currentConversationId, document.getElementById('detailSubject').textContent)"><i class="ti ti-trash"></i> Delete</button>
            </div>
          </div>

          <div class="reply-box visible" id="replyBox">
            <div class="reply-box-label" id="replyLabel">Reply</div>
            <div id="attachmentPreview" style="display:none; font-size:12.5px; color:var(--text-secondary); margin-bottom:8px;">
              <i class="ti ti-paperclip"></i> <span id="attachmentName"></span>
              <button onclick="clearAttachment()" style="background:none;border:none;color:var(--error);cursor:pointer;margin-left:8px;font-size:12px;">Remove</button>
            </div>
            <div id="attachmentAlert" class="alert alert-error" style="display:none;"></div>
            <textarea id="replyBody" placeholder="Write your reply…"></textarea>
            <div class="reply-box-footer">
              <button class="reply-attach-btn" id="attachBtn" aria-label="Attach file"><i class="ti ti-paperclip"></i></button>
              <input type="file" id="fileInput" accept=".pdf,.xlsx" style="display:none;">
              <button class="btn btn-primary" id="sendReplyBtn" style="width:auto; padding:10px 22px;">Send</button>
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
    let currentConversationId = null;
    const params = new URLSearchParams(window.location.search);
    const openId = params.get('id');

    function initials(name) {
      if (!name) return '?';
      return name.split(' ').map(p => p[0]).join('').slice(0, 2).toUpperCase();
    }

    async function init() {
      try {
        const result = await apiRequest('/dashboard-check');
        currentStaffId = result.staff.id;
      } catch (err) {
        window.location.href = 'login.html';
        return;
      }

      if (openId) {
        openMessage(openId);
      } else {
        loadList();
      }
      loadUnreadBadge();
    }

    async function loadList() {
      const list = document.getElementById('emailList');
      try {
        const result = await apiRequest('/messages/conversations');
        if (result.conversations.length === 0) {
          list.innerHTML = '<div class="email-empty">No messages yet. Click New Message to start one.</div>';
          return;
        }
        list.innerHTML = result.conversations.map(c => {
          const senderName = c.displayName || 'Unknown';
          const unread = c.isUnread ? 'unread' : '';
          return '<div class="email-row ' + unread + '" onclick="window.location.href=\'inbox.html?id=' + c.id + '\'">' +
            '<div class="email-sender"><span class="email-sender-avatar">' + initials(senderName) + '</span>' + senderName + '</div>' +
            '<div class="email-subject">' + (c.subject || '(no subject)') + ' <span class="preview">— ' + (c.lastMessagePreview || 'No messages yet') + '</span></div>' +
            '<div class="email-date">' + (c.lastMessageAt ? new Date(c.lastMessageAt).toLocaleDateString() : '') + '</div>' +
            '<button class="email-row-delete" onclick="event.stopPropagation(); deleteConversation(\'' + c.id + '\', \'' + (c.subject || 'this message').replace(/'/g, "\\'") + '\')" aria-label="Delete"><i class="ti ti-trash"></i></button>' +
            '</div>';
        }).join('');
      } catch (err) {
        list.innerHTML = '<div class="email-empty">Could not load inbox.</div>';
      }
    }

    async function openMessage(id) {
      currentConversationId = id;
      document.getElementById('listView').style.display = 'none';
      document.getElementById('detailView').style.display = 'block';

      try {
        const result = await apiRequest('/messages/conversations/' + id);
        document.getElementById('detailSubject').textContent = result.subject || '(no subject)';
        document.getElementById('replyLabel').textContent = 'Replying to: ' + result.toLine;

        const container = document.getElementById('messagesContainer');
        container.innerHTML = result.messages.map(m => {
          let attachmentHtml = '';
          if (m.attachment_url) {
            const icon = m.attachment_type === 'pdf' ? 'ti-file-type-pdf' : 'ti-file-spreadsheet';
            attachmentHtml = '<a href="' + m.attachment_url + '" target="_blank" rel="noopener" class="email-attachment"><i class="ti ' + icon + '"></i> Download attachment</a>';
          }
          return '<div class="email-meta-row">' +
            '<div class="email-meta-avatar">' + initials(m.senderName) + '</div>' +
            '<div class="email-meta-text">' +
              '<div class="email-meta-from">' + m.senderName + (m.status === 'draft' ? ' (draft)' : '') + '</div>' +
              '<div class="email-meta-to">To: ' + result.toLine + '</div>' +
              '<div class="email-body-text">' + (m.body || '') + '</div>' +
              attachmentHtml +
            '</div>' +
            '<div class="email-meta-date">' + (m.sent_at ? new Date(m.sent_at).toLocaleString() : '') + '</div>' +
            '</div>';
        }).join('<hr style="border:none;border-top:1px solid var(--border);margin:16px 0;">');

        loadUnreadBadge();
      } catch (err) {
        document.getElementById('messagesContainer').innerHTML = '<div style="color:var(--text-muted);font-size:13px;">' + err.message + '</div>';
      }
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
        await apiRequest('/messages/conversations/' + currentConversationId + '/reply', {
          method: 'POST',
          body: {
            body: savedBody,
            status: 'sent',
            attachmentUrl: savedAttachment ? savedAttachment.url : undefined,
            attachmentType: savedAttachment ? savedAttachment.type : undefined
          }
        });
        openMessage(currentConversationId);
      } catch (err) {
        alert(err.message);
        textarea.value = savedBody;
        pendingAttachment = savedAttachment;
      } finally {
        sendBtn.disabled = false;
      }
    });

    let pendingAttachment = null;

    document.getElementById('attachBtn').addEventListener('click', () => {
      document.getElementById('fileInput').click();
    });

    document.getElementById('fileInput').addEventListener('change', async (e) => {
      const file = e.target.files[0];
      if (!file) return;
      const alertEl = document.getElementById('attachmentAlert');
      hideAlert(alertEl);

      const formData = new FormData();
      formData.append('attachment', file);

      try {
        const res = await fetch('/api/accounting/messages/upload', {
          method: 'POST', credentials: 'include', body: formData
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Upload failed.');
        pendingAttachment = data;
        document.getElementById('attachmentName').textContent = data.name;
        document.getElementById('attachmentPreview').style.display = 'block';
      } catch (err) {
        showAlert(alertEl, err.message);
      }
      e.target.value = '';
    });

    function clearAttachment() {
      pendingAttachment = null;
      document.getElementById('attachmentPreview').style.display = 'none';
    }

    let pendingDeleteId = null;

    function deleteConversation(id, subject) {
      pendingDeleteId = id;
      document.getElementById('deleteModalText').textContent = 'This will permanently delete "' + subject + '". This cannot be undone.';
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
      const btn = document.getElementById('deleteModalConfirm');
      hideAlert(alertEl);
      btn.disabled = true;
      btn.textContent = 'Deleting…';
      try {
        await apiRequest('/messages/conversations/' + pendingDeleteId, { method: 'DELETE' });
        document.getElementById('deleteModalBackdrop').classList.remove('visible');
        pendingDeleteId = null;
        window.location.href = 'inbox.html';
      } catch (err) {
        showAlert(alertEl, err.message);
      } finally {
        btn.disabled = false;
        btn.textContent = 'Delete';
      }
    });

    init();
  </script>
</body>
</html>

EOF_ACCOUNTING_INBOX_HTML

cat > accounting/compose.html << 'EOF_ACCOUNTING_COMPOSE_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Compose — MACDEN Portal</title>
  <link rel="stylesheet" href="assets/portal-style.css">
  <link rel="stylesheet" href="assets/portal-shell.css">
  <link rel="stylesheet" href="assets/portal-inbox.css">
  <style>
    .search-results { position: absolute; top: 100%; left: 0; right: 0; background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-sm); margin-top: 4px; max-height: 220px; overflow-y: auto; z-index: 5; display: none; box-shadow: 0 4px 12px rgba(0,0,0,0.08); }
    .search-result-item { padding: 9px 12px; cursor: pointer; font-size: 13px; display: flex; align-items: center; gap: 8px; }
    .search-result-item:hover { background: var(--surface-raised); }
  </style>
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
        <a href="inbox.html" class="sidebar-link"><i class="ti ti-mail"></i> Inbox <span class="badge" id="unreadBadge" style="display:none;">0</span></a>
        <a href="compose.html" class="sidebar-link active"><i class="ti ti-pencil"></i> Compose</a>
        <a href="broadcasts.html" class="sidebar-link"><i class="ti ti-speakerphone"></i> Broadcasts</a>
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
        <h1 class="page-greeting" style="font-size: 22px;">Compose</h1>
        <p class="page-greeting-sub"><a href="inbox.html" style="color: var(--primary); text-decoration:none; font-weight:600;">← Back to inbox</a></p>

        <div id="alert" class="alert alert-error"></div>

        <div class="compose-card">
          <div class="compose-field">
            <label>To</label>
            <div class="compose-recipients" id="recipientChips">
              <input type="text" class="compose-recipient-input" id="recipientSearch" placeholder="Search staff by name or username…">
              <div class="search-results" id="searchResults"></div>
            </div>
          </div>
          <div class="compose-field">
            <label>Subject</label>
            <input type="text" id="subject" placeholder="What's this about?">
          </div>
          <div class="compose-body-area">
            <textarea id="body" placeholder="Write your message…"></textarea>
          </div>

          <div id="attachmentPreview" style="display:none; font-size:12.5px; color:var(--text-secondary); margin-top:10px;">
            <i class="ti ti-paperclip"></i> <span id="attachmentName"></span>
            <button onclick="clearAttachment()" style="background:none;border:none;color:var(--error);cursor:pointer;margin-left:8px;font-size:12px;">Remove</button>
          </div>

          <div class="compose-footer">
            <button id="attachBtn" style="background:none;border:1px solid var(--border);border-radius:50%;width:38px;height:38px;color:var(--text-secondary);cursor:pointer;font-size:15px;"><i class="ti ti-paperclip"></i></button>
            <input type="file" id="fileInput" accept=".pdf,.xlsx" style="display:none;">
            <div style="display:flex; gap:8px;">
              <button class="btn btn-ghost" id="saveDraftBtn" style="width:auto; padding:10px 20px;">Save as Draft</button>
              <button class="btn btn-primary" id="sendBtn" style="width:auto; padding:10px 24px;">Send</button>
            </div>
          </div>
        </div>
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

    let selectedRecipients = [];
    let pendingAttachment = null;
    let searchTimeout = null;

    async function init() {
      try {
        await apiRequest('/dashboard-check');
      } catch (err) {
        window.location.href = 'login.html';
      }
      loadUnreadBadge();
    }

    const searchInput = document.getElementById('recipientSearch');
    const searchResults = document.getElementById('searchResults');

    searchInput.addEventListener('input', () => {
      clearTimeout(searchTimeout);
      const q = searchInput.value.trim();
      if (!q) { searchResults.style.display = 'none'; return; }
      searchTimeout = setTimeout(() => searchStaff(q), 250);
    });

    async function searchStaff(query) {
      try {
        const result = await apiRequest('/staff?search=' + encodeURIComponent(query));
        const available = result.staff.filter(s => !selectedRecipients.find(r => r.id === s.id));
        if (available.length === 0) {
          searchResults.innerHTML = '<div class="search-result-item" style="color:var(--text-muted);">No matches.</div>';
        } else {
          searchResults.innerHTML = available.map(s =>
            '<div class="search-result-item" onclick=\'selectRecipient(' + JSON.stringify(s) + ')\'>' +
            '<span class="presence-dot ' + (s.isOnline ? 'online' : '') + '"></span>' +
            '<span>' + s.full_name + ' · ' + s.username + '</span></div>'
          ).join('');
        }
        searchResults.style.display = 'block';
      } catch (err) {
        searchResults.style.display = 'none';
      }
    }

    function selectRecipient(staff) {
      selectedRecipients.push(staff);
      renderChips();
      searchInput.value = '';
      searchResults.style.display = 'none';
    }

    function removeRecipient(id) {
      selectedRecipients = selectedRecipients.filter(r => r.id !== id);
      renderChips();
    }

    function renderChips() {
      const chipsHtml = selectedRecipients.map(r =>
        '<span class="compose-chip">' + r.full_name + ' <button onclick="removeRecipient(\'' + r.id + '\')">×</button></span>'
      ).join('');
      const container = document.getElementById('recipientChips');
      const inputWrap = container.querySelector('#recipientSearch');
      container.innerHTML = chipsHtml + '<input type="text" class="compose-recipient-input" id="recipientSearch" placeholder="Search staff by name or username…"><div class="search-results" id="searchResults"></div>';
      document.getElementById('recipientSearch').addEventListener('input', searchInputHandler);
    }

    function searchInputHandler() {
      clearTimeout(searchTimeout);
      const q = document.getElementById('recipientSearch').value.trim();
      const sr = document.getElementById('searchResults');
      if (!q) { sr.style.display = 'none'; return; }
      searchTimeout = setTimeout(() => searchStaff(q), 250);
    }

    document.getElementById('attachBtn').addEventListener('click', () => {
      document.getElementById('fileInput').click();
    });

    document.getElementById('fileInput').addEventListener('change', async (e) => {
      const file = e.target.files[0];
      if (!file) return;
      const alertEl = document.getElementById('alert');
      hideAlert(alertEl);

      const formData = new FormData();
      formData.append('attachment', file);

      try {
        const res = await fetch('/api/accounting/messages/upload', {
          method: 'POST', credentials: 'include', body: formData
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Upload failed.');
        pendingAttachment = data;
        document.getElementById('attachmentName').textContent = data.name;
        document.getElementById('attachmentPreview').style.display = 'block';
      } catch (err) {
        showAlert(alertEl, err.message);
      }
      e.target.value = '';
    });

    function clearAttachment() {
      pendingAttachment = null;
      document.getElementById('attachmentPreview').style.display = 'none';
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
            subject: subject,
            body: body,
            status: status,
            attachmentUrl: pendingAttachment ? pendingAttachment.url : undefined,
            attachmentType: pendingAttachment ? pendingAttachment.type : undefined
          }
        });
        window.location.href = 'inbox.html?id=' + result.conversationId;
      } catch (err) {
        showAlert(alertEl, err.message);
      }
    }

    document.addEventListener('click', (e) => {
      if (!e.target.closest('.compose-recipients')) {
        const sr = document.getElementById('searchResults');
        if (sr) sr.style.display = 'none';
      }
    });

    init();
  </script>
</body>
</html>

EOF_ACCOUNTING_COMPOSE_HTML

echo "Broadcasts feature added (screens 6A + 7)."