const express = require('express');
const bcrypt = require('bcrypt');
const multer = require('multer');
const { authenticator } = require('otplib');
const supabase = require('../config/supabaseClient');
const pgPool = require('../config/pgPool');

const router = express.Router();

const photoUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 3 * 1024 * 1024 }, // 3MB — photos, not documents
  fileFilter: (req, file, cb) => {
    const allowed = ['image/jpeg', 'image/png', 'image/webp'];
    if (allowed.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Only JPG, PNG, or WEBP images are allowed.'));
    }
  }
});

// GET /api/accounting/settings/me — full profile for the Settings page
router.get('/me', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('staff')
      .select('id, full_name, username, email, role, bio, created_at, departments(name), notify_email_broadcasts, notify_email_messages, notify_desktop, mfa_enabled, photo_url')
      .eq('id', req.session.staff.id)
      .single();

    if (error) {
      console.error('Settings fetch error:', error);
      return res.status(500).json({ error: 'Could not load your profile.' });
    }

    res.json({
      profile: {
        fullName: data.full_name,
        username: data.username,
        email: data.email,
        role: data.role,
        department: data.departments ? data.departments.name : null,
        bio: data.bio,
        dateJoined: data.created_at,
        notifyEmailBroadcasts: data.notify_email_broadcasts,
        notifyEmailMessages: data.notify_email_messages,
        notifyDesktop: data.notify_desktop,
        mfaEnabled: data.mfa_enabled,
        photoUrl: data.photo_url
      }
    });
  } catch (err) {
    console.error('Settings fetch unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading your profile.' });
  }
});

// PUT /api/accounting/settings/profile — only bio is editable by the staff member themselves
router.put('/profile', async (req, res) => {
  try {
    const { bio } = req.body;

    const { error } = await supabase
      .from('staff')
      .update({ bio: bio || null })
      .eq('id', req.session.staff.id);

    if (error) {
      return res.status(500).json({ error: 'Could not update your profile.' });
    }
    res.json({ success: true });
  } catch (err) {
    console.error('Profile update unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong updating your profile.' });
  }
});

// PUT /api/accounting/settings/notifications
router.put('/notifications', async (req, res) => {
  try {
    const { notifyEmailBroadcasts, notifyEmailMessages, notifyDesktop } = req.body;

    const { error } = await supabase
      .from('staff')
      .update({
        notify_email_broadcasts: !!notifyEmailBroadcasts,
        notify_email_messages: !!notifyEmailMessages,
        notify_desktop: !!notifyDesktop
      })
      .eq('id', req.session.staff.id);

    if (error) {
      return res.status(500).json({ error: 'Could not update notification preferences.' });
    }
    res.json({ success: true });
  } catch (err) {
    console.error('Notifications update unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// PUT /api/accounting/settings/password — real password change
router.put('/password', async (req, res) => {
  try {
    const { currentPassword, newPassword } = req.body;

    if (!currentPassword || !newPassword) {
      return res.status(400).json({ error: 'Current and new password are required.' });
    }
    if (newPassword.length < 8) {
      return res.status(400).json({ error: 'New password must be at least 8 characters.' });
    }

    const { data: staffMember, error: fetchError } = await supabase
      .from('staff')
      .select('password_hash')
      .eq('id', req.session.staff.id)
      .single();

    if (fetchError || !staffMember) {
      return res.status(500).json({ error: 'Could not verify your account.' });
    }

    const matches = await bcrypt.compare(currentPassword, staffMember.password_hash);
    if (!matches) {
      return res.status(401).json({ error: 'Current password is incorrect.' });
    }

    const newHash = await bcrypt.hash(newPassword, 10);
    const { error: updateError } = await supabase
      .from('staff')
      .update({ password_hash: newHash, must_change_password: false })
      .eq('id', req.session.staff.id);

    if (updateError) {
      return res.status(500).json({ error: 'Could not update your password.' });
    }

    // Clear the forced-change flag in the session too, so the frontend
    // stops redirecting immediately without needing a fresh login.
    req.session.staff.mustChangePassword = false;

    res.json({ success: true });
  } catch (err) {
    console.error('Password change unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong changing your password.' });
  }
});

// POST /api/accounting/settings/logout-all-devices
// Deletes every session row belonging to this person from the Postgres
// session store, forcing every logged-in device/browser to be signed out.
// Their CURRENT session is deleted too, so they'll need to log back in here as well.
router.post('/logout-all-devices', async (req, res) => {
  try {
    const staffId = req.session.staff.id;

    await pgPool.query(
      `DELETE FROM user_sessions WHERE sess::jsonb -> 'staff' ->> 'id' = $1`,
      [staffId]
    );

    res.json({ success: true });
  } catch (err) {
    console.error('Logout-all-devices unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong logging out other devices.' });
  }
});

// POST /api/accounting/settings/mfa/setup — generates a new secret, not
// active yet until confirmed with a real code via /mfa/verify
router.post('/mfa/setup', async (req, res) => {
  try {
    const secret = authenticator.generateSecret();
    const uri = authenticator.keyuri(req.session.staff.username, 'MACDEN Portal', secret);

    // Store the pending secret temporarily in the session (not the DB yet) —
    // it only becomes permanent once they prove they can generate a valid
    // code from it in the next step. Prevents someone locking themselves
    // out with a secret they never actually saved into their app.
    req.session.pendingMfaSecret = secret;

    res.json({ secret, uri });
  } catch (err) {
    console.error('MFA setup unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong setting up two-factor authentication.' });
  }
});

// POST /api/accounting/settings/mfa/verify — confirms setup with a real code
router.post('/mfa/verify', async (req, res) => {
  try {
    const { code } = req.body;
    const pendingSecret = req.session.pendingMfaSecret;

    if (!pendingSecret) {
      return res.status(400).json({ error: 'Start MFA setup again first.' });
    }
    if (!code) {
      return res.status(400).json({ error: 'Enter the 6-digit code from your authenticator app.' });
    }

    const isValid = authenticator.verify({ token: code, secret: pendingSecret });
    if (!isValid) {
      return res.status(400).json({ error: 'Incorrect code. Check your authenticator app and try again.' });
    }

    const { error } = await supabase
      .from('staff')
      .update({ mfa_secret: pendingSecret, mfa_enabled: true })
      .eq('id', req.session.staff.id);

    if (error) {
      console.error('MFA enable error:', error);
      return res.status(500).json({ error: 'Could not enable two-factor authentication.' });
    }

    delete req.session.pendingMfaSecret;
    res.json({ success: true });
  } catch (err) {
    console.error('MFA verify unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong confirming two-factor authentication.' });
  }
});

// POST /api/accounting/settings/mfa/disable — requires current password
router.post('/mfa/disable', async (req, res) => {
  try {
    const { currentPassword } = req.body;
    if (!currentPassword) {
      return res.status(400).json({ error: 'Enter your current password to disable two-factor authentication.' });
    }

    const { data: staffMember } = await supabase
      .from('staff')
      .select('password_hash')
      .eq('id', req.session.staff.id)
      .single();

    const matches = await bcrypt.compare(currentPassword, staffMember.password_hash);
    if (!matches) {
      return res.status(401).json({ error: 'Incorrect password.' });
    }

    const { error } = await supabase
      .from('staff')
      .update({ mfa_secret: null, mfa_enabled: false })
      .eq('id', req.session.staff.id);

    if (error) {
      return res.status(500).json({ error: 'Could not disable two-factor authentication.' });
    }

    res.json({ success: true });
  } catch (err) {
    console.error('MFA disable unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// POST /api/accounting/settings/photo — self-upload only, one person's own photo
router.post('/photo', (req, res) => {
  photoUpload.single('photo')(req, res, async (err) => {
    if (err) {
      return res.status(400).json({ error: err.message });
    }
    if (!req.file) {
      return res.status(400).json({ error: 'No image provided.' });
    }

    try {
      const storagePath = `${req.session.staff.id}-${Date.now()}.jpg`;

      const { error: uploadError } = await supabase.storage
        .from('staff-photos')
        .upload(storagePath, req.file.buffer, { contentType: req.file.mimetype, upsert: true });

      if (uploadError) {
        console.error('Photo storage upload error:', uploadError);
        return res.status(500).json({ error: 'Upload failed: ' + uploadError.message });
      }

      const { data: publicUrlData } = supabase.storage.from('staff-photos').getPublicUrl(storagePath);

      const { error: updateError } = await supabase
        .from('staff')
        .update({ photo_url: publicUrlData.publicUrl })
        .eq('id', req.session.staff.id);

      if (updateError) {
        console.error('Photo URL save error:', updateError);
        return res.status(500).json({ error: 'Could not save your photo.' });
      }

      // Update the session too, so the new photo shows up immediately on
      // every page without needing to log out and back in.
      req.session.staff.photoUrl = publicUrlData.publicUrl;

      res.json({ success: true, photoUrl: publicUrlData.publicUrl });
    } catch (err) {
      console.error('Photo upload unexpected error:', err);
      res.status(500).json({ error: 'Something went wrong uploading your photo.' });
    }
  });
});

module.exports = router;

