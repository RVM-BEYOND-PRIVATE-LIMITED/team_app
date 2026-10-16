/**
 * The Scheduler's role names and inheritance, copied from Scheduler_Backend config/roles.js at
 * commit c28b9ca (lines 4-103 and 135-136).
 *
 * A copy, not a shared package, because the ESS runs as a separate process from a separate
 * repository (ADR-0005). tests/roles.test.js compares this file with the Scheduler's whenever
 * SCHEDULER_BACKEND_DIR points at a checkout, so the copy cannot drift silently (ADR-0008).
 * Change the Scheduler first, then copy the change here; never edit only this side.
 *
 * Only the parts the ESS reads are copied. The comments are the Scheduler's.
 */

const ROLES = {
  CEO: 'ceo',
  SUPER_ADMIN: 'super_admin',
  HOO: 'hoo',
  HOD: 'hod',
  HOD_PLACEMENT: 'hod_placement',
  ADMIN_MANAGER: 'admin_manager',
  ADMIN: 'admin',
  ACCOUNTS_ADMIN: 'accounts_admin',
  HR: 'hr',
  // HR without the attendance controls (RVM, 2026-10-14). See config/hrPolicy.js.
  HR_EXECUTIVE: 'hr_executive',
  FACULTY: 'faculty',
  STUDENT: 'student',
  // The connector identity (control-room-bot). Inherits nothing and grants
  // nothing: it never signs in, never appears on screens, and reaches data
  // only through the MCP connector's own OAuth. Nothing inherits from it.
  BOT_READONLY: 'bot_readonly',
};

// Who inherits whose capabilities. Resolved transitively by expandRoles().
// This is what makes "Admin Manager has every admin duty" true without editing controllers.
// HOD deliberately does NOT inherit admin — the HOD charter owns the technical track only
// (no leave approval, no batch allotment, no ops). A HOD is still a teaching faculty member.
const INHERITS = {
  [ROLES.CEO]: [ROLES.SUPER_ADMIN],
  [ROLES.SUPER_ADMIN]: [ROLES.ADMIN],
  [ROLES.ADMIN_MANAGER]: [ROLES.ADMIN],
  [ROLES.HOO]: [ROLES.ADMIN],
  [ROLES.HOD]: [ROLES.FACULTY],
  // Finance admin (accounts_admin) was merged with branch admin in DUTIES, not in
  // scope: it now satisfies every admin permission and is no longer read-only, but
  // it remains a distinct role that still sees all centres (see SEES_ALL_LOCATIONS).
  [ROLES.ACCOUNTS_ADMIN]: [ROLES.ADMIN],
  // HR inherits nothing, and that is the whole of its access model. The HR workspace
  // is the only thing the role reaches; every other Scheduler endpoint refuses it.
  // Adding it to ADMIN here would hand HR students, admissions, fees and attendance,
  // which is the opposite of what the module is for. Its capabilities live in
  // config/hrPolicy.js, enforced with allowRoles rather than requireRole.
  [ROLES.HR]: [],
  // HR Executive inherits nothing either -- and in particular NOT `hr`: it holds every HR
  // capability EXCEPT attendance, and an inheritance would hand it attendance too. It is
  // listed by name in each config/hrPolicy.js set it belongs to, and left out of the
  // attendance ones.
  [ROLES.HR_EXECUTIVE]: [],
  // HOD Placement owns the interview calendar only — no admin duties, no teaching record.
  // Like HR, it inherits nothing and nothing inherits from it.
  [ROLES.HOD_PLACEMENT]: [],
  // The connector identity. Like HR and HOD Placement it inherits nothing — and
  // additionally, NO_BRANCH_ROLES aside, nothing anywhere may treat it as staff:
  // it cannot sign in (see userController) and is dropped from user listings.
  [ROLES.BOT_READONLY]: [],
};

function expandRoles(role) {
  const out = new Set();
  const walk = (r) => {
    if (!r || out.has(r)) return;
    out.add(r);
    (INHERITS[r] || []).forEach(walk);
  };
  walk(role);
  return out;
}

function roleSatisfies(role, target) {
  return expandRoles(role).has(target);
}

// Every role that satisfies `target`, e.g. rolesSatisfying('admin') ->
// ['admin','super_admin','admin_manager','hoo','ceo']. Derived, never hand-maintained.
function rolesSatisfying(target) {
  return Object.values(ROLES).filter((r) => roleSatisfies(r, target));
}

// Roles exempt from location filtering. `req.isSuperAdmin` is set from this set and keeps
// its long-standing meaning of "bypass the branch filter" — ~141 call sites depend on it.
// Branch-scoped roles (hoo, hod, admin_manager) are deliberately absent so the existing
// .eq('location_id', req.locationId) filtering applies to them unchanged.
const SEES_ALL_LOCATIONS = new Set([
  ROLES.CEO,
  ROLES.SUPER_ADMIN,
  // Finance admin keeps all-centre visibility for now. It gained write access when it
  // was merged with branch admin, but deliberately kept its global scope.
  ROLES.ACCOUNTS_ADMIN,
]);

/**
 * Roles that do not belong to a branch, and so are created without one.
 *
 * Deliberately NOT the same set as SEES_ALL_LOCATIONS, even though it contains it.
 * SEES_ALL_LOCATIONS drives `req.isSuperAdmin`, which ~141 call sites read as "skip the
 * branch filter". HR is company-wide in the sense that it has no branch, but it must not
 * gain that bypass: it would hand HR every centre's students, fees and attendance, which
 * is the opposite of a role that sees only its own workspace.
 *
 * So this set answers one narrow question — "must a branch be chosen when creating this
 * account?" — and nothing else.
 */
const NO_BRANCH_ROLES = new Set([...SEES_ALL_LOCATIONS, ROLES.HR, ROLES.HR_EXECUTIVE, ROLES.BOT_READONLY]);

// Roles that hold a teaching faculty record, so auth resolves them via users.faculty_id.
const TEACHING_ROLES = new Set([ROLES.FACULTY, ROLES.HOD]);

module.exports = {
  ROLES,
  INHERITS,
  expandRoles,
  roleSatisfies,
  rolesSatisfying,
  SEES_ALL_LOCATIONS,
  NO_BRANCH_ROLES,
  TEACHING_ROLES,
};
