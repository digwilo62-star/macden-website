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

  const fullLink = 'https://macden.com.ng/portal/' + link;

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

    const { subject, body, scheduledAt, isDashboardAnnouncement, vanishAt } = req.body;
    const staffId = req.session.staff.id;

    if (!subject || !subject.trim()) {
      return res.status(400).json({ error: 'Subject is required.' });
    }
    if (!body || !body.trim()) {
      return res.status(400).json({ error: 'Message body is required.' });
    }

    // If a future send time was given, this becomes a scheduled broadcast
    // instead of sending right now. Note: reliable delivery depends on the
    // app being awake at that moment — Render's free tier sleeps when idle,
    // so timing can drift by a few minutes depending on UptimeRobot's ping
    // schedule. Not instant-guaranteed, but close in practice.
    let isScheduled = false;
    let scheduledDate = null;
    if (scheduledAt) {
      scheduledDate = new Date(scheduledAt);
      if (isNaN(scheduledDate.getTime())) {
        return res.status(400).json({ error: 'Invalid scheduled time.' });
      }
      if (scheduledDate.getTime() > Date.now() + 60000) { // more than 1 min in the future
        isScheduled = true;
      }
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
        status: isScheduled ? 'scheduled' : 'sent',
        sent_at: isScheduled ? null : new Date().toISOString(),
        scheduled_at: isScheduled ? scheduledDate.toISOString() : null,
        is_dashboard_announcement: !!isDashboardAnnouncement,
        vanish_at: (isDashboardAnnouncement && vanishAt) ? new Date(vanishAt).toISOString() : null
      })
      .select()
      .single();

    if (msgError) {
      return res.status(500).json({ error: 'Could not send broadcast.' });
    }

    if (isScheduled) {
      // Don't create read rows or send emails yet — the scheduler picks
      // this up and does that at the actual send time.
      return res.json({
        success: true,
        conversationId: conversation.id,
        recipientCount: allActiveStaff.length,
        scheduled: true,
        scheduledAt: scheduledDate.toISOString()
      });
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
// GET /api/accounting/messages/announcements/active -- any logged-in
// staff member, for the Dashboard Announcements card. Vanishing only
// affects this list -- the underlying broadcast stays in Inbox history
// regardless.
router.get('/announcements/active', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('messages')
      .select('id, conversation_id, body, sent_at, vanish_at, conversations(subject)')
      .eq('status', 'sent')
      .eq('is_dashboard_announcement', true)
      .order('sent_at', { ascending: false });

    if (error) {
      console.error('Active announcements fetch error:', error);
      return res.status(500).json({ error: 'Could not load announcements.' });
    }

    const now = Date.now();
    const active = (data || []).filter(m => !m.vanish_at || new Date(m.vanish_at).getTime() > now);

    res.json({
      announcements: active.map(m => ({
        id: m.id,
        conversationId: m.conversation_id,
        subject: m.conversations ? m.conversations.subject : 'Announcement',
        body: m.body,
        sentAt: m.sent_at,
        vanishAt: m.vanish_at
      }))
    });
  } catch (err) {
    console.error('Active announcements unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading announcements.' });
  }
});

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

// GET /api/accounting/messages/broadcasts/scheduled — admin-only, upcoming
// scheduled broadcasts not yet sent
router.get('/broadcasts/scheduled', async (req, res) => {
  try {
    if (req.session.staff.role !== 'admin') {
      return res.status(403).json({ error: 'Only admins can view scheduled broadcasts.' });
    }

    const { data, error } = await supabase
      .from('messages')
      .select('id, conversation_id, body, scheduled_at, conversations(subject)')
      .eq('status', 'scheduled')
      .order('scheduled_at', { ascending: true });

    if (error) {
      console.error('Scheduled broadcasts fetch error:', error);
      return res.status(500).json({ error: 'Could not load scheduled broadcasts.' });
    }

    const scheduled = data.map(m => ({
      conversationId: m.conversation_id,
      subject: m.conversations ? m.conversations.subject : '(no subject)',
      preview: (m.body || '').slice(0, 80),
      scheduledAt: m.scheduled_at
    }));

    res.json({ scheduled });
  } catch (err) {
    console.error('Scheduled broadcasts unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading scheduled broadcasts.' });
  }
});

// Checks for scheduled broadcasts whose time has arrived and actually sends
// them — creates read rows and fires notification emails, same as an
// immediate send. Called by the cron job in server.js every minute.
async function publishDueScheduledBroadcasts() {
  try {
    const { data: due, error } = await supabase
      .from('messages')
      .select('id, conversation_id, sender_id, body')
      .eq('status', 'scheduled')
      .lte('scheduled_at', new Date().toISOString());

    if (error) {
      console.error('Scheduled broadcast check error:', error);
      return;
    }
    if (!due || due.length === 0) return;

    for (const message of due) {
      const { error: updateError } = await supabase
        .from('messages')
        .update({ status: 'sent', sent_at: new Date().toISOString() })
        .eq('id', message.id);

      if (updateError) {
        console.error('Failed to publish scheduled broadcast', message.id, updateError);
        continue;
      }

      await createReadRowsForRecipients(message.conversation_id, message.id, message.sender_id);

      const { data: conv } = await supabase
        .from('conversations')
        .select('subject')
        .eq('id', message.conversation_id)
        .single();

      const { data: memberRows } = await supabase
        .from('conversation_members')
        .select('staff_id')
        .eq('conversation_id', message.conversation_id)
        .neq('staff_id', message.sender_id);

      notifyRecipientsByEmail(
        (memberRows || []).map(m => m.staff_id), 'notify_email_broadcasts', null,
        conv ? conv.subject : 'Broadcast', (message.body || '').slice(0, 150),
        'inbox.html?id=' + message.conversation_id
      ).catch(err => console.error('Scheduled broadcast email notify error:', err));

      console.log('Published scheduled broadcast:', message.id);
    }
  } catch (err) {
    console.error('publishDueScheduledBroadcasts unexpected error:', err);
  }
}

module.exports = router;
module.exports.publishDueScheduledBroadcasts = publishDueScheduledBroadcasts;

