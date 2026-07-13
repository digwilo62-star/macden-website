// Run this from the server folder to add a staff member.
// Usage:  node scripts/createStaff.js
// You'll be prompted for each field — no arguments needed.

require('dotenv').config();
const readline = require('readline');
const bcrypt = require('bcrypt');
const supabase = require('../config/supabaseClient');

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });

function ask(question) {
  return new Promise((resolve) => rl.question(question, resolve));
}

async function main() {
  console.log('--- Add a new accounting staff member ---\n');

  const fullName = await ask('Full name: ');
  const username = await ask('Username: ');
  const email = await ask('Email: ');
  const password = await ask('Temporary password (staff should change this later): ');
  const canEditPricesInput = await ask('Can this person edit prices? (y/N): ');
  const roleInput = await ask('Role — "staff" or "admin" (default: staff): ');

  rl.close();

  const role = roleInput.trim().toLowerCase() === 'admin' ? 'admin' : 'staff';

  const { data: dept, error: deptError } = await supabase
    .from('departments')
    .select('id')
    .eq('slug', 'accounting')
    .single();

  if (deptError || !dept) {
    console.error('Could not find the Accounting department row. Did the schema script run correctly?');
    process.exit(1);
  }

  const passwordHash = await bcrypt.hash(password, 10);

  const { data, error } = await supabase
    .from('staff')
    .insert({
      department_id: dept.id,
      full_name: fullName,
      username: username,
      email: email,
      password_hash: passwordHash,
      role: role,
      email_verified: true,   // trusted, created directly by an admin — skips the signup flow
      is_active: true,        // no approval step needed for admin-created accounts
      can_edit_prices: canEditPricesInput.trim().toLowerCase() === 'y'
    })
    .select()
    .single();

  if (error) {
    console.error('Failed to create staff member:', error.message);
    process.exit(1);
  }

  console.log(`\nStaff member created: ${data.full_name} (${data.username})`);
}

main();

