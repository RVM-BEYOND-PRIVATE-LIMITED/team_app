const { ROLES } = require('./roles');

/**
 * The Scheduler's HR and attendance role sets, copied from Scheduler_Backend
 * config/hrPolicy.js at commit c28b9ca (lines 17-85). The comments are the Scheduler's.
 *
 * The ESS needs them because "HR" means different sets in different places. For attendance and
 * leave, "HR may decide any request" means ATTENDANCE_OVERRIDE_ROLES (hr, ceo, super_admin),
 * never HR_ROLES, which includes hr_executive (docs/03-decisions.md, decision 1). An approval
 * writes the day through HR's override function (ADR-0020), and these are the roles the
 * Scheduler lets use it.
 *
 * tests/roles.test.js compares this copy with the Scheduler's whenever SCHEDULER_BACKEND_DIR
 * points at a checkout (ADR-0008). Change the Scheduler first, then copy the change here.
 */

/**
 * Who may open the HR workspace at all. Nobody else sees the tab or reaches the API.
 *
 * HR_EXECUTIVE (RVM, 2026-10-14) is in every HR set EXCEPT the three attendance ones below
 * (HR_ATTENDANCE_ROLES, ATTENDANCE_OVERRIDE_ROLES, ATTENDANCE_ACCOUNT_ROLES): "HR executive
 * will not be able to see these attendance control and tab."
 */
const HR_ROLES = new Set([
  ROLES.HR,
  ROLES.HR_EXECUTIVE,
  ROLES.CEO,
  ROLES.SUPER_ADMIN,
]);

/**
 * Who may change HR data. Identical to HR_ROLES today, and kept as its own constant so
 * a read-only HR viewer can be added later without touching a single route.
 */
const HR_WRITE_ROLES = new Set([
  ROLES.HR,
  ROLES.HR_EXECUTIVE,
  ROLES.CEO,
  ROLES.SUPER_ADMIN,
]);

/**
 * Who may read and mark staff attendance. The branch Admin Manager marks their
 * own centre (HR marks HQ staff); HR, the CEO and a super admin are global.
 * Deliberately wider than HR_ROLES — marking happens at the branches, not in
 * the HR workspace — with the branch fence enforced per row in the controller.
 */
const HR_ATTENDANCE_ROLES = new Set([
  ROLES.HR,
  ROLES.ADMIN_MANAGER,
  ROLES.CEO,
  ROLES.SUPER_ADMIN,
]);

/**
 * WHO MAY OVERRIDE ATTENDANCE, AND RUN THE PUNCH SYSTEM.
 *
 * RVM, 2026-10-14: "the override button to HR, CEO and Superadmin." Overriding sets any day
 * for anybody -- past or today -- with a reason, and the row it writes is then closed to
 * the daily sheet, so an Admin Manager re-marking the branch cannot quietly undo it. The
 * same three reset a person's registered phone, set a branch's geofence and read the punch
 * log, because each of those decides whether a punch counts.
 *
 * Narrower than HR_ATTENDANCE_ROLES on purpose: the Admin Manager marks the day, but does
 * not get to overrule HR's correction of it.
 */
const ATTENDANCE_OVERRIDE_ROLES = new Set([
  ROLES.HR,
  ROLES.CEO,
  ROLES.SUPER_ADMIN,
]);

/**
 * WHO MAY CREATE AND MANAGE ATTENDANCE-ONLY LOGINS -- HR and a super admin.
 *
 * RVM, 2026-10-14: "create account for them where they can set password and give attendance
 * only. That feature should also be given to HR only." Widened 2026-10-15: "give the option of
 * creating login and passwords to Superadmin as well." The CEO still corrects days but does not
 * keep the login register. Mirror: client/lib/roles.ts.
 */
const ATTENDANCE_ACCOUNT_ROLES = new Set([
  ROLES.HR,
  ROLES.SUPER_ADMIN,
]);

module.exports = {
  HR_ROLES,
  HR_WRITE_ROLES,
  HR_ATTENDANCE_ROLES,
  ATTENDANCE_OVERRIDE_ROLES,
  ATTENDANCE_ACCOUNT_ROLES,
};
