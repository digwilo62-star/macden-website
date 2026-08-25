const fs = require('fs');
const filePath = 'server/routes/auth.js';

const raw = fs.readFileSync(filePath, 'utf8');
const usesCRLF = raw.includes('\r\n');
let content = raw.replace(/\r\n/g, '\n');

if (content.includes('[LOGIN DEBUG]')) {
  console.log('Already instrumented.');
  process.exit(0);
}

let changes = 0;

content = content.replace(
  /(console\.log\('\[LOGIN TIMING\] staff lookup took[^\n]*\n)/,
  (match) => {
    changes++;
    return match +
      "    console.log('[LOGIN DEBUG] searched for: \"' + username + '\" (as ' + (isEmail ? 'email' : 'username') + ') -- found: ' + (staffMember ? staffMember.username : 'NOTHING'));\n";
  }
);

content = content.replace(
  /(console\.log\('\[LOGIN TIMING\] bcrypt compare took[^\n]*\n)/,
  (match) => {
    changes++;
    return match +
      "    console.log('[LOGIN DEBUG] password match result: ' + passwordMatches);\n";
  }
);

console.log('Applied ' + changes + ' debug line(s) (expected: 2).');

const out = usesCRLF ? content.replace(/\n/g, '\r\n') : content;
fs.writeFileSync(filePath, out);
console.log('Done.');
