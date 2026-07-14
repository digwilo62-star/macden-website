const express = require('express');
const supabase = require('../config/supabaseClient');

const router = express.Router();

// Helper: create an unread "message_reads" row for everyone in the conversation
// except the sender. Only called when a message is actually SENT, never for drafts —
// recipients shouldn't know a draft exists until it's sent.
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

// GET /api/accounting/messages/unread-count — powers the hamburger badge
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

// GET /api/accounting/messages/conversations — inbox list
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
    .select('id, subject, created_at')
    .in('id', conversationIds)
    .order('created_at', { ascending: false });

  if (convError) {
    return res.status(500).json({ error: 'Could not load inbox.' });
  }

  // For each conversation, grab the latest SENT message and whether it's unread for this user
  const enriched = await Promise.all(conversations.map(async (conv) => {
    const { data: lastMessage } = await supabase
      .from('messages')
      .select('id, sender_id, body, sent_at')
      .eq('conversation_id', conv.id)
      .eq('status', 'sent')
      .order('sent_at', { ascending: false })
      .limit(1)
      .maybeSingle();

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
      lastMessagePreview: lastMessage ? lastMessage.body.slice(0, 80) : null,
      lastMessageAt: lastMessage ? lastMessage.sent_at : conv.created_at,
      isUnread
    };
  }));

  enriched.sort((a, b) => new Date(b.lastMessageAt) - new Date(a.lastMessageAt));

  res.json({ conversations: enriched });
});

// GET /api/accounting/messages/conversations/:id — full thread, marks it read
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

  // Show sent messages to everyone, but a draft only to the person who wrote it
  const { data: messages, error } = await supabase
    .from('messages')
    .select('id, sender_id, body, status, sent_at, created_at, attachment_url, attachment_type')
    .eq('conversation_id', id)
    .or(`status.eq.sent,and(status.eq.draft,sender_id.eq.${staffId})`)
    .order('created_at', { ascending: true });

  if (error) {
    return res.status(500).json({ error: 'Could not load conversation.' });
  }

  // Mark all sent messages in this thread as read for this user
  const sentMessageIds = messages.filter(m => m.status === 'sent').map(m => m.id);
  if (sentMessageIds.length > 0) {
    await supabase
      .from('message_reads')
      .update({ read_at: new Date().toISOString() })
      .eq('staff_id', staffId)
      .in('message_id', sentMessageIds)
      .is('read_at', null);
  }

  res.json({ conversation, messages });
});

// POST /api/accounting/messages/compose — start a new conversation (draft or send)
router.post('/compose', async (req, res) => {
  const { recipientIds, subject, body, status } = req.body;
  const staffId = req.session.staff.id;

  if (!subject || !recipientIds || recipientIds.length === 0) {
    return res.status(400).json({ error: 'Subject and at least one recipient are required.' });
  }

  const { data: conversation, error: convError } = await supabase
    .from('conversations')
    .insert({ department_id: req.session.staff.departmentId, subject, is_group: recipientIds.length > 1 })
    .select()
    .single();

  if (convError) {
    return res.status(500).json({ error: 'Could not create conversation.' });
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
    return res.status(500).json({ error: 'Could not create message.' });
  }

  if (isSent) {
    await createReadRowsForRecipients(conversation.id, message.id, staffId);
  }

  res.json({ success: true, conversationId: conversation.id, messageId: message.id });
});

// POST /api/accounting/messages/conversations/:id/reply — reply within an existing thread
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
    return res.status(500).json({ error: 'Could not send reply.' });
  }

  if (isSent) {
    await createReadRowsForRecipients(id, message.id, staffId);
  }

  res.json({ success: true, message });
});

// GET /api/accounting/messages/drafts — this user's own unsent messages
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
    const { data: conv } = await supabase
      .from('conversations')
      .select('subject')
      .eq('id', draft.conversation_id)
      .single();
    return { ...draft, subject: conv ? conv.subject : '(no subject)' };
  }));

  res.json({ drafts: enriched });
});

// PUT /api/accounting/messages/:id — update a draft's content, or send it
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

module.exports = router;

