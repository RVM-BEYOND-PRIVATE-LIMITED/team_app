const { readToken, bearerToken } = require('../lib/tokens');
const { HttpError, MESSAGES, notAuthenticated } = require('../lib/errors');
const { istDay } = require('../lib/time');
const { isActive } = require('../policy/employment');
const { NOT_STAFF_ROLES } = require('../policy/staff');

/**
 * employeeAuth (task A1): who is calling, as an employee.
 *
 * Accepts both tokens the Scheduler issues (lib/tokens.js) and resolves either one to the
 * caller's hr_employees row. The row is re-read on every request, so somebody who leaves is
 * refused on their next tap, whatever their token says.
 *
 * The checks and their order are the Scheduler's own, from loadEmployee
 * (controllers/hr/attendancePunchController.js:101-119) and sessionProblem
 * (services/attendanceAccounts.js:39-53) at c28b9ca:
 *
 *   attendance session  employee deleted -> 401; left -> 403 NOT_ACTIVE; attendance login
 *                       missing or switched off -> 403 NO_ATTENDANCE_LOGIN; issued before the
 *                       login's sessions_valid_from -> 401 NOT_AUTHENTICATED; signed in with
 *                       HR's first-time password, not yet replaced -> 403
 *                       PASSWORD_CHANGE_REQUIRED (passwordChangeDue, attendancePunchController.js:190-197)
 *   portal token        account deleted -> 401; not a staff login -> 403 NOT_AN_EMPLOYEE; no
 *                       HR record -> 403 NOT_LINKED; left -> 403 NOT_ACTIVE
 *
 * A failed database read reaches the error handler as the store's 503, never as a 401. The app
 * signs out on a 401 alone, and a database outage must not sign the whole company out
 * (ADR-0006). The Scheduler's auth.js answers 401 in that case; this is where the two differ.
 *
 * A token the ESS minted for a kept sign-in (task A3, lib/accessTokens.js) carries `sid`. Before
 * anything else, that session must still be live: not signed out, not revoked, not expired, and
 * the token's own person's. Otherwise 401, so signing out or a revocation ends every token of
 * that sign-in at once on the ESS, not only when its hour runs out. The Scheduler cannot know
 * this, which is why the tokens it accepts last an hour and no longer.
 *
 * On success: req.auth = { kind: 'portal'|'attendance', userId, role, employee, sessionId,
 * issuedAt, method, locationName }, the last four for the session endpoints (routes/sessions.js).
 */

const notAnEmployee = () => new HttpError(403, 'NOT_AN_EMPLOYEE', MESSAGES.NOT_AN_EMPLOYEE);
const notActive = () => new HttpError(403, 'NOT_ACTIVE', MESSAGES.NOT_ACTIVE);

/**
 * services/attendanceAccounts.js:39-53: the login must exist and be active, and the session must
 * not predate the last password change, reset or switch-off. The one addition is the unreadable
 * cut-off below; tests/policy.test.js holds every other case against the Scheduler's copy.
 */
function sessionProblem(session, account) {
  if (!account) return new HttpError(403, 'NO_ATTENDANCE_LOGIN', MESSAGES.NO_ATTENDANCE_LOGIN);
  if (account.status !== 'active') return new HttpError(403, 'NO_ATTENDANCE_LOGIN', MESSAGES.ATTENDANCE_LOGIN_OFF);
  // Whole seconds on both sides: a session's iat is whole seconds, so one issued in the same
  // second as the cut-off (a login created and signed into within a second) is the new one.
  const cutoff = account.sessions_valid_from ? Math.floor(Date.parse(account.sessions_valid_from) / 1000) * 1000 : 0;
  // A cut-off that cannot be read would otherwise compare false and let every old session in.
  // Refuse without signing anybody out: the fault is the server's, not the session's.
  if (Number.isNaN(cutoff)) return new HttpError(503, 'UNAVAILABLE', MESSAGES.UNAVAILABLE);
  if (session.issuedAt < cutoff) return notAuthenticated(MESSAGES.PASSWORD_CHANGED);
  return null;
}

/**
 * passwordChangeDue (controllers/hr/attendancePunchController.js:190-197): a session signed in
 * with the password HR gave, before the person chose their own, may only choose one. HR can give
 * a whole batch one shared first-time password, and the employee code that goes with it is on
 * the ID card, so such a session proves nothing about who is holding the phone. The Scheduler
 * shows it only the "choose your password" screen and refuses the challenge, punch and ping; the
 * ESS refuses it everywhere. The Scheduler also checks that a hash exists; the ESS never reads
 * the hash, and a 'pw' session already proves there was one.
 */
const passwordChangeDue = (session, account) => session.method === 'pw' && !account.password_set_at;

async function fromAttendanceSession(session, store, today) {
  const employee = await store.getEmployeeById(session.employeeId);
  // A session whose employee has since been deleted is a stale sign-in, not "unlinked".
  if (!employee) throw notAuthenticated(MESSAGES.SIGN_IN_AGAIN);
  if (!isActive(employee, today)) throw notActive();
  const account = await store.getAttendanceAccount(employee.id);
  const problem = sessionProblem(session, account);
  if (problem) throw problem;
  if (passwordChangeDue(session, account)) {
    throw new HttpError(403, 'PASSWORD_CHANGE_REQUIRED', MESSAGES.PASSWORD_CHANGE_REQUIRED);
  }
  return { kind: 'attendance', userId: null, role: null, employee };
}

async function fromPortalToken(claims, store, today) {
  const user = await store.getUser(claims.userId);
  // The account was deleted after the token was issued: that sign-in is over.
  if (!user) throw notAuthenticated(MESSAGES.SIGN_IN_AGAIN);
  // auth.js finds a teaching role's account by the faculty id in the token (auth.js:50-57).
  // When that id no longer belongs to this account, the Scheduler would act as somebody else or
  // refuse, so this refuses as well; signing in again issues a token that agrees.
  if (claims.facultyId && user.faculty_id !== claims.facultyId) throw notAuthenticated(MESSAGES.SIGN_IN_AGAIN);
  // The account's role, not the token's, exactly as auth.js chooses (auth.js:80-81).
  const role = user.role || claims.role || null;
  if (NOT_STAFF_ROLES.has(role)) throw notAnEmployee();
  const employee = await store.getEmployeeByUserId(user.id);
  if (!employee) throw new HttpError(403, 'NOT_LINKED', MESSAGES.NOT_LINKED);
  if (!isActive(employee, today)) throw notActive();
  return { kind: 'portal', userId: user.id, role, employee };
}

/**
 * A minted token's session must be live and its own: the same person and the same kind of
 * sign-in it was minted for. Only the ESS can sign a sid in, so a mismatch means a broken or
 * forged token, and it is refused the same way.
 */
async function requireLiveSession(found, store, at) {
  const live = await store.getLiveSession(found.sessionId);
  const own = live && live.login_kind === found.kind && (found.kind === 'attendance'
    ? live.employee_id === found.employeeId
    : live.user_id === found.userId);
  if (!own || !(Date.parse(live.expires_at) > at.getTime())) throw notAuthenticated(MESSAGES.SIGN_IN_AGAIN);
}

/**
 * @param {{ config: { jwtSecret: string }, store: object, now: () => Date }} deps
 */
function createEmployeeAuth({ config, store, now }) {
  async function identify(req) {
    const token = bearerToken(req.get('authorization'));
    if (!token) throw notAuthenticated(MESSAGES.SIGN_IN);
    const at = now();
    const found = readToken(token, { jwtSecret: config.jwtSecret, nowMs: at.getTime() });
    if (found.kind === 'rejected') {
      throw notAuthenticated(found.reason === 'expired' ? MESSAGES.SESSION_EXPIRED : MESSAGES.SIGN_IN_AGAIN);
    }
    if (found.kind === 'not_staff') throw notAnEmployee();
    if (found.sessionId) await requireLiveSession(found, store, at);
    const today = istDay(at);
    const auth = found.kind === 'attendance'
      ? await fromAttendanceSession(found, store, today)
      : await fromPortalToken(found, store, today);
    return {
      ...auth,
      sessionId: found.sessionId,
      issuedAt: found.issuedAt,
      method: found.kind === 'attendance' ? found.method : null,
      locationName: found.kind === 'portal' ? found.locationName : null,
    };
  }

  return function employeeAuth(req, _res, next) {
    identify(req).then((auth) => {
      req.auth = auth;
      next();
    }, next);
  };
}

module.exports = { createEmployeeAuth, sessionProblem, passwordChangeDue };
