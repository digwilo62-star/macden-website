// Makes Directory show ALL staff (active + inactive) for admins, with a
// status badge, and turns the profile modal's action button into a
// toggle: red "Deactivate" for active people, green "Reactivate" for
// deactivated ones. Uses the includeInactive backend support added earlier.
//
//   node fix-directory-show-all.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'accounting', 'directory.html');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');
let changed = false;

// ---- 1. Request includeInactive when admin ----
const oldFetch = "const result = await apiRequest('/staff?search=' + encodeURIComponent(query));";
const newFetch = "const result = await apiRequest('/staff?search=' + encodeURIComponent(query) + (isAdmin ? '&includeInactive=true' : ''));";

if (content.includes(oldFetch)) {
  content = content.replace(oldFetch, newFetch);
  changed = true;
  console.log('Directory now requests inactive staff too (admin-only).');
} else if (content.includes('includeInactive=true')) {
  console.log('Already requesting inactive staff, skipping that part.');
}

// ---- 2. Show a "Deactivated" badge in the list instead of online/offline dot ----
const oldStatusDot = `const statusDot = s.isOnline ? '<span style="color:var(--primary-light); font-size:11px;">● Online</span>' : '<span style="color:var(--text-muted); font-size:11px;">○ Offline</span>';`;
const newStatusDot = `const statusDot = s.isActive === false
            ? '<span style="color:var(--error); font-size:11px; font-weight:600;">Deactivated</span>'
            : (s.isOnline ? '<span style="color:var(--primary-light); font-size:11px;">● Online</span>' : '<span style="color:var(--text-muted); font-size:11px;">○ Offline</span>');`;

if (content.includes(oldStatusDot)) {
  content = content.replace(oldStatusDot, newStatusDot);
  changed = true;
  console.log('Added Deactivated badge to the list rows.');
} else if (content.includes('Deactivated</span>')) {
  console.log('Deactivated badge already present, skipping that part.');
}

// ---- 3. Turn the modal's action button into a Deactivate/Reactivate toggle ----
const oldButtonLogic = `document.getElementById('deactivateProfileBtn').style.display = isAdmin ? 'inline-flex' : 'none';
      document.getElementById('deactivateProfileBtn').onclick = () => deactivateFromDirectory(person.id, person.full_name);`;

const newButtonLogic = `const actionBtn = document.getElementById('deactivateProfileBtn');
      actionBtn.style.display = isAdmin ? 'inline-flex' : 'none';
      if (person.isActive === false) {
        actionBtn.innerHTML = '<i class="ti ti-user-check"></i> Reactivate';
        actionBtn.style.color = 'var(--success)';
        actionBtn.style.borderColor = 'var(--success)';
        actionBtn.onclick = () => reactivateFromDirectory(person.id, person.full_name);
      } else {
        actionBtn.innerHTML = '<i class="ti ti-user-off"></i> Deactivate';
        actionBtn.style.color = 'var(--error)';
        actionBtn.style.borderColor = 'var(--error)';
        actionBtn.onclick = () => deactivateFromDirectory(person.id, person.full_name);
      }`;

if (content.includes(oldButtonLogic)) {
  content = content.replace(oldButtonLogic, newButtonLogic);
  changed = true;
  console.log('Turned the action button into a Deactivate/Reactivate toggle.');
} else if (content.includes('reactivateFromDirectory')) {
  console.log('Toggle logic already present, skipping that part.');
} else {
  console.log('WARNING: could not find the button-wiring anchor. Toggle not added.');
}

// ---- 4. Add the reactivateFromDirectory function ----
if (!content.includes('async function reactivateFromDirectory')) {
  const fnCode = `
    async function reactivateFromDirectory(id, name) {
      try {
        await apiRequest('/admin/staff/' + id + '/reactivate', { method: 'POST' });
        closeProfileModal();
        loadDirectory(document.getElementById('dirSearch').value.trim());
      } catch (err) {
        alert(err.message);
      }
    }

    `;
  content = content.replace('function closeProfileModal()', fnCode + 'function closeProfileModal()');
  changed = true;
  console.log('Added reactivateFromDirectory() function.');
}

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\ndirectory.html patched successfully.');
}

