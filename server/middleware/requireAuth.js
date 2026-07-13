// Blocks any route from running unless there's an active staff session.
// Use this on every accounting API route except /auth/login.
function requireAuth(req, res, next) {
  if (!req.session || !req.session.staff) {
    return res.status(401).json({ error: 'Please log in to continue.' });
  }
  next();
}

module.exports = requireAuth;

