// Updates the notification email link builder from /accounting/ to /portal/,
// matching the URL change. Single, short, safe anchor -- low risk.
const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'server', 'routes', 'messages.js');
let content = fs.readFileSync(filePath, 'utf8');

const old1 = "'https://macden.com.ng/accounting/' + link";
const new1 = "'https://macden.com.ng/portal/' + link";

if (content.includes(old1)) {
  content = content.replace(old1, new1);
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('Updated email notification links to use /portal/.');
} else if (content.includes(new1)) {
  console.log('Already updated, skipping.');
} else {
  console.log('WARNING: could not find the expected link-building line in messages.js.');
  console.log('This just means notification emails will still link to /accounting/ for now');
  console.log('(the redirect we added means those links still work fine -- just longer).');
  console.log('Not blocking -- paste back messages.js if you want this exact line updated too.');
}

