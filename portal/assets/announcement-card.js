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
