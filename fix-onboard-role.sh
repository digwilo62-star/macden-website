#!/usr/bin/env bash
# Fixes the missing Admin option in Add New Staff. Root cause: the
# 'Role / Job Title' field was plain free text -- whatever HR typed
# became the account's ACTUAL permission level in the database, but
# there was never a real way to type/select 'admin' specifically
# through the UI. Now a real dropdown (Staff / Admin), same field id
# so no other code needed to change -- select.value works identically
# to input.value in JS.
set -e
cat > fix-onboard-role-dropdown.js << 'EOF_FIXER_JS'
// Converts the free-text "Role / Job Title" field into a real Staff/Admin
// dropdown. This field directly becomes the account's actual permission
// level in the database -- there was never a proper way to select Admin,
// only whatever text HR happened to type. Keeps the same field id="role"
// so nothing else in the form's JS needs to change.
//
//   node fix-onboard-role-dropdown.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'portal', 'onboard.html');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');

if (content.includes('<option value="admin">Admin</option>')) {
  console.log('Already fixed, skipping.');
  process.exit(0);
}

const oldField = '<div class="onb-field"><label>Role / Job Title *</label><input type="text" id="role"></div>';
const newField = `<div class="onb-field"><label>Account Type *</label>
              <select id="role">
                <option value="staff">Staff</option>
                <option value="admin">Admin</option>
              </select>
            </div>`;

if (content.includes(oldField)) {
  content = content.replace(oldField, newField);
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('Fixed: Role field is now a real Staff/Admin dropdown, directly controlling actual permissions.');
} else {
  console.log('WARNING: could not find the expected field. Nothing changed -- paste back your current onboard.html.');
  process.exit(1);
}

EOF_FIXER_JS
echo "Running the fix..."
node fix-onboard-role-dropdown.js
echo "Done. Hard-refresh (Ctrl+F5) -- no server restart needed."