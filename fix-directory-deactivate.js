// Adds a "Deactivate" button to the staff profile modal in Directory,
// admin-only. Reuses the existing DELETE /admin/staff/:id route (already
// built for Manage Staff). Uses index-based slicing for the button
// insertion instead of a naive string replace, to avoid ambiguity with
// other </button> tags elsewhere on the page.
//
//   node fix-directory-deactivate.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'accounting', 'directory.html');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');
let changed = false;

// ---- 1. Insert the Deactivate button right after the Message button closes ----
if (!content.includes('id="deactivateProfileBtn"')) {
  const msgBtnIdx = content.indexOf('id="messageProfileBtn"');
  if (msgBtnIdx === -1) {
    console.log('WARNING: could not find messageProfileBtn. Nothing changed.');
    process.exit(1);
  }
  const closeBtnIdx = content.indexOf('</button>', msgBtnIdx);
  const insertAt = closeBtnIdx + '</button>'.length;

  const deactivateBtnHtml = `
      <button class="btn btn-ghost" id="deactivateProfileBtn" style="display:none; margin-top:10px; align-items:center; justify-content:center; gap:8px; width:auto; padding:10px 24px; color:var(--error); border-color:var(--error);">
        <i class="ti ti-user-off"></i> Deactivate
      </button>`;

  content = content.slice(0, insertAt) + deactivateBtnHtml + content.slice(insertAt);
  changed = true;
  console.log('Added Deactivate button to profile modal.');
} else {
  console.log('Deactivate button already present, skipping that part.');
}

// ---- 2. Track isAdmin, and store it during init() ----
if (!content.includes('let isAdmin')) {
  content = content.replace(
    'let staffCache = [];',
    'let staffCache = [];\n    let isAdmin = false;'
  );
  changed = true;
  console.log('Added isAdmin tracking variable.');
}

if (!content.includes('isAdmin = result.staff.role')) {
  content = content.replace(
    "if (result.staff.role === 'admin') {",
    "isAdmin = result.staff.role === 'admin';\n        if (isAdmin) {"
  );
  changed = true;
  console.log('Set isAdmin during init().');
}

// ---- 3. Show/hide the Deactivate button in openProfile(), and wire its click ----
{
  const msgClickAnchor = "document.getElementById('messageProfileBtn').onclick = () => {";
  if (content.includes(msgClickAnchor) && !content.includes("deactivateProfileBtn').style.display")) {
    const wireCode = `document.getElementById('deactivateProfileBtn').style.display = isAdmin ? 'inline-flex' : 'none';
      document.getElementById('deactivateProfileBtn').onclick = () => deactivateFromDirectory(person.id, person.full_name);

      ${msgClickAnchor}`;
    content = content.replace(msgClickAnchor, wireCode);
    changed = true;
    console.log('Wired Deactivate button visibility and click handler.');
  } else if (content.includes("deactivateProfileBtn').style.display")) {
    console.log('Deactivate button already wired, skipping that part.');
  }
}

// ---- 4. Add the deactivateFromDirectory function ----
if (!content.includes('async function deactivateFromDirectory')) {
  const fnCode = `
    async function deactivateFromDirectory(id, name) {
      if (!confirm('Deactivate ' + name + '? They will no longer be able to log in. This can be undone later from Manage Staff.')) return;
      try {
        await apiRequest('/admin/staff/' + id, { method: 'DELETE' });
        closeProfileModal();
        loadDirectory(document.getElementById('dirSearch').value.trim());
      } catch (err) {
        alert(err.message);
      }
    }

    `;
  content = content.replace('function closeProfileModal()', fnCode + 'function closeProfileModal()');
  changed = true;
  console.log('Added deactivateFromDirectory() function.');
}

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\ndirectory.html patched successfully.');
}

