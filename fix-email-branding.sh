#!/usr/bin/env bash
# Fixes 'MACDEN Accounting' branding (sender name AND subject lines --
# it was hardcoded in more than just the sender field) to 'MACDEN
# Portal', and replaces plain unstyled paragraphs with a real designed
# HTML template: branded green header with your logo, organized
# credential display, a real login button, consistent footer. Tested
# with a real captured API payload (not just syntax-checked) --
# confirmed no 'Accounting' text remains anywhere, and all dynamic
# values (code/username/password/link) interpolate correctly.
set -e
cat > server/utils/email.js << 'EOF_EMAIL_JS'
// Uses Brevo's HTTP API instead of raw SMTP. This is the fix for Render's
// free-tier policy that blocks all outbound SMTP ports (25, 465, 587) to
// prevent spam abuse -- HTTPS (port 443) is never blocked, so the API works
// everywhere: locally and in production, no exceptions needed.

// Shared branded wrapper -- every email now shares the same header, colors,
// and footer, matching the portal's own green/gold look instead of plain
// unstyled paragraphs.
function wrapInBrandedTemplate(bodyHtml) {
  return `
  <div style="font-family: -apple-system, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background: #f7f8fa; padding: 32px 16px;">
    <div style="max-width: 480px; margin: 0 auto; background: #ffffff; border-radius: 12px; overflow: hidden; border: 1px solid #e5e7eb;">

      <div style="background: #0d5c2f; padding: 24px 28px; display: flex; align-items: center;">
        <img src="https://macden.com.ng/portal/assets/logo.jpeg" alt="MACDEN" width="32" height="32" style="border-radius: 6px; vertical-align: middle; margin-right: 10px;">
        <span style="color: #ffffff; font-size: 16px; font-weight: 700; vertical-align: middle;">MACDEN Portal</span>
      </div>

      <div style="padding: 28px;">
        ${bodyHtml}
      </div>

      <div style="padding: 16px 28px; background: #f7f8fa; border-top: 1px solid #e5e7eb; text-align: center;">
        <p style="margin: 0; font-size: 11.5px; color: #9ca3af;">This is an automated message from the MACDEN Portal. Please do not reply to this email.</p>
      </div>

    </div>
  </div>`;
}

async function sendViaBrevoAPI(toEmail, toName, subject, textContent, htmlContent) {
  const res = await fetch('https://api.brevo.com/v3/smtp/email', {
    method: 'POST',
    headers: {
      'api-key': process.env.BREVO_API_KEY,
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    },
    body: JSON.stringify({
      sender: { name: 'MACDEN Portal', email: process.env.SMTP_FROM_EMAIL },
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
    'Verify your MACDEN Portal account',
    `Hi ${fullName},\n\nYour verification code is: ${code}\n\nThis code expires in 15 minutes.\n\nAfter verifying, your account will still need admin approval before you can log in.`,
    wrapInBrandedTemplate(`
      <p style="margin: 0 0 16px; font-size: 14px; color: #2b2d31;">Hi ${fullName},</p>
      <p style="margin: 0 0 8px; font-size: 14px; color: #2b2d31;">Your verification code is:</p>
      <div style="background: #f7f8fa; border: 1px solid #e5e7eb; border-radius: 8px; padding: 16px; text-align: center; margin: 12px 0 20px;">
        <span style="font-size: 28px; font-weight: 800; letter-spacing: 6px; color: #0d5c2f;">${code}</span>
      </div>
      <p style="margin: 0 0 8px; font-size: 13px; color: #6b7280;">This code expires in 15 minutes.</p>
      <p style="margin: 0; font-size: 13px; color: #6b7280;">After verifying, your account will still need admin approval before you can log in.</p>
    `)
  );
}

async function sendWelcomeEmail(toEmail, fullName, username, tempPassword) {
  await sendViaBrevoAPI(
    toEmail,
    fullName,
    'Welcome to MACDEN Portal — Your account is ready',
    `Hi ${fullName},\n\nYour MACDEN Portal account is ready.\n\nUsername: ${username}\nTemporary password: ${tempPassword}\n\nPlease log in and change your password as soon as possible from Settings.\n\nLog in here: https://macden.com.ng/portal`,
    wrapInBrandedTemplate(`
      <p style="margin: 0 0 16px; font-size: 14px; color: #2b2d31;">Hi ${fullName},</p>
      <p style="margin: 0 0 20px; font-size: 14px; color: #2b2d31;">Your MACDEN Portal account is ready.</p>
      <div style="background: #f7f8fa; border: 1px solid #e5e7eb; border-radius: 8px; padding: 16px 18px; margin: 0 0 20px;">
        <p style="margin: 0 0 8px; font-size: 13px; color: #6b7280;">Username</p>
        <p style="margin: 0 0 14px; font-size: 15px; font-weight: 700; color: #2b2d31;">${username}</p>
        <p style="margin: 0 0 8px; font-size: 13px; color: #6b7280;">Temporary password</p>
        <p style="margin: 0; font-size: 15px; font-weight: 700; color: #2b2d31; font-family: monospace;">${tempPassword}</p>
      </div>
      <a href="https://macden.com.ng/portal" style="display: inline-block; background: #0d5c2f; color: #ffffff; text-decoration: none; padding: 12px 24px; border-radius: 8px; font-size: 14px; font-weight: 700;">Log in to MACDEN Portal</a>
      <p style="margin: 20px 0 0; font-size: 13px; color: #6b7280;">Please change your password as soon as possible from Settings after logging in.</p>
    `)
  );
}

async function sendNotificationEmail(toEmail, toName, subject, textContent, htmlBody) {
  await sendViaBrevoAPI(
    toEmail,
    toName,
    subject,
    textContent,
    wrapInBrandedTemplate(htmlBody || `<p style="margin:0; font-size:14px; color:#2b2d31;">${textContent}</p>`)
  );
}

module.exports = { sendVerificationEmail, sendWelcomeEmail, sendNotificationEmail };

EOF_EMAIL_JS
echo "Done. Restart your server (or push + wait for Render)."