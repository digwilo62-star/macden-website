require('dotenv').config();
const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

async function main() {
  console.log('Testing with SUPABASE_URL:', process.env.SUPABASE_URL);
  console.log('Service role key starts with:', process.env.SUPABASE_SERVICE_ROLE_KEY.slice(0, 20) + '...');
  console.log('');

  const { data, error, count } = await supabase
    .from('staff')
    .select('id, username, full_name', { count: 'exact' })
    .eq('username', 'Igwilodaniel_224');

  console.log('Query result:');
  console.log('  Error:', error);
  console.log('  Rows found:', data ? data.length : 0);
  console.log('  Data:', JSON.stringify(data, null, 2));

  console.log('');
  console.log('Separately -- total staff rows visible AT ALL through this same client:');
  const { count: totalCount, error: totalError } = await supabase
    .from('staff')
    .select('*', { count: 'exact', head: true });
  console.log('  Total visible rows:', totalCount);
  console.log('  Error (if any):', totalError);
}

main().catch(err => console.error('Script error:', err));
