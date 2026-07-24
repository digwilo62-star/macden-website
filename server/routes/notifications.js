const express = require('express');
const supabase = require('../config/supabaseClient');

const router = express.Router();

function timeAgo(dateStr) {
  const diffMs = Date.now() - new Date(dateStr).getTime();
  const mins = Math.floor(diffMs / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return mins + 'm ago';
  const hours = Math.floor(mins / 60);
  if (hours < 24) return hours + 'h ago';
  const days = Math.floor(hours / 24);
  return days + 'd ago';
}

// GET /api/accounting/notifications — aggregates real recent activity for this
// person: unread messages, their own reviewed leave requests, and new hires.
// No separate notifications table — this reads directly from data that
// already exists, so everything shown is genuinely real.
router.get('/', async (req, res) => {
  try {
    const staffId = req.session.staff.id;
    const items = [];

    // Get the TRUE unread count separately from the 5-row sample used for display below
    const { count: trueUnreadCount } = await supabase
      .from('message_reads')
      .select('*', { count: 'exact', head: true })
      .eq('staff_id', staffId)
      .is('read_at', null);

    // Unread messages (up to 5 most recent, for display)
    const { data: unreadRows } = await supabase
      .from('message_reads')
      .select('message_id, read_at')
      .eq('staff_id', staffId)
      .is('read_at', null)
      .limit(5);

    if (unreadRows && unreadRows.length > 0) {
      const messageIds = unreadRows.map(r => r.message_id);
      const { data: messages } = await supabase
        .from('messages')
        .select('id, sender_id, body, sent_at, conversation_id')
        .in('id', messageIds);

      if (messages) {
        const senderIds = [...new Set(messages.map(m => m.sender_id))];
        const { data: senders } = await supabase.from('staff').select('id, full_name').in('id', senderIds);
        const nameById = {};
        (senders || []).forEach(s => { nameById[s.id] = s.full_name; });

        messages.forEach(m => {
          items.push({
            type: 'message',
            icon: 'ti-mail',
            title: (nameById[m.sender_id] || 'Someone') + ' sent you a message',
            detail: (m.body || '').slice(0, 60),
            time: m.sent_at,
            link: 'inbox.html?id=' + m.conversation_id
          });
        });
      }
    }

    // Own leave requests reviewed in the last 7 days
    const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
    const { data: reviewedLeave } = await supabase
      .from('leave_requests')
      .select('id, status, leave_type, reviewed_at')
      .eq('staff_id', staffId)
      .not('reviewed_at', 'is', null)
      .gte('reviewed_at', sevenDaysAgo)
      .order('reviewed_at', { ascending: false })
      .limit(3);

    (reviewedLeave || []).forEach(r => {
      items.push({
        type: 'leave',
        icon: r.status === 'approved' ? 'ti-circle-check' : 'ti-circle-x',
        title: 'Your leave request was ' + r.status,
        detail: r.leave_type,
        time: r.reviewed_at,
        link: 'leave.html'
      });
    });

    // New staff joined in the last 3 days (everyone sees this)
    const threeDaysAgo = new Date(Date.now() - 3 * 24 * 60 * 60 * 1000).toISOString();
    const { data: newStaff } = await supabase
      .from('staff')
      .select('id, full_name, created_at')
      .neq('id', staffId)
      .gte('created_at', threeDaysAgo)
      .order('created_at', { ascending: false })
      .limit(3);

    (newStaff || []).forEach(s => {
      items.push({
        type: 'staff',
        icon: 'ti-user-plus',
        title: s.full_name + ' joined the company',
        detail: 'Welcome to MACDEN!',
        time: s.created_at,
        link: 'directory.html'
      });
    });

    // Sort everything by recency, cap at 8
    items.sort((a, b) => new Date(b.time) - new Date(a.time));
    const limited = items.slice(0, 8).map(i => ({ ...i, timeAgo: timeAgo(i.time) }));

    res.json({ notifications: limited, unreadCount: trueUnreadCount || 0 });
  } catch (err) {
    console.error('Notifications fetch error:', err);
    res.status(500).json({ error: 'Something went wrong loading notifications.' });
  }
});

module.exports = router;

