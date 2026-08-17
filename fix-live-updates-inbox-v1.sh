#!/bin/bash
# fix-live-updates-inbox-v1.sh
#
# Inbox listens for the shared 'macden:newActivity' event. If a
# conversation is currently open, refreshes that thread (new message
# appears live). If sitting on the list view, refreshes the list.
# Reuses the existing openMessage() and loadList() functions, no new
# fetch logic. Requires fix-live-updates-engine-v1.sh applied first.

set -e

if grep -q "macden:newActivity" portal/inbox.html; then
  echo "==> Already applied -- skipping (safe to re-run)."
  exit 0
fi

cat > .tmp-patch-inboxlive.js << 'NODE_EOF'
const fs = require('fs');

function readNormalized(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  const usesCRLF = raw.includes('\r\n');
  return { normalized: raw.replace(/\r\n/g, '\n'), usesCRLF };
}
function writeRestoringLineEndings(filePath, normalizedContent, usesCRLF) {
  const out = usesCRLF ? normalizedContent.replace(/\n/g, '\r\n') : normalizedContent;
  fs.writeFileSync(filePath, out);
}

const filePath = 'portal/inbox.html';
let { normalized: content, usesCRLF } = readNormalized(filePath);

const anchor = `      if (openId) {
        openMessage(openId);
      } else {
        loadList();
      }
      loadUnreadBadge();
    }`;

const withListener = `      if (openId) {
        openMessage(openId);
      } else {
        loadList();
      }
      loadUnreadBadge();

      window.addEventListener('macden:newActivity', () => {
        if (currentConversationId) {
          openMessage(currentConversationId);
        } else {
          loadList();
        }
      });
    }`;

if (!content.includes(anchor)) {
  console.error('ERROR: could not find the init() body in inbox.html.');
  process.exit(1);
}
content = content.replace(anchor, withListener);

writeRestoringLineEndings(filePath, content, usesCRLF);
console.log('    Patched portal/inbox.html (live-refreshes list or open thread on new activity).');
NODE_EOF

node .tmp-patch-inboxlive.js
rm .tmp-patch-inboxlive.js

echo ""
echo "Done. Push with your usual save-progress.sh."
