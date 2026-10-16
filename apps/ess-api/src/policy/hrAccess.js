const { ROLES } = require('./roles');
const { ATTENDANCE_OVERRIDE_ROLES } = require('./hrPolicy');

/**
 * Who may use the ESS's HR tools. Every role is named, never inherited, as the Scheduler's HR
 * module names them (config/hrPolicy.js:3-16, guarded with allowRoles at routes/hr.js:39-53).
 *
 * HR_RECORD_ROLES: an employee's personal details and their requests to correct or delete their
 * data. The Scheduler's HR_ROLES (config/hrPolicy.js:25-30: hr, ceo, super_admin), who read the
 * HR record today, plus hr_executive (docs/03-decisions.md: an HR Executive "approves documents,
 * profile changes"). Every HR read of someone's personal details is written to hr_ess_audit.
 *
 * ATTENDANCE_ROLES: the location trail, the mocked-location reports and the phone reset. The
 * Scheduler's ATTENDANCE_OVERRIDE_ROLES (hr, ceo, super_admin; config/hrPolicy.js:68-72): "the
 * same three reset a person's registered phone ... and read the punch log". HR Executive is not
 * among them (KP, 16 Oct: HR's powers without attendance).
 */
const HR_RECORD_ROLES = new Set([
  ROLES.HR,
  ROLES.HR_EXECUTIVE,
  ROLES.CEO,
  ROLES.SUPER_ADMIN,
]);

const ATTENDANCE_ROLES = ATTENDANCE_OVERRIDE_ROLES;

module.exports = { HR_RECORD_ROLES, ATTENDANCE_ROLES };
