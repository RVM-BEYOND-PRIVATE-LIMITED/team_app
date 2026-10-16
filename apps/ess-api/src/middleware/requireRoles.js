const { HttpError, MESSAGES } = require('../lib/errors');

/**
 * An exact-role guard for HR's tools, placed after employeeAuth: the Scheduler's allowRoles
 * (middleware/allowRoles.js:14-33), which asks one question, whether the caller's own role is in
 * the set. Nothing inherits its way in.
 *
 * An attendance session carries no portal role (capabilities.js), so it is refused before the
 * role is looked at, with a reply that says which sign-in would work. HR's writes also record the
 * actor's users.id (the Scheduler's revoked_by and the ESS's *_by_user_id columns), which an
 * attendance session does not have.
 *
 * @param {Set<string>} roles
 * @param {'HR_ACCESS_DENIED'|'ATTENDANCE_OVERRIDE_DENIED'} code  the Scheduler's code for the same refusal
 */
function requireRoles(roles, code) {
  return function roleGuard(req, _res, next) {
    const { kind, role } = req.auth;
    if (kind !== 'portal') return next(new HttpError(403, 'PORTAL_LOGIN_REQUIRED', MESSAGES.PORTAL_LOGIN_REQUIRED));
    if (!roles.has(role)) return next(new HttpError(403, code, MESSAGES[code]));
    return next();
  };
}

module.exports = { requireRoles };
