#!/usr/bin/env bash
# TIGHTENING BATCH 5: per-recipient broadcast read status ('who's read
# this?'), a real 'Suggest a Policy' channel via Compose pre-fill, and
# an Admin Activity dashboard tying together the audit log with real
# leave/broadcast stats. Caught and fixed a real duplication bug in
# compose.html mid-build.
# NO SQL MIGRATION NEEDED for this batch.
# Run this from the ROOT of your macden-website repo, in Git Bash.
set -e

mkdir -p server/routes accounting

cat > server/routes/messages.js << 'EOF_SERVER_ROUTES_MESSAGES_JS'
const express = require('express');
const multer = require('multer');
const supabase = require('../config/supabaseClient');
const { isOnline } = require('./staff');
const { sendNotificationEmail } = require('../utils/email');

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

// Sends a real email notification to each recipient who has the relevant
// preference toggled on (Settings > Notifications). This actually wires up
// those toggles for real, instead of them just being saved and ignored.
// One failed send doesn't block the others — each is caught individually.
async function notifyRecipientsByEmail(staffIds, prefColumn, senderName, subject, bodyPreview, link) {
  if (!staffIds || staffIds.length === 0) return;

  const { data: recipients } = await supabase
    .from('staff')
    .select('id, full_name, email, ' + prefColumn)
    .in('id', staffIds)
    .eq(prefColumn, true);

  if (!recipients || recipients.length === 0) return;

  const fullLink = 'https://macden.com.ng/accounting/' + link;

  await Promise.allSettled(recipients.map(r =>
    sendNotificationEmail(
      r.email,
      r.full_name,
      subject,
      `Hi ${r.full_name},\n\n${senderName ? senderName + ' sent you a message' : subject} on the MACDEN Portal:\n\n"${bodyPreview}"\n\nView it here: ${fullLink}\n\n(You can turn off these emails anytime in Settings > Notifications.)`,
      `<p>Hi ${r.full_name},</p>
       <p>${senderName ? senderName + ' sent you a message' : subject} on the MACDEN Portal:</p>
       <p style="background:#f2f3f5; padding:12px 16px; border-radius:8px;">${bodyPreview}</p>
       <p><a href="${fullLink}">View it on the portal</a></p>
       <p style="font-size:12px; color:#888;">You can turn off these emails anytime in Settings &gt; Notifications.</p>`
    ).catch(err => console.error('Notification email failed for', r.email, ':', err.message))
  ));
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
  try {
    const { count, error } = await supabase
      .from('message_reads')
      .select('*', { count: 'exact', head: true })
      .eq('staff_id', req.session.staff.id)
      .is('read_at', null);

    if (error) {
      console.error('Unread count error:', error);
      return res.status(500).json({ error: 'Could not load unread count.' });
    }

    res.json({ unreadCount: count });
  } catch (err) {
    console.error('Unread count unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

router.get('/conversations', async (req, res) => {
  try {
    const staffId = req.session.staff.id;

    const { data: memberRows, error: memberError } = await supabase
      .from('conversation_members')
      .select('conversation_id')
      .eq('staff_id', staffId);

    if (memberError) {
      console.error('Conversation members fetch error:', memberError);
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
      console.error('Conversations fetch error:', convError);
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
  } catch (err) {
    console.error('Conversations list unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading your inbox.' });
  }
});

router.get('/conversations/:id', async (req, res) => {
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
      console.error('Conversation messages fetch error:', error);
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
  } catch (err) {
    console.error('Conversation detail unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading this conversation.' });
  }
});

router.post('/compose', async (req, res) => {
  try {
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
      console.error('Compose conversation insert error:', convError);
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
      console.error('Compose message insert error:', msgError);
      return res.status(500).json({ error: 'Could not send message.' });
    }

    if (isSent) {
      await createReadRowsForRecipients(conversation.id, message.id, staffId);
      notifyRecipientsByEmail(
        recipientIds, 'notify_email_messages', req.session.staff.fullName,
        subject.trim(), (body || '').slice(0, 150), 'inbox.html?id=' + conversation.id
      ).catch(err => console.error('Compose email notify error:', err));
    }

    res.json({ success: true, conversationId: conversation.id, messageId: message.id });
  } catch (err) {
    console.error('Compose unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong sending this message.' });
  }
});

router.post('/conversations/:id/reply', async (req, res) => {
  try {
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
      console.error('Reply insert error:', error);
      return res.status(500).json({ error: 'Could not send message.' });
    }

    if (isSent) {
      await createReadRowsForRecipients(id, message.id, staffId);
      const otherParticipants = await getOtherParticipants(id, staffId);
      notifyRecipientsByEmail(
        otherParticipants.map(p => p.id), 'notify_email_messages', req.session.staff.fullName,
        'New reply on the MACDEN Portal', (body || '').slice(0, 150), 'inbox.html?id=' + id
      ).catch(err => console.error('Reply email notify error:', err));
    }

    res.json({ success: true, message });
  } catch (err) {
    console.error('Reply unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong sending your reply.' });
  }
});

router.get('/drafts', async (req, res) => {
  try {
    const staffId = req.session.staff.id;

    const { data: drafts, error } = await supabase
      .from('messages')
      .select('id, conversation_id, body, created_at')
      .eq('sender_id', staffId)
      .eq('status', 'draft')
      .order('created_at', { ascending: false });

    if (error) {
      console.error('Drafts fetch error:', error);
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
  } catch (err) {
    console.error('Drafts unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading your drafts.' });
  }
});

router.put('/:id', async (req, res) => {
  try {
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
      console.error('Draft update error:', updateError);
      return res.status(500).json({ error: 'Could not update message.' });
    }

    if (isSending) {
      await createReadRowsForRecipients(existing.conversation_id, id, staffId);
    }

    res.json({ success: true, message: updated });
  } catch (err) {
    console.error('Draft update unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong updating this message.' });
  }
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
    notifyRecipientsByEmail(
      allActiveStaff.map(s => s.id), 'notify_email_broadcasts', null,
      subject.trim(), body.trim().slice(0, 150), 'inbox.html?id=' + conversation.id
    ).catch(err => console.error('Broadcast email notify error:', err));

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

// GET /api/accounting/messages/broadcasts/:id/reads — admin-only, exactly
// who has and hasn't opened this specific broadcast, not just a percentage.
router.get('/broadcasts/:id/reads', async (req, res) => {
  try {
    if (req.session.staff.role !== 'admin') {
      return res.status(403).json({ error: 'Only admins can view this.' });
    }

    const { data: message } = await supabase
      .from('messages')
      .select('id')
      .eq('conversation_id', req.params.id)
      .eq('status', 'sent')
      .limit(1)
      .maybeSingle();

    if (!message) {
      return res.status(404).json({ error: 'Broadcast message not found.' });
    }

    const { data: reads, error } = await supabase
      .from('message_reads')
      .select('staff_id, read_at')
      .eq('message_id', message.id);

    if (error) {
      console.error('Broadcast reads fetch error:', error);
      return res.status(500).json({ error: 'Could not load read status.' });
    }

    const staffIds = reads.map(r => r.staff_id);
    const { data: staffRows } = await supabase
      .from('staff')
      .select('id, full_name')
      .in('id', staffIds.length > 0 ? staffIds : ['00000000-0000-0000-0000-000000000000']);
    const nameById = {};
    (staffRows || []).forEach(s => { nameById[s.id] = s.full_name; });

    const recipients = reads
      .map(r => ({
        fullName: nameById[r.staff_id] || 'Unknown',
        hasRead: r.read_at !== null,
        readAt: r.read_at
      }))
      .sort((a, b) => {
        if (a.hasRead !== b.hasRead) return a.hasRead ? 1 : -1; // unread first
        return a.fullName.localeCompare(b.fullName);
      });

    res.json({ recipients });
  } catch (err) {
    console.error('Broadcast reads unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading read status.' });
  }
});

module.exports = router;

EOF_SERVER_ROUTES_MESSAGES_JS

cat > server/routes/admin.js << 'EOF_SERVER_ROUTES_ADMIN_JS'
const express = require('express');
const bcrypt = require('bcrypt');
const crypto = require('crypto');
const supabase = require('../config/supabaseClient');
const { sendWelcomeEmail } = require('../utils/email');
const { encrypt, decrypt } = require('../utils/encryption');

const router = express.Router();

// Only staff with role = 'admin' can reach these routes.
function requireAdmin(req, res, next) {
  if (req.session.staff.role !== 'admin') {
    return res.status(403).json({ error: 'Admin access only.' });
  }
  next();
}

// Logs sensitive admin actions (who did what, when, from where) — closes the
// "who touched HR data" gap flagged when NIN/address fields were first added.
// Fire-and-forget: a logging failure should never block the actual action.
function logAdminAction(req, action, targetId, details) {
  supabase
    .from('admin_audit_log')
    .insert({
      staff_id: req.session.staff.id,
      action,
      target_id: targetId ? String(targetId) : null,
      details: details || null,
      ip_address: req.ip || req.headers['x-forwarded-for'] || null
    })
    .then(({ error }) => {
      if (error) console.error('Audit log insert failed:', error);
    });
}

router.use(requireAdmin);

// GET /api/accounting/admin/departments — for the onboarding Work Info dropdown
router.get('/departments', async (req, res) => {
  try {
    const { data, error } = await supabase.from('departments').select('id, name').order('name');
    if (error) {
      return res.status(500).json({ error: 'Could not load departments.' });
    }
    res.json({ departments: data });
  } catch (err) {
    console.error('Departments fetch error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// GET /api/accounting/admin/all-staff — everyone including inactive, for Manage Staff
router.get('/all-staff', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('staff')
      .select('id, full_name, username, email, role, phone, branch, is_active, created_at, departments(name)')
      .order('full_name');

    if (error) {
      console.error('All-staff fetch error:', error);
      return res.status(500).json({ error: 'Could not load staff.' });
    }

    const staff = data.map(s => ({
      id: s.id,
      fullName: s.full_name,
      username: s.username,
      email: s.email,
      role: s.role,
      phone: s.phone,
      branch: s.branch,
      department: s.departments ? s.departments.name : null,
      isActive: s.is_active,
      dateStarted: s.created_at
    }));

    res.json({ staff });
  } catch (err) {
    console.error('All-staff unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading staff.' });
  }
});

// POST /api/accounting/admin/onboard-staff — HR-initiated account creation
router.post('/onboard-staff', async (req, res) => {
  try {
    const { fullName, email, phone, nin, address, role, departmentId, branch, dateStarted, reportsTo } = req.body;

    if (!fullName || !email || !role || !departmentId) {
      return res.status(400).json({ error: 'Full name, email, role, and department are required.' });
    }

    // Generate a username from the name, and a random temporary password
    const baseUsername = fullName.toLowerCase().replace(/[^a-z]+/g, '.').replace(/^\.|\.$/g, '');
    const username = baseUsername + '.' + crypto.randomInt(100, 999);
    // Longer temp password (was 10 chars, now 14) — generate extra bytes
    // since base64/alphanumeric stripping shrinks the usable length.
    const tempPassword = crypto.randomBytes(14).toString('base64').replace(/[^a-zA-Z0-9]/g, '').slice(0, 14);
    const passwordHash = await bcrypt.hash(tempPassword, 10);

    const { data, error } = await supabase
      .from('staff')
      .insert({
        full_name: fullName,
        username: username,
        email: email,
        password_hash: passwordHash,
        role: role,
        department_id: departmentId,
        phone: phone || null,
        nin: nin ? encrypt(nin) : null,
        address: address ? encrypt(address) : null,
        branch: branch || null,
        reports_to: reportsTo || null,
        email_verified: true,  // HR-created accounts are trusted, skip the self-signup flow
        is_active: true,
        must_change_password: true
      })
      .select()
      .single();

    if (error) {
      console.error('Onboard staff insert error:', error);
      return res.status(400).json({ error: 'Could not create account. Email may already be in use.' });
    }

    try {
      await sendWelcomeEmail(email, fullName, username, tempPassword);
    } catch (emailErr) {
      console.error('Welcome email failed:', emailErr);
      // Account was created successfully even if the email failed — tell the admin so they can share credentials manually
      return res.json({
        success: true,
        staff: data,
        warning: 'Account created, but the welcome email failed to send. Username: ' + username + ', temporary password: ' + tempPassword
      });
    }

    logAdminAction(req, 'onboard_staff', data.id, `Created account for ${fullName} (${email})`);
    res.json({ success: true, staff: data });
  } catch (err) {
    console.error('Onboard staff unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong creating this account.' });
  }
});

// PUT /api/accounting/admin/staff/:id — edit an existing staff member
router.put('/staff/:id', async (req, res) => {
  try {
    const { fullName, role, departmentId, phone, branch } = req.body;

    const { error } = await supabase
      .from('staff')
      .update({
        full_name: fullName,
        role: role,
        department_id: departmentId,
        phone: phone || null,
        branch: branch || null
      })
      .eq('id', req.params.id);

    if (error) {
      return res.status(500).json({ error: 'Could not update this account.' });
    }
    logAdminAction(req, 'edit_staff', req.params.id, `Updated profile fields (role/department/phone/branch)`);
    res.json({ success: true });
  } catch (err) {
    console.error('Staff edit unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// POST /api/accounting/admin/staff/:id/reactivate
router.post('/staff/:id/reactivate', async (req, res) => {
  try {
    const { error } = await supabase.from('staff').update({ is_active: true }).eq('id', req.params.id);
    if (error) {
      return res.status(500).json({ error: 'Could not reactivate this account.' });
    }
    logAdminAction(req, 'reactivate_staff', req.params.id, 'Reactivated account');
    res.json({ success: true });
  } catch (err) {
    console.error('Reactivate unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// GET /api/accounting/admin/pending-staff
// Lists everyone who has verified their email but is still waiting on approval.
router.get('/pending-staff', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('staff')
      .select('id, full_name, username, email, created_at')
      .eq('email_verified', true)
      .eq('is_active', false)
      .order('created_at', { ascending: true });

    if (error) {
      console.error('Pending staff fetch error:', error);
      return res.status(500).json({ error: 'Could not load pending accounts.' });
    }

    res.json({ pending: data });
  } catch (err) {
    console.error('Pending staff unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// POST /api/accounting/admin/approve-staff/:id
router.post('/approve-staff/:id', async (req, res) => {
  try {
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

    logAdminAction(req, 'approve_staff', id, `Approved ${data.full_name}`);
    res.json({ success: true, message: `${data.full_name} has been approved and can now log in.` });
  } catch (err) {
    console.error('Approve staff unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong approving this account.' });
  }
});

// DELETE /api/accounting/admin/staff/:id
// Deactivates a staff member (soft-disable, not a hard delete — their past
// messages and price edits stay intact) and clears any shared conversation
// with the admin performing this action.
router.delete('/staff/:id', async (req, res) => {
  try {
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
      console.error('Deactivate staff error:', error);
      return res.status(500).json({ error: 'Could not deactivate this account.' });
    }

    logAdminAction(req, 'deactivate_staff', id, 'Deactivated account');
    res.json({ success: true });
  } catch (err) {
    console.error('Deactivate staff unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong deactivating this account.' });
  }
});

// GET /api/accounting/admin/audit-log — recent sensitive admin actions
router.get('/audit-log', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('admin_audit_log')
      .select('id, staff_id, action, target_id, details, created_at')
      .order('created_at', { ascending: false })
      .limit(25);

    if (error) {
      console.error('Audit log fetch error:', error);
      return res.status(500).json({ error: 'Could not load the audit log.' });
    }

    const staffIds = [...new Set(data.map(l => l.staff_id).filter(Boolean))];
    const { data: staffRows } = await supabase
      .from('staff')
      .select('id, full_name')
      .in('id', staffIds.length > 0 ? staffIds : ['00000000-0000-0000-0000-000000000000']);
    const nameById = {};
    (staffRows || []).forEach(s => { nameById[s.id] = s.full_name; });

    const entries = data.map(l => ({
      ...l,
      staffName: nameById[l.staff_id] || 'Unknown'
    }));

    res.json({ entries });
  } catch (err) {
    console.error('Audit log unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading the audit log.' });
  }
});

module.exports = router;

EOF_SERVER_ROUTES_ADMIN_JS

cat > server/routes/leave.js << 'EOF_SERVER_ROUTES_LEAVE_JS'
const express = require('express');
const supabase = require('../config/supabaseClient');

const router = express.Router();

function daysBetween(startDate, endDate) {
  const start = new Date(startDate);
  const end = new Date(endDate);
  const diffMs = end - start;
  return Math.round(diffMs / (1000 * 60 * 60 * 24)) + 1; // inclusive of both days
}

// POST /api/accounting/leave — submit a new leave request
router.post('/', async (req, res) => {
  try {
    const { leaveType, startDate, endDate, reason } = req.body;
    const staffId = req.session.staff.id;

    if (!leaveType || !startDate || !endDate) {
      return res.status(400).json({ error: 'Leave type, start date, and end date are required.' });
    }

    if (new Date(endDate) < new Date(startDate)) {
      return res.status(400).json({ error: 'End date cannot be before start date.' });
    }

    const { data, error } = await supabase
      .from('leave_requests')
      .insert({
        staff_id: staffId,
        leave_type: leaveType,
        start_date: startDate,
        end_date: endDate,
        reason: reason || null
      })
      .select()
      .single();

    if (error) {
      console.error('Leave request insert error:', error);
      return res.status(500).json({ error: 'Could not submit leave request.' });
    }

    res.json({ success: true, request: data });
  } catch (err) {
    console.error('Leave submit unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong submitting your request.' });
  }
});

// GET /api/accounting/leave/mine — this staff member's own requests
router.get('/mine', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('leave_requests')
      .select('id, leave_type, start_date, end_date, reason, status, requested_at')
      .eq('staff_id', req.session.staff.id)
      .order('requested_at', { ascending: false });

    if (error) {
      console.error('Leave mine fetch error:', error);
      return res.status(500).json({ error: 'Could not load your requests.' });
    }

    const withDays = data.map(r => ({ ...r, days: daysBetween(r.start_date, r.end_date) }));
    res.json({ requests: withDays });
  } catch (err) {
    console.error('Leave mine unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading your requests.' });
  }
});

// GET /api/accounting/leave/pending — admin-only, everyone's pending requests
router.get('/pending', async (req, res) => {
  try {
    if (req.session.staff.role !== 'admin') {
      return res.status(403).json({ error: 'Only admins can view pending approvals.' });
    }

    const { data, error } = await supabase
      .from('leave_requests')
      .select('id, staff_id, leave_type, start_date, end_date, reason, status, requested_at')
      .eq('status', 'pending')
      .order('requested_at', { ascending: true });

    if (error) {
      console.error('Leave pending fetch error:', error);
      return res.status(500).json({ error: 'Could not load pending requests.' });
    }

    const staffIds = [...new Set(data.map(r => r.staff_id))];
    const { data: staffRows } = await supabase
      .from('staff')
      .select('id, full_name, username, is_active')
      .in('id', staffIds.length > 0 ? staffIds : ['00000000-0000-0000-0000-000000000000']);
    const staffById = {};
    (staffRows || []).forEach(s => { staffById[s.id] = s; });

    const enriched = data.map(r => ({
      ...r,
      days: daysBetween(r.start_date, r.end_date),
      staffName: staffById[r.staff_id] ? staffById[r.staff_id].full_name : 'Unknown',
      staffUsername: staffById[r.staff_id] ? staffById[r.staff_id].username : '',
      staffIsActive: staffById[r.staff_id] ? staffById[r.staff_id].is_active : true
    }));

    res.json({ requests: enriched });
  } catch (err) {
    console.error('Leave pending unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading pending requests.' });
  }
});

// POST /api/accounting/leave/:id/approve — admin-only
router.post('/:id/approve', async (req, res) => {
  try {
    if (req.session.staff.role !== 'admin') {
      return res.status(403).json({ error: 'Only admins can approve requests.' });
    }

    const { error } = await supabase
      .from('leave_requests')
      .update({ status: 'approved', reviewed_by: req.session.staff.id, reviewed_at: new Date().toISOString() })
      .eq('id', req.params.id);

    if (error) {
      return res.status(500).json({ error: 'Could not approve this request.' });
    }
    res.json({ success: true });
  } catch (err) {
    console.error('Leave approve unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// POST /api/accounting/leave/:id/reject — admin-only
router.post('/:id/reject', async (req, res) => {
  try {
    if (req.session.staff.role !== 'admin') {
      return res.status(403).json({ error: 'Only admins can reject requests.' });
    }

    const { error } = await supabase
      .from('leave_requests')
      .update({ status: 'rejected', reviewed_by: req.session.staff.id, reviewed_at: new Date().toISOString() })
      .eq('id', req.params.id);

    if (error) {
      return res.status(500).json({ error: 'Could not reject this request.' });
    }
    res.json({ success: true });
  } catch (err) {
    console.error('Leave reject unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// GET /api/accounting/leave/stats — admin-only, last 30 days summary
router.get('/stats', async (req, res) => {
  try {
    if (req.session.staff.role !== 'admin') {
      return res.status(403).json({ error: 'Only admins can view stats.' });
    }

    const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
    const { data, error } = await supabase
      .from('leave_requests')
      .select('status, requested_at, reviewed_at')
      .not('reviewed_at', 'is', null)
      .gte('reviewed_at', thirtyDaysAgo);

    if (error) {
      console.error('Leave stats fetch error:', error);
      return res.status(500).json({ error: 'Could not load leave stats.' });
    }

    const approvedCount = data.filter(r => r.status === 'approved').length;
    const rejectedCount = data.filter(r => r.status === 'rejected').length;

    let avgTurnaroundHours = null;
    if (data.length > 0) {
      const totalHours = data.reduce((sum, r) => {
        const hours = (new Date(r.reviewed_at) - new Date(r.requested_at)) / (1000 * 60 * 60);
        return sum + hours;
      }, 0);
      avgTurnaroundHours = Math.round(totalHours / data.length);
    }

    res.json({ approvedCount, rejectedCount, avgTurnaroundHours });
  } catch (err) {
    console.error('Leave stats unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading leave stats.' });
  }
});

module.exports = router;

EOF_SERVER_ROUTES_LEAVE_JS

cat > accounting/admin-dashboard.html << 'EOF_ACCOUNTING_ADMIN-DASHBOARD_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Admin Activity — MACDEN Portal</title>
  <link rel="stylesheet" href="assets/portal-style.css">
  <link rel="stylesheet" href="assets/portal-shell.css">
  <link rel="stylesheet" href="assets/portal-inbox.css">
  <style>
    .ad-stat-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; margin-bottom: 24px; }
    .ad-audit-list { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-md); overflow: hidden; }
    .ad-audit-row { display: grid; grid-template-columns: 150px 160px 1fr 140px; gap: 12px; padding: 12px 18px; border-bottom: 1px solid var(--border); font-size: 12.5px; }
    .ad-audit-row:last-child { border-bottom: none; }
    .ad-audit-row.header { font-size: 10.5px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.04em; color: var(--text-muted); }
    .ad-action-tag { display: inline-block; padding: 2px 8px; border-radius: 999px; font-size: 10.5px; font-weight: 700; background: var(--primary-dim); color: var(--primary); }
  </style>
</head>
<body>
  <div class="app-shell">
    <div class="sidebar">
      <div class="sidebar-brand"><img src="assets/logo.jpeg" alt="MACDEN"><span>MACDEN</span></div>
      <nav class="sidebar-nav">
        <a href="dashboard.html" class="sidebar-link"><i class="ti ti-layout-dashboard"></i> Dashboard</a>
        <a href="inbox.html" class="sidebar-link"><i class="ti ti-mail"></i> Inbox <span class="badge" id="unreadBadge" style="display:none;">0</span></a>
        <a href="compose.html" class="sidebar-link"><i class="ti ti-pencil"></i> Compose</a>
        <a href="broadcasts.html" class="sidebar-link"><i class="ti ti-speakerphone"></i> Broadcasts</a>
        <a href="directory.html" class="sidebar-link"><i class="ti ti-users"></i> Directory</a>
        <a href="leave.html" class="sidebar-link"><i class="ti ti-calendar-event"></i> Leave &amp; Requests</a>
        <a href="documents.html" class="sidebar-link"><i class="ti ti-file-text"></i> Documents</a>
        <a href="policies.html" class="sidebar-link"><i class="ti ti-book"></i> Policies</a>
        <a href="settings.html" class="sidebar-link"><i class="ti ti-settings"></i> Settings</a>
      </nav>
      <div class="sidebar-logout">
        <a href="help.html" class="sidebar-link" style="margin-bottom:6px;"><i class="ti ti-help-circle"></i> Help</a>
        <button id="logoutBtn"><i class="ti ti-logout"></i> Logout</button>
      </div>
    </div>

    <div class="main-content">
      <div class="topbar">
        <div class="topbar-search"><input type="text" placeholder="Search messages, people, documents…"></div>
        <div class="notif-wrap">
          <button class="topbar-bell" id="notifBell" aria-label="Notifications"><i class="ti ti-bell"></i><span class="dot" id="notifDot" style="display:none;">0</span></button>
          <div class="notif-dropdown" id="notifDropdown"></div>
        </div>
        <img class="topbar-avatar" src="assets/logo.jpeg" alt="You">
      </div>

      <div class="page-body">
        <h1 class="page-greeting" style="font-size: 22px;">Admin Activity</h1>
        <p class="page-greeting-sub" id="notAdminNote" style="display:none;">Admin access only.</p>
        <p class="page-greeting-sub" id="pageSub"><a href="dashboard.html" style="color: var(--primary); text-decoration:none; font-weight:600;">← Back to dashboard</a></p>

        <div id="content" style="display:none;">
          <div class="ad-stat-grid">
            <div class="stat-card"><div class="num" id="statBroadcasts">—</div><div class="lbl">Broadcasts (30 days)</div></div>
            <div class="stat-card"><div class="num" id="statApproved">—</div><div class="lbl">Leave Approved (30 days)</div></div>
            <div class="stat-card"><div class="num" id="statRejected">—</div><div class="lbl">Leave Rejected (30 days)</div></div>
            <div class="stat-card"><div class="num" id="statTurnaround">—</div><div class="lbl">Avg. Approval Turnaround</div></div>
          </div>

          <h2 style="font-size: 15.5px; margin-bottom: 12px;">Recent Admin Activity</h2>
          <div class="ad-audit-list">
            <div class="ad-audit-row header"><div>Admin</div><div>Action</div><div>Details</div><div>When</div></div>
            <div id="auditRows"><div class="doc-empty">Loading…</div></div>
          </div>
        </div>
      </div>
    </div>
  </div>

  <script src="assets/api.js"></script>
  <script src="assets/presence.js"></script>
  <script src="assets/notifications.js"></script>
  <script>
    document.getElementById('logoutBtn').addEventListener('click', async () => {
      await apiRequest('/auth/logout', { method: 'POST' });
      window.location.href = 'login.html';
    });

    const actionLabels = {
      onboard_staff: 'Onboarded staff',
      edit_staff: 'Edited staff',
      deactivate_staff: 'Deactivated staff',
      reactivate_staff: 'Reactivated staff',
      approve_staff: 'Approved staff'
    };

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
        document.getElementById('notAdminNote').style.display = 'block';
        document.getElementById('pageSub').style.display = 'none';
        return;
      }

      document.getElementById('content').style.display = 'block';
      loadUnreadBadge();
      loadStats();
      loadAuditLog();
    }

    async function loadStats() {
      try {
        const leaveStats = await apiRequest('/leave/stats');
        document.getElementById('statApproved').textContent = leaveStats.approvedCount;
        document.getElementById('statRejected').textContent = leaveStats.rejectedCount;
        document.getElementById('statTurnaround').textContent = leaveStats.avgTurnaroundHours !== null ? leaveStats.avgTurnaroundHours + 'h' : '—';
      } catch (err) {}

      try {
        const bc = await apiRequest('/messages/broadcasts');
        const thirtyDaysAgo = Date.now() - 30 * 24 * 60 * 60 * 1000;
        const recent = bc.broadcasts.filter(b => new Date(b.sentAt).getTime() > thirtyDaysAgo);
        document.getElementById('statBroadcasts').textContent = recent.length;
      } catch (err) {}
    }

    async function loadAuditLog() {
      const rows = document.getElementById('auditRows');
      try {
        const result = await apiRequest('/admin/audit-log');
        if (result.entries.length === 0) {
          rows.innerHTML = '<div class="doc-empty">No admin activity logged yet.</div>';
          return;
        }
        rows.innerHTML = result.entries.map(e =>
          '<div class="ad-audit-row">' +
            '<div>' + e.staffName + '</div>' +
            '<div><span class="ad-action-tag">' + (actionLabels[e.action] || e.action) + '</span></div>' +
            '<div>' + (e.details || '—') + '</div>' +
            '<div>' + new Date(e.created_at).toLocaleString() + '</div>' +
          '</div>'
        ).join('');
      } catch (err) {
        rows.innerHTML = '<div class="doc-empty">Could not load audit log.</div>';
      }
    }

    init();
  </script>
</body>
</html>

EOF_ACCOUNTING_ADMIN-DASHBOARD_HTML

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
        <a href="directory.html" class="sidebar-link"><i class="ti ti-users"></i> Directory</a>
        <a href="leave.html" class="sidebar-link"><i class="ti ti-calendar-event"></i> Leave &amp; Requests</a>
        <a href="documents.html" class="sidebar-link"><i class="ti ti-file-text"></i> Documents</a>
        <a href="policies.html" class="sidebar-link"><i class="ti ti-book"></i> Policies</a>
        <a href="settings.html" class="sidebar-link"><i class="ti ti-settings"></i> Settings</a>
      </nav>
      <div class="sidebar-logout">
        <a href="help.html" class="sidebar-link" style="margin-bottom:6px;"><i class="ti ti-help-circle"></i> Help</a>
        <button id="logoutBtn"><i class="ti ti-logout"></i> Logout</button>
      </div>
    </div>

    <div class="main-content">
      <div class="topbar">
        <div class="topbar-search"><input type="text" placeholder="Search messages, people, documents…"></div>
        <div class="notif-wrap">
          <button class="topbar-bell" id="notifBell" aria-label="Notifications"><i class="ti ti-bell"></i><span class="dot" id="notifDot" style="display:none;">0</span></button>
          <div class="notif-dropdown" id="notifDropdown"></div>
        </div>
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

  <div class="modal-backdrop" id="readsModalBackdrop">
    <div class="modal" style="width: 380px;">
      <h3 id="readsModalTitle">Who's read this?</h3>
      <div id="readsModalList" style="max-height: 320px; overflow-y: auto; margin-top: 12px;"></div>
      <div class="modal-actions">
        <button class="btn btn-ghost" onclick="document.getElementById('readsModalBackdrop').classList.remove('visible')">Close</button>
      </div>
    </div>
  </div>

  <script src="assets/api.js"></script>
  <script src="assets/notifications.js"></script>
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
            '<div>Subject</div><div>Date Sent</div><div>Recipients</div><div>Opened</div><div></div>' +
          '</div>' +
          result.broadcasts.map(b => {
            const pct = b.recipientCount > 0 ? Math.round((b.openedCount / b.recipientCount) * 100) : 0;
            return '<div class="bc-row" onclick="window.location.href=\'inbox.html?id=' + b.id + '\'">' +
              '<div class="bc-subject">' + b.subject + '</div>' +
              '<div class="bc-date">' + new Date(b.sentAt).toLocaleString() + '</div>' +
              '<div class="bc-count">' + b.recipientCount + ' sent</div>' +
              '<div class="bc-opened">' + b.openedCount + ' opened (' + pct + '%)</div>' +
              '<div><button style="border:1px solid var(--border); border-radius:var(--radius-sm); padding:6px 12px; font-size:11.5px; font-weight:600; color:var(--text-primary); background:none; cursor:pointer; font-family:var(--font-body);" onclick="event.stopPropagation(); viewReadStatus(\'' + b.id + '\', \'' + b.subject.replace(/'/g, "\\'") + '\')">Who\\'s read this?</button></div>' +
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

    async function viewReadStatus(conversationId, subject) {
      document.getElementById('readsModalTitle').textContent = subject;
      const listEl = document.getElementById('readsModalList');
      listEl.innerHTML = '<div style="text-align:center; padding:20px; color:var(--text-muted); font-size:13px;">Loading…</div>';
      document.getElementById('readsModalBackdrop').classList.add('visible');

      try {
        const result = await apiRequest('/messages/broadcasts/' + conversationId + '/reads');
        if (result.recipients.length === 0) {
          listEl.innerHTML = '<div style="text-align:center; padding:20px; color:var(--text-muted); font-size:13px;">No recipients found.</div>';
          return;
        }
        listEl.innerHTML = result.recipients.map(r =>
          '<div style="display:flex; justify-content:space-between; align-items:center; padding:9px 0; border-bottom:1px solid var(--border); font-size:13px;">' +
            '<span>' + r.fullName + '</span>' +
            (r.hasRead
              ? '<span style="color:var(--success); font-size:11.5px; font-weight:600;"><i class="ti ti-check"></i> Read ' + new Date(r.readAt).toLocaleDateString() + '</span>'
              : '<span style="color:var(--text-muted); font-size:11.5px;">Not opened yet</span>') +
          '</div>'
        ).join('');
      } catch (err) {
        listEl.innerHTML = '<div style="text-align:center; padding:20px; color:var(--error); font-size:13px;">' + err.message + '</div>';
      }
    }

    init();
  </script>
</body>
</html>

EOF_ACCOUNTING_BROADCASTS_HTML

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
        <a href="directory.html" class="sidebar-link"><i class="ti ti-users"></i> Directory</a>
        <a href="leave.html" class="sidebar-link"><i class="ti ti-calendar-event"></i> Leave &amp; Requests</a>
        <a href="documents.html" class="sidebar-link"><i class="ti ti-file-text"></i> Documents</a>
        <a href="policies.html" class="sidebar-link"><i class="ti ti-book"></i> Policies</a>
        <a href="settings.html" class="sidebar-link"><i class="ti ti-settings"></i> Settings</a>
      </nav>
      <div class="sidebar-logout">
        <a href="help.html" class="sidebar-link" style="margin-bottom:6px;"><i class="ti ti-help-circle"></i> Help</a>
        <button id="logoutBtn"><i class="ti ti-logout"></i> Logout</button>
      </div>
    </div>

    <div class="main-content">
      <div class="topbar">
        <div class="topbar-search"><input type="text" placeholder="Search messages, people, documents…"></div>
        <div class="notif-wrap">
          <button class="topbar-bell" id="notifBell" aria-label="Notifications"><i class="ti ti-bell"></i><span class="dot" id="notifDot" style="display:none;">0</span></button>
          <div class="notif-dropdown" id="notifDropdown"></div>
        </div>
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
            <button id="attachBtn" aria-label="Attach file" style="background:none;border:1px solid var(--border);border-radius:50%;width:38px;height:38px;color:var(--text-secondary);cursor:pointer;font-size:15px;"><i class="ti ti-paperclip"></i></button>
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
  <script src="assets/notifications.js"></script>
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
        return;
      }
      loadUnreadBadge();

      const params = new URLSearchParams(window.location.search);
      const prefillId = params.get('to');
      const prefillName = params.get('name');
      if (prefillId && prefillName) {
        selectedRecipients.push({ id: prefillId, full_name: decodeURIComponent(prefillName) });
        renderChips();
      }

      const prefillSubject = params.get('subject');
      if (prefillSubject) {
        document.getElementById('subject').value = decodeURIComponent(prefillSubject);
        document.getElementById('body').focus();
      }
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

cat > accounting/policies.html << 'EOF_ACCOUNTING_POLICIES_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Policies — MACDEN Portal</title>
  <link rel="stylesheet" href="assets/portal-style.css">
  <link rel="stylesheet" href="assets/portal-shell.css">
  <link rel="stylesheet" href="assets/portal-inbox.css">
  <style>
    .pol-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; }
    .pol-card { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-md); padding: 20px; }
    .pol-card h3 { font-size: 14.5px; margin: 0 0 8px; }
    .pol-card p { font-size: 12.5px; color: var(--text-secondary); margin: 0 0 14px; line-height: 1.5; }
    .pol-card .updated { font-size: 11.5px; color: var(--text-muted); margin-bottom: 12px; }
    .pol-card-actions { display: flex; gap: 8px; }
    .pol-read-btn { border: 1px solid var(--border); border-radius: var(--radius-sm); padding: 7px 14px; font-size: 12px; font-weight: 600; color: var(--text-primary); background: none; cursor: pointer; font-family: var(--font-body); }
    .pol-read-btn:hover { border-color: var(--primary); color: var(--primary); }
    .pol-empty { padding: 60px 20px; text-align: center; color: var(--text-muted); font-size: 13px; grid-column: 1 / -1; }

    #detailView .email-card { max-width: 720px; }
    #detailView .email-body-text { font-size: 13.5px; line-height: 1.75; }

    .pol-form-field { margin-bottom: 14px; }
    .pol-form-field label { display: block; font-size: 12.5px; font-weight: 600; margin-bottom: 6px; }
    .pol-form-field input, .pol-form-field textarea {
      width: 100%; background: var(--surface-raised); border: 1px solid var(--border); border-radius: var(--radius-sm);
      padding: 10px 12px; font-size: 13px; font-family: var(--font-body); color: var(--text-primary);
    }
    .pol-form-field textarea { min-height: 200px; resize: vertical; }
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
        <a href="broadcasts.html" class="sidebar-link"><i class="ti ti-speakerphone"></i> Broadcasts</a>
        <a href="directory.html" class="sidebar-link"><i class="ti ti-users"></i> Directory</a>
        <a href="leave.html" class="sidebar-link"><i class="ti ti-calendar-event"></i> Leave &amp; Requests</a>
        <a href="documents.html" class="sidebar-link"><i class="ti ti-file-text"></i> Documents</a>
        <a href="policies.html" class="sidebar-link active"><i class="ti ti-book"></i> Policies</a>
        <a href="settings.html" class="sidebar-link"><i class="ti ti-settings"></i> Settings</a>
      </nav>
      <div class="sidebar-logout">
        <a href="help.html" class="sidebar-link" style="margin-bottom:6px;"><i class="ti ti-help-circle"></i> Help</a>
        <button id="logoutBtn"><i class="ti ti-logout"></i> Logout</button>
      </div>
    </div>

    <div class="main-content">
      <div class="topbar">
        <div class="topbar-search"><input type="text" placeholder="Search messages, people, documents…"></div>
        <div class="notif-wrap">
          <button class="topbar-bell" id="notifBell" aria-label="Notifications"><i class="ti ti-bell"></i><span class="dot" id="notifDot" style="display:none;">0</span></button>
          <div class="notif-dropdown" id="notifDropdown"></div>
        </div>
        <img class="topbar-avatar" src="assets/logo.jpeg" alt="You">
      </div>

      <div class="page-body">

        <div id="listView">
          <div class="email-toolbar">
            <div>
              <h1 class="page-greeting" style="font-size: 22px;">Policies</h1>
              <p class="page-greeting-sub" style="margin:0;"><a href="dashboard.html" style="color: var(--primary); text-decoration:none; font-weight:600;">← Back to dashboard</a></p>
            </div>
            <button class="btn btn-primary" id="addPolicyBtn" style="width:auto; padding:10px 20px; display:none; align-items:center; gap:8px;"><i class="ti ti-plus"></i> Add Policy</button>
            <a href="compose.html?subject=Policy%20Suggestion" class="btn btn-ghost" style="width:auto; padding:10px 20px; text-decoration:none; display:inline-flex; align-items:center; gap:8px; margin-left:8px;"><i class="ti ti-message-2"></i> Suggest a Policy</a>
          </div>

          <div class="pol-grid" id="polGrid">
            <div class="pol-empty">Loading…</div>
          </div>
        </div>

        <div id="detailView" style="display:none;">
          <a href="policies.html" class="email-back" style="display:inline-flex; align-items:center; gap:5px; margin-bottom:16px;"><i class="ti ti-arrow-left"></i> Back to Policies</a>
          <div class="email-card">
            <h2 class="email-detail-subject" id="detailTitle">—</h2>
            <p class="pol-card .updated" style="font-size:12px; color:var(--text-muted); margin-bottom:14px;" id="detailUpdated"></p>
            <div class="email-body-text" id="detailBody"></div>
            <div class="email-action-row" id="detailAdminActions" style="display:none;">
              <button class="email-action-btn" id="editPolicyBtn"><i class="ti ti-pencil"></i> Edit</button>
              <button class="email-action-btn danger" id="deletePolicyBtn"><i class="ti ti-trash"></i> Delete</button>
            </div>
          </div>
        </div>

      </div>
    </div>
  </div>

  <div class="modal-backdrop" id="policyModalBackdrop">
    <div class="modal" style="width: 480px;">
      <h3 id="policyModalTitle">Add Policy</h3>
      <div id="policyModalAlert" class="alert alert-error"></div>
      <div class="pol-form-field">
        <label>Title</label>
        <input type="text" id="policyTitleInput" placeholder="e.g. Remote Work Policy">
      </div>
      <div class="pol-form-field">
        <label>Content</label>
        <textarea id="policyBodyInput" placeholder="Write the full policy text…"></textarea>
      </div>
      <div class="modal-actions">
        <button class="btn btn-ghost" id="policyModalCancel">Cancel</button>
        <button class="btn btn-primary" id="policyModalSave">Save</button>
      </div>
    </div>
  </div>

  <script src="assets/api.js"></script>
  <script src="assets/notifications.js"></script>
  <script src="assets/presence.js"></script>
  <script>
    document.getElementById('logoutBtn').addEventListener('click', async () => {
      await apiRequest('/auth/logout', { method: 'POST' });
      window.location.href = 'login.html';
    });

    let isAdmin = false;
    let policiesCache = [];
    let editingPolicyId = null;
    const params = new URLSearchParams(window.location.search);
    const openId = params.get('id');

    async function init() {
      try {
        const result = await apiRequest('/dashboard-check');
        isAdmin = result.staff.role === 'admin';
        if (isAdmin) document.getElementById('addPolicyBtn').style.display = 'inline-flex';
      } catch (err) {
        window.location.href = 'login.html';
        return;
      }
      loadUnreadBadge();
      await loadPolicies();

      if (openId) openDetail(openId);
    }

    async function loadPolicies() {
      const grid = document.getElementById('polGrid');
      try {
        const result = await apiRequest('/policies');
        policiesCache = result.policies;

        if (result.policies.length === 0) {
          grid.innerHTML = '<div class="pol-empty">No policies added yet.' + (isAdmin ? ' Click Add Policy to create one.' : '') + '</div>';
          return;
        }

        grid.innerHTML = result.policies.map(p => {
          const excerpt = p.body.length > 90 ? p.body.slice(0, 90) + '…' : p.body;
          return '<div class="pol-card">' +
            '<h3>' + p.title + '</h3>' +
            '<p>' + excerpt + '</p>' +
            '<div class="updated">Last updated: ' + new Date(p.updated_at).toLocaleDateString() + '</div>' +
            '<div class="pol-card-actions"><button class="pol-read-btn" onclick="window.location.href=\'policies.html?id=' + p.id + '\'"><i class="ti ti-book"></i> Read Policy</button></div>' +
            '</div>';
        }).join('');
      } catch (err) {
        grid.innerHTML = '<div class="pol-empty">Could not load policies.</div>';
      }
    }

    function openDetail(id) {
      const policy = policiesCache.find(p => p.id === id);
      if (!policy) return;

      document.getElementById('listView').style.display = 'none';
      document.getElementById('detailView').style.display = 'block';
      document.getElementById('detailTitle').textContent = policy.title;
      document.getElementById('detailUpdated').textContent = 'Last updated: ' + new Date(policy.updated_at).toLocaleDateString();
      document.getElementById('detailBody').textContent = policy.body;

      if (isAdmin) {
        document.getElementById('detailAdminActions').style.display = 'flex';
        document.getElementById('editPolicyBtn').onclick = () => openPolicyModal(policy);
        document.getElementById('deletePolicyBtn').onclick = () => deletePolicy(policy.id);
      }
    }

    function openPolicyModal(policy) {
      editingPolicyId = policy ? policy.id : null;
      document.getElementById('policyModalTitle').textContent = policy ? 'Edit Policy' : 'Add Policy';
      document.getElementById('policyTitleInput').value = policy ? policy.title : '';
      document.getElementById('policyBodyInput').value = policy ? policy.body : '';
      hideAlert(document.getElementById('policyModalAlert'));
      document.getElementById('policyModalBackdrop').classList.add('visible');
    }

    document.getElementById('addPolicyBtn').addEventListener('click', () => openPolicyModal(null));
    document.getElementById('policyModalCancel').addEventListener('click', () => {
      document.getElementById('policyModalBackdrop').classList.remove('visible');
    });

    document.getElementById('policyModalSave').addEventListener('click', async () => {
      const alertEl = document.getElementById('policyModalAlert');
      hideAlert(alertEl);
      const title = document.getElementById('policyTitleInput').value.trim();
      const body = document.getElementById('policyBodyInput').value.trim();

      if (!title || !body) { showAlert(alertEl, 'Title and content are required.'); return; }

      const btn = document.getElementById('policyModalSave');
      btn.disabled = true;

      try {
        if (editingPolicyId) {
          await apiRequest('/policies/' + editingPolicyId, { method: 'PUT', body: { title, body } });
        } else {
          await apiRequest('/policies', { method: 'POST', body: { title, body } });
        }
        document.getElementById('policyModalBackdrop').classList.remove('visible');
        window.location.href = 'policies.html';
      } catch (err) {
        showAlert(alertEl, err.message);
      } finally {
        btn.disabled = false;
      }
    });

    async function deletePolicy(id) {
      if (!confirm('Delete this policy? This cannot be undone.')) return;
      try {
        await apiRequest('/policies/' + id, { method: 'DELETE' });
        window.location.href = 'policies.html';
      } catch (err) {
        alert(err.message);
      }
    }

    init();
  </script>
</body>
</html>

EOF_ACCOUNTING_POLICIES_HTML

cat > accounting/directory.html << 'EOF_ACCOUNTING_DIRECTORY_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Staff Directory — MACDEN Portal</title>
  <link rel="stylesheet" href="assets/portal-style.css">
  <link rel="stylesheet" href="assets/portal-shell.css">
  <link rel="stylesheet" href="assets/portal-inbox.css">
  <style>
    .dir-toolbar { display: flex; gap: 12px; margin-bottom: 18px; }
    .dir-toolbar input {
      flex: 1; max-width: 380px; background: var(--surface); border: 1px solid var(--border);
      border-radius: var(--radius-sm); padding: 10px 14px; font-size: 13px; font-family: var(--font-body);
      color: var(--text-primary);
    }
    .dir-list { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-md); overflow: hidden; }
    .dir-header-row { display: grid; grid-template-columns: 220px 160px 160px 1fr 130px; gap: 14px; padding: 12px 20px; font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.04em; color: var(--text-muted); border-bottom: 1px solid var(--border); }
    .dir-row { display: grid; grid-template-columns: 220px 160px 160px 1fr 130px; gap: 14px; align-items: center; padding: 13px 20px; border-bottom: 1px solid var(--border); cursor: pointer; }
    .dir-row:last-child { border-bottom: none; }
    .dir-row:hover { background: var(--surface-raised); }
    .dir-name-cell { display: flex; align-items: center; gap: 10px; font-size: 13.5px; font-weight: 600; color: var(--text-primary); }
    .dir-avatar { width: 32px; height: 32px; border-radius: 50%; background: var(--gold-dim); color: #a17a00; display: flex; align-items: center; justify-content: center; font-size: 11.5px; font-weight: 700; flex-shrink: 0; position: relative; }
    .dir-cell { font-size: 12.5px; color: var(--text-secondary); }
    .dir-role-badge { display: inline-block; padding: 2px 9px; border-radius: 999px; font-size: 10.5px; font-weight: 700; text-transform: uppercase; background: var(--primary-dim); color: var(--primary); }
    .dir-empty { padding: 60px 20px; text-align: center; color: var(--text-muted); font-size: 13px; }

    .profile-field-row { display: flex; justify-content: space-between; padding: 10px 0; border-bottom: 1px solid var(--border); font-size: 13px; }
    .profile-field-row:last-child { border-bottom: none; }
    .profile-field-label { color: var(--text-secondary); }
    .profile-field-value { color: var(--text-primary); font-weight: 500; }
    .profile-field-value.muted { color: var(--text-muted); font-style: italic; font-weight: 400; }
    .profile-avatar-large { width: 72px; height: 72px; border-radius: 50%; background: var(--gold-dim); color: #a17a00; display: flex; align-items: center; justify-content: center; font-size: 24px; font-weight: 700; margin: 0 auto 14px; }
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
        <a href="broadcasts.html" class="sidebar-link"><i class="ti ti-speakerphone"></i> Broadcasts</a>
        <a href="directory.html" class="sidebar-link active"><i class="ti ti-users"></i> Directory</a>
        <a href="leave.html" class="sidebar-link"><i class="ti ti-calendar-event"></i> Leave &amp; Requests</a>
        <a href="documents.html" class="sidebar-link"><i class="ti ti-file-text"></i> Documents</a>
        <a href="policies.html" class="sidebar-link"><i class="ti ti-book"></i> Policies</a>
        <a href="settings.html" class="sidebar-link"><i class="ti ti-settings"></i> Settings</a>
      </nav>
      <div class="sidebar-logout">
        <a href="help.html" class="sidebar-link" style="margin-bottom:6px;"><i class="ti ti-help-circle"></i> Help</a>
        <button id="logoutBtn"><i class="ti ti-logout"></i> Logout</button>
      </div>
    </div>

    <div class="main-content">
      <div class="topbar">
        <div class="topbar-search"><input type="text" placeholder="Search messages, people, documents…"></div>
        <div class="notif-wrap">
          <button class="topbar-bell" id="notifBell" aria-label="Notifications"><i class="ti ti-bell"></i><span class="dot" id="notifDot" style="display:none;">0</span></button>
          <div class="notif-dropdown" id="notifDropdown"></div>
        </div>
        <img class="topbar-avatar" src="assets/logo.jpeg" alt="You">
      </div>

      <div class="page-body">
        <h1 class="page-greeting" style="font-size: 22px;">Staff Directory</h1>
        <p class="page-greeting-sub"><a href="dashboard.html" style="color: var(--primary); text-decoration:none; font-weight:600;">← Back to dashboard</a></p>

        <div class="dir-toolbar">
          <input type="text" id="dirSearch" placeholder="Search by name or username…">
          <a href="admin-dashboard.html" id="adminActivityLink" class="btn btn-ghost" style="width:auto; padding:10px 18px; text-decoration:none; display:none; align-items:center; gap:8px;"><i class="ti ti-chart-bar"></i> Admin Activity</a>
          <a href="manage-staff.html" class="btn btn-primary" id="manageStaffLink" style="width:auto; padding:10px 18px; text-decoration:none; display:none; align-items:center; gap:8px; margin-left:auto;"><i class="ti ti-settings"></i> Manage Staff</a>
          <a href="orgchart.html" class="btn btn-ghost" style="width:auto; padding:10px 18px; text-decoration:none; display:inline-flex; align-items:center; gap:8px;"><i class="ti ti-sitemap"></i> Org Chart</a>
        </div>

        <div class="dir-list">
          <div class="dir-header-row">
            <div>Staff Member</div><div>Role</div><div>Department</div><div>Email</div><div>Status</div>
          </div>
          <div id="dirRows">
            <div class="dir-empty">Loading…</div>
          </div>
        </div>
      </div>
    </div>
  </div>

  <div class="modal-backdrop" id="profileModalBackdrop">
    <div class="modal" style="width: 380px; text-align: center;">
      <button onclick="closeProfileModal()" aria-label="Close profile" style="float:right; background:none; border:none; cursor:pointer; color:var(--text-muted); font-size:16px;"><i class="ti ti-x"></i></button>
      <div class="profile-avatar-large" id="profileAvatar">—</div>
      <h3 id="profileName" style="text-align:center; font-size:17px;">—</h3>
      <p id="profileRole" style="text-align:center; color:var(--text-secondary); font-size:12.5px; margin-top:-6px;">—</p>

      <div style="text-align:left; margin-top:18px;">
        <div class="profile-field-row"><span class="profile-field-label">Department</span><span class="profile-field-value" id="profileDept">—</span></div>
        <div class="profile-field-row"><span class="profile-field-label">Username</span><span class="profile-field-value" id="profileUsername">—</span></div>
        <div class="profile-field-row"><span class="profile-field-label">Email</span><span class="profile-field-value" id="profileEmail">—</span></div>
        <div class="profile-field-row"><span class="profile-field-label">Date Joined</span><span class="profile-field-value" id="profileDate">—</span></div>
        <div class="profile-field-row"><span class="profile-field-label">Phone</span><span class="profile-field-value muted">Not yet added</span></div>
        <div class="profile-field-row"><span class="profile-field-label">Branch</span><span class="profile-field-value muted">Not yet added</span></div>
      </div>

      <button class="btn btn-primary" id="messageProfileBtn" style="margin-top:18px; display:inline-flex; align-items:center; justify-content:center; gap:8px; width:auto; padding:10px 24px;">
        <i class="ti ti-mail"></i> Message
      </button>
    </div>
  </div>

  <script src="assets/api.js"></script>
  <script src="assets/notifications.js"></script>
  <script src="assets/presence.js"></script>
  <script>
    document.getElementById('logoutBtn').addEventListener('click', async () => {
      await apiRequest('/auth/logout', { method: 'POST' });
      window.location.href = 'login.html';
    });

    function initials(name) {
      if (!name) return '?';
      return name.split(' ').map(p => p[0]).join('').slice(0, 2).toUpperCase();
    }

    let staffCache = [];
    let searchTimeout = null;

    async function init() {
      try {
        const result = await apiRequest('/dashboard-check');
        if (result.staff.role === 'admin') {
          document.getElementById('manageStaffLink').style.display = 'inline-flex';
          document.getElementById('adminActivityLink').style.display = 'inline-flex';
        }
      } catch (err) {
        window.location.href = 'login.html';
        return;
      }
      loadUnreadBadge();
      loadDirectory('');
    }

    async function loadDirectory(query) {
      const rows = document.getElementById('dirRows');
      try {
        const result = await apiRequest('/staff?search=' + encodeURIComponent(query));
        staffCache = result.staff;

        if (result.staff.length === 0) {
          rows.innerHTML = '<div class="dir-empty">No staff found.</div>';
          return;
        }

        rows.innerHTML = result.staff.map(s => {
          const statusDot = s.isOnline ? '<span style="color:var(--primary-light); font-size:11px;">● Online</span>' : '<span style="color:var(--text-muted); font-size:11px;">○ Offline</span>';
          return '<div class="dir-row" onclick="openProfile(\'' + s.id + '\')">' +
            '<div class="dir-name-cell"><span class="dir-avatar">' + initials(s.full_name) + '</span>' + s.full_name + '</div>' +
            '<div class="dir-cell"><span class="dir-role-badge">' + s.role + '</span></div>' +
            '<div class="dir-cell">' + (s.department || '—') + '</div>' +
            '<div class="dir-cell">' + s.email + '</div>' +
            '<div class="dir-cell">' + statusDot + '</div>' +
            '</div>';
        }).join('');
      } catch (err) {
        rows.innerHTML = '<div class="dir-empty">Could not load directory.</div>';
      }
    }

    document.getElementById('dirSearch').addEventListener('input', (e) => {
      clearTimeout(searchTimeout);
      searchTimeout = setTimeout(() => loadDirectory(e.target.value.trim()), 250);
    });

    function openProfile(id) {
      const person = staffCache.find(s => s.id === id);
      if (!person) return;

      document.getElementById('profileAvatar').textContent = initials(person.full_name);
      document.getElementById('profileName').textContent = person.full_name;
      document.getElementById('profileRole').textContent = person.role + (person.department ? ' · ' + person.department : '');
      document.getElementById('profileDept').textContent = person.department || '—';
      document.getElementById('profileUsername').textContent = person.username;
      document.getElementById('profileEmail').textContent = person.email;
      document.getElementById('profileDate').textContent = person.dateStarted ? new Date(person.dateStarted).toLocaleDateString() : '—';

      document.getElementById('messageProfileBtn').onclick = () => {
        window.location.href = 'compose.html?to=' + person.id + '&name=' + encodeURIComponent(person.full_name);
      };

      document.getElementById('profileModalBackdrop').classList.add('visible');
    }

    function closeProfileModal() {
      document.getElementById('profileModalBackdrop').classList.remove('visible');
    }

    init();
  </script>
</body>
</html>

EOF_ACCOUNTING_DIRECTORY_HTML

echo "Tightening batch 5 complete: 18 of 40 items now done."