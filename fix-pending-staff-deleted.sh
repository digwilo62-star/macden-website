#!/usr/bin/env bash
# Fixes permanently-deleted accounts still showing in Pending Staff
# Approvals -- a gap missed when the delete feature was built (only
# Directory and Manage Staff got the deleted_at exclusion, this route
# was missed). Deleted accounts keep is_active=false and
# email_verified=true (neither is touched during the scrub), so they
# still matched this route's 'pending' criteria.
set -e
cat > fix-pending-staff-exclude-deleted.js << 'EOF_FIXER_JS'
// Fixes deleted accounts still showing in Pending Staff Approvals. A
// permanently-deleted account keeps is_active=false and email_verified=true
// (neither gets touched during the scrub) -- so it still matched this
// route's query, which only checked those two fields. Adds the missing
// deleted_at exclusion.
//
//   node fix-pending-staff-exclude-deleted.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'server', 'routes', 'admin.js');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');

if (content.includes(".eq('email_verified', true)\n      .eq('is_active', false)\n      .is('deleted_at', null)")) {
  console.log('Already fixed, skipping.');
  process.exit(0);
}

const oldQuery = ".eq('email_verified', true)\n      .eq('is_active', false)\n      .order('created_at', { ascending: true });";
const newQuery = ".eq('email_verified', true)\n      .eq('is_active', false)\n      .is('deleted_at', null)\n      .order('created_at', { ascending: true });";

if (content.includes(oldQuery)) {
  content = content.replace(oldQuery, newQuery);
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('Fixed: deleted accounts no longer show in Pending Staff Approvals.');
} else {
  console.log('WARNING: could not find the expected pending-staff query. Nothing changed -- paste back admin.js if this persists.');
  process.exit(1);
}

EOF_FIXER_JS
echo "Running the fix..."
node fix-pending-staff-exclude-deleted.js
echo "Done. Restart your server."