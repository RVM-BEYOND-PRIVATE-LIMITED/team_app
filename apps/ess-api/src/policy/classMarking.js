/**
 * Phase 2D (task H1, decision 8): who may mark a batch, on which day, and which students count.
 *
 * The rules are the Scheduler's own, enforced here because its marking endpoint has no
 * server-side checks (docs/02-reconciliation.md, H1 and J1):
 *
 *   who may mark     faculty and hod (teaching); admin, admin_manager, hoo, accounts_admin, ceo
 *                    and super_admin (the Scheduler's register roles). Everybody else, including
 *                    hr, hr_executive, hod_placement and attendance sessions, is refused.
 *   ownership        batches.faculty_id = users.faculty_id, or a faculty_substitutions row for
 *                    that batch whose range includes the day (attendanceController.js:537-547)
 *   branch           an admin marks only batches whose location_id is their own branch, by name
 *                    (hr_branches.name to locations.name); the CEO and super admins are global
 *   the day          a real YYYY-MM-DD, batch.start_date <= day <= min(batch.end_date, today IST)
 *   the roster       batch_students.joined_at set, admissions.joined true unless the student has
 *                    no admissions row at all (utils/attendanceEligibility.js:55-89), and not on
 *                    hold on the day (hold_periods, or students.is_on_hold with
 *                    hold_applied_at <= day)
 *
 * Pure functions only: routes/classMarking.js supplies the rows and the store does the reading.
 */

const TEACHING_ROLES = new Set(['faculty', 'hod']);
const ADMIN_ROLES = new Set(['admin', 'admin_manager', 'hoo', 'accounts_admin', 'ceo', 'super_admin']);
const GLOBAL_ADMIN_ROLES = new Set(['ceo', 'super_admin']);

const isTeaching = (role) => TEACHING_ROLES.has(role);
const isAdmin = (role) => ADMIN_ROLES.has(role);
const mayMark = (role) => isTeaching(role) || isAdmin(role);

/** Does the substitution cover this day? */
const coversOn = (substitution, day) => substitution.start_date <= day && substitution.end_date >= day;

/** Is the batch inside its dates, and not in the future? Both ends are included. */
function inWindow(batch, day, today) {
  if (!day || !today) return false;
  if (batch.start_date && day < batch.start_date) return false;
  const last = batch.end_date && batch.end_date < today ? batch.end_date : today;
  return day <= last;
}

/** The batches.faculty_id owner, or a substitution covering the day. */
function ownsOrCovers({ batch, day, facultyId, substitutions = [] }) {
  if (!facultyId) return false;
  if (batch.faculty_id === facultyId) return true;
  return substitutions.some((s) => s.batch_id === batch.id
    && s.substitute_faculty_id === facultyId
    && coversOn(s, day));
}

/**
 * The Scheduler's locations.id for an HR branch name. The two vocabularies differ, so the name is
 * the only key they share; trimmed and compared without case, and null when no branch matches.
 */
function branchLocationId(branchName, locations = []) {
  if (!branchName) return null;
  const wanted = String(branchName).trim().toLowerCase();
  if (!wanted) return null;
  const found = locations.find((l) => String(l.name || '').trim().toLowerCase() === wanted);
  return found ? found.id : null;
}

/** An admin marks batches at their own branch; the CEO and super admins mark anywhere. */
function adminCoversBatch({ role, batch, branchName, locations = [] }) {
  if (GLOBAL_ADMIN_ROLES.has(role)) return true;
  const locationId = branchLocationId(branchName, locations);
  return locationId !== null && batch.location_id === locationId;
}

/** A hold_periods row covering the day, or students.is_on_hold with no later applied date. */
function onHoldOn({ periods = [], student, day }) {
  for (const p of periods) {
    if (p.hold_start <= day && (!p.hold_end || p.hold_end >= day)) return true;
  }
  if (student && student.is_on_hold) {
    const applied = student.hold_applied_at ? String(student.hold_applied_at).slice(0, 10) : null;
    return !applied || applied <= day;
  }
  return false;
}

/**
 * admissions.joined must agree with the roster link, unless the student has no admissions row at
 * all (legacy/direct adds), exactly as utils/attendanceEligibility.js:55-89.
 */
function admissionsAllow(studentId, admissions = []) {
  const rows = admissions.filter((a) => a.student_id === studentId);
  if (!rows.length) return true;
  return rows.some((a) => a.joined === true);
}

/** One roster link's eligibility on the day. */
function studentEligible({ link, admissions = [], periods = [], student = null, day }) {
  if (!link || !link.joined_at) return false;
  if (!admissionsAllow(link.student_id, admissions)) return false;
  return !onHoldOn({ periods, student, day });
}

module.exports = {
  TEACHING_ROLES,
  ADMIN_ROLES,
  GLOBAL_ADMIN_ROLES,
  isTeaching,
  isAdmin,
  mayMark,
  coversOn,
  inWindow,
  ownsOrCovers,
  branchLocationId,
  adminCoversBatch,
  onHoldOn,
  admissionsAllow,
  studentEligible,
};
