const express = require('express');
const supabase = require('../config/supabaseClient');

const router = express.Router();

function snippet(text, maxLen) {
  if (!text) return '';
  return text.length > maxLen ? text.slice(0, maxLen) + '…' : text;
}

// GET /api/accounting/search?q=... — searches across messages (only ones
// you're actually a participant in), documents, and policies. This is the
// search bar that's been sitting in every topbar unwired since the portal
// rebuild started.
router.get('/', async (req, res) => {
  try {
    const q = (req.query.q || '').trim();
    if (!q || q.length < 2) {
      return res.json({ messages: [], documents: [], policies: [] });
    }

    const staffId = req.session.staff.id;

    // ---- Messages: only within conversations this person is actually part of ----
    const { data: memberRows } = await supabase
      .from('conversation_members')
      .select('conversation_id')
      .eq('staff_id', staffId);
    const myConversationIds = (memberRows || []).map(m => m.conversation_id);

    let messageResults = [];
    if (myConversationIds.length > 0) {
      const { data: convMatches } = await supabase
        .from('conversations')
        .select('id, subject')
        .in('id', myConversationIds)
        .ilike('subject', `%${q}%`)
        .limit(8);

      const { data: bodyMatches } = await supabase
        .from('messages')
        .select('id, conversation_id, body')
        .in('conversation_id', myConversationIds)
        .eq('status', 'sent')
        .ilike('body', `%${q}%`)
        .limit(8);

      const subjectIdsFound = new Set((convMatches || []).map(c => c.id));
      const bodyMatchConvos = (bodyMatches || []).filter(m => !subjectIdsFound.has(m.conversation_id));

      const subjectById = {};
      (convMatches || []).forEach(c => { subjectById[c.id] = c.subject; });

      messageResults = [
        ...(convMatches || []).map(c => ({
          conversationId: c.id,
          subject: c.subject,
          matchedOn: 'subject'
        })),
        ...bodyMatchConvos.map(m => ({
          conversationId: m.conversation_id,
          subject: subjectById[m.conversation_id] || '(no subject)',
          snippet: snippet(m.body, 80),
          matchedOn: 'body'
        }))
      ].slice(0, 8);
    }

    // ---- Documents (current versions only) ----
    const { data: docMatches } = await supabase
      .from('documents')
      .select('id, file_name, category')
      .eq('is_current', true)
      .ilike('file_name', `%${q}%`)
      .limit(8);

    // ---- Policies ----
    const { data: policyMatches } = await supabase
      .from('policies')
      .select('id, title, body')
      .or(`title.ilike.%${q}%,body.ilike.%${q}%`)
      .limit(8);

    res.json({
      messages: messageResults,
      documents: (docMatches || []).map(d => ({ id: d.id, fileName: d.file_name, category: d.category })),
      policies: (policyMatches || []).map(p => ({ id: p.id, title: p.title, snippet: snippet(p.body, 80) }))
    });
  } catch (err) {
    console.error('Search unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong searching.' });
  }
});

module.exports = router;

