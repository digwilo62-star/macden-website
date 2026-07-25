const crypto = require('crypto');

// Encrypts sensitive fields (NIN, address) at the application level before
// they're stored, using AES-256-GCM. This is on top of Supabase's own
// at-rest encryption -- an extra layer specifically for the most sensitive
// fields, since NIN is Nigeria's national ID equivalent (SSN-level
// sensitivity), flagged as a real concern when these fields were first added.
//
// Requires ENCRYPTION_KEY in .env -- a 32-byte (64 hex character) random key.
// Generate one with: node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"

const ALGORITHM = 'aes-256-gcm';

function getKey() {
  const keyHex = process.env.ENCRYPTION_KEY;
  if (!keyHex || keyHex.length !== 64) {
    throw new Error('ENCRYPTION_KEY must be set in .env as a 64-character hex string.');
  }
  return Buffer.from(keyHex, 'hex');
}

function encrypt(plainText) {
  if (!plainText) return null;
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv(ALGORITHM, getKey(), iv);
  const encrypted = Buffer.concat([cipher.update(plainText, 'utf8'), cipher.final()]);
  const authTag = cipher.getAuthTag();
  // Store iv + authTag + ciphertext together, base64-encoded, so it's one string per DB column
  return Buffer.concat([iv, authTag, encrypted]).toString('base64');
}

function decrypt(encryptedText) {
  if (!encryptedText) return null;
  const data = Buffer.from(encryptedText, 'base64');
  const iv = data.subarray(0, 12);
  const authTag = data.subarray(12, 28);
  const encrypted = data.subarray(28);
  const decipher = crypto.createDecipheriv(ALGORITHM, getKey(), iv);
  decipher.setAuthTag(authTag);
  return Buffer.concat([decipher.update(encrypted), decipher.final()]).toString('utf8');
}

module.exports = { encrypt, decrypt };

