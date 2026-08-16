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

// 1. Accept the two new fields from the request body
const oldDestructure = `    const { subject, body, scheduledAt } = req.body;`;
const newDestructure = `    const { subject, body, scheduledAt, isDashboardAnnouncement, vanishAt } = req.body;`;

if (!content.includes(oldDestructure)) {
  console.error('ERROR: could not find the req.body destructure line in messages.js.');
  process.exit(1);
}
content = content.replace(oldDestructure, newDestructure);

// 2. Include the new fields in the message insert
const oldInsert = `        status: isScheduled ? 'scheduled' : 'sent',
        sent_at: isScheduled ? null : new Date().toISOString(),
        scheduled_at: isScheduled ? scheduledDate.toISOString() : null
      })`;

const newInsert = `        status: isScheduled ? 'scheduled' : 'sent',
        sent_at: isScheduled ? null : new Date().toISOString(),
        scheduled_at: isScheduled ? scheduledDate.toISOString() : null,
        is_dashboard_announcement: !!isDashboardAnnouncement,
        vanish_at: (isDashboardAnnouncement && vanishAt) ? new Date(vanishAt).toISOString() : null
      })`;

if (!content.includes(oldInsert)) {
  console.error('ERROR: could not find the messages insert block in messages.js.');
  process.exit(1);
}
content = content.replace(oldInsert, newInsert);

// 3. Add the new GET /announcements/active endpoint, right before the
//    existing GET /broadcasts route (any logged-in staff can view this --
//    unlike creating a broadcast, viewing the dashboard isn't admin-only)
const anchor = `// GET /api/accounting/messages/broadcasts — admin-only, sent history with open rates
router.get('/broadcasts', async (req, res) =>{`;

const newEndpoint = `// GET /api/accounting/messages/announcements/active -- any logged-in
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

// GET /api/accounting/messages/broadcasts — admin-only, sent history with open rates
router.get('/broadcasts', async (req, res) =>{`;

if (!content.includes(anchor)) {
  console.error('ERROR: could not find the GET /broadcasts anchor in messages.js.');
  process.exit(1);
}
content = content.replace(anchor, newEndpoint);

writeRestoringLineEndings(filePath, content, usesCRLF);
console.log('    Patched server/routes/messages.js (broadcast fields + new active-announcements endpoint).');
