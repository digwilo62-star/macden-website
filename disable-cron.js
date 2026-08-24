const fs = require('fs');
const filePath = 'server/server.js';
let content = fs.readFileSync(filePath, 'utf8');

const oldBlock = `cron.schedule('* * * * *', () => {
  messageRoutes.publishDueScheduledBroadcasts();
  announcementRoutes.publishDueScheduledAnnouncements();
});`;

const newBlock = `// TEMPORARILY DISABLED for testing whether this is causing the login
// connection issues -- to re-enable, delete the /* and */ below.
/*
cron.schedule('* * * * *', () => {
  messageRoutes.publishDueScheduledBroadcasts();
  announcementRoutes.publishDueScheduledAnnouncements();
});
*/`;

if (content.includes(newBlock)) {
  console.log('Already disabled.');
  process.exit(0);
}
if (!content.includes(oldBlock)) {
  console.error('ERROR: exact block not found. Nothing changed.');
  process.exit(1);
}

content = content.replace(oldBlock, newBlock);
fs.writeFileSync(filePath, content);
console.log('Cron jobs disabled for testing.');
