// Tests the ACTUAL regex directly against your ACTUAL file, right here,
// with zero guessing. Doesn't change anything.
const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'accounting', 'dashboard.html');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');

const statGridRegex = /<div class="stat-grid">\s*<div class="stat-card">\s*<div class="num" id="statUnread">[^<]*<\/div>\s*<div class="lbl">Unread Messages<\/div>\s*<\/div>\s*<div class="stat-card">\s*<div class="num">[^<]*<\/div>\s*<div class="lbl">Pending Requests \(coming soon\)<\/div>\s*<\/div>\s*<div class="stat-card">\s*<div class="num">[^<]*<\/div>\s*<div class="lbl">Tasks Assigned\(coming soon\)<\/div>\s*<\/div>\s*<div class="stat-card">\s*<div class="num">[^<]*<\/div>\s*<div class="lbl">Approvals \(coming soon\)<\/div>\s*<\/div>\s*<\/div>/;

console.log('Regex matches:', statGridRegex.test(content));

// If it fails, test each piece separately to find exactly which part breaks
const pieces = [
  ['stat-grid opening', /<div class="stat-grid">/],
  ['first stat-card', /<div class="stat-grid">\s*<div class="stat-card">/],
  ['statUnread block', /<div class="num" id="statUnread">[^<]*<\/div>/],
  ['Unread Messages label', /<div class="lbl">Unread Messages<\/div>/],
  ['Pending Requests label', /<div class="lbl">Pending Requests \(coming soon\)<\/div>/],
  ['Tasks Assigned label', /<div class="lbl">Tasks Assigned\(coming soon\)<\/div>/],
  ['Approvals label', /<div class="lbl">Approvals \(coming soon\)<\/div>/],
];

console.log('\nPiece-by-piece test:');
pieces.forEach(([name, regex]) => {
  console.log(' ', name, ':', regex.test(content));
});
