#!/bin/bash
# fix-ghost-photo-doubleexposure-v1.sh
#
# Fixes the ghost photo (small circle in the seal) showing wrong color
# and looking blurry in the PDF. Root cause: the sharp canvas built for
# PDF capture was being layered ON TOP of the old blurry background-image,
# which was still present underneath -- since the ghost photo is
# semi-transparent by design (that's what creates the tinted seal look),
# both layers showed through and blended together.
#
# Fix: the underlying background-image is now hidden right before the
# sharp canvas is added, and properly restored afterward so the live
# page still displays normally. Verified with a colored test image
# (not just line patterns) to specifically catch color-blending issues,
# not just blur.
#
# Full, safe overwrite -- fully known/controlled.

set -e

echo "==> Overwriting portal/id-card-view.html"
mkdir -p portal
cat > portal/id-card-view.html << 'VIEW_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>MACDEN Staff ID Card</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@500;700;800&family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
<script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js"></script>
<style>
  :root{
    --green:#0d5c2f;
    --green-deep:#0a4a25;
    --maroon:#6b1f1f;
    --maroon-deep:#4d1616;
    --bg:#fbfaf6;
    --ink:#1a1a1a;
    --ink-soft:#4a4a4a;
    --hairline:rgba(107,31,31,0.18);
  }
  *{box-sizing:border-box; margin:0; padding:0;}
  body{
    background:#e9e5db;
    font-family:'Inter', sans-serif;
    padding:40px;
    display:flex;
    flex-wrap:wrap;
    gap:28px;
    align-items:flex-start;
    justify-content:center;
  }
  .stage-label{ width:100%; text-align:center; font-size:13px; color:#8a8478; letter-spacing:0.08em; text-transform:uppercase; margin-bottom:6px; }
  .card{ width:85.6mm; height:53.98mm; position:relative; background:var(--bg); border-radius:2.6mm; overflow:hidden; box-shadow:0 6px 22px rgba(0,0,0,0.28); color:var(--ink); }
  .guilloche{ position:absolute; inset:0; width:100%; height:100%; z-index:1; opacity:0.55; }
  .seal{ position:absolute; z-index:2; pointer-events:none; }
  .seal img{ width:100%; height:100%; display:block; opacity:0.13; }
  .front .seal{ width:44mm; height:44mm; right:-6mm; top:50%; transform:translateY(-50%); }
  .back .seal{ width:34mm; height:34mm; left:-4mm; bottom:-6mm; }
  .microring{ position:absolute; z-index:2; pointer-events:none; background-image:url('assets/microring.png'); background-size:contain; background-repeat:no-repeat; }
  .front .microring{ width:44mm; height:44mm; right:-6mm; top:50%; transform:translateY(-50%); }
  .header{ position:relative; z-index:5; height:9.2mm; background:linear-gradient(90deg, var(--green-deep) 0%, var(--green) 62%, var(--maroon) 100%); display:flex; align-items:center; padding:0 3mm; gap:2mm; }
  .header img{ height:6.4mm; width:6.4mm; object-fit:contain; background:#fff; border-radius:50%; padding:0.5mm; }
  .header .wordmark{ display:flex; flex-direction:column; line-height:1; }
  .header .wordmark .name{ font-family:'Manrope', sans-serif; font-weight:800; font-size:4.1mm; color:#fff; letter-spacing:0.02em; }
  .header .wordmark .tag{ font-family:'Inter', sans-serif; font-weight:500; font-size:1.5mm; color:rgba(255,255,255,0.82); letter-spacing:0.05em; text-transform:uppercase; }
  .header .doctype{ margin-left:auto; font-family:'Inter', sans-serif; font-weight:700; font-size:2mm; color:#fff; letter-spacing:0.12em; border:0.3mm solid rgba(255,255,255,0.55); padding:0.8mm 1.6mm; border-radius:1mm; white-space:nowrap; }
  .front-body{ position:relative; z-index:5; display:flex; gap:3mm; padding:2.6mm 3mm 2mm 3mm; align-items:flex-start; }
  .photo-wrap{ position:relative; flex-shrink:0; }
  .photo{ width:19mm; height:23mm; border-radius:1.4mm; background:linear-gradient(155deg, var(--green) 0%, var(--green-deep) 45%, var(--maroon) 100%); display:flex; align-items:center; justify-content:center; box-shadow:0 0.5mm 1.5mm rgba(0,0,0,0.25); border:0.35mm solid #fff; overflow:hidden; }
  .photo.has-photo{ background-size:cover; background-position:center 15%; }
  .photo .initials{ font-family:'Manrope', sans-serif; font-weight:800; font-size:6.5mm; color:#fbfaf6; letter-spacing:0.02em; }
  .ghost-photo{ position:absolute; width:9mm; height:9mm; border-radius:50%; background:var(--green-deep); overflow:hidden; display:flex; align-items:center; justify-content:center; z-index:3; left:51mm; top:33mm; }
  .ghost-photo.has-photo{ background-size:cover; background-position:center 15%; filter:grayscale(1) brightness(1.3) contrast(0.9); opacity:0.5; }
  .ghost-photo span{ font-family:'Manrope', sans-serif; font-weight:800; font-size:2.6mm; color:#fff; opacity:0.85; }
  .info{ display:flex; flex-direction:column; padding-top:0.5mm; min-width:0; }
  .info .label{ font-family:'Inter', sans-serif; font-weight:600; font-size:1.5mm; color:var(--maroon); letter-spacing:0.09em; text-transform:uppercase; margin-top:1.6mm; }
  .info .label:first-child{margin-top:0;}
  .info .value{ font-family:'Inter', sans-serif; font-weight:600; font-size:2.5mm; color:var(--ink); line-height:1.15; }
  .info .staff-name{ font-family:'Manrope', sans-serif; font-weight:800; font-size:3.6mm; color:var(--green-deep); line-height:1.08; margin-top:0.2mm; }
  .front-footer{ position:absolute; z-index:5; bottom:0; left:0; right:0; display:flex; justify-content:space-between; align-items:center; padding:1.2mm 3mm; background:rgba(255,255,255,0.55); border-top:0.25mm solid var(--hairline); }
  .staff-id-chip{ font-family:'Manrope', sans-serif; font-weight:800; font-size:2.3mm; color:#fff; background:linear-gradient(90deg, var(--maroon-deep), var(--maroon)); padding:0.9mm 2.2mm; border-radius:1mm; letter-spacing:0.03em; }
  .valid-line{ font-family:'Inter', sans-serif; font-weight:500; font-size:1.4mm; color:var(--ink-soft); letter-spacing:0.03em; }
  .back-body{ position:relative; z-index:5; display:flex; height:calc(100% - 9.2mm - 5mm); }
  .back-left{ flex:1; padding:2.2mm 2.6mm 1.2mm 2.6mm; display:flex; flex-direction:column; gap:1.4mm; }
  .back-left .block-label{ font-family:'Inter', sans-serif; font-weight:700; font-size:1.5mm; color:var(--maroon); letter-spacing:0.08em; text-transform:uppercase; }
  .back-left .block-value{ font-family:'Inter', sans-serif; font-weight:500; font-size:2mm; color:var(--ink); line-height:1.35; margin-top:0.3mm; }
  .back-left .divider{ height:0.25mm; background:var(--hairline); margin:0.4mm 0; }
  .property-line{ margin-top:auto; font-family:'Inter', sans-serif; font-weight:600; font-size:1.6mm; color:var(--green-deep); line-height:1.3; border-left:0.6mm solid var(--maroon); padding-left:1.4mm; }
  .back-right{ width:24mm; flex-shrink:0; display:flex; flex-direction:column; align-items:center; justify-content:center; gap:1.2mm; padding:2mm 1.6mm; background:rgba(13,92,47,0.045); border-left:0.25mm solid var(--hairline); }
  .qr-box{ width:18.5mm; height:18.5mm; background:#fff; border-radius:1mm; padding:1mm; box-shadow:0 0.4mm 1mm rgba(0,0,0,0.15); }
  .qr-box img{ width:100%; height:100%; display:block; }
  .verify-label{ font-family:'Manrope', sans-serif; font-weight:800; font-size:1.7mm; color:var(--green-deep); letter-spacing:0.06em; text-align:center; }
  .verify-sub{ font-family:'Inter', sans-serif; font-weight:500; font-size:1.25mm; color:var(--ink-soft); text-align:center; line-height:1.3; }
  .back-footer{ position:absolute; z-index:5; bottom:0; left:0; right:0; display:flex; justify-content:center; padding:1mm; background:linear-gradient(90deg, var(--green-deep), var(--maroon-deep)); }
  .back-footer span{ font-family:'Inter', sans-serif; font-weight:600; font-size:1.3mm; color:rgba(255,255,255,0.85); letter-spacing:0.1em; text-transform:uppercase; }
  #loading, #error{ width:100%; text-align:center; padding:60px 20px; font-size:15px; color:#5a5a5a; }
  #error{ color:#8a1f1f; display:none; }
  #cards{ display:none; }
  #downloadBar{ display:none; width:100%; text-align:center; margin-top:8px; }
  #downloadBtn{
    font-family:'Manrope', sans-serif; font-weight:700; font-size:14px;
    background:var(--green); color:#fff; border:none; padding:11px 24px;
    border-radius:8px; cursor:pointer; box-shadow:0 2px 8px rgba(13,92,47,0.25);
  }
  #downloadBtn:hover{ background:var(--green-deep); }
  #downloadBtn:disabled{ opacity:0.6; cursor:wait; }
  #downloadStatus{ font-size:12.5px; color:#5a5a5a; margin-top:8px; }
  @media print{
    body{ background:#fff; padding:0; display:block; }
    .stage-label{display:none;}
    #loading, #error{display:none !important;}
    .card-wrap{ page-break-after:always; display:flex; align-items:center; justify-content:center; height:100vh; }
    .card{ box-shadow:none; }
    @page{ size:85.6mm 53.98mm; margin:0; }
  }
</style>
</head>
<body>

<div id="loading">Loading staff ID card…</div>
<div id="error"></div>

<div id="cards">
<div class="stage-label">Front</div>
<div class="card-wrap">
<div class="card front">
  <svg class="guilloche" viewBox="0 0 856 540" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">
    <defs>
      <pattern id="wave1" width="60" height="60" patternUnits="userSpaceOnUse" patternTransform="rotate(8)">
        <path d="M0 30 Q15 5 30 30 T60 30" stroke="#0d5c2f" stroke-width="0.6" fill="none" opacity="0.16"/>
        <path d="M0 45 Q15 20 30 45 T60 45" stroke="#6b1f1f" stroke-width="0.5" fill="none" opacity="0.12"/>
      </pattern>
    </defs>
    <rect width="856" height="540" fill="url(#wave1)"/>
  </svg>
  <div class="seal"><img src="assets/logo-seal-mono.png" alt=""></div>
  <div class="microring"></div>
  <div class="header">
    <img src="assets/logo.jpeg" alt="MACDEN">
    <div class="wordmark"><div class="name">MACDEN</div><div class="tag">Communications Ltd</div></div>
    <div class="doctype">STAFF ID</div>
  </div>
  <div class="front-body">
    <div class="photo-wrap">
      <div class="photo" id="main-photo"></div>
    </div>
    <div class="info">
      <div class="label">Full Name</div>
      <div class="value staff-name" id="f-name"></div>
      <div class="label">Department</div>
      <div class="value" id="f-dept"></div>
      <div class="label">Role</div>
      <div class="value" id="f-role"></div>
    </div>
  </div>
  <div class="ghost-photo" id="ghost-photo"></div>
  <div class="front-footer">
    <div class="staff-id-chip" id="f-staffid"></div>
    <div class="valid-line">Valid while active</div>
  </div>
</div>
</div>

<div class="stage-label">Back</div>
<div class="card-wrap">
<div class="card back">
  <svg class="guilloche" viewBox="0 0 856 540" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">
    <defs>
      <pattern id="wave1back" width="60" height="60" patternUnits="userSpaceOnUse" patternTransform="rotate(8)">
        <path d="M0 30 Q15 5 30 30 T60 30" stroke="#0d5c2f" stroke-width="0.6" fill="none" opacity="0.16"/>
        <path d="M0 45 Q15 20 30 45 T60 45" stroke="#6b1f1f" stroke-width="0.5" fill="none" opacity="0.12"/>
      </pattern>
    </defs>
    <rect width="856" height="540" fill="url(#wave1back)"/>
  </svg>
  <div class="seal"><img src="assets/logo-seal-mono.png" alt=""></div>
  <div class="header">
    <img src="assets/logo.jpeg" alt="MACDEN">
    <div class="wordmark"><div class="name">MACDEN</div><div class="tag">Communications Ltd</div></div>
    <div class="doctype">STAFF ID</div>
  </div>
  <div class="back-body">
    <div class="back-left">
      <div>
        <div class="block-label">Head Office</div>
        <div class="block-value">4, Wempco Road,<br>Ogba, Lagos state.</div>
      </div>
      <div class="divider"></div>
      <div>
        <div class="block-label">Emergency Contact</div>
        <div class="block-value">Company: +234 904 211 7497</div>
        <div class="block-value" id="b-employee-phone" style="display:none;"></div>
      </div>
      <div class="property-line">
        Property of MACDEN Communications Ltd.<br>
        If found, please return to the address above.
      </div>
    </div>
    <div class="back-right">
      <div class="qr-box"><img id="qr-img" src="" alt="QR Verification"></div>
      <div class="verify-label">VERIFY STAFF ID</div>
      <div class="verify-sub">Scan to confirm identity &amp; active status</div>
    </div>
  </div>
  <div class="back-footer"><span>This card remains the property of MACDEN Communications Ltd</span></div>
</div>
</div>
</div>

<div id="downloadBar">
  <button id="downloadBtn">Download PDF</button>
  <div id="downloadStatus"></div>
</div>

<script>
(function(){
  const params = new URLSearchParams(window.location.search);
  const requestId = params.get('requestId');
  const fieldId = params.get('fieldId');
  const $ = (id) => document.getElementById(id);

  function initials(name){
    return (name || '?').split(' ').filter(Boolean).slice(0,2).map(w => w[0].toUpperCase()).join('');
  }

  if (!requestId && !fieldId) {
    $('loading').style.display = 'none';
    $('error').style.display = 'block';
    $('error').textContent = 'No request specified.';
    return;
  }

  const fetchUrl = fieldId
    ? '/api/field-staff/' + encodeURIComponent(fieldId) + '/card'
    : '/api/id-card/card/' + encodeURIComponent(requestId);

  fetch(fetchUrl, { credentials: 'include' })
    .then(r => r.json().then(data => ({ ok: r.ok, data })))
    .then(({ ok, data }) => {
      $('loading').style.display = 'none';

      if (!ok) {
        $('error').style.display = 'block';
        $('error').textContent = data.error || 'Could not load this ID card.';
        return;
      }

      $('cards').style.display = 'flex';
      $('f-name').textContent = data.full_name;
      $('f-dept').textContent = data.department || '—';
      $('f-role').textContent = data.role;
      $('f-staffid').textContent = data.staff_id;
      $('qr-img').src = data.qr_data_url;

      if (data.employee_phone) {
        const phoneEl = $('b-employee-phone');
        phoneEl.textContent = 'Employee: ' + data.employee_phone;
        phoneEl.style.display = 'block';
      }

      const mainPhoto = $('main-photo');
      const ghostPhoto = $('ghost-photo');
      if (data.photo_url) {
        mainPhoto.classList.add('has-photo');
        mainPhoto.style.backgroundImage = "url('" + data.photo_url + "')";
        mainPhoto.innerHTML = '';
        ghostPhoto.classList.add('has-photo');
        ghostPhoto.style.backgroundImage = "url('" + data.photo_url + "')";
        ghostPhoto.innerHTML = '';
      } else {
        mainPhoto.innerHTML = '<span class="initials">' + initials(data.full_name) + '</span>';
        ghostPhoto.innerHTML = '<span>' + initials(data.full_name) + '</span>';
      }

      document.getElementById('downloadBar').style.display = 'block';
      document.getElementById('downloadBtn').addEventListener('click', function(){
        downloadCardAsPDF(data.full_name, data.staff_id, data.photo_url || null);
      });
    })
    .catch(() => {
      $('loading').style.display = 'none';
      $('error').style.display = 'block';
      $('error').textContent = 'Something went wrong loading this card.';
    });

  // Draws an image into a canvas with cover-fit + object-position math,
  // matching the CSS object-fit:cover / object-position:center 15% look
  // exactly, but as a plain <canvas> element -- which html2canvas
  // captures natively and sharply, unlike CSS background-image (verified
  // blurry) or <img object-fit> (verified mismatched crop).
  function buildCroppedCanvas(img, boxWidthPx, boxHeightPx, scale, filterCss, alpha) {
    const canvas = document.createElement('canvas');
    canvas.width = boxWidthPx * scale;
    canvas.height = boxHeightPx * scale;
    canvas.style.width = '100%';
    canvas.style.height = '100%';
    canvas.style.display = 'block';
    const ctx = canvas.getContext('2d');

    const boxRatio = boxWidthPx / boxHeightPx;
    const imgRatio = img.naturalWidth / img.naturalHeight;
    let sw, sh, sx, sy;
    if (imgRatio > boxRatio) {
      sh = img.naturalHeight;
      sw = sh * boxRatio;
      sy = 0;
      sx = (img.naturalWidth - sw) * 0.5;
    } else {
      sw = img.naturalWidth;
      sh = sw / boxRatio;
      sx = 0;
      sy = (img.naturalHeight - sh) * 0.15;
    }

    if (filterCss) ctx.filter = filterCss;
    if (alpha !== undefined) ctx.globalAlpha = alpha;
    ctx.drawImage(img, sx, sy, sw, sh, 0, 0, canvas.width, canvas.height);
    return canvas;
  }

  async function loadImage(src){
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.crossOrigin = 'anonymous';
      img.onload = () => resolve(img);
      img.onerror = reject;
      img.src = src;
    });
  }

  async function downloadCardAsPDF(fullName, staffId, photoUrl){
    const btn = document.getElementById('downloadBtn');
    const status = document.getElementById('downloadStatus');
    btn.disabled = true;
    status.textContent = 'Generating PDF…';

    const tempCanvases = [];

    try {
      const front = document.querySelector('.card.front');
      const back = document.querySelector('.card.back');

      // Swap the (visually correct but blurry-when-captured) background-image
      // photos for sharp pre-cropped canvases, just for this capture.
      if (photoUrl) {
        const img = await loadImage(photoUrl);
        const mainPhoto = document.getElementById('main-photo');
        const ghostPhoto = document.getElementById('ghost-photo');

        const mainCanvas = buildCroppedCanvas(img, mainPhoto.offsetWidth, mainPhoto.offsetHeight, 6);
        mainPhoto.style.backgroundImage = 'none';
        mainPhoto.appendChild(mainCanvas);
        tempCanvases.push({ el: mainPhoto, canvas: mainCanvas, restoreBg: "url('" + photoUrl + "')" });

        const ghostCanvas = buildCroppedCanvas(
          img, ghostPhoto.offsetWidth, ghostPhoto.offsetHeight, 6,
          'grayscale(1) brightness(1.3) contrast(0.9)', 0.5
        );
        ghostPhoto.style.backgroundImage = 'none';
        ghostPhoto.appendChild(ghostCanvas);
        tempCanvases.push({ el: ghostPhoto, canvas: ghostCanvas, restoreBg: "url('" + photoUrl + "')" });
      }

      const [frontCanvas, backCanvas] = await Promise.all([
        html2canvas(front, { scale: 6, backgroundColor: null, useCORS: true }),
        html2canvas(back, { scale: 6, backgroundColor: null, useCORS: true })
      ]);

      const { jsPDF } = window.jspdf;
      const doc = new jsPDF({ unit: 'mm', format: [85.6, 53.98], orientation: 'landscape' });

      doc.addImage(frontCanvas.toDataURL('image/png', 1.0), 'PNG', 0, 0, 85.6, 53.98);
      doc.addPage([85.6, 53.98], 'landscape');
      doc.addImage(backCanvas.toDataURL('image/png', 1.0), 'PNG', 0, 0, 85.6, 53.98);

      const safeName = (fullName || 'staff').replace(/[^a-z0-9]+/gi, '-').toLowerCase();
      const safeId = (staffId || '').replace(/[^a-z0-9]+/gi, '-').toLowerCase();
      doc.save('macden-id-card-' + safeName + (safeId ? '-' + safeId : '') + '.pdf');

      status.textContent = 'Downloaded.';
    } catch (err) {
      console.error('PDF generation failed:', err);
      status.textContent = 'Could not generate PDF. If your photo is hosted somewhere blocking cross-site access, that may be why -- try again, or contact IT.';
    } finally {
      // Clean up the temporary canvases so the live page still shows the
      // normal background-image version afterward, and repeat downloads
      // don't stack duplicate canvases on top of each other.
      tempCanvases.forEach(({ el, canvas, restoreBg }) => {
        el.removeChild(canvas);
        el.style.backgroundImage = restoreBg;
      });
      btn.disabled = false;
    }
  }
})();
</script>

</body>
</html>
VIEW_EOF

echo ""
echo "Done. Push with your usual save-progress.sh."
