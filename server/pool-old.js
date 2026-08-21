// Simulates the CURRENT pool settings (Node's pg defaults)
const { Pool } = require('pg');
module.exports = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false }
  // no idleTimeoutMillis or min set -- uses pg's defaults:
  // idleTimeoutMillis: 10000 (10s), min: 0
});
