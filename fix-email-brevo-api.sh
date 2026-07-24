#!/usr/bin/env bash
# Switches email sending from SMTP to Brevo's HTTP API. Render's free tier
# blocks all outbound SMTP ports (25, 465, 587) as an anti-spam measure --
# this was the actual cause of the connection timeouts on production. HTTPS
# is never blocked, so this fixes it permanently, on Render and locally.
# Run this from the ROOT of your macden-website repo, in Git Bash.
set -e

mkdir -p server/utils

cat > server/utils/email.js << "EOF_EMAIL_JS"
// Uses Brevo's HTTP API instead of raw SMTP. This is the fix for Render's
// free-tier policy that blocks all outbound SMTP ports (25, 465, 587) to
// prevent spam abuse -- HTTPS (port 443) is never blocked, so the API works
// everywhere: locally and in production, no exceptions needed.

async function sendViaBrevoAPI(toEmail, toName, subject, textContent, htmlContent) {
  const res = await fetch('https://api.brevo.com/v3/smtp/email', {
    method: 'POST',
    headers: {
      'api-key': process.env.BREVO_API_KEY,
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    },
    body: JSON.stringify({
      sender: { name: 'MACDEN Accounting', email: process.env.SMTP_FROM_EMAIL },
      to: [{ email: toEmail, name: toName }],
      subject: subject,
      textContent: textContent,
      htmlContent: htmlContent
    })
  });

  if (!res.ok) {
    const errorBody = await res.text();
    throw new Error('Brevo API error (' + res.status + '): ' + errorBody);
  }
}

async function sendVerificationEmail(toEmail, fullName, code) {
  await sendViaBrevoAPI(
    toEmail,
    fullName,
    'Verify your MACDEN Accounting account',
    `Hi ${fullName},\n\nYour verification code is: ${code}\n\nThis code expires in 15 minutes.\n\nAfter verifying, your account will still need admin approval before you can log in.`,
    `<p>Hi ${fullName},</p>
     <p>Your verification code is:</p>
     <p style="font-size: 24px; font-weight: bold; letter-spacing: 4px;">${code}</p>
     <p>This code expires in 15 minutes.</p>
     <p>After verifying, your account will still need admin approval before you can log in.</p>`
  );
}

async function sendWelcomeEmail(toEmail, fullName, username, tempPassword) {
  await sendViaBrevoAPI(
    toEmail,
    fullName,
    'Welcome to MACDEN — Your account is ready',
    `Hi ${fullName},\n\nHR has created your MACDEN portal account.\n\nUsername: ${username}\nTemporary password: ${tempPassword}\n\nPlease log in and change your password as soon as possible from Settings.`,
    `<p>Hi ${fullName},</p>
     <p>HR has created your MACDEN portal account.</p>
     <p><strong>Username:</strong> ${username}<br>
     <strong>Temporary password:</strong> ${tempPassword}</p>
     <p>Please log in and change your password as soon as possible from Settings.</p>`
  );
}

module.exports = { sendVerificationEmail, sendWelcomeEmail };
EOF_EMAIL_JS

echo "Email switched to Brevo API. You must add BREVO_API_KEY and SMTP_FROM_EMAIL to .env and Render."
