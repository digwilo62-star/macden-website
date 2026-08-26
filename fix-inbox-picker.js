const fs = require('fs');
const filePath = 'portal/inbox.html';

const raw = fs.readFileSync(filePath, 'utf8');
const usesCRLF = raw.includes('\r\n');
let content = raw.replace(/\r\n/g, '\n');

const oldAccept = `accept=".pdf,.xlsx"`;
const newAccept = `accept=".pdf,.xlsx,.docx,.zip,.jpg,.jpeg,.png,.gif,.webp"`;

if (content.includes(newAccept)) {
  console.log('Already applied.');
  process.exit(0);
}
if (!content.includes(oldAccept)) {
  console.error('ERROR: exact text not found.');
  process.exit(1);
}

content = content.replace(oldAccept, newAccept);
const out = usesCRLF ? content.replace(/\n/g, '\r\n') : content;
fs.writeFileSync(filePath, out);
console.log('Fixed inbox.html file picker.');
