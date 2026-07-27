#!/usr/bin/env bash
# BACKEND ITEM #29: Document version history. New POST /documents/:id/replace
# uploads a new version linked back to the old one via previous_version_id;
# the old version drops off the main list (is_current=false) but stays
# retrievable via GET /documents/:id/history. BACKEND ONLY - a 'Replace'
# button and history viewer in the UI are frontend work, saved for later.
# RUN THE SQL MIGRATION FIRST in Supabase before running this script.
# Run this from the ROOT of your macden-website repo, in Git Bash.
set -e

mkdir -p server/routes

cat > server/routes/documents.js << 'EOF_SERVER_ROUTES_DOCUMENTS_JS'
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
      .select('id, file_name, category, uploaded_by, file_url, file_size, mime_type, created_at, previous_version_id')
      .eq('is_current', true)
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
      createdAt: d.created_at,
      hasHistory: !!d.previous_version_id
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

// POST /api/accounting/documents/:id/replace — admin-only, uploads a new
// version linked back to the old one, which drops off the main list but
// stays retrievable via /history
router.post('/:id/replace', (req, res) => {
  if (req.session.staff.role !== 'admin') {
    return res.status(403).json({ error: 'Only admins can replace documents.' });
  }

  upload.single('file')(req, res, async (err) => {
    if (err) {
      return res.status(400).json({ error: err.message });
    }
    if (!req.file) {
      return res.status(400).json({ error: 'No file provided.' });
    }

    try {
      const oldId = req.params.id;
      const { data: oldDoc, error: oldFetchError } = await supabase
        .from('documents')
        .select('id, category, is_current')
        .eq('id', oldId)
        .single();

      if (oldFetchError || !oldDoc) {
        return res.status(404).json({ error: 'Original document not found.' });
      }
      if (!oldDoc.is_current) {
        return res.status(400).json({ error: 'This document has already been replaced by a newer version.' });
      }

      const storagePath = `${Date.now()}-${req.file.originalname}`;
      const { error: uploadError } = await supabase.storage
        .from('documents')
        .upload(storagePath, req.file.buffer, { contentType: req.file.mimetype });

      if (uploadError) {
        console.error('Document replace storage upload error:', uploadError);
        return res.status(500).json({ error: 'Upload failed: ' + uploadError.message });
      }

      const { data: publicUrlData } = supabase.storage.from('documents').getPublicUrl(storagePath);

      const { data: newDoc, error: insertError } = await supabase
        .from('documents')
        .insert({
          file_name: req.file.originalname,
          category: oldDoc.category,
          uploaded_by: req.session.staff.id,
          storage_path: storagePath,
          file_url: publicUrlData.publicUrl,
          file_size: req.file.size,
          mime_type: req.file.mimetype,
          is_current: true,
          previous_version_id: oldId
        })
        .select()
        .single();

      if (insertError) {
        console.error('Document replace insert error:', insertError);
        return res.status(500).json({ error: 'Could not save the new version.' });
      }

      const { error: updateOldError } = await supabase
        .from('documents')
        .update({ is_current: false })
        .eq('id', oldId);

      if (updateOldError) {
        console.error('Marking old document as superseded failed:', updateOldError);
        // The new version was still saved successfully — not fatal, just log it
      }

      res.json({ success: true, document: newDoc });
    } catch (err) {
      console.error('Document replace unexpected error:', err);
      res.status(500).json({ error: 'Something went wrong replacing this document.' });
    }
  });
});

// GET /api/accounting/documents/:id/history — everyone can view, walks the
// full version chain from the current document back to the original
router.get('/:id/history', async (req, res) => {
  try {
    const versions = [];
    let currentId = req.params.id;
    let guard = 0; // safety against any accidental circular reference

    while (currentId && guard < 50) {
      const { data: doc } = await supabase
        .from('documents')
        .select('id, file_name, file_url, file_size, uploaded_by, created_at, is_current, previous_version_id')
        .eq('id', currentId)
        .single();

      if (!doc) break;
      versions.push(doc);
      currentId = doc.previous_version_id;
      guard++;
    }

    if (versions.length === 0) {
      return res.status(404).json({ error: 'Document not found.' });
    }

    const uploaderIds = [...new Set(versions.map(v => v.uploaded_by).filter(Boolean))];
    const { data: staffRows } = await supabase
      .from('staff')
      .select('id, full_name')
      .in('id', uploaderIds.length > 0 ? uploaderIds : ['00000000-0000-0000-0000-000000000000']);
    const nameById = {};
    (staffRows || []).forEach(s => { nameById[s.id] = s.full_name; });

    const history = versions.map(v => ({
      id: v.id,
      fileName: v.file_name,
      fileUrl: v.file_url,
      fileSize: formatFileSize(v.file_size),
      uploadedBy: nameById[v.uploaded_by] || 'Unknown',
      createdAt: v.created_at,
      isCurrent: v.is_current
    }));

    res.json({ history });
  } catch (err) {
    console.error('Document history unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading version history.' });
  }
});

module.exports = router;

EOF_SERVER_ROUTES_DOCUMENTS_JS

echo "Document version history backend complete (#29). 21 of 40 items now done."