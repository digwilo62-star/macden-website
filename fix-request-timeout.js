// Adds a genuine request timeout to server.js. Right now, if any request
// hangs (a stuck database connection, an unresolved promise, etc.), it
// hangs FOREVER -- the browser just waits with zero error shown, exactly
// matching the frozen "Approving..." button. This makes any hung request
// fail visibly after 15 seconds with a real JSON error instead, which the
// frontend already knows how to handle (shows an alert, re-enables the
// button) -- fixing the "frozen forever" symptom regardless of the exact
// underlying cause.
//
//   node fix-request-timeout.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'server', 'server.js');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');

if (content.includes('REQUEST_TIMEOUT_MS')) {
  console.log('Request timeout already added, skipping.');
  process.exit(0);
}

const anchor = "app.use(helmet({ contentSecurityPolicy: false }));";
if (!content.includes(anchor)) {
  console.log('WARNING: could not find the expected anchor. Nothing changed.');
  process.exit(1);
}

const timeoutMiddleware = `app.use(helmet({ contentSecurityPolicy: false }));

// Any request that hangs for more than 15 seconds (a stuck database
// connection, an unresolved promise, etc.) now fails with a real, visible
// JSON error instead of hanging forever with no error at all -- which is
// exactly what a frozen button with zero console errors looks like.
const REQUEST_TIMEOUT_MS = 15000;
app.use((req, res, next) => {
  res.setTimeout(REQUEST_TIMEOUT_MS, () => {
    if (!res.headersSent) {
      console.error('Request timed out after ' + REQUEST_TIMEOUT_MS + 'ms:', req.method, req.originalUrl);
      res.status(504).json({ error: 'This is taking too long. Please try again.' });
    }
  });
  next();
});`;

content = content.replace(anchor, timeoutMiddleware);
fs.writeFileSync(filePath, content, 'utf8');
console.log('Added request timeout protection to server.js.');

