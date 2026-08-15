#!/bin/bash
# fix-verify-redesign-v1.sh
#
# Full redesign of portal/verify.html (the QR verification page):
#   - Large, instant-read verdict banner (checkmark/X icon, full-color background)
#   - Live "Verified: [date] — [time]" timestamp
#   - Single, prominent tap-to-call button (removed the duplicate phone
#     number that used to also appear in the footer)
#   - Faint watermark seal visible on every state, not just loading
#   - A genuine fourth state: "NOT RECOGNIZED" (amber) for a fake/invalid
#     code, distinct from "NOT ACTIVE" (red) for a real-but-deactivated
#     staff member -- these mean different things and now look different
#   - Real animated loading spinner (not static dots)
#   - Mobile-first, large tap targets
#
# Tested against all four real states (loading, active, inactive,
# unrecognized) with actual rendered screenshots before shipping.
#
# Full, safe overwrite -- fully known/controlled.

set -e

echo "==> Overwriting portal/verify.html"
mkdir -p portal
cat > portal/verify.html << 'VIEW_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="robots" content="noindex, nofollow">
<title>MACDEN Staff Verification</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@600;700;800&family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
  :root{
    --green:#0d5c2f;
    --green-deep:#0a4a25;
    --maroon:#6b1f1f;
    --bg:#fbfaf6;
    --ink:#1a1a1a;
    --ink-soft:#5a5a5a;
    --error:#8a1f1f;
    --error-deep:#6b1717;
    --amber:#8a6d00;
    --amber-deep:#6b5500;
  }
  *{box-sizing:border-box; margin:0; padding:0;}
  body{
    font-family:'Inter', sans-serif;
    background:#e9e5db;
    min-height:100vh;
    display:flex;
    align-items:center;
    justify-content:center;
    padding:16px;
  }

  .phone{
    width:100%;
    max-width:400px;
    background:var(--bg);
    border-radius:20px;
    overflow:hidden;
    box-shadow:0 20px 50px rgba(0,0,0,0.25);
    position:relative;
  }

  .topbar{
    display:flex; align-items:center; gap:8px;
    padding:14px 20px;
    background:var(--bg);
    border-bottom:1px solid rgba(0,0,0,0.06);
  }
  .topbar .lock{ font-size:14px; }
  .topbar .label{
    font-family:'Manrope', sans-serif; font-weight:700; font-size:13px;
    color:var(--ink); letter-spacing:0.01em;
  }

  /* ===== Watermark seal, visible on every state ===== */
  .seal-watermark{
    position:absolute;
    top:110px; left:50%; transform:translateX(-50%);
    width:280px; height:280px;
    opacity:0.05;
    pointer-events:none;
    z-index:0;
    background-size:contain;
    background-repeat:no-repeat;
    background-position:center;
  }

  /* ===== Verdict banner (full-width, colored) ===== */
  .verdict-banner{
    position:relative; z-index:1;
    padding:32px 24px 26px;
    text-align:center;
    color:#fff;
  }
  .verdict-banner.active{ background:linear-gradient(160deg, var(--green), var(--green-deep)); }
  .verdict-banner.inactive{ background:linear-gradient(160deg, var(--error), var(--error-deep)); }
  .verdict-banner.unrecognized{ background:linear-gradient(160deg, var(--amber), var(--amber-deep)); }

  .verdict-icon{
    width:76px; height:76px; border-radius:50%;
    border:3px solid rgba(255,255,255,0.55);
    display:flex; align-items:center; justify-content:center;
    margin:0 auto 14px;
    background:rgba(255,255,255,0.12);
  }
  .verdict-icon svg{ width:38px; height:38px; }

  .verdict-title{
    font-family:'Manrope', sans-serif; font-weight:800; font-size:26px;
    letter-spacing:0.01em; margin-bottom:4px;
  }
  .verdict-sub{ font-size:13px; opacity:0.92; margin-bottom:10px; }
  .verdict-time{
    display:inline-flex; align-items:center; gap:5px;
    font-size:11.5px; opacity:0.85;
    background:rgba(255,255,255,0.15);
    padding:4px 10px; border-radius:20px;
  }

  /* ===== Content area ===== */
  .content{ position:relative; z-index:1; padding:20px; }

  .staff-card{
    display:flex; gap:14px; align-items:center;
    background:#fff;
    border-radius:12px;
    padding:16px;
    box-shadow:0 1px 6px rgba(0,0,0,0.06);
    margin-bottom:16px;
  }
  .staff-photo{
    width:64px; height:64px; border-radius:10px; flex-shrink:0;
    background:linear-gradient(155deg, var(--green), var(--maroon));
    display:flex; align-items:center; justify-content:center;
    overflow:hidden;
  }
  .staff-photo img{ width:100%; height:100%; object-fit:cover; }
  .staff-photo span{ color:#fff; font-family:'Manrope', sans-serif; font-weight:800; font-size:20px; }

  .staff-details{ flex:1; min-width:0; }
  .staff-name{ font-family:'Manrope', sans-serif; font-weight:800; font-size:17px; color:var(--ink); line-height:1.2; margin-bottom:6px; }
  .staff-grid{ display:grid; grid-template-columns:1fr 1fr; gap:6px 10px; }
  .staff-field .label{ font-size:9.5px; font-weight:700; color:var(--maroon); text-transform:uppercase; letter-spacing:0.04em; }
  .staff-field .value{ font-size:12.5px; font-weight:600; color:var(--ink); }

  .call-btn{
    display:flex; align-items:center; justify-content:center; gap:8px;
    width:100%;
    padding:14px;
    border-radius:12px;
    text-decoration:none;
    font-family:'Manrope', sans-serif; font-weight:700; font-size:15px;
    margin-bottom:14px;
    transition:transform 0.1s ease;
  }
  .call-btn:active{ transform:scale(0.98); }
  .call-btn.active{ background:var(--green); color:#fff; }
  .call-btn.inactive{ background:var(--error); color:#fff; }
  .call-btn.unrecognized{ background:var(--amber); color:#fff; }
  .call-btn svg{ width:16px; height:16px; }

  .trust-note{
    display:flex; align-items:flex-start; gap:8px;
    background:rgba(13,92,47,0.06);
    border-radius:10px;
    padding:10px 12px;
    font-size:11px; color:var(--ink-soft); line-height:1.4;
    margin-bottom:16px;
  }
  .trust-note svg{ width:14px; height:14px; flex-shrink:0; margin-top:1px; color:var(--green); }

  .footer{ text-align:center; padding-top:2px; }
  .footer .company{ font-family:'Manrope', sans-serif; font-weight:700; font-size:12px; color:var(--ink); margin-bottom:2px; }
  .footer .address{ font-size:11px; color:var(--ink-soft); }

  /* ===== Loading state ===== */
  .loading-wrap{
    position:relative; z-index:1;
    padding:70px 24px 50px;
    text-align:center;
  }
  .loading-badge{
    width:90px; height:90px; border-radius:50%;
    background:#fff;
    display:flex; align-items:center; justify-content:center;
    margin:0 auto 22px;
    box-shadow:0 4px 16px rgba(0,0,0,0.08);
    position:relative;
  }
  .loading-badge img{ width:56px; height:56px; border-radius:50%; }
  .loading-ring{
    position:absolute; inset:-6px;
    border-radius:50%;
    border:3px solid rgba(13,92,47,0.15);
    border-top-color:var(--green);
    animation:spin 1s linear infinite;
  }
  @keyframes spin{ to{ transform:rotate(360deg); } }

  .loading-title{ font-family:'Manrope', sans-serif; font-weight:700; font-size:17px; color:var(--ink); margin-bottom:6px; }
  .loading-sub{ font-size:12.5px; color:var(--ink-soft); margin-bottom:20px; }

  .pulse-dots{ display:flex; gap:6px; justify-content:center; }
  .pulse-dots span{
    width:7px; height:7px; border-radius:50%; background:var(--green);
    animation:pulse 1.2s ease-in-out infinite;
  }
  .pulse-dots span:nth-child(2){ animation-delay:0.15s; background:var(--maroon); }
  .pulse-dots span:nth-child(3){ animation-delay:0.3s; background:var(--green); opacity:0.5; }
  @keyframes pulse{ 0%,100%{ opacity:0.3; transform:scale(0.8); } 50%{ opacity:1; transform:scale(1.1); } }

  .hidden{ display:none !important; }
</style>
</head>
<body>

<div class="phone">
  <div class="topbar">
    <span class="lock">🔒</span>
    <span class="label">MACDEN Staff Verification</span>
  </div>

  <div class="seal-watermark" id="seal-watermark"></div>

  <!-- Loading state -->
  <div id="state-loading">
    <div class="loading-wrap">
      <div class="loading-badge">
        <div class="loading-ring"></div>
        <img src="assets/logo.jpeg" alt="MACDEN">
      </div>
      <div class="loading-title">Verifying Staff…</div>
      <div class="loading-sub">Please wait a moment while we confirm details.</div>
      <div class="pulse-dots"><span></span><span></span><span></span></div>
    </div>
  </div>

  <!-- Unrecognized code state -->
  <div id="state-invalid" class="hidden">
    <div class="verdict-banner unrecognized">
      <div class="verdict-icon">
        <svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.5" stroke-linecap="round"><path d="M12 8v5M12 16.5h.01M10.3 3.9L2.7 17a2 2 0 0 0 1.7 3h15.2a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/></svg>
      </div>
      <div class="verdict-title">NOT RECOGNIZED</div>
      <div class="verdict-sub">This code doesn't match any MACDEN staff record.</div>
    </div>
    <div class="content">
      <div class="trust-note">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 2 3 7v6c0 5 4 9 9 9s9-4 9-9V7z"/></svg>
        If you believe this is a genuine MACDEN staff card, please contact the number below directly rather than relying on this scan.
      </div>
      <a class="call-btn unrecognized" id="call-btn-invalid" href="#">
        <svg viewBox="0 0 24 24" fill="currentColor"><path d="M6.6 10.8c1.4 2.8 3.8 5.1 6.6 6.6l2.2-2.2c.3-.3.7-.4 1-.2 1.1.4 2.3.6 3.6.6.6 0 1 .4 1 1V20c0 .6-.4 1-1 1C10.6 21 3 13.4 3 4c0-.6.4-1 1-1h3.5c.6 0 1 .4 1 1 0 1.3.2 2.5.6 3.6.1.4 0 .8-.2 1L6.6 10.8z"/></svg>
        Call MACDEN to Confirm
      </a>
      <div class="footer">
        <div class="company">MACDEN COMMUNICATIONS LTD.</div>
        <div class="address">4, Wempco Road, Ogba, Lagos state.</div>
      </div>
    </div>
  </div>

  <!-- Connection/server error state -->
  <div id="state-error" class="hidden">
    <div class="loading-wrap">
      <div class="loading-badge" style="box-shadow:none; border:2px solid var(--error);">
        <img src="assets/logo.jpeg" alt="MACDEN" style="opacity:0.5;">
      </div>
      <div class="loading-title">Verification Unavailable</div>
      <div class="loading-sub">Something went wrong. Please try scanning again in a moment.</div>
    </div>
  </div>

  <!-- Result state: active or inactive -->
  <div id="state-result" class="hidden">
    <div class="verdict-banner" id="verdict-banner">
      <div class="verdict-icon" id="verdict-icon"></div>
      <div class="verdict-title" id="verdict-title"></div>
      <div class="verdict-sub" id="verdict-sub"></div>
      <div class="verdict-time" id="verdict-time"></div>
    </div>

    <div class="content">
      <div class="staff-card">
        <div class="staff-photo" id="staff-photo"><span id="staff-photo-initials"></span></div>
        <div class="staff-details">
          <div class="staff-name" id="staff-name"></div>
          <div class="staff-grid">
            <div class="staff-field"><div class="label">Role</div><div class="value" id="f-role"></div></div>
            <div class="staff-field"><div class="label">Staff ID</div><div class="value" id="f-staffid"></div></div>
            <div class="staff-field"><div class="label">Department</div><div class="value" id="f-department"></div></div>
            <div class="staff-field" id="branch-field" style="display:none;"><div class="label">Branch</div><div class="value" id="f-branch"></div></div>
          </div>
        </div>
      </div>

      <a class="call-btn" id="call-btn-result" href="#">
        <svg viewBox="0 0 24 24" fill="currentColor"><path d="M6.6 10.8c1.4 2.8 3.8 5.1 6.6 6.6l2.2-2.2c.3-.3.7-.4 1-.2 1.1.4 2.3.6 3.6.6.6 0 1 .4 1 1V20c0 .6-.4 1-1 1C10.6 21 3 13.4 3 4c0-.6.4-1 1-1h3.5c.6 0 1 .4 1 1 0 1.3.2 2.5.6 3.6.1.4 0 .8-.2 1L6.6 10.8z"/></svg>
        Call MACDEN
      </a>

      <div class="trust-note">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 2 3 7v6c0 5 4 9 9 9s9-4 9-9V7z"/></svg>
        This page is generated live by MACDEN's staff system and cannot be faked.
      </div>

      <div class="footer">
        <div class="company">MACDEN COMMUNICATIONS LTD.</div>
        <div class="address">4, Wempco Road, Ogba, Lagos state.</div>
      </div>
    </div>
  </div>
</div>

<script>
(function(){
  const COMPANY_PHONE = '+2348079907497';
  const token = new URLSearchParams(window.location.search).get('token');
  const $ = (id) => document.getElementById(id);

  function show(id){ $(id).classList.remove('hidden'); }
  function hide(id){ $(id).classList.add('hidden'); }

  function initials(name){
    return (name || '?').split(' ').filter(Boolean).slice(0,2).map(w => w[0].toUpperCase()).join('');
  }

  function checkIconSvg(){
    return '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>';
  }
  function xIconSvg(){
    return '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18M6 6l12 12"/></svg>';
  }

  // Set up tel: links
  document.querySelectorAll('#call-btn-invalid, #call-btn-result').forEach(a => {
    a.href = 'tel:' + COMPANY_PHONE;
  });

  // Watermark seal -- visible on every state, set once
  $('seal-watermark').style.backgroundImage = "url('assets/logo-seal-mono.png')";

  if (!token) {
    hide('state-loading');
    show('state-invalid');
    return;
  }

  fetch('/api/verify/' + encodeURIComponent(token))
    .then(r => r.json().then(data => ({ ok: r.ok, data })))
    .then(({ ok, data }) => {
      hide('state-loading');

      if (!ok || !data.valid) {
        show('state-invalid');
        return;
      }

      show('state-result');

      const banner = $('verdict-banner');
      const icon = $('verdict-icon');
      const callBtn = $('call-btn-result');

      if (data.active) {
        banner.classList.add('active');
        callBtn.classList.add('active');
        icon.innerHTML = checkIconSvg();
        $('verdict-title').textContent = 'ACTIVE';
        $('verdict-sub').textContent = 'This staff member is currently active.';
      } else {
        banner.classList.add('inactive');
        callBtn.classList.add('inactive');
        icon.innerHTML = xIconSvg();
        $('verdict-title').textContent = 'NOT ACTIVE';
        $('verdict-sub').textContent = 'This staff member is not currently active.';
      }

      const now = new Date();
      const timeStr = now.toLocaleDateString('en-US', { month:'short', day:'numeric', year:'numeric' }) +
        ' — ' + now.toLocaleTimeString('en-US', { hour:'2-digit', minute:'2-digit' });
      $('verdict-time').innerHTML = '🕐 Verified: ' + timeStr;

      $('staff-name').textContent = data.full_name || 'Unknown';
      $('f-role').textContent = data.role || '—';
      $('f-staffid').textContent = data.staff_id || '—';
      $('f-department').textContent = data.department || '—';

      if (data.branch) {
        $('f-branch').textContent = data.branch;
        $('branch-field').style.display = 'block';
      }

      const photoBox = $('staff-photo');
      if (data.photo_url) {
        photoBox.innerHTML = '<img src="' + data.photo_url + '" alt="">';
      } else {
        $('staff-photo-initials').textContent = initials(data.full_name);
      }
    })
    .catch(() => {
      hide('state-loading');
      show('state-error');
    });
})();
</script>

</body>
</html>
VIEW_EOF

echo ""
echo "Done. Push with your usual save-progress.sh."
