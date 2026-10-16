const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { TEACHING_ROLES } = require('../policy/roles');

/**
 * Reads the two sign-in tokens the Scheduler issues, the way the Scheduler reads them, so that
 * one sign-in works for both services (ADR-0006).
 *
 * This mirrors Scheduler_Backend at commit c28b9ca:
 *   services/attendancePunch.js:205-239        the attendance session: the derived key, the
 *                                              audience, the payload and readPunchSession
 *   middleware/punchAuth.js:21-34              the attendance session is tried first, then the
 *                                              portal token
 *   middleware/auth.js:6-14,50-66              the portal token, verified against JWT_SECRET,
 *                                              and how a teaching role's token finds its account
 *   controllers/userController.js:498-512      the portal token's payload, at sign-in
 *   controllers/authSecurityController.js:20-31  the same payload, after a two-factor code
 *   controllers/userController.js:797-801      the student token, refused here
 *   utils/admissionUndertakingToken.js:3-13    the admission-undertaking token, refused here
 *
 * If the Scheduler changes how it signs either token, this file changes in the same release.
 * tests/helpers/schedulerTokens.js signs test tokens with verbatim copies of that code, so a
 * difference between the two breaks the tests.
 *
 * Two deliberate differences, both stricter than auth.js. The portal token's algorithm is pinned
 * to HS256 (auth.js accepts any HMAC algorithm jsonwebtoken allows). And a portal token must
 * look like one: auth.js admits anything signed with JWT_SECRET, a student token included, while
 * this service answers NOT_AN_EMPLOYEE for every shape that is not a staff login.
 */

/** The attendance session's audience: services/attendancePunch.js:206. */
const ATTENDANCE_AUDIENCE = 'rvm-punch';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * sha256hex('rvm-punch-session:' + JWT_SECRET) (services/attendancePunch.js:209-213).
 *
 * The attendance session is signed with this derived key and never with JWT_SECRET itself, so a
 * portal guard that verifies against JWT_SECRET rejects it as a bad signature.
 */
const attendanceSessionKey = (jwtSecret) =>
  crypto.createHash('sha256').update(`rvm-punch-session:${jwtSecret}`).digest('hex');

/**
 * readPunchSession (services/attendancePunch.js:230-239) with the clock passed in:
 * { employeeId, method, issuedAt (ms) } for an attendance session, null for anything else.
 */
function readAttendanceSession(token, { jwtSecret, nowMs }) {
  if (!token) return null;
  try {
    const p = jwt.verify(token, attendanceSessionKey(jwtSecret), {
      algorithms: ['HS256'],
      audience: ATTENDANCE_AUDIENCE,
      clockTimestamp: Math.floor(nowMs / 1000),
    });
    if (!(p && p.k === 'punch' && typeof p.e === 'string' && UUID_RE.test(p.e))) return null;
    return { employeeId: p.e, method: p.m === 'pw' ? 'pw' : 'otp', issuedAt: (Number(p.iat) || 0) * 1000 };
  } catch {
    return null;
  }
}

/**
 * Whether a payload verified with JWT_SECRET is a staff portal token.
 *
 * The portal payload is { userId, role, locationId, username, locationName, isSuperAdmin }, plus
 * id = the faculty id for a teaching role. It never carries an audience, an issuer or a scope.
 * Every other token signed with JWT_SECRET differs in at least one of these: the student token
 * has role 'student' and no userId, the undertaking token an issuer and a scope, and a
 * look-alike attendance session signed with the portal key an audience and k.
 */
function isPortalPayload(p) {
  if (!p || typeof p !== 'object') return false;
  if (p.role === 'student') return false;
  if (p.aud !== undefined || p.iss !== undefined || p.scope !== undefined || p.k !== undefined) return false;
  return typeof p.userId === 'string' && UUID_RE.test(p.userId);
}

/**
 * What a bearer token is, tried in the Scheduler's order (attendance session first):
 *
 *   { kind: 'attendance', employeeId, method, issuedAt }
 *   { kind: 'portal', userId, role, facultyId, issuedAt }
 *   { kind: 'not_staff' }                         signed with JWT_SECRET but not a staff login
 *   { kind: 'rejected', reason: 'expired'|'invalid' }  absent, forged, expired or malformed
 */
function readToken(token, { jwtSecret, nowMs }) {
  if (!token) return { kind: 'rejected', reason: 'invalid' };
  const session = readAttendanceSession(token, { jwtSecret, nowMs });
  if (session) return { kind: 'attendance', ...session };

  let p;
  try {
    p = jwt.verify(token, jwtSecret, { algorithms: ['HS256'], clockTimestamp: Math.floor(nowMs / 1000) });
  } catch (e) {
    return { kind: 'rejected', reason: e && e.name === 'TokenExpiredError' ? 'expired' : 'invalid' };
  }
  if (!isPortalPayload(p)) return { kind: 'not_staff' };
  const role = typeof p.role === 'string' ? p.role : null;
  return {
    kind: 'portal',
    userId: p.userId,
    role,
    // auth.js finds a teaching role's account by this id rather than by userId (auth.js:50-57).
    facultyId: TEACHING_ROLES.has(role) && p.id ? p.id : null,
    issuedAt: (Number(p.iat) || 0) * 1000,
  };
}

/**
 * The token from "Authorization: Bearer <token>", or null.
 *
 * "Bearer " is matched exactly as the Scheduler strips it (auth.js:8), so a client that works
 * here also works there.
 */
function bearerToken(header) {
  if (typeof header !== 'string') return null;
  const m = /^Bearer (\S+)$/.exec(header);
  return m ? m[1] : null;
}

module.exports = {
  ATTENDANCE_AUDIENCE,
  attendanceSessionKey,
  readAttendanceSession,
  readToken,
  bearerToken,
};
