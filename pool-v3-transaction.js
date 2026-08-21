// Same sizing as v2, but on the Transaction pooler (port 6543) instead
// of Session mode (5432). Session mode caps at a hard 15 total
// connections project-wide -- a single burst of 8 nearly exhausted it
// entirely, on its own, before counting anything else using the
// database at the same time. Transaction mode exists specifically to
// support many brief, concurrent connections without that ceiling.
const { Pool } = require('pg');
module.exports = new Pool({
  connectionString: process.env.DATABASE_URL.replace(':5432/', ':6543/'),
  ssl: { rejectUnauthorized: false },
  min: 8,
  max: 10,
  idleTimeoutMillis: 1800000
});
