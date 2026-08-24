const fs = require('fs');

function normalize(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  return { content: raw.replace(/\r\n/g, '\n'), usesCRLF: raw.includes('\r\n') };
}
function save(filePath, content, usesCRLF) {
  fs.writeFileSync(filePath, usesCRLF ? content.replace(/\n/g, '\r\n') : content);
}

{
  const filePath = 'portal/assets/api.js';
  let { content, usesCRLF } = normalize(filePath);
  const count = (content.match(/20000/g) || []).length;
  content = content.replace(/20000/g, '60000');
  save(filePath, content, usesCRLF);
  console.log('api.js: replaced ' + count + ' instance(s) of 20000ms -> 60000ms');
}

{
  const filePath = 'portal/assets/presence.js';
  if (fs.existsSync(filePath)) {
    let { content, usesCRLF } = normalize(filePath);
    const count = (content.match(/20000/g) || []).length;
    content = content.replace(/20000/g, '60000');
    save(filePath, content, usesCRLF);
    console.log('presence.js: replaced ' + count + ' instance(s) of 20000ms -> 60000ms');
  } else {
    console.log('presence.js not found, skipped');
  }
}

{
  const filePath = 'server/server.js';
  let { content, usesCRLF } = normalize(filePath);
  const count = (content.match(/15000/g) || []).length;
  content = content.replace(/15000/g, '30000');
  save(filePath, content, usesCRLF);
  console.log('server.js: replaced ' + count + ' instance(s) of 15000ms -> 30000ms');
}

console.log('');
console.log('Done. These are TEMPORARY relief measures for tonight, not a permanent fix.');
