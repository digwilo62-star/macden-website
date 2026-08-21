require('dotenv').config();
const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

async function timedQuery(label) {
  const start = Date.now();
  const { count, error } = await supabase
    .from('staff')
    .select('*', { count: 'exact', head: true });
  const time = Date.now() - start;
  if (error) {
    console.log(label + ': ERROR - ' + error.message);
  } else {
    console.log(label + ': ' + time + 'ms (staff count: ' + count + ')');
  }
  return time;
}

async function main() {
  console.log('Testing Supabase JS client speed...\n');
  await timedQuery('Call 1 (cold start)');
  await timedQuery('Call 2 (immediately after)');
  await timedQuery('Call 3 (immediately after)');
  console.log('\nWaiting 15 seconds (simulating a real pause between clicks)...\n');
  await new Promise(r => setTimeout(r, 15000));
  await timedQuery('Call 4 (after the pause)');
  await timedQuery('Call 5 (immediately after)');
}

main().catch(err => { console.error('Error:', err.message); process.exit(1); });
