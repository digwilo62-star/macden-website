// Simulates real usage: connect (page load), pause like a person reading
// (15s -- longer than pg's default 10s idle timeout), then connect again
// (next click). This is the exact pattern that would expose the bug.

require('dotenv').config();
const poolFile = process.argv[2]; // 'pool-old.js' or 'pool-new.js'
const pool = require('./' + poolFile);

async function timedQuery(label) {
  const start = Date.now();
  const client = await pool.connect();
  const connectTime = Date.now() - start;
  await client.query('SELECT count(*) FROM user_sessions');
  client.release();
  console.log(label + ': connection took ' + connectTime + 'ms');
  return connectTime;
}

async function main() {
  console.log('Testing with: ' + poolFile + '\n');
  await timedQuery('Request 1 (initial page load)');

  console.log('Waiting 15 seconds (simulating someone reading the page)...\n');
  await new Promise(r => setTimeout(r, 15000));

  await timedQuery('Request 2 (next click, after the pause)');

  await pool.end();
}

main().catch(err => { console.error(err); process.exit(1); });
