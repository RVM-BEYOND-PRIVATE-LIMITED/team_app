const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { ATTENDANCE_AUDIENCE, attendanceSessionKey } = require('./tokens');
const { SEES_ALL_LOCATIONS, TEACHING_ROLES } = require('../policy/roles');
const { ACCESS_TOKEN_SECONDS } = require('../policy/sessions');

/**
 * The tokens of a kept sign-in (task A3): short access tokens in the Scheduler's own two formats,
 * signed with the shared JWT_SECRET, so the Scheduler's punch path and every portal route accept
 * them unchanged (ADR-0006: the Scheduler cannot be changed to accept a new kind), plus the
 * opaque refresh token the app trades for the next one.
 *
 * Each access token adds one claim, `sid`, the ESS session it belongs to. The Scheduler ignores
 * it; the ESS refuses the token once that session has ended (middleware/employeeAuth.js).
 *
 * THE iat IS THE ORIGINAL SIGN-IN, never the moment of minting. The Scheduler reads iat as "when
 * did this person last prove who they are":
 *   - a code ('otp') session may set the attendance password for 15 minutes after its iat
 *     (controllers/hr/attendanceOtpController.js:341-352, PASSWORD_SET_WINDOW_MS);
 *   - a session issued before the login's sessions_valid_from is over
 *     (services/attendanceAccounts.js:39-53), which is how a password change, a reset or HR
 *     switching the login off end every session.
 * A fresh iat on every refresh would hand each refresh a new 15-minute password window with no
 * code typed, and would carry a sign-in past the password change that should have ended it. So
 * iat stays put and exp is set by hand: jsonwebtoken counts expiresIn from the payload's iat,
 * which here can be weeks old.
 *
 * tests/accessTokens.test.js holds these tokens against verbatim copies of the Scheduler's own
 * readers (middleware/auth.js, middleware/punchAuth.js, readPunchSession and setPassword's gate).
 */

/**
 * The portal token's payload, field by field as the Scheduler builds it at sign-in
 * (controllers/userController.js:498-510) and after a two-factor code
 * (controllers/authSecurityController.js:20-29), from the users row read at this mint, so a new
 * role or branch is in the next token, within the hour.
 *
 * `locationName` is the branch the person signed in at: the Scheduler signs whatever the client
 * typed (userController.js:503), and a kept sign-in carries the one from the token it traded in.
 */
function portalPayload(user, locationName) {
  const payload = {
    userId: user.id,
    role: user.role,
    locationId: user.location_id,
    username: user.username,
    locationName,
    isSuperAdmin: SEES_ALL_LOCATIONS.has(user.role),
  };
  // Teaching roles carry faculty_id as `id`: auth.js finds their account by it (auth.js:50-57).
  if (TEACHING_ROLES.has(user.role)) payload.id = user.faculty_id;
  return payload;
}

/** iat from the original sign-in, exp an hour from now: both whole seconds, as JWTs count. */
const lifetime = (signedInAtMs, nowMs) => ({
  iat: Math.floor(signedInAtMs / 1000),
  exp: Math.floor(nowMs / 1000) + ACCESS_TOKEN_SECONDS,
});

/** A portal JWT: HS256 over JWT_SECRET, no audience or issuer, as userController.js:512 signs it. */
function mintPortalToken({ user, locationName, sessionId, signedInAtMs, nowMs, jwtSecret }) {
  return jwt.sign({ ...portalPayload(user, locationName), sid: sessionId, ...lifetime(signedInAtMs, nowMs) }, jwtSecret, {
    algorithm: 'HS256',
  });
}

/**
 * An attendance session: { k: 'punch', e, m } over sha256hex('rvm-punch-session:' + JWT_SECRET),
 * audience 'rvm-punch', as issuePunchSession signs it (services/attendancePunch.js:220-224). `m` is
 * how the original sign-in was earned and never changes, for the same reason iat does not.
 */
function mintAttendanceToken({ employeeId, method, sessionId, signedInAtMs, nowMs, jwtSecret }) {
  const payload = { k: 'punch', e: employeeId, m: method === 'pw' ? 'pw' : 'otp', sid: sessionId, ...lifetime(signedInAtMs, nowMs) };
  return jwt.sign(payload, attendanceSessionKey(jwtSecret), { algorithm: 'HS256', audience: ATTENDANCE_AUDIENCE });
}

/**
 * The access token for one session row, in the format of the sign-in it came from.
 *
 * @param {object} session  an hr_ess_sessions row
 * @param {object} deps
 * @param {object|null} deps.user  the users row, read just now (portal only)
 * @returns {{ token: string, expiresAt: Date }}
 */
function mintAccessToken(session, { user, nowMs, jwtSecret }) {
  const common = { sessionId: session.family_id, signedInAtMs: Date.parse(session.signed_in_at), nowMs, jwtSecret };
  const token = session.login_kind === 'portal'
    ? mintPortalToken({ ...common, user, locationName: session.location_name ?? null })
    : mintAttendanceToken({ ...common, employeeId: session.employee_id, method: session.method });
  return { token, expiresAt: new Date((Math.floor(nowMs / 1000) + ACCESS_TOKEN_SECONDS) * 1000) };
}

/**
 * The refresh token: 32 random bytes, base64url. It is opaque, so it says nothing about whose it
 * is, and it is never stored: hr_ess_sessions keeps only its hash.
 */
const newRefreshToken = () => crypto.randomBytes(32).toString('base64url');

/**
 * The key the refresh hashes are made with, derived from JWT_SECRET as the attendance session's
 * key is (services/attendancePunch.js:209-213), and never JWT_SECRET itself.
 */
const refreshHashKey = (jwtSecret) => crypto.createHash('sha256').update(`rvm-ess-refresh:${jwtSecret}`).digest('hex');

/**
 * HMAC-SHA256 of the token, keyed from JWT_SECRET. A plain sha256 would do for secrecy, since the
 * token is 256 random bits. The key is there so that rotating JWT_SECRET still signs everybody out
 * of both services (docs/04-build-plan.md, Risks), kept sign-ins included: under a new secret no
 * stored hash matches, so every refresh answers `unknown`. Without it, somebody who learned the
 * old secret could forge a fresh sign-in, keep it, and stay in after the rotation.
 */
const refreshTokenHash = (token, jwtSecret) =>
  crypto.createHmac('sha256', refreshHashKey(jwtSecret)).update(token, 'utf8').digest('hex');

module.exports = {
  portalPayload,
  mintPortalToken,
  mintAttendanceToken,
  mintAccessToken,
  newRefreshToken,
  refreshTokenHash,
};
