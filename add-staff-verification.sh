#!/bin/bash
# add-staff-verification.sh
#
# Adds the live staff verification system: the /api/verify/:token endpoint
# and the public portal/verify.html page. This is the QR-code destination
# for the staff ID card -- confirms a card is real and the staff member is
# currently active, without exposing anything beyond what's already printed
# on the physical card.
#
# Does NOT run the Supabase migration -- that's a database-side change and
# must be run manually in the Supabase SQL editor (see the printed reminder
# at the end of this script). This script only touches the git repo.

set -e  # stop immediately if anything fails, don't push a half-applied patch

echo "==> Creating server/routes/verify.js"
mkdir -p server/routes
cat > server/routes/verify.js << 'ROUTE_EOF'
// server/routes/verify.js
//
// Public staff verification endpoint. Scanned from the QR code on the back
// of a staff ID card. Deliberately returns ONLY what's needed to confirm
// someone is a real, active MACDEN staff member -- no email, phone, or
// other PII that isn't already visible on the printed card itself.
//
// Looked up by verification_token (random UUID), never by the human-readable
// staff ID, so the endpoint can't be scraped by guessing sequential IDs.

const express = require('express');
const router = express.Router();
const rateLimit = require('express-rate-limit');
const { supabase } = require('../config/supabaseClient'); // adjust destructure if supabaseClient exports differently (module.exports = supabase vs { supabase })

// Basic abuse protection: this is a public, unauthenticated endpoint,
// so throttle it independently of your normal API rate limits.
const verifyLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 30,                  // 30 lookups per IP per window is generous for real scans, tight for scraping
  message: { error: 'Too many verification requests. Please try again shortly.' }
});

router.get('/api/verify/:token', verifyLimiter, async (req, res) => {
  const { token } = req.params;

  // UUID shape check before hitting the DB at all
  const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!uuidPattern.test(token)) {
    return res.status(400).json({ valid: false, error: 'Invalid verification code.' });
  }

  try {
    // NOTE: department_id is a foreign key, not the name itself. This assumes
    // a `departments` table with a `name` column and a standard Supabase/PostgREST
    // relationship Postgres can embed automatically. If your relation/table is
    // named differently, adjust the select string below accordingly.
    const { data: staffMember, error } = await supabase
      .from('staff')
      .select('full_name, staff_id, department_id, departments(name), role, branch, photo_url, is_active')
      .eq('verification_token', token)
      .single();

    if (error || !staffMember) {
      return res.status(404).json({ valid: false, error: 'No matching staff record found.' });
    }

    return res.json({
      valid: true,
      active: staffMember.is_active,
      full_name: staffMember.full_name,
      staff_id: staffMember.staff_id,
      department: staffMember.departments ? staffMember.departments.name : null,
      role: staffMember.role,
      branch: staffMember.branch || null,
      photo_url: staffMember.photo_url || null
    });

  } catch (err) {
    console.error('[VERIFY-ERROR]', err);
    return res.status(500).json({ valid: false, error: 'Verification service temporarily unavailable.' });
  }
});

module.exports = router;
ROUTE_EOF

echo "==> Creating portal/verify.html"
mkdir -p portal
cat > portal/verify.html << 'HTML_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="robots" content="noindex, nofollow">
<title>MACDEN Staff Verification</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@500;700;800&family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
  :root{
    --green:#0d5c2f;
    --green-deep:#0a4a25;
    --maroon:#6b1f1f;
    --bg:#fbfaf6;
    --ink:#1a1a1a;
    --ink-soft:#5a5a5a;
    --ok:#0d5c2f;
    --fail:#8a1f1f;
  }
  *{box-sizing:border-box; margin:0; padding:0;}
  body{
    font-family:'Inter', sans-serif;
    background:linear-gradient(160deg, #0a4a25 0%, #1a1a1a 70%);
    min-height:100vh;
    display:flex;
    align-items:center;
    justify-content:center;
    padding:24px;
  }
  .panel{
    width:100%;
    max-width:380px;
    background:var(--bg);
    border-radius:14px;
    overflow:hidden;
    box-shadow:0 20px 50px rgba(0,0,0,0.35);
  }
  .panel-header{
    background:linear-gradient(90deg, var(--green-deep), var(--green) 65%, var(--maroon));
    padding:20px 22px;
    display:flex;
    align-items:center;
    gap:10px;
  }
  .panel-header img{
    width:34px; height:34px;
    border-radius:50%;
    background:#fff;
    padding:2px;
  }
  .panel-header .brand-name{
    font-family:'Manrope', sans-serif;
    font-weight:800;
    font-size:17px;
    color:#fff;
  }
  .panel-header .brand-sub{
    font-family:'Inter', sans-serif;
    font-weight:500;
    font-size:10.5px;
    color:rgba(255,255,255,0.82);
    text-transform:uppercase;
    letter-spacing:0.06em;
  }

  .panel-body{
    padding:26px 22px 22px 22px;
  }

  #state-loading, #state-error, #state-invalid{
    text-align:center;
    padding:20px 4px;
    color:var(--ink-soft);
    font-size:14px;
  }

  .status-badge{
    display:inline-flex;
    align-items:center;
    gap:6px;
    font-family:'Manrope', sans-serif;
    font-weight:800;
    font-size:13px;
    letter-spacing:0.04em;
    padding:6px 12px;
    border-radius:20px;
    margin-bottom:16px;
  }
  .status-badge.active{ background:rgba(13,92,47,0.12); color:var(--ok); }
  .status-badge.inactive{ background:rgba(138,31,31,0.12); color:var(--fail); }
  .status-badge .dot{
    width:8px; height:8px; border-radius:50%;
    background:currentColor;
  }

  .staff-row{
    display:flex;
    gap:14px;
    align-items:center;
    margin-bottom:18px;
  }
  .staff-photo{
    width:56px; height:56px;
    border-radius:10px;
    background:linear-gradient(155deg, var(--green), var(--maroon));
    display:flex;
    align-items:center;
    justify-content:center;
    color:#fff;
    font-family:'Manrope', sans-serif;
    font-weight:800;
    font-size:20px;
    flex-shrink:0;
    overflow:hidden;
  }
  .staff-photo img{ width:100%; height:100%; object-fit:cover; }
  .staff-name{
    font-family:'Manrope', sans-serif;
    font-weight:800;
    font-size:18px;
    color:var(--green-deep);
    line-height:1.2;
  }
  .staff-role{
    font-family:'Inter', sans-serif;
    font-weight:500;
    font-size:13px;
    color:var(--ink-soft);
  }

  .detail-grid{
    display:grid;
    grid-template-columns:1fr 1fr;
    gap:12px 14px;
    padding:14px 0;
    border-top:1px solid rgba(107,31,31,0.14);
  }
  .detail-grid .label{
    font-family:'Inter', sans-serif;
    font-weight:600;
    font-size:10.5px;
    color:var(--maroon);
    text-transform:uppercase;
    letter-spacing:0.06em;
  }
  .detail-grid .value{
    font-family:'Inter', sans-serif;
    font-weight:600;
    font-size:13.5px;
    color:var(--ink);
    margin-top:2px;
  }

  .footer-note{
    text-align:center;
    font-size:11px;
    color:var(--ink-soft);
    margin-top:16px;
    line-height:1.5;
  }

  .inactive-warning{
    background:rgba(138,31,31,0.08);
    border:1px solid rgba(138,31,31,0.25);
    color:var(--fail);
    font-size:12.5px;
    font-weight:600;
    padding:10px 12px;
    border-radius:8px;
    margin-bottom:16px;
    line-height:1.4;
  }

  .hidden{ display:none; }
</style>
</head>
<body>

<div class="panel">
  <div class="panel-header">
    <img src="/portal/assets/logo.jpeg" alt="MACDEN">
    <div>
      <div class="brand-name">MACDEN</div>
      <div class="brand-sub">Staff Verification</div>
    </div>
  </div>

  <div class="panel-body">
    <div id="state-loading">Checking staff record…</div>

    <div id="state-invalid" class="hidden">
      This verification code is not recognized. If you're checking a physical
      MACDEN staff card, please contact the address printed on the card directly.
    </div>

    <div id="state-error" class="hidden">
      Verification is temporarily unavailable. Please try again shortly.
    </div>

    <div id="state-result" class="hidden">
      <div id="badge-active" class="status-badge active hidden">
        <span class="dot"></span> ACTIVE STAFF MEMBER
      </div>
      <div id="badge-inactive" class="status-badge inactive hidden">
        <span class="dot"></span> NOT CURRENTLY ACTIVE
      </div>

      <div id="inactive-warning" class="inactive-warning hidden">
        This card is not currently associated with an active staff member.
        Please do not treat it as valid identification.
      </div>

      <div class="staff-row">
        <div class="staff-photo" id="photo-box">
          <span id="photo-initials"></span>
        </div>
        <div>
          <div class="staff-name" id="staff-name"></div>
          <div class="staff-role" id="staff-role"></div>
        </div>
      </div>

      <div class="detail-grid">
        <div>
          <div class="label">Staff ID</div>
          <div class="value" id="staff-id"></div>
        </div>
        <div>
          <div class="label">Department</div>
          <div class="value" id="staff-dept"></div>
        </div>
        <div id="branch-row" class="hidden">
          <div class="label">Branch</div>
          <div class="value" id="staff-branch"></div>
        </div>
      </div>
    </div>

    <div class="footer-note">
      Verified against the live MACDEN staff directory.<br>
      MACDEN Communications Ltd &middot; Ogba, Wemco Road, Lagos, Nigeria
    </div>
  </div>
</div>

<script>
(function(){
  const token = new URLSearchParams(window.location.search).get('token');
  const $ = (id) => document.getElementById(id);

  function show(id){ $(id).classList.remove('hidden'); }
  function hide(id){ $(id).classList.add('hidden'); }

  function initials(name){
    return name.split(' ').filter(Boolean).slice(0,2).map(w => w[0].toUpperCase()).join('');
  }

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
      $('staff-name').textContent = data.full_name;
      $('staff-role').textContent = data.role;
      $('staff-id').textContent = data.staff_id;
      $('staff-dept').textContent = data.department;

      if (data.branch) {
        $('staff-branch').textContent = data.branch;
        show('branch-row');
      }

      if (data.photo_url) {
        $('photo-box').innerHTML = '<img src="' + data.photo_url + '" alt="">';
      } else {
        $('photo-initials').textContent = initials(data.full_name || '?');
      }

      if (data.active) {
        show('badge-active');
      } else {
        show('badge-inactive');
        show('inactive-warning');
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
HTML_EOF

echo "==> Saving the SQL migration to server/migrations/ for reference (NOT auto-run)"
mkdir -p server/migrations
cat > server/migrations/add_verification_token.sql << 'SQL_EOF'
-- Run this in the Supabase SQL editor against the `staff` table.
-- Two separate columns, two separate jobs:
--   staff_id           -> human-readable, printed on the badge (e.g. MAC-2026-0017)
--   verification_token -> random, never shown, encoded in the QR code only

ALTER TABLE staff ADD COLUMN IF NOT EXISTS staff_id TEXT UNIQUE;
ALTER TABLE staff ADD COLUMN IF NOT EXISTS verification_token UUID DEFAULT gen_random_uuid();

CREATE UNIQUE INDEX IF NOT EXISTS idx_staff_verification_token ON staff(verification_token);

-- Backfill any existing rows that predate the default
UPDATE staff SET verification_token = gen_random_uuid() WHERE verification_token IS NULL;

-- staff_id is NOT auto-generated here on purpose -- the numbering convention
-- (prefix, sequencing, department-tied or not) still needs to be decided.
-- Assign real staff_id values manually or via a follow-up script once that's settled.
SQL_EOF

echo "==> Wiring the route into server/server.js"
if grep -q "require('./routes/verify')" server/server.js; then
  echo "    Already wired in -- skipping (script is safe to re-run)."
else
  if ! grep -qF "app.use('/api/accounting', requireAuth);" server/server.js; then
    echo "    ERROR: could not find the expected anchor line in server/server.js."
    echo "    Expected to find: app.use('/api/accounting', requireAuth);"
    echo "    Nothing was changed. Check server/server.js manually and re-run."
    exit 1
  fi

  python3 - << 'PYEOF'
import re

with open('server/server.js', 'r') as f:
    content = f.read()

anchor = "app.use('/api/accounting', requireAuth);"
insertion = (
    "// --- MACDEN Staff Verification (public, no auth) ---\n"
    "const verifyRoutes = require('./routes/verify');\n"
    "app.use(verifyRoutes);\n"
    "// --- end staff verification block ---\n\n"
)

content = content.replace(anchor, insertion + anchor, 1)

with open('server/server.js', 'w') as f:
    f.write(content)

print("    Inserted require + mount before the requireAuth line.")
PYEOF
fi

echo "==> Installing express-rate-limit"
npm install express-rate-limit --save

echo ""
echo "=================================================================="
echo "Files created. Two manual steps remain before this actually works:"
echo ""
echo "1. Run server/migrations/add_verification_token.sql in the Supabase"
echo "   SQL editor. This script does NOT do that for you -- it's a"
echo "   database change, not a git-tracked one."
echo ""
echo "2. Confirm the departments join in server/routes/verify.js actually"
echo "   matches your schema (see the NOTE comment in that file). If your"
echo "   departments table or relation is named differently, the department"
echo "   field on the verify page will silently come back null until fixed."
echo ""
echo "Then push with your usual save-progress.sh, and test with a real"
echo "verification_token at:"
echo "  macden.com.ng/portal/verify.html?token=<a real verification_token>"
echo "=================================================================="
