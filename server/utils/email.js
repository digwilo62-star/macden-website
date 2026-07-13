const nodemailer = require('nodemailer');

const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST,
  port: process.env.SMTP_PORT,
  secure: process.env.SMTP_PORT === '465', // true for port 465, false for 587/others
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS
  }
});

async function sendVerificationEmail(toEmail, fullName, code) {
  await transporter.sendMail({
    from: process.env.SMTP_FROM || '"MACDEN Accounting" <no-reply@macden.com.ng>',
    to: toEmail,
    subject: 'Verify your MACDEN Accounting account',
    text: `Hi ${fullName},\n\nYour verification code is: ${code}\n\nThis code expires in 15 minutes.\n\nAfter verifying, your account will still need admin approval before you can log in.`,
    html: `
      <p>Hi ${fullName},</p>
      <p>Your verification code is:</p>
      <p style="font-size: 24px; font-weight: bold; letter-spacing: 4px;">${code}</p>
      <p>This code expires in 15 minutes.</p>
      <p>After verifying, your account will still need admin approval before you can log in.</p>
    `
  });
}

module.exports = { sendVerificationEmail };

