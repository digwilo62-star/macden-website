const fs = require('fs');
const filePath = 'portal/inbox.html';

const raw = fs.readFileSync(filePath, 'utf8');
const usesCRLF = raw.includes('\r\n');
let content = raw.replace(/\r\n/g, '\n');

const oldIconInfo = `const iconInfo = { pdf: { icon: 'ti-file-type-pdf', bg: '#c0392b' }, xlsx: { icon: 'ti-file-spreadsheet', bg: '#1d6f42' }, docx: { icon: 'ti-file-type-doc', bg: '#2b579a' } }[m.attachment_type] || {icon: 'ti-file', bg: '#666' };`;

const newIconInfo = `const iconInfo = { pdf: { icon: 'ti-file-type-pdf', bg: '#c0392b' }, xlsx: { icon: 'ti-file-spreadsheet', bg: '#1d6f42' }, docx: { icon: 'ti-file-type-doc', bg: '#2b579a' }, zip: { icon: 'ti-file-zip', bg: '#c9770a' }, image: { icon: 'ti-photo', bg: '#8e44ad' } }[m.attachment_type] || {icon: 'ti-file', bg: '#666' };`;

if (content.includes(newIconInfo)) {
  console.log('Already applied.');
  process.exit(0);
}
if (!content.includes(oldIconInfo)) {
  console.error('ERROR: still not found.');
  process.exit(1);
}

content = content.replace(oldIconInfo, newIconInfo);
const out = usesCRLF ? content.replace(/\n/g, '\r\n') : content;
fs.writeFileSync(filePath, out);
console.log('Icon map fixed in inbox.html.');
