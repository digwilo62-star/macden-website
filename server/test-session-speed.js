// test-session-speed.js
//
// Isolates exactly one thing: how long does it take to connect to the
// database and query the user_sessions table -- the same step that
// happens on every single authenticated request, before any route
// logic even runs. This is read-only and changes nothing.

require('dotenv').config();
const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false }
});

async function main() {
  console.log('Testing connection + query speed against your real database...\n');

  const connectStart = Date.now();
  const client = await pool.connect();
  const connectTime = Date.now() - connectStart;
  console.log('Time to establish a connection: ' + connectTime + 'ms');

  const queryStart = Date.now();
  const result = await client.query('SELECT count(*) FROM user_sessions');
  const queryTime = Date.now() - queryStart;
  console.log('Time to query user_sessions (count=' + result.rows[0].count + '): ' + queryTime + 'ms');

  // Run it a second time on the SAME connection -- this tells us whether
  // it's the connection setup itself that's slow, or the query, or both
  const secondQueryStart = Date.now();
  await client.query('SELECT count(*) FROM user_sessions');
  const secondQueryTime = Date.now() - secondQueryStart;
  console.log('Same query again, same connection: ' + secondQueryTime + 'ms');

  client.release();
  await pool.end();

  console.log('\n--- Summary ---');
  console.log('Connection setup: ' + connectTime + 'ms');
  console.log('First query: ' + queryTime + 'ms');
  console.log('Second query (warm connection): ' + secondQueryTime + 'ms');
}

main().catch(err => {
  console.error('Error:', err.message);
  process.exit(1);
});
