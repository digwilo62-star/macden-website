#!/bin/bash
# fix-remove-from-dashboard-v1.sh
#
# Adds a "Remove from Dashboard" action to sent broadcasts -- lets you
# pull a broadcast off the Dashboard's featured Announcements card
# immediately, whenever you want, instead of waiting for its scheduled
# vanish time. The underlying broadcast message is completely unaffected
# -- it stays permanently in everyone's Inbox history either way. This
# only controls whether it's currently featured on the Dashboard.
#
# The button only appears on broadcasts that are actually currently
# featured, since there's nothing to remove otherwise.

set -e

if grep -q "unfeature-from-dashboard" server/routes/messages.js; then
  echo "==> Already applied -- skipping (safe to re-run)."
  exit 0
fi

cat > .tmp-patch-unfeature.js << 'NODE_EOF'
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

// ---------- 1. server/routes/messages.js ----------
{
  const filePath = 'server/routes/messages.js';
  let { normalized: content, usesCRLF } = readNormalized(filePath);

  // Include the two new fields when fetching each broadcast's message
  const oldSelect = `        .select('id, body, sent_at')
        .eq('conversation_id', conv.id)
        .eq('status', 'sent')
        .limit(1)
        .maybeSingle();`;
  const newSelect = `        .select('id, body, sent_at, is_dashboard_announcement, vanish_at')
        .eq('conversation_id', conv.id)
        .eq('status', 'sent')
        .limit(1)
        .maybeSingle();`;

  if (!content.includes(oldSelect)) {
    console.error('ERROR: could not find the message select in the broadcast history handler.');
    process.exit(1);
  }
  content = content.replace(oldSelect, newSelect);

  // Include them in the returned object
  const oldReturn = `      return {
        id: conv.id,
        subject: conv.subject,
        sentAt: message ? message.sent_at : conv.created_at,
        recipientCount,
        openedCount
      };`;
  const newReturn = `      return {
        id: conv.id,
        subject: conv.subject,
        sentAt: message ? message.sent_at : conv.created_at,
        recipientCount,
        openedCount,
        isDashboardAnnouncement: message ? !!message.is_dashboard_announcement : false,
        vanishAt: message ? message.vanish_at : null
      };`;

  if (!content.includes(oldReturn)) {
    console.error('ERROR: could not find the broadcast return object.');
    process.exit(1);
  }
  content = content.replace(oldReturn, newReturn);

  // New endpoint: unfeature-from-dashboard, by conversation id (matching
  // the existing convention -- the frontend already tracks conversation
  // id per row, not message id)
  const anchor = `// GET /api/accounting/messages/broadcasts/:id/reads — admin-only, exactly
// who has and hasn't opened this specific broadcast, not just a percentage.
router.get('/broadcasts/:id/reads', async (req, res) => {`;

  const newEndpoint = `// POST /api/accounting/messages/broadcasts/:id/unfeature-from-dashboard --
// admin-only. Removes a broadcast from the Dashboard's featured
// Announcements card immediately, regardless of its scheduled vanish
// time. Does NOT touch the underlying message -- it stays in Inbox
// history exactly as before, this only controls Dashboard featuring.
router.post('/broadcasts/:id/unfeature-from-dashboard', async (req, res) => {
  if (req.session.staff.role !== 'admin') {
    return res.status(403).json({ error: 'Only admins can do this.' });
  }
  try {
    const { error } = await supabase
      .from('messages')
      .update({ is_dashboard_announcement: false, vanish_at: null })
      .eq('conversation_id', req.params.id)
      .eq('status', 'sent');

    if (error) {
      console.error('Unfeature from dashboard error:', error);
      return res.status(500).json({ error: 'Could not remove this from the Dashboard.' });
    }
    res.json({ success: true });
  } catch (err) {
    console.error('Unfeature from dashboard unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// GET /api/accounting/messages/broadcasts/:id/reads — admin-only, exactly
// who has and hasn't opened this specific broadcast, not just a percentage.
router.get('/broadcasts/:id/reads', async (req, res) => {`;

  if (!content.includes(anchor)) {
    console.error('ERROR: could not find the GET /broadcasts/:id/reads anchor.');
    process.exit(1);
  }
  content = content.replace(anchor, newEndpoint);

  writeRestoringLineEndings(filePath, content, usesCRLF);
  console.log('    Patched server/routes/messages.js (unfeature-from-dashboard endpoint).');
}

// ---------- 2. portal/broadcasts.html ----------
{
  const filePath = 'portal/broadcasts.html';
  let { normalized: content, usesCRLF } = readNormalized(filePath);

  const oldRow = `            return '<div class="bc-row" data-conversation-id="' + b.id + '">' +
              '<div class="bc-subject">' + b.subject + '</div>' +
              '<div class="bc-date">' + new Date(b.sentAt).toLocaleString() + '</div>' +
              '<div class="bc-count">' + b.recipientCount + ' sent</div>' +
              '<div class="bc-opened">' + b.openedCount + ' opened (' + pct + '%)</div>' +
              '<div><button class="who-read-btn" data-conversation-id="' + b.id + '" data-subject="' + b.subject.replace(/"/g, '&quot;') + '" style="border:1px solid var(--border); border-radius:var(--radius-sm); padding:6px 12px; font-size:11.5px; font-weight:600; color:var(--text-primary); background:none; cursor:pointer; font-family:var(--font-body);">Who\\u2019s read this?</button></div>' +
              '</div>';`;

  const newRow = `            const unfeatureBtn = b.isDashboardAnnouncement
              ? '<button class="unfeature-btn" data-conversation-id="' + b.id + '" style="border:1px solid var(--error); border-radius:var(--radius-sm); padding:6px 10px; font-size:11px; font-weight:600; color:var(--error); background:none; cursor:pointer; font-family:var(--font-body); margin-left:6px;">Remove from Dashboard</button>'
              : '';
            return '<div class="bc-row" data-conversation-id="' + b.id + '">' +
              '<div class="bc-subject">' + b.subject + '</div>' +
              '<div class="bc-date">' + new Date(b.sentAt).toLocaleString() + '</div>' +
              '<div class="bc-count">' + b.recipientCount + ' sent</div>' +
              '<div class="bc-opened">' + b.openedCount + ' opened (' + pct + '%)</div>' +
              '<div><button class="who-read-btn" data-conversation-id="' + b.id + '" data-subject="' + b.subject.replace(/"/g, '&quot;') + '" style="border:1px solid var(--border); border-radius:var(--radius-sm); padding:6px 12px; font-size:11.5px; font-weight:600; color:var(--text-primary); background:none; cursor:pointer; font-family:var(--font-body);">Who\\u2019s read this?</button>' + unfeatureBtn + '</div>' +
              '</div>';`;

  if (!content.includes(oldRow)) {
    console.error('ERROR: could not find the broadcast row rendering in broadcasts.html.');
    process.exit(1);
  }
  content = content.replace(oldRow, newRow);

  // Add the click handler, right after loadBroadcasts() is defined -- using
  // event delegation on the list container so it works for dynamically
  // rendered rows without needing a fresh listener per row
  const handlerAnchor = `    async function loadBroadcasts() {`;
  const handlerCode = `    document.getElementById('bcList').addEventListener('click', async (e) => {
      const btn = e.target.closest('.unfeature-btn');
      if (!btn) return;
      if (!confirm('Remove this from the Dashboard? The broadcast itself will stay in everyone\\'s Inbox -- this only stops featuring it on the Dashboard.')) return;
      btn.disabled = true;
      btn.textContent = 'Removing…';
      try {
        await apiRequest('/messages/broadcasts/' + btn.dataset.conversationId + '/unfeature-from-dashboard', { method: 'POST' });
        loadBroadcasts();
      } catch (err) {
        alert(err.message);
        btn.disabled = false;
        btn.textContent = 'Remove from Dashboard';
      }
    });

    async function loadBroadcasts() {`;

  if (!content.includes(handlerAnchor)) {
    console.error('ERROR: could not find the loadBroadcasts function start.');
    process.exit(1);
  }
  content = content.replace(handlerAnchor, handlerCode);

  writeRestoringLineEndings(filePath, content, usesCRLF);
  console.log('    Patched portal/broadcasts.html (Remove from Dashboard button + handler).');
}
NODE_EOF

node .tmp-patch-unfeature.js
rm .tmp-patch-unfeature.js

echo ""
echo "Done. Push with your usual save-progress.sh."
