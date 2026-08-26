const fs = require('fs');

function normalize(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  return { content: raw.replace(/\r\n/g, '\n'), usesCRLF: raw.includes('\r\n') };
}
function save(filePath, content, usesCRLF) {
  fs.writeFileSync(filePath, usesCRLF ? content.replace(/\n/g, '\r\n') : content);
}

let changes = 0;

// 1. Backend: the accept/reject filter
{
  const filePath = 'server/routes/messages.js';
  let { content, usesCRLF } = normalize(filePath);

  const oldAllowed = `    const allowed = {
      'application/pdf': 'pdf',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx'
    };
    if (allowed[file.mimetype]) {
      cb(null, true);
    } else {
      cb(new Error('Only PDF, Excel (.xlsx), and Word (.docx) files are allowed.'));
    }`;

  const newAllowed = `    const allowed = {
      'application/pdf': 'pdf',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
      'application/zip': 'zip',
      'application/x-zip-compressed': 'zip',
      'image/jpeg': 'image',
      'image/png': 'image',
      'image/gif': 'image',
      'image/webp': 'image'
    };
    if (allowed[file.mimetype]) {
      cb(null, true);
    } else {
      cb(new Error('Only PDF, Excel (.xlsx), Word (.docx), zip, and image files are allowed.'));
    }`;

  if (content.includes(newAllowed)) {
    console.log('SKIP  fileFilter in messages.js (already applied)');
  } else if (!content.includes(oldAllowed)) {
    console.error('FAIL  fileFilter in messages.js -- exact text not found');
  } else {
    content = content.replace(oldAllowed, newAllowed);
    save(filePath, content, usesCRLF);
    console.log('OK    fileFilter in messages.js');
    changes++;
  }

  // 2. Backend: the type-label map (same file, second occurrence)
  const oldTypeMap = `      const typeMap = {
        'application/pdf': 'pdf',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx'
      };`;

  const newTypeMap = `      const typeMap = {
        'application/pdf': 'pdf',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
        'application/zip': 'zip',
        'application/x-zip-compressed': 'zip',
        'image/jpeg': 'image',
        'image/png': 'image',
        'image/gif': 'image',
        'image/webp': 'image'
      };`;

  ({ content, usesCRLF } = normalize(filePath));
  if (content.includes(newTypeMap)) {
    console.log('SKIP  typeMap in messages.js (already applied)');
  } else if (!content.includes(oldTypeMap)) {
    console.error('FAIL  typeMap in messages.js -- exact text not found');
  } else {
    content = content.replace(oldTypeMap, newTypeMap);
    save(filePath, content, usesCRLF);
    console.log('OK    typeMap in messages.js');
    changes++;
  }
}

// 3. Frontend: the file picker's accept attribute
{
  const filePath = 'portal/compose.html';
  let { content, usesCRLF } = normalize(filePath);

  const oldAccept = `accept=".pdf,.xlsx,.docx"`;
  const newAccept = `accept=".pdf,.xlsx,.docx,.zip,.jpg,.jpeg,.png,.gif,.webp"`;

  if (content.includes(newAccept)) {
    console.log('SKIP  file picker accept in compose.html (already applied)');
  } else if (!content.includes(oldAccept)) {
    console.error('FAIL  file picker accept in compose.html -- exact text not found');
  } else {
    content = content.replace(oldAccept, newAccept);
    save(filePath, content, usesCRLF);
    console.log('OK    file picker accept in compose.html');
    changes++;
  }
}

// 4. Frontend: the icon/color display map
{
  const filePath = 'portal/inbox.html';
  let { content, usesCRLF } = normalize(filePath);

  const oldIconInfo = `const iconInfo = { pdf: { icon: 'ti-file-type-pdf',bg: '#c0392b' }, xlsx: { icon: 'ti-file-spreadsheet', bg: '#1d6f42' }, docx: { icon: 'ti-file-type-doc', bg: '#2b579a' } }[m.attachment_type] || { icon: 'ti-file', bg: '#666' };`;

  const newIconInfo = `const iconInfo = { pdf: { icon: 'ti-file-type-pdf',bg: '#c0392b' }, xlsx: { icon: 'ti-file-spreadsheet', bg: '#1d6f42' }, docx: { icon: 'ti-file-type-doc', bg: '#2b579a' }, zip: { icon: 'ti-file-zip', bg: '#c9770a' }, image: { icon: 'ti-photo', bg: '#8e44ad' } }[m.attachment_type] || { icon: 'ti-file', bg: '#666' };`;

  if (content.includes(newIconInfo)) {
    console.log('SKIP  icon map in inbox.html (already applied)');
  } else if (!content.includes(oldIconInfo)) {
    console.error('FAIL  icon map in inbox.html -- exact text not found');
  } else {
    content = content.replace(oldIconInfo, newIconInfo);
    save(filePath, content, usesCRLF);
    console.log('OK    icon map in inbox.html');
    changes++;
  }
}

console.log('');
console.log(changes + ' change(s) applied.');
