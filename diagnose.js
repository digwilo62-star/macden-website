// Diagnostic only -- doesn't change anything, just reports exactly what's
// going on so we can stop guessing.
const fs = require('fs');
const path = require('path');

console.log('Current working directory:', process.cwd());
console.log('Script location (__dirname):', __dirname);

const filePath = path.join(__dirname, 'accounting', 'dashboard.html');
console.log('Looking for file at:', filePath);
console.log('File exists:', fs.existsSync(filePath));

if (fs.existsSync(filePath)) {
  const buffer = fs.readFileSync(filePath);
  console.log('File size in bytes:', buffer.length);
  console.log('First 3 bytes (hex):', buffer.slice(0, 3).toString('hex'), '-- "efbbbf" would mean a UTF-8 BOM is present');

  const content = fs.readFileSync(filePath, 'utf8');
  console.log('Contains "stat-grid":', content.includes('stat-grid'));
  console.log('Contains "Tasks Assigned":', content.includes('Tasks Assigned'));
  console.log('Contains CRLF (\\r\\n):', content.includes('\r\n'));

  const idx = content.indexOf('stat-grid');
  if (idx !== -1) {
    const snippet = content.slice(idx, idx + 100);
    console.log('Raw snippet right after "stat-grid":', JSON.stringify(snippet));
  }
}
