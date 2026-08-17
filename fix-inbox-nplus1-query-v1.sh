
#!/bin/bash
# fix-inbox-nplus1-query-v1.sh
#
# Speed fix: GET /messages/conversations was running up to 4 separate
# database queries PER conversation (last message, participant IDs,
# participant names, read status) -- for 20 conversations, that's up to
# 80 individual round-trips just to load the Inbox list. This gets
# progressively slower the more conversations exist.
#
# Rewritten to run a small, FIXED number of batched queries (about 5
# total) regardless of how many conversations exist, then assemble the
# same result in JavaScript. Output format is identical to before --
# verified against multiple test scenarios (unread/read, broadcasts,
# multi-participant, conversations with zero messages) before shipping.
# Frontend needs no changes at all.

set -e

if grep -q "Batched inbox query" server/routes/messages.js; then
  echo "==> Already applied -- skipping (safe to re-run)."
  exit 0
fi

cat > .tmp-patch-inboxperf.js << 'NODE_EOF'
const fs = require('fs');

function readNormalized(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  const usesCRLF = raw.includes('\r\n');
  return { normalized: raw.replace(/\r\n/g, '\n'), usesCRLF };
}
function writeRestoringLineEndings(filePath, normalizedContent, usesCRLF) {
  const out = usesCRLF ? normalizedContent.replace(/\n/g, '\r\n') : normalizedContent;
  fs.writeFileSync(filePath, out);
}

const filePath = 'server/routes/messages.js';
let { normalized: content, usesCRLF } = readNormalized(filePath);

const oldBlock = `    const enriched = await Promise.all(conversations.map(async (conv) => {
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
    enriched.sort((a, b) => new Date(b.lastMessageAt) - new Date(a.lastMessageAt));`;

const newBlock = `    // Batched inbox query -- runs a small fixed number of queries total,
    // instead of up to 4 queries PER conversation (which got slower as
    // the inbox grew). Same output shape as before, just assembled from
    // batch-fetched data instead of looping and querying per-conversation.
    const [membersResult, messagesResult] = await Promise.all([
      supabase
        .from('conversation_members')
        .select('conversation_id, staff_id')
        .in('conversation_id', conversationIds),
      supabase
        .from('messages')
        .select('id, conversation_id, sender_id, body, sent_at, status')
        .in('conversation_id', conversationIds)
        .eq('status', 'sent')
        .order('sent_at', { ascending: false })
    ]);

    const allMembers = membersResult.data || [];
    const allMessages = messagesResult.data || [];

    const otherStaffIds = [...new Set(allMembers.filter(m => m.staff_id !== staffId).map(m => m.staff_id))];
    const { data: allStaff } = otherStaffIds.length
      ? await supabase.from('staff').select('id, full_name').in('id', otherStaffIds)
      : { data: [] };
    const staffById = {};
    for (const s of (allStaff || [])) staffById[s.id] = s;

    const membersByConv = {};
    for (const m of allMembers) {
      if (m.staff_id === staffId) continue;
      (membersByConv[m.conversation_id] = membersByConv[m.conversation_id] || []).push(m.staff_id);
    }

    const latestByConv = {};
    for (const msg of allMessages) {
      const existing = latestByConv[msg.conversation_id];
      if (!existing || new Date(msg.sent_at) > new Date(existing.sent_at)) {
        latestByConv[msg.conversation_id] = msg;
      }
    }

    const latestMessageIds = Object.values(latestByConv).map(m => m.id);
    const { data: readRows } = latestMessageIds.length
      ? await supabase.from('message_reads').select('message_id, read_at').in('message_id', latestMessageIds).eq('staff_id', staffId)
      : { data: [] };
    const readByMessageId = {};
    for (const r of (readRows || [])) readByMessageId[r.message_id] = r;

    const enriched = conversations.map(conv => {
      const participantIds = membersByConv[conv.id] || [];
      const participants = participantIds.map(id => ({
        id, fullName: staffById[id] ? staffById[id].full_name : 'Unknown'
      }));
      const lastMessage = latestByConv[conv.id] || null;
      let isUnread = false;
      if (lastMessage) {
        const readRow = readByMessageId[lastMessage.id];
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
    });
    enriched.sort((a, b) => new Date(b.lastMessageAt) - new Date(a.lastMessageAt));`;

if (!content.includes(oldBlock)) {
  console.error('ERROR: could not find the N+1 enrichment block in messages.js.');
  console.error('Nothing was changed.');
  process.exit(1);
}
content = content.replace(oldBlock, newBlock);

writeRestoringLineEndings(filePath, content, usesCRLF);
console.log('    Patched server/routes/messages.js (batched queries instead of per-conversation loop).');
NODE_EOF

node .tmp-patch-inboxperf.js
rm .tmp-patch-inboxperf.js

echo ""
echo "Done. Push with your usual save-progress.sh."
