// Adds a single-record staff fetch endpoint, needed so the Edit form can
// pre-fill someone's CURRENT full details (including the raw department_id,
// not just the joined department name) before submitting changes -- the
// existing PUT /staff/:id route expects all editable fields every time,
// so an accurate pre-fill is what prevents accidentally wiping out
// unrelated fields when only changing one thing like role.
//
//   node fix-add-single-staff-fetch.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'server', 'routes', 'admin.js');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');

if (content.includes("router.get('/staff/:id'")) {
  console.log('Already added, skipping.');
  process.exit(0);
}

const anchor = "// PUT /api/accounting/admin/staff/:id — edit an existing staff member";
const newRoute = `// GET /api/accounting/admin/staff/:id -- single staff record with the
// raw department_id (not just the joined name), needed to accurately
// pre-fill the Edit form before submitting changes back.
router.get('/staff/:id', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('staff')
      .select('id, full_name, role, department_id, phone, branch')
      .eq('id', req.params.id)
      .single();

    if (error || !data) {
      return res.status(404).json({ error: 'Staff member not found.' });
    }

    res.json({ staff: data });
  } catch (err) {
    console.error('Single staff fetch error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

${anchor}`;

if (content.includes(anchor)) {
  content = content.replace(anchor, newRoute);
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('Added GET /admin/staff/:id single-record endpoint.');
} else {
  console.log('WARNING: could not find the expected anchor. Nothing changed -- paste back your current admin.js.');
  process.exit(1);
}

