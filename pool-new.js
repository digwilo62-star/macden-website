// The proposed fix: keep at least one connection warm, and don't tear
// down idle connections during a normal pause between clicks.
const { Pool } = require('pg');
module.exports = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
  min: 1,                    // always keep at least 1 ready connection
  idleTimeoutMillis: 1800000 // 30 minutes, not 10 seconds
});
