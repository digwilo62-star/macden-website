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

