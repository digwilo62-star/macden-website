const fs = require('fs');
const filePath = 'portal/inbox.html';

const raw = fs.readFileSync(filePath, 'utf8');
const usesCRLF = raw.includes('\r\n');
let content = raw.replace(/\r\n/g, '\n');

if (content.includes("zip: { icon: 'ti-file-zip'")) {
  console.log('Already applied.');
  process.exit(0);
}

const regex = /(docx:\s*\{\s*icon:\s*'ti-file-type-doc',\s*bg:\s*'#2b579a'\s*\})(\s*\})/;

const match = content.match(regex);
if (!match) {
  console.error('ERROR: could not find the docx icon entry at all.');
  process.exit(1);
}

const insertion = `, zip: { icon: 'ti-file-zip', bg: '#c9770a' }, image: { icon: 'ti-photo', bg: '#8e44ad' }`;
content = content.replace(regex, `$1${insertion}$2`);

const out = usesCRLF ? content.replace(/\n/g, '\r\n') : content;
fs.writeFileSync(filePath, out);
console.log('Icon map fixed in inbox.html (surgical insertion).');
