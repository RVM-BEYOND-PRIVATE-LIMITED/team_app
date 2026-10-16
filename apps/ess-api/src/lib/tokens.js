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
 *
 * The short access tokens the ESS mints for a kept sign-in (task A3, lib/accessTokens.js) are
 * these same two formats with one more claim, `sid`, naming the ESS session. The Scheduler
 * ignores it; readToken reports it, and employeeAuth refuses the token once that session ends.
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

/** The verified payload of an attendance session, or null: readPunchSession's checks. */
function attendancePayload(token, { jwtSecret, nowMs }) {
  if (!token) return null;
  try {
    const p = jwt.verify(token, attendanceSessionKey(jwtSecret), {
      algorithms: ['HS256'],
      audience: ATTENDANCE_AUDIENCE,
      clockTimestamp: Math.floor(nowMs / 1000),
    });
    return p && p.k === 'punch' && typeof p.e === 'string' && UUID_RE.test(p.e) ? p : null;
  } catch {
    return null;
  }
}

const attendanceFields = (p) => ({ employeeId: p.e, method: p.m === 'pw' ? 'pw' : 'otp', issuedAt: (Number(p.iat) || 0) * 1000 });

/**
 * readPunchSession (services/attendancePunch.js:230-239) with the clock passed in:
 * { employeeId, method, issuedAt (ms) } for an attendance session, null for anything else.
 */
function readAttendanceSession(token, options) {
  const p = attendancePayload(token, options);
  return p ? attendanceFields(p) : null;
}

/**
 * The ESS session a token was minted for (lib/accessTokens.js), from its `sid` claim; null for a
 * token the Scheduler issued, which never carries one. Only the ESS signs a sid in, so one that
 * is not a uuid means the token is not what it claims to be.
 */
function sessionIdOf(p) {
  if (p.sid === undefined) return { sessionId: null };
  return typeof p.sid === 'string' && UUID_RE.test(p.sid) ? { sessionId: p.sid.toLowerCase() } : null;
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
 *   { kind: 'attendance', employeeId, method, issuedAt, sessionId }
 *   { kind: 'portal', userId, role, facultyId, locationName, issuedAt, sessionId }
 *   { kind: 'not_staff' }                         signed with JWT_SECRET but not a staff login
 *   { kind: 'rejected', reason: 'expired'|'invalid' }  absent, forged, expired or malformed
 *
 * sessionId is the ESS session a minted token belongs to, and null for the Scheduler's own.
 */
function readToken(token, { jwtSecret, nowMs }) {
  if (!token) return { kind: 'rejected', reason: 'invalid' };
  const a = attendancePayload(token, { jwtSecret, nowMs });
  if (a) {
    const sid = sessionIdOf(a);
    if (!sid) return { kind: 'rejected', reason: 'invalid' };
    return { kind: 'attendance', ...attendanceFields(a), ...sid };
  }

  let p;
  try {
    p = jwt.verify(token, jwtSecret, { algorithms: ['HS256'], clockTimestamp: Math.floor(nowMs / 1000) });
  } catch (e) {
    return { kind: 'rejected', reason: e && e.name === 'TokenExpiredError' ? 'expired' : 'invalid' };
  }
  if (!isPortalPayload(p)) return { kind: 'not_staff' };
  const sid = sessionIdOf(p);
  if (!sid) return { kind: 'rejected', reason: 'invalid' };
  const role = typeof p.role === 'string' ? p.role : null;
  return {
    kind: 'portal',
    userId: p.userId,
    role,
    // auth.js finds a teaching role's account by this id rather than by userId (auth.js:50-57).
    facultyId: TEACHING_ROLES.has(role) && p.id ? p.id : null,
    // The branch typed at sign-in, signed unchecked (userController.js:503). Never used to decide
    // anything; an ESS session only carries it into the tokens it mints, as the Scheduler's does.
    locationName: typeof p.locationName === 'string' ? p.locationName : null,
    issuedAt: (Number(p.iat) || 0) * 1000,
    ...sid,
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
