const fs = require('fs');
const filePath = 'server/routes/auth.js';

const raw = fs.readFileSync(filePath, 'utf8');
const usesCRLF = raw.includes('\r\n');
let content = raw.replace(/\r\n/g, '\n');

if (content.includes('[LOGIN TIMING]')) {
  console.log('Already instrumented.');
  process.exit(0);
}

let changes = 0;

content = content.replace(
  /(\.select\('id, full_name, username, password_hash[^\n]*\n(?:[^\n]*\n){0,3}?\s*\.single\(\);\s*\n)/,
  (match) => {
    changes++;
    return match + "    console.log('[LOGIN TIMING] staff lookup took ' + (Date.now() - __t0) + 'ms');\n";
  }
);

content = content.replace(
  /(router\.post\('\/login', authLimiter, async \(req, res\) => \{\s*\n\s*try \{\s*\n)/,
  (match) => {
    changes++;
    return match.replace('try {', "const __t0 = Date.now();\n  try {");
  }
);

content = content.replace(
  /(const passwordMatches = await bcrypt\.compare\(password, staffMember\.password_hash\);?\s*\n)/,
  (match) => {
    changes++;
    return "    const __t1 = Date.now();\n" + match + "    console.log('[LOGIN TIMING] bcrypt compare took ' + (Date.now() - __t1) + 'ms');\n";
  }
);

content = content.replace(
  /(req\.session\.regenerate\(\(regenErr\) => \{\s*\n)/,
  (match) => {
    changes++;
    const withT2 = match.replace('req.session.regenerate', 'const __t2 = Date.now();\n    req.session.regenerate');
    return withT2 + "      console.log('[LOGIN TIMING] session.regenerate took ' + (Date.now() - __t2) + 'ms');\n";
  }
);

console.log('Applied ' + changes + ' insertions (expected: 4).');

if (changes < 4) {
  console.error('WARNING: fewer than 4 insertions matched.');
}

const out = usesCRLF ? content.replace(/\n/g, '\r\n') : content;
fs.writeFileSync(filePath, out);
console.log('Done. Run: grep -n "LOGIN TIMING" server/routes/auth.js  to verify.');
