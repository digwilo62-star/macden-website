// Simulates a REAL page load: 8 requests fired at the SAME TIME, not one
// after another -- matching exactly what the video showed happening on
// every single page (dashboard-check, notifications, unread-count,
// active, summary-today, pending, pending-staff, and one more).

require('dotenv').config();
const poolFile = process.argv[2];
const pool = require('./' + poolFile);

async function oneRequest(label) {
  const start = Date.now();
  const client = await pool.connect();
  const connectTime = Date.now() - start;
  await client.query('SELECT count(*) FROM user_sessions');
  client.release();
  return { label, connectTime };
}

async function burstOf8(roundLabel) {
  console.log(roundLabel + ':');
  const labels = ['dashboard-check', 'notifications', 'unread-count', 'active', 'summary-today', 'pending', 'pending-staff', 'unread-count-2'];
  const results = await Promise.all(labels.map(l => oneRequest(l)));
  results.forEach(r => console.log('  ' + r.label + ': ' + r.connectTime + 'ms'));
  const slowest = Math.max(...results.map(r => r.connectTime));
  console.log('  SLOWEST in this burst (what the user actually waits for): ' + slowest + 'ms\n');
  return slowest;
}

async function main() {
  console.log('Testing with: ' + poolFile + '\n');

  await burstOf8('Page load 1 (right after login)');

  console.log('Waiting 15 seconds (reading the page)...\n');
  await new Promise(r => setTimeout(r, 15000));

  await burstOf8('Page load 2 (next click, after the pause)');

  await pool.end();
}

main().catch(err => { console.error(err); process.exit(1); });
