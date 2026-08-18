#!/bin/bash
# fix-announcements-frontend-v1.sh
#
# The new Announcement page (compose + history), the shared popup card
# component, and a corrected backend (fixes a camelCase field naming
# bug found while building the Dashboard integration -- caught and
# fixed before it ever shipped).
#
# Tested: full compose-post-list-delete flow with real clicks, popup
# card opening and closing for real, all against the real page markup.
# Backend re-verified against the full 22-test suite after the fix.
#
# This does NOT yet touch the Dashboard, sidebar, or retire the old
# broadcasts page -- that is the next script.

set -e

echo "==> Overwriting server/routes/announcements.js (corrected field naming)"
mkdir -p server/routes
cat > server/routes/announcements.js << 'BACKEND_EOF'
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
BACKEND_EOF

echo "==> Creating portal/announcement.html"
mkdir -p portal/assets
cat > portal/announcement.html << 'PAGE_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Announcement — MACDEN Portal</title>
<link rel="stylesheet" href="assets/portal-style.css">
<link rel="stylesheet" href="assets/portal-shell.css">
<style>
  .ann-toolbar{ display:flex; justify-content:space-between; align-items:center; margin-bottom:18px; }
  .ann-list{ background:var(--surface); border:1px solid var(--border); border-radius:var(--radius-md); overflow:hidden; }
  .ann-row{ display:grid; grid-template-columns: 1fr auto auto; gap:16px; align-items:center; padding:16px 20px; border-bottom:1px solid var(--border); }
  .ann-row:last-child{ border-bottom:none; }
  .ann-subject{ font-weight:600; cursor:pointer; color:var(--text-primary); }
  .ann-subject:hover{ color:var(--primary); }
  .ann-date{ font-size:12px; color:var(--text-muted); white-space:nowrap; }
  .ann-empty{ padding:50px 20px; text-align:center; color:var(--text-muted); font-size:13px; }
  .ann-delete-btn{ border:1px solid var(--error); border-radius:var(--radius-sm); padding:6px 12px; font-size:11.5px; font-weight:600; color:var(--error); background:none; cursor:pointer; white-space:nowrap; }
  .ann-section-label{ font-size:11px; font-weight:700; text-transform:uppercase; letter-spacing:0.04em; color:var(--text-muted); padding:14px 20px 6px; }
  .ann-badge-scheduled{ display:inline-block; padding:2px 8px; border-radius:999px; font-size:10.5px; font-weight:700; background:#f5e6c8; color:#8a6d00; margin-left:8px; }

  #composeView{ display:none; }
  .ann-field{ margin-bottom:16px; }
  .ann-field label{ display:block; font-size:12.5px; font-weight:600; margin-bottom:6px; color:var(--text-secondary); }
  .ann-field input[type="text"], .ann-field textarea{ width:100%; padding:10px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); font-family:var(--font-body); font-size:13.5px; box-sizing:border-box; }
  .ann-field textarea{ min-height:140px; resize:vertical; }
  .ann-timing{ display:flex; gap:16px; align-items:center; margin-bottom:16px; }
  .ann-timing label{ display:flex; align-items:center; gap:6px; font-size:13px; cursor:pointer; }
</style>
</head>
<body>
  <div class="app-shell">
    <div class="sidebar">
      <div class="sidebar-brand"><img src="assets/logo.jpeg" alt="MACDEN"><span>MACDEN</span></div>
      <nav class="sidebar-nav">
        <a href="dashboard.html" class="sidebar-link"><i class="ti ti-layout-dashboard"></i> Dashboard</a>
        <a href="inbox.html" class="sidebar-link"><i class="ti ti-mail"></i> Inbox</a>
        <a href="compose.html" class="sidebar-link"><i class="ti ti-pencil"></i> Compose</a>
        <a href="announcement.html" class="sidebar-link active"><i class="ti ti-speakerphone"></i> Announcement</a>
        <a href="directory.html" class="sidebar-link"><i class="ti ti-users"></i> Directory</a>
        <a href="attendance.html" class="sidebar-link"><i class="ti ti-clock"></i> Attendance</a>
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
      <div class="page-body">

        <div id="notAdminView" style="display:none;">
          <h1 class="page-greeting" style="font-size:22px;">Announcement</h1>
          <div class="ann-empty">Only admins can send or view announcements.</div>
        </div>

        <div id="adminView" style="display:none;">
          <div id="listView">
            <div class="ann-toolbar">
              <div>
                <h1 class="page-greeting" style="font-size:22px; margin-bottom:2px;">Announcement</h1>
                <p class="page-greeting-sub" style="margin:0;">Post updates that reach every staff member.</p>
              </div>
              <button class="btn btn-primary" id="newAnnouncementBtn" style="width:auto; padding:10px 20px; display:inline-flex; align-items:center; gap:8px;"><i class="ti ti-speakerphone"></i> New Announcement</button>
            </div>

            <div class="ann-list" id="annList">
              <div class="ann-empty">Loading…</div>
            </div>
          </div>

          <div id="composeView">
            <h1 class="page-greeting" style="font-size:22px;">New Announcement</h1>
            <p class="page-greeting-sub" style="margin:0 0 20px;">This goes out to every staff member.</p>

            <div id="annAlert" class="alert"></div>

            <div class="ann-field">
              <label>Subject</label>
              <input type="text" id="annSubject" placeholder="e.g. Office closed Monday for public holiday">
            </div>
            <div class="ann-field">
              <label>Message</label>
              <textarea id="annBody" placeholder="Write the announcement…"></textarea>
            </div>

            <div class="ann-timing">
              <label><input type="radio" name="annTiming" id="annTimingNow" checked> Send now</label>
              <label><input type="radio" name="annTiming" id="annTimingLater"> Schedule for later</label>
            </div>
            <input type="datetime-local" id="annScheduledAt" style="display:none; margin-bottom:16px; padding:9px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); font-family:var(--font-body); font-size:13px;">

            <div style="display:flex; gap:10px;">
              <button class="btn btn-primary" id="sendAnnouncementBtn" style="width:auto; padding:10px 24px;">Post Announcement</button>
              <button class="btn" id="cancelComposeBtn" style="width:auto; padding:10px 24px; background:none; border:1px solid var(--border);">Cancel</button>
            </div>
          </div>
        </div>

      </div>
    </div>
  </div>

  <script src="assets/api.js"></script>
  <script src="assets/confirm-modal.js"></script>
  <script src="assets/announcement-card.js"></script>
  <script>
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
      loadList();
    }

    async function loadList() {
      const listEl = document.getElementById('annList');
      try {
        const res = await fetch('/api/accounting/announcements', { credentials: 'include' });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Could not load announcements.');

        if (data.sent.length === 0 && data.scheduled.length === 0) {
          listEl.innerHTML = '<div class="ann-empty">No announcements yet. Click New Announcement to post your first one.</div>';
          return;
        }

        let html = '';
        if (data.scheduled.length > 0) {
          html += '<div class="ann-section-label">Scheduled</div>';
          html += data.scheduled.map(a => rowHtml(a, true)).join('');
        }
        if (data.sent.length > 0) {
          html += '<div class="ann-section-label">Sent</div>';
          html += data.sent.map(a => rowHtml(a, false)).join('');
        }
        listEl.innerHTML = html;

        listEl.querySelectorAll('.ann-subject').forEach(el => {
          el.addEventListener('click', () => showAnnouncementCard(el.dataset.id));
        });
        listEl.querySelectorAll('.ann-delete-btn').forEach(btn => {
          btn.addEventListener('click', async () => {
            const ok = await confirmModal('This removes the announcement permanently. It cannot be undone.', { title: 'Delete this announcement?', confirmLabel: 'Delete', danger: true });
            if (!ok) return;
            btn.disabled = true;
            btn.textContent = 'Deleting…';
            try {
              const res = await fetch('/api/accounting/announcements/' + btn.dataset.id, { method: 'DELETE', credentials: 'include' });
              const data = await res.json();
              if (!res.ok) throw new Error(data.error);
              loadList();
            } catch (err) {
              alert(err.message);
              btn.disabled = false;
              btn.textContent = 'Delete';
            }
          });
        });
      } catch (err) {
        listEl.innerHTML = '<div class="ann-empty">' + err.message + '</div>';
      }
    }

    function rowHtml(a, isScheduled) {
      const dateLabel = isScheduled
        ? 'Scheduled: ' + new Date(a.scheduled_at).toLocaleString()
        : new Date(a.sent_at).toLocaleString();
      const subjectHtml = isScheduled
        ? a.subject + '<span class="ann-badge-scheduled">Pending</span>'
        : '<span class="ann-subject" data-id="' + a.id + '">' + a.subject + '</span>';
      return '<div class="ann-row">' +
        '<div>' + subjectHtml + '</div>' +
        '<div class="ann-date">' + dateLabel + '</div>' +
        '<div><button class="ann-delete-btn" data-id="' + a.id + '">Delete</button></div>' +
        '</div>';
    }

    document.getElementById('newAnnouncementBtn').addEventListener('click', () => {
      document.getElementById('listView').style.display = 'none';
      document.getElementById('composeView').style.display = 'block';
    });
    document.getElementById('cancelComposeBtn').addEventListener('click', () => {
      document.getElementById('composeView').style.display = 'none';
      document.getElementById('listView').style.display = 'block';
    });
    document.getElementById('annTimingNow').addEventListener('change', () => {
      document.getElementById('annScheduledAt').style.display = 'none';
    });
    document.getElementById('annTimingLater').addEventListener('change', () => {
      document.getElementById('annScheduledAt').style.display = 'block';
    });

    document.getElementById('sendAnnouncementBtn').addEventListener('click', async () => {
      const alertEl = document.getElementById('annAlert');
      hideAlert(alertEl);
      const subject = document.getElementById('annSubject').value.trim();
      const body = document.getElementById('annBody').value.trim();
      if (!subject) { showAlert(alertEl, 'Add a subject.'); return; }
      if (!body) { showAlert(alertEl, 'Write a message.'); return; }

      const isScheduled = document.getElementById('annTimingLater').checked;
      const scheduledAtValue = document.getElementById('annScheduledAt').value;
      if (isScheduled && !scheduledAtValue) {
        showAlert(alertEl, 'Pick a date and time to schedule this for.');
        return;
      }

      const btn = document.getElementById('sendAnnouncementBtn');
      btn.disabled = true;
      btn.textContent = 'Posting…';
      try {
        const res = await fetch('/api/accounting/announcements', {
          method: 'POST',
          credentials: 'include',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            subject, body,
            scheduledAt: isScheduled ? new Date(scheduledAtValue).toISOString() : undefined
          })
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error);

        document.getElementById('annSubject').value = '';
        document.getElementById('annBody').value = '';
        document.getElementById('annTimingNow').checked = true;
        document.getElementById('annScheduledAt').style.display = 'none';
        document.getElementById('annScheduledAt').value = '';
        document.getElementById('composeView').style.display = 'none';
        document.getElementById('listView').style.display = 'block';
        loadList();
      } catch (err) {
        showAlert(alertEl, err.message);
      } finally {
        btn.disabled = false;
        btn.textContent = 'Post Announcement';
      }
    });

    document.getElementById('logoutBtn').addEventListener('click', async () => {
      await apiRequest('/auth/logout', { method: 'POST' });
      window.location.href = 'login.html';
    });

    init();
  </script>
</body>
</html>
PAGE_EOF

echo "==> Creating portal/assets/announcement-card.js"
cat > portal/assets/announcement-card.js << 'CARD_EOF'
// assets/announcement-card.js
//
// Shared popup card for viewing an announcement -- used from both the
// Dashboard and the Announcement page's own history list, so clicking
// an announcement anywhere always gives the identical experience.
// Self-contained (injects its own styles), same pattern as confirm-modal.js.

async function showAnnouncementCard(id) {
  const backdrop = document.createElement('div');
  backdrop.style.cssText = 'position:fixed; inset:0; background:rgba(0,0,0,0.5); display:flex; align-items:center; justify-content:center; z-index:9999; font-family:-apple-system,sans-serif;';
  backdrop.addEventListener('click', (e) => { if (e.target === backdrop) close(); });

  const card = document.createElement('div');
  card.style.cssText = 'width:400px; max-width:90vw; max-height:80vh; overflow-y:auto; background:#fbfaf6; border-radius:16px; box-shadow:0 20px 50px rgba(0,0,0,0.3); position:relative;';

  const header = document.createElement('div');
  header.style.cssText = 'background:linear-gradient(160deg, #0d5c2f, #0a4a25); padding:20px 24px; border-radius:16px 16px 0 0; position:relative;';
  header.innerHTML = `
    <div style="color:rgba(255,255,255,0.75); font-size:11px; font-weight:700; text-transform:uppercase; letter-spacing:0.05em; margin-bottom:4px;">Announcement</div>
    <div id="annCardSubject" style="color:#fff; font-family:'Manrope',sans-serif; font-weight:800; font-size:19px; line-height:1.3;">Loading…</div>
  `;

  const closeBtn = document.createElement('button');
  closeBtn.innerHTML = '&times;';
  closeBtn.style.cssText = 'position:absolute; top:14px; right:16px; background:rgba(255,255,255,0.15); border:none; color:#fff; width:28px; height:28px; border-radius:50%; font-size:20px; line-height:1; cursor:pointer;';
  closeBtn.addEventListener('click', close);
  header.appendChild(closeBtn);

  const body = document.createElement('div');
  body.id = 'annCardBody';
  body.style.cssText = 'padding:20px 24px; color:#1a1a1a; font-size:14px; line-height:1.6; white-space:pre-wrap;';
  body.textContent = 'Loading…';

  const footer = document.createElement('div');
  footer.id = 'annCardFooter';
  footer.style.cssText = 'padding:0 24px 20px; color:#8a8a8a; font-size:11.5px;';

  card.appendChild(header);
  card.appendChild(body);
  card.appendChild(footer);
  backdrop.appendChild(card);
  document.body.appendChild(backdrop);

  function close() {
    if (backdrop.parentNode) backdrop.parentNode.removeChild(backdrop);
  }

  try {
    const res = await fetch('/api/accounting/announcements/' + id, { credentials: 'include' });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'Could not load this announcement.');

    document.getElementById('annCardSubject').textContent = data.subject;
    document.getElementById('annCardBody').textContent = data.body;

    const posted = new Date(data.sentAt);
    const postedStr = posted.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) +
      ' — ' + posted.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
    document.getElementById('annCardFooter').textContent = 'Posted by ' + data.postedBy + ' — ' + postedStr;
  } catch (err) {
    document.getElementById('annCardSubject').textContent = 'Could not load';
    document.getElementById('annCardBody').textContent = err.message;
  }

  return { close };
}
CARD_EOF

echo ""
echo "Done. Push with your usual save-progress.sh."
