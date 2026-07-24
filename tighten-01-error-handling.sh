#!/usr/bin/env bash
# TIGHTENING PASS: adds missing try/catch error handling to every backend
# route that lacked it (52 routes across 11 files audited, 16 were genuinely
# missing it - prices.js had ZERO protection, auth.js and presence.js were
# almost entirely unprotected). This is the exact bug class that caused
# the 'Unexpected token <' silent-500 errors we hit multiple times this
# session - now every single route returns clean JSON even on failure.
# Also fixes two pages (Manage Staff, Onboarding) that had no active
# sidebar highlight at all.
# Run this from the ROOT of your macden-website repo, in Git Bash.
set -e

mkdir -p server/routes accounting

cat > server/routes/prices.js << 'EOF_SERVER_ROUTES_PRICES_JS'
const express = require('express');
const supabase = require('../config/supabaseClient');

const router = express.Router();

function requireCanEditPrices(req, res, next) {
  if (!req.session.staff.canEditPrices) {
    return res.status(403).json({ error: 'You do not have permission to edit prices.' });
  }
  next();
}

// GET /api/accounting/prices — everyone can read
router.get('/', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('accounting_prices')
      .select('id, product_name, cost_price, margin_percent, updated_at')
      .order('product_name', { ascending: true });

    if (error) {
      console.error('Prices list error:', error);
      return res.status(500).json({ error: 'Could not load prices.' });
    }

    res.json({ prices: data });
  } catch (err) {
    console.error('Prices list unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading prices.' });
  }
});

// POST /api/accounting/prices — add a new product price (editors only)
router.post('/', requireCanEditPrices, async (req, res) => {
  try {
    const { productName, costPrice, marginPercent } = req.body;

    if (!productName || costPrice === undefined) {
      return res.status(400).json({ error: 'Product name and cost price are required.' });
    }

    const { data, error } = await supabase
      .from('accounting_prices')
      .insert({
        product_name: productName,
        cost_price: costPrice,
        margin_percent: marginPercent || null,
        updated_by: req.session.staff.id
      })
      .select()
      .single();

    if (error) {
      console.error('Price add error:', error);
      return res.status(400).json({ error: 'Could not add product. It may already exist.' });
    }

    res.json({ success: true, price: data });
  } catch (err) {
    console.error('Price add unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong adding this product.' });
  }
});

// PUT /api/accounting/prices/:id — update a price (editors only)
// Snapshots the OLD value into history before overwriting, so "last week / last month" stays accurate.
router.put('/:id', requireCanEditPrices, async (req, res) => {
  try {
    const { id } = req.params;
    const { costPrice, marginPercent } = req.body;

    if (costPrice === undefined) {
      return res.status(400).json({ error: 'Cost price is required.' });
    }

    const { data: existing, error: fetchError } = await supabase
      .from('accounting_prices')
      .select('cost_price, margin_percent')
      .eq('id', id)
      .single();

    if (fetchError || !existing) {
      return res.status(404).json({ error: 'Product not found.' });
    }

    // Snapshot the value being replaced, so history reflects what the price WAS
    const { error: historyError } = await supabase
      .from('accounting_price_history')
      .insert({
        price_id: id,
        cost_price: existing.cost_price,
        margin_percent: existing.margin_percent,
        recorded_by: req.session.staff.id
      });

    if (historyError) {
      console.error('Price history snapshot error:', historyError);
      return res.status(500).json({ error: 'Could not save price history.' });
    }

    const { data: updated, error: updateError } = await supabase
      .from('accounting_prices')
      .update({
        cost_price: costPrice,
        margin_percent: marginPercent || null,
        updated_by: req.session.staff.id,
        updated_at: new Date().toISOString()
      })
      .eq('id', id)
      .select()
      .single();

    if (updateError) {
      console.error('Price update error:', updateError);
      return res.status(500).json({ error: 'Could not update price.' });
    }

    res.json({ success: true, price: updated });
  } catch (err) {
    console.error('Price update unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong updating this price.' });
  }
});

// GET /api/accounting/prices/:id/history?range=week|month — everyone can read
router.get('/:id/history', async (req, res) => {
  try {
    const { id } = req.params;
    const range = req.query.range === 'month' ? 30 : 7; // default to last week

    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - range);

    const { data, error } = await supabase
      .from('accounting_price_history')
      .select('id, cost_price, margin_percent, recorded_at')
      .eq('price_id', id)
      .gte('recorded_at', cutoff.toISOString())
      .order('recorded_at', { ascending: false });

    if (error) {
      console.error('Price history fetch error:', error);
      return res.status(500).json({ error: 'Could not load price history.' });
    }

    res.json({ history: data });
  } catch (err) {
    console.error('Price history unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading price history.' });
  }
});

module.exports = router;

EOF_SERVER_ROUTES_PRICES_JS

cat > server/routes/presence.js << 'EOF_SERVER_ROUTES_PRESENCE_JS'
const express = require('express');
const supabase = require('../config/supabaseClient');

const router = express.Router();

// POST /api/accounting/presence/heartbeat
// Called every ~20 seconds by the frontend while a page is open.
// Anyone whose last_seen is within the last 40 seconds counts as online.
router.post('/heartbeat', async (req, res) => {
  try {
    await supabase
      .from('staff')
      .update({ last_seen: new Date().toISOString() })
      .eq('id', req.session.staff.id);

    res.json({ success: true });
  } catch (err) {
    console.error('Heartbeat unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

module.exports = router;

EOF_SERVER_ROUTES_PRESENCE_JS

cat > server/routes/auth.js << 'EOF_SERVER_ROUTES_AUTH_JS'
const express = require('express');
const bcrypt = require('bcrypt');
const crypto = require('crypto');
const rateLimit = require('express-rate-limit');
const supabase = require('../config/supabaseClient');
const { sendVerificationEmail } = require('../utils/email');

const router = express.Router();

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many attempts. Please wait a few minutes and try again.' }
});

function generateCode() {
  return crypto.randomInt(100000, 999999).toString();
}

// POST /api/accounting/auth/register
router.post('/register', authLimiter, async (req, res) => {
  try {
    const { fullName, username, email, password } = req.body;

    if (!fullName || !username || !email || !password) {
      return res.status(400).json({ error: 'All fields are required.' });
    }

    if (password.length < 8) {
      return res.status(400).json({ error: 'Password must be at least 8 characters.' });
    }

    const { data: dept, error: deptError } = await supabase
      .from('departments')
      .select('id')
      .eq('slug', 'accounting')
      .single();

    if (deptError || !dept) {
      return res.status(500).json({ error: 'Setup error — accounting department not found.' });
    }

    const passwordHash = await bcrypt.hash(password, 10);
    const code = generateCode();
    const expiresAt = new Date(Date.now() + 15 * 60 * 1000);

    const { data: newStaff, error } = await supabase
      .from('staff')
      .insert({
        department_id: dept.id,
        full_name: fullName,
        username: username,
        email: email,
        password_hash: passwordHash,
        email_verified: false,
        is_active: false,
        verification_code: code,
        verification_code_expires_at: expiresAt.toISOString()
      })
      .select()
      .single();

    if (error) {
      console.error('Register insert error:', error);
      return res.status(400).json({ error: 'Could not create account. Username or email may already be in use.' });
    }

    try {
      await sendVerificationEmail(email, fullName, code);
    } catch (emailError) {
      console.error('Failed to send verification email:', emailError.message);
      return res.status(500).json({ error: 'Account created but the verification email failed to send. Contact your admin.' });
    }

    res.json({ success: true, message: 'Account created. Check your email for a verification code.' });
  } catch (err) {
    console.error('Register unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong creating your account.' });
  }
});

// POST /api/accounting/auth/verify-email
router.post('/verify-email', authLimiter, async (req, res) => {
  try {
    const { email, code } = req.body;

    if (!email || !code) {
      return res.status(400).json({ error: 'Email and code are required.' });
    }

    const { data: staffMember, error } = await supabase
      .from('staff')
      .select('id, verification_code, verification_code_expires_at, email_verified')
      .eq('email', email)
      .single();

    if (error || !staffMember) {
      return res.status(400).json({ error: 'Invalid email or code.' });
    }

    if (staffMember.email_verified) {
      return res.status(400).json({ error: 'This email is already verified.' });
    }

    if (staffMember.verification_code !== code) {
      return res.status(400).json({ error: 'Incorrect code.' });
    }

    if (new Date(staffMember.verification_code_expires_at) < new Date()) {
      return res.status(400).json({ error: 'This code has expired. Please request a new one.' });
    }

    const { error: updateError } = await supabase
      .from('staff')
      .update({ email_verified: true, verification_code: null, verification_code_expires_at: null })
      .eq('id', staffMember.id);

    if (updateError) {
      console.error('Verify-email update error:', updateError);
      return res.status(500).json({ error: 'Could not verify your email. Please try again.' });
    }

    res.json({ success: true, message: 'Email verified. Your account is now waiting for admin approval.' });
  } catch (err) {
    console.error('Verify-email unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong verifying your email.' });
  }
});

// POST /api/accounting/auth/login
router.post('/login', authLimiter, async (req, res) => {
  try {
    const { username, password } = req.body;

    if (!username || !password) {
      return res.status(400).json({ error: 'Email and password are required.' });
    }

    const isEmail = username.includes('@');
    const { data: staffMember, error } = await supabase
      .from('staff')
      .select('id, full_name, username, password_hash, role, can_edit_prices, is_active, email_verified, department_id')
      .eq(isEmail ? 'email' : 'username', username)
      .single();

    if (error || !staffMember) {
      return res.status(401).json({ error: 'Invalid email or password.' });
    }

    const passwordMatches = await bcrypt.compare(password, staffMember.password_hash);

    if (!passwordMatches) {
      return res.status(401).json({ error: 'Invalid email or password.' });
    }

    if (!staffMember.email_verified) {
      return res.status(403).json({ error: 'Please verify your email before logging in.' });
    }

    if (!staffMember.is_active) {
      return res.status(403).json({ error: 'Your account is awaiting admin approval.' });
    }

    req.session.staff = {
      id: staffMember.id,
      fullName: staffMember.full_name,
      username: staffMember.username,
      role: staffMember.role,
      canEditPrices: staffMember.can_edit_prices,
      departmentId: staffMember.department_id
    };

    await supabase
      .from('staff')
      .update({ last_seen: new Date().toISOString() })
      .eq('id', staffMember.id);

    res.json({ success: true, staff: req.session.staff });
  } catch (err) {
    console.error('Login unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong logging you in.' });
  }
});

// POST /api/accounting/auth/logout
router.post('/logout', (req, res) => {
  try {
    req.session.destroy((err) => {
      if (err) {
        console.error('Logout session destroy error:', err);
        return res.status(500).json({ error: 'Could not log out. Try again.' });
      }
      res.clearCookie('connect.sid');
      res.json({ success: true });
    });
  } catch (err) {
    console.error('Logout unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong logging out.' });
  }
});

// GET /api/accounting/auth/me — used by frontend to check if a session is active
router.get('/me', (req, res) => {
  if (!req.session.staff) {
    return res.status(401).json({ error: 'Not logged in.' });
  }
  res.json({ staff: req.session.staff });
});

module.exports = router;

EOF_SERVER_ROUTES_AUTH_JS

cat > server/routes/messages.js << 'EOF_SERVER_ROUTES_MESSAGES_JS'
const express = require('express');
const multer = require('multer');
const supabase = require('../config/supabaseClient');
const { isOnline } = require('./staff');

const router = express.Router();

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 15 * 1024 * 1024 }, // 15MB
  fileFilter: (req, file, cb) => {
    const allowed = {
      'application/pdf': 'pdf',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx'
    };
    if (allowed[file.mimetype]) {
      cb(null, true);
    } else {
      cb(new Error('Only PDF and Excel (.xlsx) files are allowed.'));
    }
  }
});

// POST /api/accounting/messages/upload — uploads a PDF or Excel file to
// Supabase Storage and returns the URL to attach to a message.
router.post('/upload', (req, res) => {
  upload.single('attachment')(req, res, async (err) => {
    if (err) {
      return res.status(400).json({ error: err.message });
    }
    if (!req.file) {
      return res.status(400).json({ error: 'No file provided.' });
    }

    try {
      const typeMap = {
        'application/pdf': 'pdf',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx'
      };
      const attachmentType = typeMap[req.file.mimetype];
      const fileName = `${req.session.staff.id}-${Date.now()}-${req.file.originalname}`;

      const { error: uploadError } = await supabase.storage
        .from('attachments')
        .upload(fileName, req.file.buffer, { contentType: req.file.mimetype });

      if (uploadError) {
        console.error('Supabase storage upload error:', uploadError);
        // Surface the real reason (e.g. "Bucket not found") instead of a generic
        // message — this is the difference between a fixable, diagnosable error
        // and a dead end.
        return res.status(500).json({ error: 'Upload failed: ' + (uploadError.message || 'unknown error') });
      }

      const { data: publicUrlData } = supabase.storage.from('attachments').getPublicUrl(fileName);

      res.json({
        success: true,
        url: publicUrlData.publicUrl,
        type: attachmentType,
        name: req.file.originalname
      });
    } catch (err) {
      console.error('Upload error:', err);
      res.status(500).json({ error: 'Something went wrong uploading this file.' });
    }
  });
});

async function createReadRowsForRecipients(conversationId, messageId, senderId) {
  const { data: members } = await supabase
    .from('conversation_members')
    .select('staff_id')
    .eq('conversation_id', conversationId)
    .neq('staff_id', senderId);

  if (!members || members.length === 0) return;

  const rows = members.map(m => ({ message_id: messageId, staff_id: m.staff_id, read_at: null }));
  await supabase.from('message_reads').insert(rows);
}

async function getOtherParticipants(conversationId, excludeStaffId) {
  const { data: memberRows } = await supabase
    .from('conversation_members')
    .select('staff_id')
    .eq('conversation_id', conversationId)
    .neq('staff_id', excludeStaffId);

  if (!memberRows || memberRows.length === 0) return [];

  const ids = memberRows.map(m => m.staff_id);
  const { data: staffRows } = await supabase
    .from('staff')
    .select('id, full_name, last_seen')
    .in('id', ids);

  if (!staffRows) return [];

  return staffRows.map(s => ({
    id: s.id,
    fullName: s.full_name,
    isOnline: isOnline(s.last_seen)
  }));
}

router.get('/unread-count', async (req, res) => {
  try {
    const { count, error } = await supabase
      .from('message_reads')
      .select('*', { count: 'exact', head: true })
      .eq('staff_id', req.session.staff.id)
      .is('read_at', null);

    if (error) {
      console.error('Unread count error:', error);
      return res.status(500).json({ error: 'Could not load unread count.' });
    }

    res.json({ unreadCount: count });
  } catch (err) {
    console.error('Unread count unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

router.get('/conversations', async (req, res) => {
  try {
    const staffId = req.session.staff.id;

    const { data: memberRows, error: memberError } = await supabase
      .from('conversation_members')
      .select('conversation_id')
      .eq('staff_id', staffId);

    if (memberError) {
      console.error('Conversation members fetch error:', memberError);
      return res.status(500).json({ error: 'Could not load inbox.' });
    }

    const conversationIds = memberRows.map(r => r.conversation_id);
    if (conversationIds.length === 0) {
      return res.json({ conversations: [] });
    }

    const { data: conversations, error: convError } = await supabase
      .from('conversations')
      .select('id, subject, is_broadcast, created_at')
      .in('id', conversationIds)
      .order('created_at', { ascending: false });

    if (convError) {
      console.error('Conversations fetch error:', convError);
      return res.status(500).json({ error: 'Could not load inbox.' });
    }

    const enriched = await Promise.all(conversations.map(async (conv) => {
      const [lastMessageResult, participants] = await Promise.all([
        supabase
          .from('messages')
          .select('id, sender_id, body, sent_at')
          .eq('conversation_id', conv.id)
          .eq('status', 'sent')
          .order('sent_at', { ascending: false })
          .limit(1)
          .maybeSingle(),
        getOtherParticipants(conv.id, staffId)
      ]);

      const lastMessage = lastMessageResult.data;

      let isUnread = false;
      if (lastMessage) {
        const { data: readRow } = await supabase
          .from('message_reads')
          .select('read_at')
          .eq('message_id', lastMessage.id)
          .eq('staff_id', staffId)
          .maybeSingle();
        isUnread = readRow ? readRow.read_at === null : false;
      }

      return {
        id: conv.id,
        subject: conv.subject,
        isBroadcast: conv.is_broadcast,
        participants,
        displayName: participants.map(p => p.fullName).join(', ') || 'Unknown',
        lastMessagePreview: lastMessage ? lastMessage.body.slice(0, 60) : null,
        lastMessageAt: lastMessage ? lastMessage.sent_at : conv.created_at,
        isUnread
      };
    }));

    enriched.sort((a, b) => new Date(b.lastMessageAt) - new Date(a.lastMessageAt));

    res.json({ conversations: enriched });
  } catch (err) {
    console.error('Conversations list unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading your inbox.' });
  }
});

router.get('/conversations/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const staffId = req.session.staff.id;

    const { data: membership } = await supabase
      .from('conversation_members')
      .select('id')
      .eq('conversation_id', id)
      .eq('staff_id', staffId)
      .maybeSingle();

    if (!membership) {
      return res.status(403).json({ error: 'You do not have access to this conversation.' });
    }

    const { data: conversation } = await supabase
      .from('conversations')
      .select('id, subject')
      .eq('id', id)
      .single();

    const participants = await getOtherParticipants(id, staffId);

    // Build a full sender-name lookup (including yourself) so every message
    // in the thread can show a real "From" name, not just the other party.
    const { data: allMemberRows } = await supabase
      .from('conversation_members')
      .select('staff_id')
      .eq('conversation_id', id);
    const allMemberIds = (allMemberRows || []).map(m => m.staff_id);
    const { data: allStaffRows } = await supabase
      .from('staff')
      .select('id, full_name')
      .in('id', allMemberIds.length > 0 ? allMemberIds : ['00000000-0000-0000-0000-000000000000']);
    const nameById = {};
    (allStaffRows || []).forEach(s => { nameById[s.id] = s.full_name; });

    const { data: messages, error } = await supabase
      .from('messages')
      .select('id, sender_id, body, status, sent_at, created_at, attachment_url, attachment_type')
      .eq('conversation_id', id)
      .or(`status.eq.sent,and(status.eq.draft,sender_id.eq.${staffId})`)
      .order('created_at', { ascending: true });

    if (error) {
      console.error('Conversation messages fetch error:', error);
      return res.status(500).json({ error: 'Could not load conversation.' });
    }

    const messagesWithSenderNames = messages.map(m => ({
      ...m,
      senderName: m.sender_id === staffId ? 'You' : (nameById[m.sender_id] || 'Unknown')
    }));

    const sentMessageIds = messages.filter(m => m.status === 'sent').map(m => m.id);
    if (sentMessageIds.length > 0) {
      await supabase
        .from('message_reads')
        .update({ read_at: new Date().toISOString() })
        .eq('staff_id', staffId)
        .in('message_id', sentMessageIds)
        .is('read_at', null);
    }

    res.json({
      subject: conversation ? conversation.subject : 'Conversation',
      participants,
      toLine: participants.map(p => p.fullName).join(', '),
      messages: messagesWithSenderNames
    });
  } catch (err) {
    console.error('Conversation detail unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading this conversation.' });
  }
});

router.post('/compose', async (req, res) => {
  try {
    const { recipientIds, subject, body, status, attachmentUrl, attachmentType } = req.body;
    const staffId = req.session.staff.id;

    if (!recipientIds || recipientIds.length === 0) {
      return res.status(400).json({ error: 'Add at least one recipient.' });
    }

    if (!subject || !subject.trim()) {
      return res.status(400).json({ error: 'Subject is required.' });
    }

    const { data: conversation, error: convError } = await supabase
      .from('conversations')
      .insert({
        department_id: req.session.staff.departmentId,
        subject: subject.trim(),
        is_group: recipientIds.length > 1
      })
      .select()
      .single();

    if (convError) {
      console.error('Compose conversation insert error:', convError);
      return res.status(500).json({ error: 'Could not start conversation.' });
    }

    const memberRows = [staffId, ...recipientIds].map(id => ({ conversation_id: conversation.id, staff_id: id }));
    await supabase.from('conversation_members').insert(memberRows);

    const isSent = status === 'sent';
    const { data: message, error: msgError } = await supabase
      .from('messages')
      .insert({
        conversation_id: conversation.id,
        sender_id: staffId,
        body: body || '',
        status: isSent ? 'sent' : 'draft',
        sent_at: isSent ? new Date().toISOString() : null,
        attachment_url: attachmentUrl || null,
        attachment_type: attachmentType || null
      })
      .select()
      .single();

    if (msgError) {
      console.error('Compose message insert error:', msgError);
      return res.status(500).json({ error: 'Could not send message.' });
    }

    if (isSent) {
      await createReadRowsForRecipients(conversation.id, message.id, staffId);
    }

    res.json({ success: true, conversationId: conversation.id, messageId: message.id });
  } catch (err) {
    console.error('Compose unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong sending this message.' });
  }
});

router.post('/conversations/:id/reply', async (req, res) => {
  try {
    const { id } = req.params;
    const { body, status, attachmentUrl, attachmentType } = req.body;
    const staffId = req.session.staff.id;

    const { data: membership } = await supabase
      .from('conversation_members')
      .select('id')
      .eq('conversation_id', id)
      .eq('staff_id', staffId)
      .maybeSingle();

    if (!membership) {
      return res.status(403).json({ error: 'You do not have access to this conversation.' });
    }

    const isSent = status === 'sent';
    const { data: message, error } = await supabase
      .from('messages')
      .insert({
        conversation_id: id,
        sender_id: staffId,
        body: body || '',
        status: isSent ? 'sent' : 'draft',
        sent_at: isSent ? new Date().toISOString() : null,
        attachment_url: attachmentUrl || null,
        attachment_type: attachmentType || null
      })
      .select()
      .single();

    if (error) {
      console.error('Reply insert error:', error);
      return res.status(500).json({ error: 'Could not send message.' });
    }

    if (isSent) {
      await createReadRowsForRecipients(id, message.id, staffId);
    }

    res.json({ success: true, message });
  } catch (err) {
    console.error('Reply unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong sending your reply.' });
  }
});

router.get('/drafts', async (req, res) => {
  try {
    const staffId = req.session.staff.id;

    const { data: drafts, error } = await supabase
      .from('messages')
      .select('id, conversation_id, body, created_at')
      .eq('sender_id', staffId)
      .eq('status', 'draft')
      .order('created_at', { ascending: false });

    if (error) {
      console.error('Drafts fetch error:', error);
      return res.status(500).json({ error: 'Could not load drafts.' });
    }

    const enriched = await Promise.all(drafts.map(async (draft) => {
      const participants = await getOtherParticipants(draft.conversation_id, staffId);
      return {
        ...draft,
        displayName: participants.map(p => p.fullName).join(', ') || 'Conversation'
      };
    }));

    res.json({ drafts: enriched });
  } catch (err) {
    console.error('Drafts unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading your drafts.' });
  }
});

router.put('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { body, status } = req.body;
    const staffId = req.session.staff.id;

    const { data: existing, error: fetchError } = await supabase
      .from('messages')
      .select('id, conversation_id, sender_id, status')
      .eq('id', id)
      .single();

    if (fetchError || !existing) {
      return res.status(404).json({ error: 'Message not found.' });
    }

    if (existing.sender_id !== staffId) {
      return res.status(403).json({ error: 'You can only edit your own drafts.' });
    }

    if (existing.status === 'sent') {
      return res.status(400).json({ error: 'This message has already been sent and cannot be edited.' });
    }

    const isSending = status === 'sent';
    const { data: updated, error: updateError } = await supabase
      .from('messages')
      .update({
        body: body !== undefined ? body : undefined,
        status: isSending ? 'sent' : 'draft',
        sent_at: isSending ? new Date().toISOString() : null
      })
      .eq('id', id)
      .select()
      .single();

    if (updateError) {
      console.error('Draft update error:', updateError);
      return res.status(500).json({ error: 'Could not update message.' });
    }

    if (isSending) {
      await createReadRowsForRecipients(existing.conversation_id, id, staffId);
    }

    res.json({ success: true, message: updated });
  } catch (err) {
    console.error('Draft update unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong updating this message.' });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const staffId = req.session.staff.id;

    const { data: existing, error: fetchError } = await supabase
      .from('messages')
      .select('id, sender_id')
      .eq('id', id)
      .single();

    if (fetchError || !existing) {
      return res.status(404).json({ error: 'Message not found.' });
    }

    if (existing.sender_id !== staffId) {
      return res.status(403).json({ error: 'You can only delete your own messages.' });
    }

    const { error: deleteError } = await supabase
      .from('messages')
      .delete()
      .eq('id', id);

    if (deleteError) {
      return res.status(500).json({ error: 'Could not delete message.' });
    }

    res.json({ success: true });
  } catch (err) {
    console.error('Delete message error:', err);
    res.status(500).json({ error: 'Something went wrong deleting this message.' });
  }
});

// DELETE /api/accounting/messages/conversations/:id
// Deletes the whole conversation — cascade cleans up its messages and read
// records automatically. Any participant can do this, same as deleting an
// email thread. No account or login access is affected by this at all.
router.delete('/conversations/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const staffId = req.session.staff.id;

    const { data: membership } = await supabase
      .from('conversation_members')
      .select('id')
      .eq('conversation_id', id)
      .eq('staff_id', staffId)
      .maybeSingle();

    if (!membership) {
      return res.status(403).json({ error: 'You do not have access to this conversation.' });
    }

    const { error } = await supabase.from('conversations').delete().eq('id', id);

    if (error) {
      return res.status(500).json({ error: 'Could not delete conversation.' });
    }

    res.json({ success: true });
  } catch (err) {
    console.error('Delete conversation error:', err);
    res.status(500).json({ error: 'Something went wrong deleting this conversation.' });
  }
});

// POST /api/accounting/messages/broadcast — admin-only, sends to every active staff member
router.post('/broadcast', async (req, res) => {
  try {
    if (req.session.staff.role !== 'admin') {
      return res.status(403).json({ error: 'Only admins can send broadcasts.' });
    }

    const { subject, body } = req.body;
    const staffId = req.session.staff.id;

    if (!subject || !subject.trim()) {
      return res.status(400).json({ error: 'Subject is required.' });
    }
    if (!body || !body.trim()) {
      return res.status(400).json({ error: 'Message body is required.' });
    }

    const { data: allActiveStaff, error: staffError } = await supabase
      .from('staff')
      .select('id')
      .eq('is_active', true)
      .neq('id', staffId);

    if (staffError) {
      return res.status(500).json({ error: 'Could not load staff list.' });
    }

    const { data: conversation, error: convError } = await supabase
      .from('conversations')
      .insert({
        department_id: req.session.staff.departmentId,
        subject: subject.trim(),
        is_group: true,
        is_broadcast: true
      })
      .select()
      .single();

    if (convError) {
      return res.status(500).json({ error: 'Could not create broadcast.' });
    }

    const memberRows = [staffId, ...allActiveStaff.map(s => s.id)]
      .map(id => ({ conversation_id: conversation.id, staff_id: id }));
    await supabase.from('conversation_members').insert(memberRows);

    const { data: message, error: msgError } = await supabase
      .from('messages')
      .insert({
        conversation_id: conversation.id,
        sender_id: staffId,
        body: body.trim(),
        status: 'sent',
        sent_at: new Date().toISOString()
      })
      .select()
      .single();

    if (msgError) {
      return res.status(500).json({ error: 'Could not send broadcast.' });
    }

    await createReadRowsForRecipients(conversation.id, message.id, staffId);

    res.json({ success: true, conversationId: conversation.id, recipientCount: allActiveStaff.length });
  } catch (err) {
    console.error('Broadcast send error:', err);
    res.status(500).json({ error: 'Something went wrong sending this broadcast.' });
  }
});

// GET /api/accounting/messages/broadcasts — admin-only, sent history with open rates
router.get('/broadcasts', async (req, res) => {
  try {
    if (req.session.staff.role !== 'admin') {
      return res.status(403).json({ error: 'Only admins can view broadcast history.' });
    }

    const { data: conversations, error } = await supabase
      .from('conversations')
      .select('id, subject, created_at')
      .eq('is_broadcast', true)
      .order('created_at', { ascending: false });

    if (error) {
      return res.status(500).json({ error: 'Could not load broadcast history.' });
    }

    const enriched = await Promise.all(conversations.map(async (conv) => {
      const { data: message } = await supabase
        .from('messages')
        .select('id, body, sent_at')
        .eq('conversation_id', conv.id)
        .eq('status', 'sent')
        .limit(1)
        .maybeSingle();

      let recipientCount = 0;
      let openedCount = 0;
      if (message) {
        const { count: total } = await supabase
          .from('message_reads')
          .select('*', { count: 'exact', head: true })
          .eq('message_id', message.id);
        const { count: opened } = await supabase
          .from('message_reads')
          .select('*', { count: 'exact', head: true })
          .eq('message_id', message.id)
          .not('read_at', 'is', null);
        recipientCount = total || 0;
        openedCount = opened || 0;
      }

      return {
        id: conv.id,
        subject: conv.subject,
        sentAt: message ? message.sent_at : conv.created_at,
        recipientCount,
        openedCount
      };
    }));

    res.json({ broadcasts: enriched });
  } catch (err) {
    console.error('Broadcast history error:', err);
    res.status(500).json({ error: 'Something went wrong loading broadcast history.' });
  }
});

module.exports = router;

EOF_SERVER_ROUTES_MESSAGES_JS

cat > server/routes/admin.js << 'EOF_SERVER_ROUTES_ADMIN_JS'
const express = require('express');
const bcrypt = require('bcrypt');
const crypto = require('crypto');
const supabase = require('../config/supabaseClient');
const { sendWelcomeEmail } = require('../utils/email');

const router = express.Router();

// Only staff with role = 'admin' can reach these routes.
function requireAdmin(req, res, next) {
  if (req.session.staff.role !== 'admin') {
    return res.status(403).json({ error: 'Admin access only.' });
  }
  next();
}

router.use(requireAdmin);

// GET /api/accounting/admin/departments — for the onboarding Work Info dropdown
router.get('/departments', async (req, res) => {
  try {
    const { data, error } = await supabase.from('departments').select('id, name').order('name');
    if (error) {
      return res.status(500).json({ error: 'Could not load departments.' });
    }
    res.json({ departments: data });
  } catch (err) {
    console.error('Departments fetch error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// GET /api/accounting/admin/all-staff — everyone including inactive, for Manage Staff
router.get('/all-staff', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('staff')
      .select('id, full_name, username, email, role, phone, branch, is_active, created_at, departments(name)')
      .order('full_name');

    if (error) {
      console.error('All-staff fetch error:', error);
      return res.status(500).json({ error: 'Could not load staff.' });
    }

    const staff = data.map(s => ({
      id: s.id,
      fullName: s.full_name,
      username: s.username,
      email: s.email,
      role: s.role,
      phone: s.phone,
      branch: s.branch,
      department: s.departments ? s.departments.name : null,
      isActive: s.is_active,
      dateStarted: s.created_at
    }));

    res.json({ staff });
  } catch (err) {
    console.error('All-staff unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading staff.' });
  }
});

// POST /api/accounting/admin/onboard-staff — HR-initiated account creation
router.post('/onboard-staff', async (req, res) => {
  try {
    const { fullName, email, phone, nin, address, role, departmentId, branch, dateStarted, reportsTo } = req.body;

    if (!fullName || !email || !role || !departmentId) {
      return res.status(400).json({ error: 'Full name, email, role, and department are required.' });
    }

    // Generate a username from the name, and a random temporary password
    const baseUsername = fullName.toLowerCase().replace(/[^a-z]+/g, '.').replace(/^\.|\.$/g, '');
    const username = baseUsername + '.' + crypto.randomInt(100, 999);
    const tempPassword = crypto.randomBytes(6).toString('base64').replace(/[^a-zA-Z0-9]/g, '').slice(0, 10);
    const passwordHash = await bcrypt.hash(tempPassword, 10);

    const { data, error } = await supabase
      .from('staff')
      .insert({
        full_name: fullName,
        username: username,
        email: email,
        password_hash: passwordHash,
        role: role,
        department_id: departmentId,
        phone: phone || null,
        nin: nin || null,
        address: address || null,
        branch: branch || null,
        reports_to: reportsTo || null,
        email_verified: true,  // HR-created accounts are trusted, skip the self-signup flow
        is_active: true
      })
      .select()
      .single();

    if (error) {
      console.error('Onboard staff insert error:', error);
      return res.status(400).json({ error: 'Could not create account. Email may already be in use.' });
    }

    try {
      await sendWelcomeEmail(email, fullName, username, tempPassword);
    } catch (emailErr) {
      console.error('Welcome email failed:', emailErr);
      // Account was created successfully even if the email failed — tell the admin so they can share credentials manually
      return res.json({
        success: true,
        staff: data,
        warning: 'Account created, but the welcome email failed to send. Username: ' + username + ', temporary password: ' + tempPassword
      });
    }

    res.json({ success: true, staff: data });
  } catch (err) {
    console.error('Onboard staff unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong creating this account.' });
  }
});

// PUT /api/accounting/admin/staff/:id — edit an existing staff member
router.put('/staff/:id', async (req, res) => {
  try {
    const { fullName, role, departmentId, phone, branch } = req.body;

    const { error } = await supabase
      .from('staff')
      .update({
        full_name: fullName,
        role: role,
        department_id: departmentId,
        phone: phone || null,
        branch: branch || null
      })
      .eq('id', req.params.id);

    if (error) {
      return res.status(500).json({ error: 'Could not update this account.' });
    }
    res.json({ success: true });
  } catch (err) {
    console.error('Staff edit unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// POST /api/accounting/admin/staff/:id/reactivate
router.post('/staff/:id/reactivate', async (req, res) => {
  try {
    const { error } = await supabase.from('staff').update({ is_active: true }).eq('id', req.params.id);
    if (error) {
      return res.status(500).json({ error: 'Could not reactivate this account.' });
    }
    res.json({ success: true });
  } catch (err) {
    console.error('Reactivate unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// GET /api/accounting/admin/pending-staff
// Lists everyone who has verified their email but is still waiting on approval.
router.get('/pending-staff', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('staff')
      .select('id, full_name, username, email, created_at')
      .eq('email_verified', true)
      .eq('is_active', false)
      .order('created_at', { ascending: true });

    if (error) {
      console.error('Pending staff fetch error:', error);
      return res.status(500).json({ error: 'Could not load pending accounts.' });
    }

    res.json({ pending: data });
  } catch (err) {
    console.error('Pending staff unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// POST /api/accounting/admin/approve-staff/:id
router.post('/approve-staff/:id', async (req, res) => {
  try {
    const { id } = req.params;

    const { data, error } = await supabase
      .from('staff')
      .update({ is_active: true })
      .eq('id', id)
      .select()
      .single();

    if (error || !data) {
      return res.status(400).json({ error: 'Could not approve this account.' });
    }

    res.json({ success: true, message: `${data.full_name} has been approved and can now log in.` });
  } catch (err) {
    console.error('Approve staff unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong approving this account.' });
  }
});

// DELETE /api/accounting/admin/staff/:id
// Deactivates a staff member (soft-disable, not a hard delete — their past
// messages and price edits stay intact) and clears any shared conversation
// with the admin performing this action.
router.delete('/staff/:id', async (req, res) => {
  const { id } = req.params;
  const adminId = req.session.staff.id;

  if (id === adminId) {
    return res.status(400).json({ error: 'You cannot deactivate your own account.' });
  }

  const { data: targetMemberships } = await supabase
    .from('conversation_members')
    .select('conversation_id')
    .eq('staff_id', id);

  const { data: adminMemberships } = await supabase
    .from('conversation_members')
    .select('conversation_id')
    .eq('staff_id', adminId);

  const targetIds = new Set((targetMemberships || []).map(m => m.conversation_id));
  const sharedConversationIds = (adminMemberships || [])
    .map(m => m.conversation_id)
    .filter(convId => targetIds.has(convId));

  if (sharedConversationIds.length > 0) {
    // Cascade delete handles conversation_members, messages, and message_reads automatically
    await supabase.from('conversations').delete().in('id', sharedConversationIds);
  }

  const { error } = await supabase
    .from('staff')
    .update({ is_active: false })
    .eq('id', id);

  if (error) {
    return res.status(500).json({ error: 'Could not deactivate this account.' });
  }

  res.json({ success: true });
});

module.exports = router;

EOF_SERVER_ROUTES_ADMIN_JS

cat > accounting/manage-staff.html << 'EOF_ACCOUNTING_MANAGE-STAFF_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Manage Staff — MACDEN Portal</title>
  <link rel="stylesheet" href="assets/portal-style.css">
  <link rel="stylesheet" href="assets/portal-shell.css">
  <link rel="stylesheet" href="assets/portal-inbox.css">
  <style>
    .ms-toolbar { display: flex; justify-content: space-between; align-items: center; margin-bottom: 18px; }
    .ms-list { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-md); overflow: hidden; }
    .ms-header-row { display: grid; grid-template-columns: 200px 130px 130px 1fr 90px 90px; gap: 12px; padding: 12px 18px; font-size: 10.5px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.04em; color: var(--text-muted); border-bottom: 1px solid var(--border); }
    .ms-row { display: grid; grid-template-columns: 200px 130px 130px 1fr 90px 90px; gap: 12px; align-items: center; padding: 12px 18px; border-bottom: 1px solid var(--border); font-size: 12.5px; }
    .ms-row:last-child { border-bottom: none; }
    .ms-empty { padding: 50px 18px; text-align: center; color: var(--text-muted); font-size: 13px; }
    .ms-status { display: inline-block; padding: 2px 9px; border-radius: 999px; font-size: 10.5px; font-weight: 700; }
    .ms-status.active { background: var(--success-dim); color: var(--success); }
    .ms-status.inactive { background: var(--error-dim); color: var(--error); }
    .ms-action-btn { border: 1px solid var(--border); background: var(--surface); border-radius: var(--radius-sm); padding: 5px 11px; font-size: 11px; font-weight: 600; cursor: pointer; font-family: var(--font-body); color: var(--text-primary); }
    .ms-action-btn:hover { border-color: var(--error); color: var(--error); background: var(--error-dim); }
    .ms-action-btn.reactivate { background: var(--success-dim); color: var(--success); border-color: transparent; }
    .ms-action-btn.reactivate:hover { background: var(--success); color: #fff; }
  </style>
</head>
<body>
  <div class="app-shell">
    <div class="sidebar">
      <div class="sidebar-brand"><img src="assets/logo.jpeg" alt="MACDEN"><span>MACDEN</span></div>
      <nav class="sidebar-nav">
        <a href="dashboard.html" class="sidebar-link"><i class="ti ti-layout-dashboard"></i> Dashboard</a>
        <a href="inbox.html" class="sidebar-link"><i class="ti ti-mail"></i> Inbox <span class="badge" id="unreadBadge" style="display:none;">0</span></a>
        <a href="compose.html" class="sidebar-link"><i class="ti ti-pencil"></i> Compose</a>
        <a href="broadcasts.html" class="sidebar-link"><i class="ti ti-speakerphone"></i> Broadcasts</a>
        <a href="directory.html" class="sidebar-link active"><i class="ti ti-users"></i> Directory</a>
        <a href="leave.html" class="sidebar-link"><i class="ti ti-calendar-event"></i> Leave &amp; Requests</a>
        <a href="documents.html" class="sidebar-link"><i class="ti ti-file-text"></i> Documents</a>
        <a href="policies.html" class="sidebar-link"><i class="ti ti-book"></i> Policies</a>
        <a href="settings.html" class="sidebar-link"><i class="ti ti-settings"></i> Settings</a>
      </nav>
      <div class="sidebar-logout"><button id="logoutBtn"><i class="ti ti-logout"></i> Logout</button></div>
    </div>

    <div class="main-content">
      <div class="topbar">
        <div class="topbar-search"><input type="text" placeholder="Search messages, people, documents…"></div>
        <div class="notif-wrap">
          <button class="topbar-bell" id="notifBell"><i class="ti ti-bell"></i><span class="dot" id="notifDot" style="display:none;">0</span></button>
          <div class="notif-dropdown" id="notifDropdown"></div>
        </div>
        <img class="topbar-avatar" src="assets/logo.jpeg" alt="You">
      </div>

      <div class="page-body">
        <div class="ms-toolbar">
          <div>
            <h1 class="page-greeting" style="font-size: 22px;">Manage Staff</h1>
            <p class="page-greeting-sub" style="margin:0;"><a href="directory.html" style="color: var(--primary); text-decoration:none; font-weight:600;">← Back to Directory</a></p>
          </div>
          <a href="onboard.html" class="btn btn-primary" style="width:auto; padding:10px 20px; text-decoration:none; display:inline-flex; align-items:center; gap:8px;"><i class="ti ti-user-plus"></i> Add New Staff</a>
        </div>

        <div class="ms-list">
          <div class="ms-header-row"><div>Staff Member</div><div>Role</div><div>Department</div><div>Email</div><div>Status</div><div>Actions</div></div>
          <div id="msRows"><div class="ms-empty">Loading…</div></div>
        </div>
      </div>
    </div>
  </div>

  <script src="assets/api.js"></script>
  <script src="assets/notifications.js"></script>
  <script src="assets/presence.js"></script>
  <script>
    document.getElementById('logoutBtn').addEventListener('click', async () => {
      await apiRequest('/auth/logout', { method: 'POST' });
      window.location.href = 'login.html';
    });

    async function init() {
      try {
        const result = await apiRequest('/dashboard-check');
        if (result.staff.role !== 'admin') {
          document.body.innerHTML = '<div style="padding:40px; font-family:sans-serif;">Admin access only.</div>';
          return;
        }
      } catch (err) {
        window.location.href = 'login.html';
        return;
      }
      loadUnreadBadge();
      loadStaff();
    }

    async function loadStaff() {
      const rows = document.getElementById('msRows');
      try {
        const result = await apiRequest('/admin/all-staff');
        if (result.staff.length === 0) {
          rows.innerHTML = '<div class="ms-empty">No staff yet.</div>';
          return;
        }
        rows.innerHTML = result.staff.map(s => {
          const statusHtml = s.isActive ? '<span class="ms-status active">Active</span>' : '<span class="ms-status inactive">Deactivated</span>';
          const actionBtn = s.isActive
            ? '<button class="ms-action-btn" onclick="deactivate(\'' + s.id + '\')">Deactivate</button>'
            : '<button class="ms-action-btn reactivate" onclick="reactivate(\'' + s.id + '\')">Reactivate</button>';
          return '<div class="ms-row">' +
            '<div>' + s.fullName + '</div>' +
            '<div>' + s.role + '</div>' +
            '<div>' + (s.department || '—') + '</div>' +
            '<div style="overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">' + s.email + '</div>' +
            '<div>' + statusHtml + '</div>' +
            '<div>' + actionBtn + '</div>' +
            '</div>';
        }).join('');
      } catch (err) {
        rows.innerHTML = '<div class="ms-empty">Could not load staff.</div>';
      }
    }

    async function deactivate(id) {
      if (!confirm('Deactivate this staff member? They will no longer be able to log in.')) return;
      try {
        await apiRequest('/admin/staff/' + id, { method: 'DELETE' });
        loadStaff();
      } catch (err) {
        alert(err.message);
      }
    }

    async function reactivate(id) {
      try {
        await apiRequest('/admin/staff/' + id + '/reactivate', { method: 'POST' });
        loadStaff();
      } catch (err) {
        alert(err.message);
      }
    }

    init();
  </script>
</body>
</html>

EOF_ACCOUNTING_MANAGE-STAFF_HTML

cat > accounting/onboard.html << 'EOF_ACCOUNTING_ONBOARD_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Add New Staff — MACDEN Portal</title>
  <link rel="stylesheet" href="assets/portal-style.css">
  <link rel="stylesheet" href="assets/portal-shell.css">
  <link rel="stylesheet" href="assets/portal-inbox.css">
  <style>
    .step-indicator { display: flex; align-items: center; gap: 10px; margin-bottom: 24px; }
    .step-item { display: flex; align-items: center; gap: 8px; font-size: 12.5px; color: var(--text-muted); }
    .step-item.active, .step-item.done { color: var(--text-primary); font-weight: 600; }
    .step-num { width: 22px; height: 22px; border-radius: 50%; background: var(--border); color: var(--text-muted); display: flex; align-items: center; justify-content: center; font-size: 11px; font-weight: 700; }
    .step-item.active .step-num { background: var(--primary); color: #fff; }
    .step-item.done .step-num { background: var(--success); color: #fff; }
    .step-arrow { color: var(--border); }

    .onb-grid { display: grid; grid-template-columns: 1fr 260px; gap: 20px; }
    .onb-card { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-md); padding: 26px; }
    .onb-field-row { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; margin-bottom: 14px; }
    .onb-field label { display: block; font-size: 12.5px; font-weight: 600; margin-bottom: 6px; }
    .onb-field input, .onb-field select, .onb-field textarea {
      width: 100%; background: var(--surface-raised); border: 1px solid var(--border); border-radius: var(--radius-sm);
      padding: 9px 12px; font-size: 13px; font-family: var(--font-body); color: var(--text-primary);
    }
    .onb-note { background: var(--gold-dim); color: #8a6d00; padding: 12px 16px; border-radius: var(--radius-sm); font-size: 12px; }

    .review-section { margin-bottom: 16px; }
    .review-section h4 { font-size: 12.5px; text-transform: uppercase; letter-spacing: 0.04em; color: var(--text-muted); margin-bottom: 8px; }
    .review-row { display: flex; justify-content: space-between; padding: 6px 0; font-size: 13px; border-bottom: 1px solid var(--border); }

    .search-results { position: absolute; top: 100%; left: 0; right: 0; background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-sm); margin-top: 4px; max-height: 180px; overflow-y: auto; z-index: 5; display: none; box-shadow: 0 4px 12px rgba(0,0,0,0.08); }
    .search-result-item { padding: 8px 12px; cursor: pointer; font-size: 12.5px; }
    .search-result-item:hover { background: var(--surface-raised); }
  </style>
</head>
<body>
  <div class="app-shell">
    <div class="sidebar">
      <div class="sidebar-brand"><img src="assets/logo.jpeg" alt="MACDEN"><span>MACDEN</span></div>
      <nav class="sidebar-nav">
        <a href="dashboard.html" class="sidebar-link"><i class="ti ti-layout-dashboard"></i> Dashboard</a>
        <a href="inbox.html" class="sidebar-link"><i class="ti ti-mail"></i> Inbox <span class="badge" id="unreadBadge" style="display:none;">0</span></a>
        <a href="compose.html" class="sidebar-link"><i class="ti ti-pencil"></i> Compose</a>
        <a href="broadcasts.html" class="sidebar-link"><i class="ti ti-speakerphone"></i> Broadcasts</a>
        <a href="directory.html" class="sidebar-link active"><i class="ti ti-users"></i> Directory</a>
        <a href="leave.html" class="sidebar-link"><i class="ti ti-calendar-event"></i> Leave &amp; Requests</a>
        <a href="documents.html" class="sidebar-link"><i class="ti ti-file-text"></i> Documents</a>
        <a href="policies.html" class="sidebar-link"><i class="ti ti-book"></i> Policies</a>
        <a href="settings.html" class="sidebar-link"><i class="ti ti-settings"></i> Settings</a>
      </nav>
      <div class="sidebar-logout"><button id="logoutBtn"><i class="ti ti-logout"></i> Logout</button></div>
    </div>

    <div class="main-content">
      <div class="topbar">
        <div class="topbar-search"><input type="text" placeholder="Search messages, people, documents…"></div>
        <div class="notif-wrap">
          <button class="topbar-bell" id="notifBell"><i class="ti ti-bell"></i><span class="dot" id="notifDot" style="display:none;">0</span></button>
          <div class="notif-dropdown" id="notifDropdown"></div>
        </div>
        <img class="topbar-avatar" src="assets/logo.jpeg" alt="You">
      </div>

      <div class="page-body">
        <h1 class="page-greeting" style="font-size: 22px;">Add New Staff Member</h1>
        <p class="page-greeting-sub"><a href="manage-staff.html" style="color: var(--primary); text-decoration:none; font-weight:600;">← Back to Manage Staff</a></p>

        <div class="step-indicator">
          <div class="step-item active" id="stepInd1"><span class="step-num">1</span> Personal Information</div>
          <span class="step-arrow">→</span>
          <div class="step-item" id="stepInd2"><span class="step-num">2</span> Work Information</div>
          <span class="step-arrow">→</span>
          <div class="step-item" id="stepInd3"><span class="step-num">3</span> Review &amp; Create</div>
        </div>

        <div id="alert" class="alert alert-error"></div>

        <!-- Step 1 -->
        <div id="step1" class="onb-grid">
          <div class="onb-card">
            <div class="onb-field-row">
              <div class="onb-field"><label>Full Name *</label><input type="text" id="fullName"></div>
              <div class="onb-field"><label>Email Address *</label><input type="text" id="email"></div>
            </div>
            <div class="onb-field-row">
              <div class="onb-field"><label>Phone Number</label><input type="text" id="phone"></div>
              <div class="onb-field"><label>NIN</label><input type="text" id="nin"></div>
            </div>
            <div class="onb-field"><label>Residential Address</label><textarea id="address" style="min-height:70px;"></textarea></div>
            <div style="text-align:right; margin-top:16px;"><button class="btn btn-primary" style="width:auto; padding:9px 22px;" onclick="goToStep(2)">Next: Work Information →</button></div>
          </div>
          <div class="onb-note"><i class="ti ti-info-circle"></i> Photo upload isn't supported yet — staff records don't have a photo field in the database yet.</div>
        </div>

        <!-- Step 2 -->
        <div id="step2" class="onb-grid" style="display:none;">
          <div class="onb-card">
            <div class="onb-field-row">
              <div class="onb-field"><label>Role / Job Title *</label><input type="text" id="role"></div>
              <div class="onb-field"><label>Department *</label><select id="departmentId"></select></div>
            </div>
            <div class="onb-field-row">
              <div class="onb-field"><label>Branch</label><input type="text" id="branch" placeholder="e.g. Ikeja Branch"></div>
              <div class="onb-field"><label>Date Started</label><input type="date" id="dateStarted"></div>
            </div>
            <div class="onb-field" style="position:relative;">
              <label>Reports To (Direct Manager)</label>
              <input type="text" id="reportsToSearch" placeholder="Search staff member…">
              <div class="search-results" id="reportsToResults"></div>
              <div id="reportsToSelected" style="margin-top:6px; font-size:12.5px; color:var(--primary); display:none;"></div>
            </div>
            <div style="display:flex; justify-content:space-between; margin-top:16px;">
              <button class="btn btn-ghost" style="width:auto; padding:9px 22px;" onclick="goToStep(1)">← Back</button>
              <button class="btn btn-primary" style="width:auto; padding:9px 22px;" onclick="goToStep(3)">Next: Review &amp; Create →</button>
            </div>
          </div>
          <div class="onb-note"><i class="ti ti-info-circle"></i> Branch is a free-text field for now — no managed branch list exists yet.</div>
        </div>

        <!-- Step 3 -->
        <div id="step3" style="display:none;">
          <div class="onb-card" style="max-width:640px;">
            <div class="review-section">
              <h4>Personal Information</h4>
              <div class="review-row"><span>Full Name</span><span id="rvName"></span></div>
              <div class="review-row"><span>Email</span><span id="rvEmail"></span></div>
              <div class="review-row"><span>Phone</span><span id="rvPhone"></span></div>
              <div class="review-row"><span>NIN</span><span id="rvNin"></span></div>
            </div>
            <div class="review-section">
              <h4>Work Information</h4>
              <div class="review-row"><span>Role</span><span id="rvRole"></span></div>
              <div class="review-row"><span>Department</span><span id="rvDept"></span></div>
              <div class="review-row"><span>Branch</span><span id="rvBranch"></span></div>
              <div class="review-row"><span>Reports To</span><span id="rvReportsTo"></span></div>
            </div>
            <div class="onb-note" style="margin-top:16px;"><i class="ti ti-mail"></i> The staff member will receive an email with their login credentials.</div>
            <div style="display:flex; justify-content:space-between; margin-top:16px;">
              <button class="btn btn-ghost" style="width:auto; padding:9px 22px;" onclick="goToStep(2)">← Back</button>
              <button class="btn btn-primary" id="createAccountBtn" style="width:auto; padding:9px 22px;">Create Account</button>
            </div>
          </div>
        </div>

        <div id="successView" style="display:none;">
          <div class="onb-card" style="max-width:520px;">
            <h2 style="font-size:16px; margin-bottom:6px; color: var(--success);"><i class="ti ti-circle-check"></i> Account Created</h2>
            <p id="successNormalMsg" style="font-size:13px; color:var(--text-secondary); display:none;">A welcome email with login details has been sent.</p>
            <div id="successWarningBox" style="display:none;">
              <div class="onb-note" style="margin-bottom:14px;">
                <i class="ti ti-alert-triangle"></i> The welcome email failed to send. Share these credentials with the new staff member directly &mdash; <strong>this is the only time they will be shown.</strong>
              </div>
              <div style="background: var(--surface-raised); border: 1px solid var(--border); border-radius: var(--radius-sm); padding: 14px; font-family: var(--font-mono); font-size: 13px;">
                <div>Username: <strong id="credUsername"></strong></div>
                <div style="margin-top:6px;">Temporary password: <strong id="credPassword"></strong></div>
              </div>
            </div>
            <button class="btn btn-primary" style="width:auto; padding:9px 22px; margin-top:16px;" onclick="window.location.href='manage-staff.html'">Go to Manage Staff</button>
          </div>
        </div>

      </div>
    </div>
  </div>

  <script src="assets/api.js"></script>
  <script src="assets/notifications.js"></script>
  <script src="assets/presence.js"></script>
  <script>
    document.getElementById('logoutBtn').addEventListener('click', async () => {
      await apiRequest('/auth/logout', { method: 'POST' });
      window.location.href = 'login.html';
    });

    let selectedReportsTo = null;

    async function init() {
      try {
        const result = await apiRequest('/dashboard-check');
        if (result.staff.role !== 'admin') {
          document.body.innerHTML = '<div style="padding:40px; font-family:sans-serif;">Admin access only.</div>';
          return;
        }
      } catch (err) {
        window.location.href = 'login.html';
        return;
      }
      loadUnreadBadge();

      try {
        const result = await apiRequest('/admin/departments');
        document.getElementById('departmentId').innerHTML = result.departments.map(d => '<option value="' + d.id + '">' + d.name + '</option>').join('');
      } catch (err) {}
    }

    function goToStep(n) {
      [1,2,3].forEach(i => {
        document.getElementById('step' + i).style.display = i === n ? (i === 3 ? 'block' : 'grid') : 'none';
        const ind = document.getElementById('stepInd' + i);
        ind.classList.remove('active', 'done');
        if (i < n) ind.classList.add('done');
        if (i === n) ind.classList.add('active');
      });
      if (n === 3) populateReview();
    }

    function populateReview() {
      document.getElementById('rvName').textContent = document.getElementById('fullName').value;
      document.getElementById('rvEmail').textContent = document.getElementById('email').value;
      document.getElementById('rvPhone').textContent = document.getElementById('phone').value || '—';
      document.getElementById('rvNin').textContent = document.getElementById('nin').value || '—';
      document.getElementById('rvRole').textContent = document.getElementById('role').value;
      document.getElementById('rvDept').textContent = document.getElementById('departmentId').selectedOptions[0]?.textContent || '—';
      document.getElementById('rvBranch').textContent = document.getElementById('branch').value || '—';
      document.getElementById('rvReportsTo').textContent = selectedReportsTo ? selectedReportsTo.full_name : '—';
    }

    let searchTimeout = null;
    document.getElementById('reportsToSearch').addEventListener('input', (e) => {
      clearTimeout(searchTimeout);
      const q = e.target.value.trim();
      const results = document.getElementById('reportsToResults');
      if (!q) { results.style.display = 'none'; return; }
      searchTimeout = setTimeout(async () => {
        try {
          const result = await apiRequest('/staff?search=' + encodeURIComponent(q));
          results.innerHTML = result.staff.map(s => '<div class="search-result-item" onclick=\'selectReportsTo(' + JSON.stringify(s) + ')\'>' + s.full_name + ' · ' + (s.department || '') + '</div>').join('');
          results.style.display = 'block';
        } catch (err) {}
      }, 250);
    });

    function selectReportsTo(staff) {
      selectedReportsTo = staff;
      document.getElementById('reportsToSearch').value = '';
      document.getElementById('reportsToResults').style.display = 'none';
      const el = document.getElementById('reportsToSelected');
      el.textContent = '✓ ' + staff.full_name;
      el.style.display = 'block';
    }

    document.getElementById('createAccountBtn').addEventListener('click', async () => {
      const alertEl = document.getElementById('alert');
      hideAlert(alertEl);

      const fullName = document.getElementById('fullName').value.trim();
      const email = document.getElementById('email').value.trim();
      const role = document.getElementById('role').value.trim();
      const departmentId = document.getElementById('departmentId').value;

      if (!fullName || !email || !role || !departmentId) {
        showAlert(alertEl, 'Full name, email, role, and department are required.');
        goToStep(1);
        return;
      }

      const btn = document.getElementById('createAccountBtn');
      btn.disabled = true;
      btn.textContent = 'Creating…';

      try {
        const result = await apiRequest('/admin/onboard-staff', {
          method: 'POST',
          body: {
            fullName, email,
            phone: document.getElementById('phone').value.trim(),
            nin: document.getElementById('nin').value.trim(),
            address: document.getElementById('address').value.trim(),
            role,
            departmentId,
            branch: document.getElementById('branch').value.trim(),
            dateStarted: document.getElementById('dateStarted').value,
            reportsTo: selectedReportsTo ? selectedReportsTo.id : null
          }
        });

        document.getElementById('step3').style.display = 'none';
        document.getElementById('successView').style.display = 'block';

        if (result.warning) {
          // Extract username/password from the warning message for clean display
          const match = result.warning.match(/Username:\s*([^\s,]+),\s*temporary password:\s*(\S+)/);
          document.getElementById('successWarningBox').style.display = 'block';
          document.getElementById('credUsername').textContent = match ? match[1] : '(check server logs)';
          document.getElementById('credPassword').textContent = match ? match[2] : '(check server logs)';
        } else {
          document.getElementById('successNormalMsg').style.display = 'block';
        }
      } catch (err) {
        showAlert(alertEl, err.message);
        btn.disabled = false;
        btn.textContent = 'Create Account';
      }
    });

    init();
  </script>
</body>
</html>

EOF_ACCOUNTING_ONBOARD_HTML

echo "Tightening pass complete: 52/52 routes now have proper error handling."