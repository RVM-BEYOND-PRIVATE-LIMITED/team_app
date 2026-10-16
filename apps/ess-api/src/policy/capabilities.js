const { ROLES } = require('./roles');
const { ATTENDANCE_OVERRIDE_ROLES } = require('./hrPolicy');
const { offeredRequestTypes, requestPolicy } = require('./requestLimits');

/**
 * What the app may show and offer one signed-in employee (task A4), from KP's decisions of
 * 16 Oct 2026 (docs/03-decisions.md).
 *
 * Every role is named, never derived through INHERITS. Inheritance answers "which admin duties
 * does this role have", which is a different question: CEO inherits admin, yet admin gets no
 * Work section while the CEO does. Naming them also means a role added to the Scheduler later
 * gets nothing here until somebody decides what it should get.
 *
 * The app hides what this says is off, but the server still checks every request on its own;
 * this document is a menu, not a permission.
 */

const TABS = Object.freeze(['home', 'inbox', 'wall', 'me', 'team']);

/**
 * The Work section: teaching and the leaders' views. Admin, Admin Manager and Finance Admin get
 * all five tabs but not this (decision 3), and neither do HR, HR Executive or attendance-only
 * staff.
 */
const WORK_ROLES = new Set([
  ROLES.FACULTY,
  ROLES.HOD,
  ROLES.HOD_PLACEMENT,
  ROLES.HOO,
  ROLES.SUPER_ADMIN,
  ROLES.CEO,
]);

/**
 * May decide anybody's request, recorded as HR's decision (decision 1): hr, ceo and
 * super_admin. Every request type so far is attendance or leave, where "HR" means the roles
 * the Scheduler lets override a day, never HR_ROLES, which includes hr_executive.
 */
const ANY_REQUEST_ROLES = ATTENDANCE_OVERRIDE_ROLES;

/**
 * HR's own queues. HR Executive has HR's powers without attendance (decided 16 Oct), so
 * attendance is missing from its list; it is also left out of ANY_REQUEST_ROLES on purpose.
 */
const HR_SCOPE = new Map([
  [ROLES.HR, ['attendance', 'documents', 'profile_changes', 'helpdesk_hr']],
  [ROLES.HR_EXECUTIVE, ['documents', 'profile_changes', 'helpdesk_hr']],
]);

/** Everyone posts on the Wall; only these post announcements, and only HR hides posts (decision 8). */
const ANNOUNCE_ROLES = new Set([ROLES.HR, ROLES.CEO, ROLES.SUPER_ADMIN]);
const MODERATE_ROLES = new Set([ROLES.HR]);

/** Play Integrity is built but stays off until RVM has a Play project (ADR-0016). */
const INTEGRITY_REQUIRED = false;

/**
 * @param {object} who
 * @param {'portal'|'attendance'} who.kind  which sign-in the caller used
 * @param {string|null} who.role            users.role for a portal login; ignored for an attendance session
 * @param {number} who.directReports        active employees whose manager_id is the caller
 * @param {boolean} who.pushEnabled         whether the FIREBASE_* settings are all present
 */
function capabilitiesFor({ kind, role, directReports, pushEnabled }) {
  // An attendance session carries no portal role, whatever the person's account says: these
  // powers come with the portal login, so a session that did not use it does not get them.
  const r = kind === 'portal' ? role : null;
  const ownReports = directReports > 0;
  const anyRequest = ANY_REQUEST_ROLES.has(r);
  return {
    tabs: [...TABS],
    sections: { time: true, helpdesk: true, documents: true, profile: true, work: WORK_ROLES.has(r) },
    team: { has_reports: ownReports, direct_reports: directReports },
    approvals: {
      own_reports: ownReports,
      any_request: anyRequest,
      request_types: anyRequest || ownReports ? offeredRequestTypes() : [],
      hr_scope: [...(HR_SCOPE.get(r) || [])],
    },
    requests: requestPolicy(),
    wall: { post: true, announce: ANNOUNCE_ROLES.has(r), moderate: MODERATE_ROLES.has(r) },
    push: { enabled: pushEnabled === true },
    integrity: { required: INTEGRITY_REQUIRED },
  };
}

module.exports = { capabilitiesFor, TABS, WORK_ROLES, ANY_REQUEST_ROLES, ANNOUNCE_ROLES, MODERATE_ROLES };
