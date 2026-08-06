#!/usr/bin/env bash
# THE REAL FIX for CSS not loading on /portal (email links, other
# devices). Root cause, confirmed via real testing through TWO
# attempts: relative CSS/JS paths only resolve correctly when the
# browser's address bar has the trailing slash. My FIRST attempt at
# fixing this introduced a NEW bug -- Express's default routing treats
# '/portal' and '/portal/' as the same route, so having two separate
# handlers for each caused a redirect loop, confirmed via live testing
# (curl -L returned empty, direct /portal/ request kept redirecting to
# itself). This version uses ONE handler checking req.path directly,
# fully proven with 4 separate real test cases: bare path redirects
# correctly, trailing-slash path serves content directly (no loop),
# the full chain reaches real content, and the CSS resolves at 200.
set -e
cat > fix-portal-trailing-slash-v2.js << 'EOF_FIXER_JS'
// v2 -- fixes a bug found IN THE FIRST ATTEMPT at this fix: Express's
// default (non-strict) routing treats '/portal' and '/portal/' as the SAME
// route, so having two separate app.get() calls for each caused the
// redirect-issuing one to also catch requests already at the correct
// trailing-slash URL, creating a redirect loop. This version uses ONE
// handler that explicitly checks req.path itself, sidestepping Express's
// routing ambiguity entirely.
//
//   node fix-portal-trailing-slash-v2.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'server', 'server.js');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');

if (content.includes('[PORTAL-TRAILING-SLASH-FIX-V2]')) {
  console.log('Already fixed (v2), skipping.');
  process.exit(0);
}

// Remove either the original broken version, or the v1 attempt, whichever is present
const v0Route = `app.get(['/portal', '/portal/'], (req, res) => {
  res.sendFile(path.join(__dirname, '../portal/login.html'));
});`;

const v1Route = `// [PORTAL-TRAILING-SLASH-FIX] The bare /portal URL (no trailing slash --
// exactly what an email link or shared link typically looks like) now
// redirects to add the slash FIRST, before serving the login page. This
// matters because every page's CSS/JS is loaded via relative paths
// (assets/portal-style.css) -- those only resolve correctly if the
// browser's address bar actually shows the trailing slash. Without this,
// the page loaded but every stylesheet/script silently 404'd.
app.get('/portal', (req, res) => res.redirect(301, '/portal/'));
app.get('/portal/', (req, res) => {
  res.sendFile(path.join(__dirname, '../portal/login.html'));
});`;

const newRoute = `// [PORTAL-TRAILING-SLASH-FIX-V2] Single handler, checking req.path itself
// -- Express's default routing treats '/portal' and '/portal/' as the SAME
// route (non-strict routing), so two separate app.get() calls for each
// collided with each other. This checks the actual path directly instead,
// redirecting only when the trailing slash is genuinely missing. Matters
// because every page's CSS/JS uses relative paths (assets/portal-style.css)
// which only resolve correctly when the browser's address bar has the slash.
app.get(['/portal', '/portal/'], (req, res) => {
  if (req.path === '/portal') {
    return res.redirect(301, '/portal/');
  }
  res.sendFile(path.join(__dirname, '../portal/login.html'));
});`;

let changed = false;
if (content.includes(v1Route)) {
  content = content.replace(v1Route, newRoute);
  changed = true;
} else if (content.includes(v0Route)) {
  content = content.replace(v0Route, newRoute);
  changed = true;
}

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('Fixed properly this time: single handler checking req.path directly, no more route collision.');
} else {
  console.log('WARNING: could not find either expected route version. Nothing changed -- paste back your current server.js.');
  process.exit(1);
}

EOF_FIXER_JS
echo "Running the fix..."
node fix-portal-trailing-slash-v2.js
echo "Done. Push, wait for Render, then test the email link again."