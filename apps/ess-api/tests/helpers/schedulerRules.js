/**
 * The Scheduler's own rules for "may this session still be used" and "is this person still on
 * strength", copied verbatim from Scheduler_Backend at c28b9ca, so the tests can show that the
 * ESS (src/middleware/employeeAuth.js, src/policy/employment.js) decides every case the same
 * way.
 *
 * Blocks are marked as in schedulerTokens.js and checked by tests/schedulerCopies.test.js
 * whenever SCHEDULER_BACKEND_DIR is set. The copied isActive reads the real clock, as it does
 * in the Scheduler.
 */

// <scheduler file="services/attendanceAccounts.js" lines="39-53">
function sessionProblem(session, account) {
  if (!account) {
    return { status: 403, code: 'NO_ATTENDANCE_LOGIN', message: 'You do not have an attendance login yet. Ask HR to create one for you.' };
  }
  if (account.status !== 'active') {
    return { status: 403, code: 'NO_ATTENDANCE_LOGIN', message: 'Your attendance login is turned off. Ask HR.' };
  }
  // Whole seconds on both sides: a session's iat is whole seconds, so one issued in the same
  // second as the cut-off (a login created and signed into within a second) is the new one.
  const cutoff = account.sessions_valid_from ? Math.floor(Date.parse(account.sessions_valid_from) / 1000) * 1000 : 0;
  if (session && session.issuedAt < cutoff) {
    return { status: 401, code: 'NOT_AUTHENTICATED', message: 'Your password was changed. Please sign in again.' };
  }
  return null;
}
// </scheduler>

// <scheduler file="services/attendancePunch.js" lines="172">
const istDay = (d = new Date()) => new Date(d.getTime() + 330 * 60000).toISOString().slice(0, 10);
// </scheduler>

// The punch controller reaches istDay as A.istDay (const A = require('../../services/attendancePunch')).
const A = { istDay };

// <scheduler file="controllers/hr/attendancePunchController.js" lines="88-90">
/** Archived, exited, or past the last working day: no longer punches. */
const isActive = (emp) =>
  !emp.is_archived && emp.employment_status !== 'exited' && !(emp.date_of_exit && emp.date_of_exit < A.istDay());
// </scheduler>

module.exports = { sessionProblem, istDay, isActive };
