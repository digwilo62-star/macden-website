// server/routes/announcements.js
//
// A genuinely separate announcements system -- not built on top of
// messages/conversations. No dependency on messages.js at all, only on
// the shared email utility, matching the same one messages.js uses.
//
// Admins compose (instant or scheduled), everyone gets notified by
// email and sees it on the Dashboard, anyone can open it as a popup
// card. Admins can delete an announcement at any time -- real, immediate
// removal, not a soft-hide.

const express = require('express');
const router = express.Router();
const supabase = require('../config/supabaseClient');
const { sendNotificationEmail } = require('../utils/email');

function isAdmin(req) {
  return req.session.staff && req.session.staff.role === 'admin';
}

// Emails every active staff member who has broadcast/announcement email
// notifications turned on in Settings. Non-fatal per-recipient -- one
// failed email never blocks the others or the announcement itself.
async function notifyAllStaffByEmail(subject, bodyPreview, announcementId) {
  const { data: recipients } = await supabase
    .from('staff')
    .select('id, full_name, email')
    .eq('is_active', true)
    .eq('notify_email_broadcasts', true);

  if (!recipients || recipients.length === 0) return;

  const link = 'https://macden.com.ng/portal/dashboard.html?announcement=' + announcementId;

  await Promise.allSettled(recipients.map(r =>
    sendNotificationEmail(
      r.email,
      r.full_name,
      subject,
      `Hi ${r.full_name},\n\nA new announcement was posted on the MACDEN Portal:\n\n"${subject}"\n\n${bodyPreview}\n\nView it here: ${link}\n\n(You can turn off these emails anytime in Settings > Notifications.)`,
      `<p>Hi ${r.full_name},</p>
       <p>A new announcement was posted on the MACDEN Portal:</p>
       <p style="font-weight:600; margin-bottom:4px;">${subject}</p>
       <p style="background:#f2f3f5; padding:12px 16px; border-radius:8px;">${bodyPreview}</p>
       <p><a href="${link}">View it on the portal</a></p>
       <p style="font-size:12px; color:#888;">You can turn off these emails anytime in Settings &gt; Notifications.</p>`
    ).catch(err => console.error('Announcement email failed for', r.email, ':', err.message))
  ));
}

// POST /api/accounting/announcements -- admin-only. Create + send now,
// or schedule for later.
router.post('/', async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ error: 'Only admins can post announcements.' });

  try {
    const { subject, body, scheduledAt } = req.body;
    if (!subject || !subject.trim()) return res.status(400).json({ error: 'Subject is required.' });
    if (!body || !body.trim()) return res.status(400).json({ error: 'Message body is required.' });

    let isScheduled = false;
    let scheduledDate = null;
    if (scheduledAt) {
      scheduledDate = new Date(scheduledAt);
      if (isNaN(scheduledDate.getTime())) return res.status(400).json({ error: 'Invalid scheduled time.' });
      if (scheduledDate.getTime() > Date.now() + 60000) isScheduled = true;
    }

    const { data: announcement, error } = await supabase
      .from('announcements')
      .insert({
        subject: subject.trim(),
        body: body.trim(),
        created_by: req.session.staff.id,
        status: isScheduled ? 'scheduled' : 'sent',
        scheduled_at: isScheduled ? scheduledDate.toISOString() : null,
        sent_at: isScheduled ? null : new Date().toISOString()
      })
      .select()
      .single();

    if (error) throw error;

    if (isScheduled) {
      return res.json({ success: true, scheduled: true, scheduledAt: scheduledDate.toISOString() });
    }

    notifyAllStaffByEmail(announcement.subject, announcement.body.slice(0, 150), announcement.id)
      .catch(err => console.error('Announcement notify error:', err));

    res.json({ success: true, id: announcement.id });
  } catch (err) {
    console.error('[ANNOUNCEMENT-CREATE-ERROR]', err);
    res.status(500).json({ error: 'Could not post the announcement.' });
  }
});

// GET /api/accounting/announcements -- admin-only. Sent history + any
// still-pending scheduled ones, for the admin's own list page.
router.get('/', async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ error: 'Only admins can view announcement history.' });

  try {
    const { data, error } = await supabase
      .from('announcements')
      .select('id, subject, body, status, scheduled_at, sent_at, created_at')
      .order('created_at', { ascending: false });

    if (error) throw error;

    res.json({
      sent: data.filter(a => a.status === 'sent'),
      scheduled: data.filter(a => a.status === 'scheduled')
    });
  } catch (err) {
    console.error('[ANNOUNCEMENT-LIST-ERROR]', err);
    res.status(500).json({ error: 'Could not load announcement history.' });
  }
});

// GET /api/accounting/announcements/active -- for the Dashboard, any
// logged-in staff member. Every currently-existing sent announcement --
// deletion is the only removal mechanism now, so "active" just means
// "still exists".
router.get('/active', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('announcements')
      .select('id, subject, body, sent_at')
      .eq('status', 'sent')
      .order('sent_at', { ascending: false });

    if (error) throw error;

    res.json({
      announcements: data.map(a => ({
        id: a.id,
        subject: a.subject,
        body: a.body,
        sentAt: a.sent_at
      }))
    });
  } catch (err) {
    console.error('[ANNOUNCEMENT-ACTIVE-ERROR]', err);
    res.status(500).json({ error: 'Could not load announcements.' });
  }
});

// GET /api/accounting/announcements/:id -- any logged-in staff member,
// for the popup card content.
router.get('/:id', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('announcements')
      .select('id, subject, body, sent_at, created_by, staff:created_by(full_name)')
      .eq('id', req.params.id)
      .maybeSingle();

    if (error) throw error;
    if (!data) return res.status(404).json({ error: 'Announcement not found.' });

    res.json({
      id: data.id,
      subject: data.subject,
      body: data.body,
      sentAt: data.sent_at,
      postedBy: data.staff ? data.staff.full_name : 'MACDEN'
    });
  } catch (err) {
    console.error('[ANNOUNCEMENT-GET-ERROR]', err);
    res.status(500).json({ error: 'Could not load this announcement.' });
  }
});

// DELETE /api/accounting/announcements/:id -- admin-only. Real,
// immediate removal.
router.delete('/:id', async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ error: 'Only admins can delete announcements.' });

  try {
    const { error } = await supabase.from('announcements').delete().eq('id', req.params.id);
    if (error) throw error;
    res.json({ success: true });
  } catch (err) {
    console.error('[ANNOUNCEMENT-DELETE-ERROR]', err);
    res.status(500).json({ error: 'Could not delete this announcement.' });
  }
});

// Called by the existing cron job in server.js, same one-minute
// schedule already checking for other scheduled sends.
async function publishDueScheduledAnnouncements() {
  try {
    const { data: due, error } = await supabase
      .from('announcements')
      .select('id, subject, body')
      .eq('status', 'scheduled')
      .lte('scheduled_at', new Date().toISOString());

    if (error) {
      console.error('Scheduled announcement check error:', error);
      return;
    }
    if (!due || due.length === 0) return;

    for (const announcement of due) {
      const { error: updateError } = await supabase
        .from('announcements')
        .update({ status: 'sent', sent_at: new Date().toISOString() })
        .eq('id', announcement.id);

      if (updateError) {
        console.error('Failed to publish scheduled announcement', announcement.id, updateError);
        continue;
      }

      notifyAllStaffByEmail(announcement.subject, announcement.body.slice(0, 150), announcement.id)
        .catch(err => console.error('Scheduled announcement notify error:', err));

      console.log('Published scheduled announcement:', announcement.id);
    }
  } catch (err) {
    console.error('publishDueScheduledAnnouncements unexpected error:', err);
  }
}

module.exports = router;
module.exports.publishDueScheduledAnnouncements = publishDueScheduledAnnouncements;
