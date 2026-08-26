const fs = require('fs');
const filePath = 'server/routes/messages.js';

const raw = fs.readFileSync(filePath, 'utf8');
const usesCRLF = raw.includes('\r\n');
let content = raw.replace(/\r\n/g, '\n');

if (content.includes('getAttachmentType')) {
  console.log('Already applied.');
  process.exit(0);
}

let changes = 0;

const helperCode = `// Some machines report unexpected MIME types for certain files (zip in
// particular is inconsistent across different Windows/security-software
// setups) -- falling back to the file extension when the MIME type
// doesn't match a known one makes this reliable everywhere, not just on
// whatever machine it was tested on.
function getAttachmentType(mimetype, originalname) {
  const byMimetype = {
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
  if (byMimetype[mimetype]) return byMimetype[mimetype];

  const ext = (originalname.split('.').pop() || '').toLowerCase();
  const byExtension = {
    pdf: 'pdf', xlsx: 'xlsx', docx: 'docx', zip: 'zip',
    jpg: 'image', jpeg: 'image', png: 'image', gif: 'image', webp: 'image'
  };
  return byExtension[ext] || null;
}
`;

content = content.replace(
  "const upload = multer({",
  helperCode + "const upload = multer({"
);
changes++;

const oldFilter = `  fileFilter: (req, file, cb) => {
    const allowed = {
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
    }
  }`;

const newFilter = `  fileFilter: (req, file, cb) => {
    if (getAttachmentType(file.mimetype, file.originalname)) {
      cb(null, true);
    } else {
      cb(new Error('Only PDF, Excel (.xlsx), Word (.docx), zip, and image files are allowed.'));
    }
  }`;

if (!content.includes(oldFilter)) {
  console.error('ERROR: fileFilter block not found as expected.');
  process.exit(1);
}
content = content.replace(oldFilter, newFilter);
changes++;

const oldTypeMap = `      const typeMap = {
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
      const attachmentType = typeMap[req.file.mimetype];`;

const newTypeMap = `      const attachmentType = getAttachmentType(req.file.mimetype, req.file.originalname);`;

if (!content.includes(oldTypeMap)) {
  console.error('ERROR: typeMap block not found as expected.');
  process.exit(1);
}
content = content.replace(oldTypeMap, newTypeMap);
changes++;

console.log('Applied ' + changes + ' change(s) (expected: 3).');

const out = usesCRLF ? content.replace(/\n/g, '\r\n') : content;
fs.writeFileSync(filePath, out);
console.log('Done.');
