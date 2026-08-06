// Adds show/hide eye-icon toggles to Settings' three password fields
// (Current, New, Confirm) -- same pattern as the login page. Uses one
// shared, reusable toggle function instead of duplicating the logic three
// times.
//
//   node fix-settings-password-eyes.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'portal', 'settings.html');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');
let changed = false;

const fields = [
  { id: 'currentPassword', label: 'Current Password' },
  { id: 'newPassword', label: 'New Password' },
  { id: 'confirmPassword', label: 'Confirm New Password' }
];

fields.forEach(({ id, label }) => {
  const oldField = `<label style="display:block; font-size:12.5px; font-weight:600; margin-bottom:6px;">${label}</label>
            <input type="password" id="${id}" style="width:100%; padding:9px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); font-family:var(--font-body);">`;

  const newField = `<label style="display:block; font-size:12.5px; font-weight:600; margin-bottom:6px;">${label}</label>
            <div style="position:relative;">
              <input type="password" id="${id}" style="width:100%; padding:9px 42px 9px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); font-family:var(--font-body); box-sizing:border-box;">
              <button type="button" class="pw-toggle-btn" data-target="${id}" aria-label="Show password" style="position:absolute; right:10px; top:50%; transform:translateY(-50%); background:none; border:none; cursor:pointer; color:var(--text-muted); padding:4px; display:flex; align-items:center;">
                <i class="ti ti-eye"></i>
              </button>
            </div>`;

  if (content.includes(oldField)) {
    content = content.replace(oldField, newField);
    changed = true;
    console.log('Added eye toggle to ' + label + '.');
  } else if (content.includes(`data-target="${id}"`)) {
    console.log(label + ' already has the toggle, skipping.');
  } else {
    console.log('WARNING: could not find ' + label + '. Nothing changed for that one.');
  }
});

// Shared toggle logic -- one function handles all three fields via data-target
if (!content.includes("querySelectorAll('.pw-toggle-btn')")) {
  const scriptAnchor = "function toggleSwitch(btn) {";
  const toggleScript = `document.querySelectorAll('.pw-toggle-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      const input = document.getElementById(btn.dataset.target);
      const icon = btn.querySelector('i');
      if (input.type === 'password') {
        input.type = 'text';
        icon.className = 'ti ti-eye-off';
      } else {
        input.type = 'password';
        icon.className = 'ti ti-eye';
      }
    });
  });

  function toggleSwitch(btn) {`;

  if (content.includes(scriptAnchor)) {
    content = content.replace(scriptAnchor, toggleScript);
    changed = true;
    console.log('Wired up the shared toggle behavior for all 3 fields.');
  } else {
    console.log('WARNING: could not find a good anchor for the toggle script.');
  }
} else {
  console.log('Toggle behavior already wired, skipping.');
}

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\nsettings.html patched successfully.');
} else {
  console.log('\nNo changes made -- everything already present.');
}

