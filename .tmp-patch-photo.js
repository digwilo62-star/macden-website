const fs = require('fs');

function readNormalized(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  const usesCRLF = raw.includes('\r\n');
  return { normalized: raw.replace(/\r\n/g, '\n'), usesCRLF };
}
function writeRestoringLineEndings(filePath, normalizedContent, usesCRLF) {
  const out = usesCRLF ? normalizedContent.replace(/\n/g, '\r\n') : normalizedContent;
  fs.writeFileSync(filePath, out);
}

const filePath = 'server/routes/settings.js';
let { normalized: content, usesCRLF } = readNormalized(filePath);

// 1. Add the require at the top, right after multer's require
const oldRequire = `const multer = require('multer');`;
const newRequire = `const multer = require('multer');
const sharp = require('sharp');`;

if (!content.includes(oldRequire)) {
  console.error('ERROR: could not find the multer require line.');
  process.exit(1);
}
content = content.replace(oldRequire, newRequire);

// 2. Insert the resize/compress step before the storage upload, tolerant
//    of an optional blank line (same defensive pattern as other patches).
const oldUploadPattern = /    try \{\n      const storagePath = `\$\{req\.session\.staff\.id\}-\$\{Date\.now\(\)\}\.jpg`;\n\n?      const \{ error: uploadError \} = await supabase\.storage\n        \.from\('staff-photos'\)\n        \.upload\(storagePath, req\.file\.buffer, \{ contentType: req\.file\.mimetype, upsert:true \}\);/;

const newUpload = `    try {
      const processedBuffer = await sharp(req.file.buffer)
        .rotate()
        .resize({ width: 1200, height: 1200, fit: 'inside', withoutEnlargement: true })
        .jpeg({ quality: 82 })
        .toBuffer();

      const storagePath = \`\${req.session.staff.id}-\${Date.now()}.jpg\`;
      const { error: uploadError } = await supabase.storage
        .from('staff-photos')
        .upload(storagePath, processedBuffer, { contentType: 'image/jpeg', upsert: true });`;

if (!oldUploadPattern.test(content)) {
  console.error('ERROR: could not find the photo upload block in settings.js.');
  process.exit(1);
}
content = content.replace(oldUploadPattern, newUpload);

writeRestoringLineEndings(filePath, content, usesCRLF);
console.log('    Patched server/routes/settings.js (resize + compress on upload).');
