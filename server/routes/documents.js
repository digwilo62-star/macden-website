const express = require('express');
const multer = require('multer');
const supabase = require('../config/supabaseClient');

const router = express.Router();

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 20 * 1024 * 1024 }, // 20MB - documents can run bigger than chat attachments
  fileFilter: (req, file, cb) => {
    const allowed = [
      'application/pdf',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/msword',
      'application/vnd.ms-excel'
    ];
    if (allowed.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Only PDF, Word, and Excel files are allowed.'));
    }
  }
});

function formatFileSize(bytes) {
  if (!bytes) return '—';
  const mb = bytes / (1024 * 1024);
  if (mb < 1) return Math.round(bytes / 1024) + ' KB';
  return mb.toFixed(1) + ' MB';
}

// GET /api/accounting/documents?category=X — everyone can view/list
router.get('/', async (req, res) => {
  try {
    const category = req.query.category;

    let query = supabase
      .from('documents')
      .select('id, file_name, category, uploaded_by, file_url, file_size, mime_type, created_at')
      .order('created_at', { ascending: false });

    if (category && category !== 'All Documents') {
      query = query.eq('category', category);
    }

    const { data, error } = await query;

    if (error) {
      console.error('Documents list error:', error);
      return res.status(500).json({ error: 'Could not load documents.' });
    }

    const uploaderIds = [...new Set(data.map(d => d.uploaded_by).filter(Boolean))];
    const { data: staffRows } = await supabase
      .from('staff')
      .select('id, full_name')
      .in('id', uploaderIds.length > 0 ? uploaderIds : ['00000000-0000-0000-0000-000000000000']);
    const nameById = {};
    (staffRows || []).forEach(s => { nameById[s.id] = s.full_name; });

    const documents = data.map(d => ({
      id: d.id,
      fileName: d.file_name,
      category: d.category,
      uploadedBy: nameById[d.uploaded_by] || 'Unknown',
      fileUrl: d.file_url,
      fileSize: formatFileSize(d.file_size),
      mimeType: d.mime_type,
      createdAt: d.created_at
    }));

    res.json({ documents });
  } catch (err) {
    console.error('Documents list unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading documents.' });
  }
});

// POST /api/accounting/documents/upload — admin-only
router.post('/upload', (req, res) => {
  if (req.session.staff.role !== 'admin') {
    return res.status(403).json({ error: 'Only admins can upload documents.' });
  }

  upload.single('file')(req, res, async (err) => {
    if (err) {
      return res.status(400).json({ error: err.message });
    }
    if (!req.file) {
      return res.status(400).json({ error: 'No file provided.' });
    }

    const category = req.body.category || 'Uncategorized';

    try {
      const storagePath = `${Date.now()}-${req.file.originalname}`;

      const { error: uploadError } = await supabase.storage
        .from('documents')
        .upload(storagePath, req.file.buffer, { contentType: req.file.mimetype });

      if (uploadError) {
        console.error('Document storage upload error:', uploadError);
        return res.status(500).json({ error: 'Upload failed: ' + uploadError.message });
      }

      const { data: publicUrlData } = supabase.storage.from('documents').getPublicUrl(storagePath);

      const { data, error: insertError } = await supabase
        .from('documents')
        .insert({
          file_name: req.file.originalname,
          category: category,
          uploaded_by: req.session.staff.id,
          storage_path: storagePath,
          file_url: publicUrlData.publicUrl,
          file_size: req.file.size,
          mime_type: req.file.mimetype
        })
        .select()
        .single();

      if (insertError) {
        console.error('Document insert error:', insertError);
        return res.status(500).json({ error: 'Could not save document record.' });
      }

      res.json({ success: true, document: data });
    } catch (err) {
      console.error('Document upload unexpected error:', err);
      res.status(500).json({ error: 'Something went wrong uploading this document.' });
    }
  });
});

// DELETE /api/accounting/documents/:id — admin-only
router.delete('/:id', async (req, res) => {
  try {
    if (req.session.staff.role !== 'admin') {
      return res.status(403).json({ error: 'Only admins can delete documents.' });
    }

    const { data: doc } = await supabase
      .from('documents')
      .select('storage_path')
      .eq('id', req.params.id)
      .single();

    if (doc) {
      await supabase.storage.from('documents').remove([doc.storage_path]);
    }

    const { error } = await supabase.from('documents').delete().eq('id', req.params.id);

    if (error) {
      return res.status(500).json({ error: 'Could not delete document.' });
    }

    res.json({ success: true });
  } catch (err) {
    console.error('Document delete unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong deleting this document.' });
  }
});

module.exports = router;

