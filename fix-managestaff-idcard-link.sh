#!/bin/bash
# fix-managestaff-idcard-link.sh (v2 -- more robust anchor matching)
#
# Adds an "ID Card Requests" button to portal/manage-staff.html's toolbar,
# right before the "onboard.html" link. Uses a short, regex-based anchor
# instead of matching the whole line verbatim, so small whitespace/quote
# differences don't break it. Safe to re-run.

set -e

if grep -q "id-card-requests.html" portal/manage-staff.html; then
  echo "==> Already applied -- skipping (safe to re-run)."
  exit 0
fi

cat > .tmp-patch-managestaff.js << 'NODE_EOF'
const fs = require('fs');

const filePath = 'portal/manage-staff.html';
let content = fs.readFileSync(filePath, 'utf8');

// Match the whole <a ...>...</a> tag that links to onboard.html,
// regardless of exact attribute spacing/order.
const anchorPattern = /<a\s+href="onboard\.html"[^>]*>[\s\S]*?<\/a>/;
const match = content.match(anchorPattern);

if (!match) {
  console.error('ERROR: could not find a link to onboard.html in portal/manage-staff.html.');
  console.error('Nothing was changed. Showing the toolbar area for reference:');
  const idx = content.indexOf('ms-toolbar');
  if (idx !== -1) {
    console.error(content.slice(idx, idx + 600));
  } else {
    console.error('(could not even find "ms-toolbar" -- the file may have changed more than expected)');
  }
  process.exit(1);
}

const newLink = '<a href="id-card-requests.html" class="btn btn-primary" style="width:auto; padding:10px 20px; text-decoration:none; display:inline-flex; align-items:center; gap:8px; margin-right:10px; background:var(--surface); color:var(--text-primary); border:1px solid var(--border);"><i class="ti ti-id-badge-2"></i> ID Card Requests</a>\n          ';

content = content.replace(match[0], newLink + match[0]);
fs.writeFileSync(filePath, content);
console.log('    Inserted ID Card Requests link next to the onboard.html link.');
NODE_EOF

echo "==> Patching portal/manage-staff.html"
node .tmp-patch-managestaff.js
rm .tmp-patch-managestaff.js

echo ""
echo "Done. Push with your usual save-progress.sh."
