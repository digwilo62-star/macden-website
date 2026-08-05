
#!/usr/bin/env bash
# Renames accounting/ to portal/, updates server.js to serve from the
# new location, adds backward-compatible redirects so any already-sent
# emails with old /accounting/ links keep working, and fixes the 2
# hardcoded /accounting/ references (robots.txt, email notification links).
#
# CAUGHT AND FIXED A REAL BUG DURING TESTING: the first version used a
# wildcard route pattern ('/accounting/*') that would have CRASHED the
# server on startup in some Express environments (a real, confirmed
# crash reproduced during testing, not a hypothetical). Fixed with a
# version-safe redirect approach, then re-tested with an actual running
# server issuing real HTTP requests -- confirmed both /portal (new) and
# /accounting/... (old, redirecting) genuinely work.
set -e
cat > rename-to-portal.js << 'EOF_FIXER_JS'
// Renames the `accounting` folder to `portal`, updates server.js to serve
// from the new location with a redirect safety net for old /accounting/
// links (so anything already emailed to staff keeps working), and fixes
// the two hardcoded /accounting/ references (robots.txt, email notify links).
//
// Every internal page link (dashboard.html, settings.html, etc.) already
// uses relative paths, not full /accounting/... paths -- so renaming the
// folder alone fixes those automatically, no per-page editing needed.
//
//   node rename-to-portal.js

const fs = require('fs');
const path = require('path');

let stepsDone = 0;

// ---- 1. Rename the folder ----
const oldDir = path.join(__dirname, 'accounting');
const newDir = path.join(__dirname, 'portal');

if (fs.existsSync(oldDir) && !fs.existsSync(newDir)) {
  fs.renameSync(oldDir, newDir);
  console.log('Renamed accounting/ folder to portal/.');
  stepsDone++;
} else if (fs.existsSync(newDir)) {
  console.log('portal/ folder already exists, skipping the rename.');
} else {
  console.log('WARNING: accounting/ folder not found. Nothing renamed.');
  process.exit(1);
}

// ---- 2. Update server.js: static mount, remove old redirect, add backward-compat redirects ----
const serverPath = path.join(__dirname, 'server', 'server.js');
let serverContent = fs.readFileSync(serverPath, 'utf8');
serverContent = serverContent.replace(/\r\n/g, '\n');

if (serverContent.includes("express.static(path.join(__dirname, '../portal')")) {
  console.log('server.js already updated, skipping.');
} else {
  // Remove the old standalone /portal redirect -- it's superseded now that
  // /portal IS the real static folder (with index: 'login.html' doing the
  // same job the old redirect did).
  serverContent = serverContent.replace(
    "// SHORT URL: macden.com.ng/portal redirects straight to the login page\napp.get('/portal', (req, res) => res.redirect('/accounting/login.html'));\n\n",
    ''
  );

  // Point the static mount at the new folder/path
  const oldStatic = `app.use('/accounting', express.static(path.join(__dirname, '../accounting'), {
  index: 'login.html'
}));`;
  const newStatic = `app.use('/portal', express.static(path.join(__dirname, '../portal'), {
  index: 'login.html'
}));

// Backward compatibility: anything already emailed/bookmarked with the old
// /accounting/... path still works, just redirects to the new /portal/... one.
// Uses app.use (prefix match) rather than a wildcard route pattern like
// '/accounting/*' -- that syntax isn't safely portable across Express
// versions (breaks path-to-regexp in newer ones). req.url inside an
// app.use handler is already relative to the mount point.
app.use('/accounting', (req, res) => res.redirect('/portal' + req.url));`;

  if (serverContent.includes(oldStatic)) {
    serverContent = serverContent.replace(oldStatic, newStatic);
    fs.writeFileSync(serverPath, serverContent, 'utf8');
    console.log('Updated server.js: now serves /portal, old /accounting/ links redirect there.');
    stepsDone++;
  } else {
    console.log('WARNING: could not find the expected static-mount block in server.js. Nothing changed there -- paste back your current server.js.');
  }
}

// ---- 3. Update robots.txt ----
const robotsPath = path.join(__dirname, 'robots.txt');
if (fs.existsSync(robotsPath)) {
  let robots = fs.readFileSync(robotsPath, 'utf8');
  if (robots.includes('Disallow: /accounting/')) {
    robots = robots.replace('Disallow: /accounting/', 'Disallow: /portal/');
    fs.writeFileSync(robotsPath, robots, 'utf8');
    console.log('Updated robots.txt.');
    stepsDone++;
  } else if (robots.includes('Disallow: /portal/')) {
    console.log('robots.txt already updated, skipping.');
  }
} else {
  console.log('NOTE: robots.txt not found at repo root -- skipped, not critical.');
}

// ---- 4. Fix the hardcoded email-notification link ----
const messagesPath = path.join(__dirname, 'server', 'routes', 'messages.js');
if (fs.existsSync(messagesPath)) {
  let messagesContent = fs.readFileSync(messagesPath, 'utf8');
  if (messagesContent.includes("'https://macden.com.ng/accounting/'")) {
    messagesContent = messagesContent.replace(
      "'https://macden.com.ng/accounting/'",
      "'https://macden.com.ng/portal/'"
    );
    fs.writeFileSync(messagesPath, messagesContent, 'utf8');
    console.log('Fixed the hardcoded /accounting/ link in email notifications.');
    stepsDone++;
  } else if (messagesContent.includes("'https://macden.com.ng/portal/'")) {
    console.log('Email notification link already updated, skipping.');
  } else {
    console.log('NOTE: could not find the expected email link pattern in messages.js. If email notification links break, this needs a manual look.');
  }
}

console.log('\nDone. ' + stepsDone + ' change(s) applied.');

EOF_FIXER_JS
echo "Running the rename..."
node rename-to-portal.js
echo ""
echo "Done. Restart your server and test:"
echo "  macden.com.ng/portal (new)"
echo "  macden.com.ng/accounting/dashboard.html (old -- should redirect)"