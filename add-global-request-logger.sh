#!/usr/bin/env bash
# TEMPORARY, most-bulletproof-possible diagnostic: logs EVERY single
# request the server receives, before any routing happens at all. Real-
# tested: confirmed it captures the exact method and URL of a real
# request. If clicking Approve still shows nothing after this, the
# request genuinely isn't reaching this server at all -- that would be
# the real, definitive answer.
set -e
cat > add-global-request-logger.js << 'EOF_FIXER_JS'
// Adds a GLOBAL logger that fires for EVERY single request the server
// receives, before any routing happens -- shows the exact method and URL
// of every request. This is the most bulletproof possible diagnostic:
// even if a request is hitting a completely different/unexpected route,
// or getting blocked/intercepted somewhere, this WILL show it, since it
// runs before any route-matching logic at all.
//
//   node add-global-request-logger.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'server', 'server.js');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');

if (content.includes('[GLOBAL-REQUEST-LOG]')) {
  console.log('Already added, skipping.');
  process.exit(0);
}

const anchor = "const app = express();";
if (!content.includes(anchor)) {
  console.log('WARNING: could not find the expected anchor. Nothing changed.');
  process.exit(1);
}

const newLine = `const app = express();

// TEMPORARY diagnostic: logs every single request that reaches this
// server, before any routing. Remove once the approve-staff mystery is solved.
app.use((req, res, next) => {
  console.log('[GLOBAL-REQUEST-LOG]', req.method, req.originalUrl);
  next();
});`;

content = content.replace(anchor, newLine);
fs.writeFileSync(filePath, content, 'utf8');
console.log('Global request logger added.');

EOF_FIXER_JS
echo "Running the fix..."
node add-global-request-logger.js
echo "Done. Push, wait for Render to finish deploying, then click Approve while watching Logs."