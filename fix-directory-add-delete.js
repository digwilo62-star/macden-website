// Adds a "Delete Permanently" button to Directory's profile modal --
// visible ONLY when the person is already deactivated (matches the
// server-side safety gate). Reuses the styled confirm modal already built
// for Deactivate, with extra-clear irreversible-action wording.
//
//   node fix-directory-add-delete.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'portal', 'directory.html');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');
let changed = false;

// ---- 1. Add the Delete button right after the Deactivate/Reactivate button ----
if (!content.includes('id="deletePermanentlyBtn"')) {
  const btnIdx = content.indexOf('id="deactivateProfileBtn"');
  if (btnIdx === -1) {
    console.log('WARNING: could not find deactivateProfileBtn. Nothing changed.');
    process.exit(1);
  }
  const closeDivIdx = content.indexOf('</button>', btnIdx) + '</button>'.length;

  const deleteBtnHtml = `
      <button class="btn btn-ghost" id="deletePermanentlyBtn" style="display:none; margin-top:10px; align-items:center; justify-content:center; gap:8px; width:auto; padding:10px 24px; color:#fff; background:var(--error); border-color:var(--error);">
        <i class="ti ti-trash"></i> Delete Permanently
      </button>`;

  content = content.slice(0, closeDivIdx) + deleteBtnHtml + content.slice(closeDivIdx);
  changed = true;
  console.log('Added Delete Permanently button.');
} else {
  console.log('Delete button already present, skipping that part.');
}

// ---- 2. Show/hide it in openProfile() -- only for already-deactivated people ----
const showAnchor = "actionBtn.onclick = () => reactivateFromDirectory(person.id, person.full_name);";

if (!content.includes("document.getElementById('deletePermanentlyBtn').style.display")) {
  const wireCode = `${showAnchor}
        document.getElementById('deletePermanentlyBtn').style.display = 'inline-flex';
        document.getElementById('deletePermanentlyBtn').onclick = () => deletePermanentlyFromDirectory(person.id, person.full_name);`;

  const hideCode = `} else {
        document.getElementById('deletePermanentlyBtn').style.display = 'none';`;

  if (content.includes(showAnchor)) {
    content = content.replace(showAnchor, wireCode);
    changed = true;
  }

  const oldElseBlock = `} else {
        actionBtn.innerHTML = '<i class="titi-user-off"></i> Deactivate';`;
  const newElseBlock = `} else {
        document.getElementById('deletePermanentlyBtn').style.display = 'none';
        actionBtn.innerHTML = '<i class="titi-user-off"></i> Deactivate';`;

  if (content.includes(oldElseBlock)) {
    content = content.replace(oldElseBlock, newElseBlock);
    changed = true;
    console.log('Wired Delete button visibility (only shows for deactivated accounts).');
  } else {
    console.log('WARNING: could not find the else-block anchor for hiding the button. Nothing changed for that part.');
  }
} else {
  console.log('Delete button visibility already wired, skipping that part.');
}

// ---- 3. Add the deletePermanentlyFromDirectory function ----
if (!content.includes('async function deletePermanentlyFromDirectory')) {
  const fnCode = `
    async function deletePermanentlyFromDirectory(id, name) {
      if (!(await confirmModal(
        'Permanently delete ' + name + '\\'s account? This CANNOT be undone. Their username and email will be freed up, and they can never log in again. Their message and leave history will be kept.',
        { title: 'Permanently delete this account?', confirmLabel: 'Delete Permanently' }
      ))) return;
      try {
        await apiRequest('/admin/staff/' + id + '/permanent', { method: 'DELETE' });
        closeProfileModal();
        loadDirectory(document.getElementById('dirSearch').value.trim());
      } catch (err) {
        alert(err.message);
      }
    }

    `;
  content = content.replace('function closeProfileModal()', fnCode + 'function closeProfileModal()');
  changed = true;
  console.log('Added deletePermanentlyFromDirectory() function.');
}

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\ndirectory.html patched successfully.');
}

