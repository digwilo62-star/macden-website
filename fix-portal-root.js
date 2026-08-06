// Fixes "Cannot GET /portal/" -- express.static's index option should
// handle this automatically, but doesn't reliably in this Express version
// (matches an earlier confirmed Express-version quirk this session, the
// wildcard route crash). This adds explicit, bulletproof routes for both
// /portal and /portal/ that directly serve login.html, sidestepping
// whatever subtle static-middleware behavior is causing the 404.
//
//   node fix-portal-root.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'server', 'server.js');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');

if (content.includes('[PORTAL-ROOT-FIX]')) {
  console.log('Already added, skipping.');
  process.exit(0);
}

const anchor = "app.use('/portal', express.static(path.join(__dirname, '../accounting'), {";

if (!content.includes(anchor)) {
  console.log('WARNING: could not find the expected anchor. Nothing changed.');
  process.exit(1);
}

const newRoutes = `// [PORTAL-ROOT-FIX] Explicit routes for the bare /portal and /portal/ paths --
// express.static's "index" option should handle serving login.html here
// automatically, but doesn't reliably in this Express version. This
// sidesteps that entirely with a direct, guaranteed route.
app.get(['/portal', '/portal/'], (req, res) => {
  res.sendFile(path.join(__dirname, '../accounting/login.html'));
});

${anchor}`;

content = content.replace(anchor, newRoutes);
fs.writeFileSync(filePath, content, 'utf8');
console.log('Added explicit /portal and /portal/ routes.');

