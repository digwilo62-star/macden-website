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

