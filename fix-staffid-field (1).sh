#!/bin/bash
# fix-staffid-field.sh
#
# Adds a "Staff ID" field to the Edit Staff modal so admins can actually
# assign the human-readable badge number (MAC-2026-0017 style) used by
# the ID card system. Touches:
#   - server/routes/admin.js   (GET /staff/:id select, PUT /staff/:id update)
#   - portal/directory.html    (modal field, openEditStaff, saveEditStaff)
#
# All five anchors are exact strings from your real files. Safe to re-run.

set -e

if grep -q "editStaffId" portal/directory.html; then
  echo "==> Already applied -- skipping (safe to re-run)."
  exit 0
fi

cat > .tmp-patch-staffid.js << 'NODE_EOF'
const fs = require('fs');

// ---------- 1. server/routes/admin.js: GET select ----------
{
  const filePath = 'server/routes/admin.js';
  let content = fs.readFileSync(filePath, 'utf8');

  const oldSelect = ".select('id, full_name, role, department_id, phone, branch')";
  const newSelect = ".select('id, full_name, role, department_id, phone, branch, staff_id')";

  if (!content.includes(oldSelect)) {
    console.error('ERROR: could not find the GET /staff/:id select line in admin.js.');
    process.exit(1);
  }
  content = content.replace(oldSelect, newSelect);

  // ---------- 2. server/routes/admin.js: PUT handler ----------
  const oldPut = `    const { fullName, role, departmentId, phone, branch } = req.body;
    const { error } = await supabase
      .from('staff')
      .update({
        full_name: fullName,
        role: role,
        department_id: departmentId,
        phone: phone || null,
        branch: branch || null
      })
      .eq('id', req.params.id);
    if (error) {
      return res.status(500).json({ error: 'Could not update this account.' });
    }`;

  const newPut = `    const { fullName, role, departmentId, phone, branch, staffId } = req.body;
    const { error } = await supabase
      .from('staff')
      .update({
        full_name: fullName,
        role: role,
        department_id: departmentId,
        phone: phone || null,
        branch: branch || null,
        staff_id: staffId || null
      })
      .eq('id', req.params.id);
    if (error) {
      if (error.code === '23505') {
        return res.status(409).json({ error: 'This Staff ID is already assigned to another staff member.' });
      }
      return res.status(500).json({ error: 'Could not update this account.' });
    }`;

  if (!content.includes(oldPut)) {
    console.error('ERROR: could not find the PUT /staff/:id handler block in admin.js.');
    process.exit(1);
  }
  content = content.replace(oldPut, newPut);

  fs.writeFileSync(filePath, content);
  console.log('    Patched server/routes/admin.js (GET select + PUT handler).');
}

// ---------- 3. portal/directory.html: modal field ----------
{
  const filePath = 'portal/directory.html';
  let content = fs.readFileSync(filePath, 'utf8');

  const anchorLabel = '<label style="display:block; font-size:12.5px; font-weight:600; margin-bottom:6px;">Account Type</label>';
  const newField = `<div style="margin-bottom:12px;">
        <label style="display:block; font-size:12.5px; font-weight:600; margin-bottom:6px;">Staff ID (for ID card)</label>
        <input type="text" id="editStaffId" placeholder="e.g. MAC-2026-0001" style="width:100%; padding:9px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); font-family:var(--font-body); box-sizing:border-box;">
      </div>
      <div style="margin-bottom:12px;">
        ${anchorLabel}`;

  const oldBlock = `<div style="margin-bottom:12px;">
        ${anchorLabel}`;

  if (!content.includes(oldBlock)) {
    console.error('ERROR: could not find the Account Type field block in directory.html.');
    process.exit(1);
  }
  content = content.replace(oldBlock, newField);

  // ---------- 4. openEditStaff(): populate the field ----------
  const oldPopulate = `document.getElementById('editFullName').value = s.full_name || '';`;
  const newPopulate = `document.getElementById('editFullName').value = s.full_name || '';
        document.getElementById('editStaffId').value = s.staff_id || '';`;

  if (!content.includes(oldPopulate)) {
    console.error('ERROR: could not find the editFullName populate line in directory.html.');
    process.exit(1);
  }
  content = content.replace(oldPopulate, newPopulate);

  // ---------- 5. saveEditStaff(): send the field ----------
  const oldSave = `fullName: document.getElementById('editFullName').value.trim(),`;
  const newSave = `fullName: document.getElementById('editFullName').value.trim(),
            staffId: document.getElementById('editStaffId').value.trim() || null,`;

  if (!content.includes(oldSave)) {
    console.error('ERROR: could not find the fullName save line in directory.html.');
    process.exit(1);
  }
  content = content.replace(oldSave, newSave);

  fs.writeFileSync(filePath, content);
  console.log('    Patched portal/directory.html (modal field, load, save).');
}
NODE_EOF

node .tmp-patch-staffid.js
rm .tmp-patch-staffid.js

echo ""
echo "Done. Push with your usual save-progress.sh."
