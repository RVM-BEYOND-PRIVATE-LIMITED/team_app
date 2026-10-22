const { HttpError, MESSAGES, asyncRoute, notAuthenticated } = require('../lib/errors');
const {
  invalid, idParam, isUuid, isPlainObject, oneQueryValue, optionalText, requiredText, chars, bodyWith,
} = require('../lib/validate');
const { istDay, isCalendarDay } = require('../lib/time');
const { recordAfter } = require('../lib/audit');
const C = require('../policy/classMarking');

/**
 * Task H1 (Phase 2D, decision 8): faculty class marking.
 *
 * Three routes, all behind employeeAuth and all portal screens:
 *
 *   GET   /api/ess/me/batches/{id}/roster?date=YYYY-MM-DD
 *   POST  /api/ess/me/batches/{id}/attendance
 *   PATCH /api/ess/me/batches/{id}/attendance/{date}/remarks
 *
 * The Scheduler's own marking endpoint has no server-side checks (J1), so the six rules live
 * here: the role, the branch, ownership or a covering substitution, the date window, the roster
 * and its eligibility, and the lock a teaching role hits once the day has rows. Admin roles may
 * correct a day; a teaching role cannot. The remark route is the after-marking path: it changes
 * no mark and is how an absent student's reason is filled in, so the lock does not close it.
 *
 * The rows written are the Scheduler's own: student_attendance (the day's marks and remarks)
 * and pending_alerts (an 'absent_remarks_missing' alert resolved when the student is present or
 * the reason is filled). The roster returns a name and an admission number and nothing else
 * about a student: never a phone, a password hash, a fee or a personal detail.
 */

const ABSENT = 'absent';
const PRESENT = 'present';

const notYours = () => new HttpError(403, 'CLASS_NOT_YOURS', MESSAGES.CLASS_NOT_YOURS);
const roleDenied = () => new HttpError(403, 'CLASS_ROLE_DENIED', MESSAGES.CLASS_ROLE_DENIED);
const windowRefused = () => new HttpError(403, 'CLASS_WINDOW', MESSAGES.CLASS_WINDOW);
const batchMissing = () => new HttpError(404, 'BATCH_NOT_FOUND', MESSAGES.BATCH_NOT_FOUND);
const alreadyMarked = () => new HttpError(409, 'CLASS_ALREADY_MARKED', MESSAGES.CLASS_ALREADY_MARKED);
const notAbsent = () => new HttpError(409, 'CLASS_NOT_ABSENT', MESSAGES.CLASS_NOT_ABSENT);

/** The caller's marking role, and the faculty record a teaching role needs (never a student's). */
async function loadViewer(store, req) {
  const role = req.auth.kind === 'portal' ? req.auth.role : null;
  if (!C.mayMark(role)) throw roleDenied();
  if (!C.isTeaching(role)) return { role, facultyId: null };
  const user = await store.getUser(req.auth.userId);
  if (!user) throw notAuthenticated(MESSAGES.SIGN_IN_AGAIN);
  return { role, facultyId: user.faculty_id ?? null };
}

async function loadBatch(store, id) {
  const batch = await store.getBatch(id);
  if (!batch) throw batchMissing();
  return batch;
}

/**
 * Branch and ownership. A teaching caller needs the batch's faculty_id or a substitution that
 * covers the day. An admin caller needs the batch's location to be their own branch, mapped by
 * name; the CEO and super admins are global.
 */
async function assertAccess({ store, req, viewer, batch, day }) {
  if (C.isTeaching(viewer.role)) {
    const substitutions = viewer.facultyId
      ? await store.listSubstitutionsForSubstitute(viewer.facultyId)
      : [];
    if (!C.ownsOrCovers({ batch, day, facultyId: viewer.facultyId, substitutions })) throw notYours();
    return;
  }
  let branchName = null;
  let locations = [];
  if (!C.GLOBAL_ADMIN_ROLES.has(viewer.role)) {
    const branch = req.auth.employee.branch_id ? await store.getBranch(req.auth.employee.branch_id) : null;
    branchName = branch ? branch.name : null;
    locations = await store.listLocations();
  }
  if (!C.adminCoversBatch({ role: viewer.role, batch, branchName, locations })) throw notYours();
}

function assertWindow(batch, day, today) {
  if (!C.inWindow(batch, day, today)) throw windowRefused();
}

function readDay(value) {
  if (!isCalendarDay(value)) throw invalid(MESSAGES.DATE_FORMAT);
  return value;
}

/**
 * The eligible roster for the day: every link whose joined_at is set, whose admissions agree,
 * and whose student is not on hold. H7 applies the same rules (routes/facultyDay.js).
 */
async function rosterContext({ store, batch, day }) {
  const links = (await store.listBatchStudents([batch.id])).filter((l) => l.joined_at);
  const studentIds = [...new Set(links.map((l) => l.student_id))];
  const [admissions, periods, holdRows, students] = await Promise.all([
    store.listAdmissionsJoined(studentIds),
    store.listHoldPeriods(studentIds),
    store.listStudentsOnHold(studentIds),
    store.listStudentsFor(studentIds),
  ]);
  const periodsBy = new Map();
  for (const p of periods) {
    if (!periodsBy.has(p.student_id)) periodsBy.set(p.student_id, []);
    periodsBy.get(p.student_id).push(p);
  }
  const holdBy = new Map(holdRows.map((s) => [s.id, s]));
  const studentBy = new Map(students.map((s) => [s.id, s]));

  const eligible = links.filter((link) => C.studentEligible({
    link,
    admissions,
    periods: periodsBy.get(link.student_id) || [],
    student: holdBy.get(link.student_id) || null,
    day,
  }));
  const eligibleIds = new Set(eligible.map((l) => l.student_id));
  return { studentBy, eligibleIds };
}

/** What the roster says about one student: a name, an admission number and the day's mark. */
function studentView(student, row) {
  const marked = row ? (row.is_present ? PRESENT : ABSENT) : null;
  return {
    id: student ? student.id : null,
    full_name: student ? student.name ?? null : null,
    admission_number: student ? student.admission_number ?? null : null,
    marked,
    absent_reason: row ? row.absent_reason ?? null : null,
    follow_up_comment: row ? row.follow_up_comment ?? null : null,
  };
}

/** The body's attendance rows, each once, with the mark rules from the plan. */
function attendanceItems(body) {
  if (!Array.isArray(body.attendance) || body.attendance.length < 1 || body.attendance.length > 500) {
    throw invalid(MESSAGES.CLASS_ATTENDANCE);
  }
  const seen = new Set();
  return body.attendance.map((item) => {
    if (!isPlainObject(item)
      || Object.keys(item).some((k) => !['student_id', 'present', 'absent_reason', 'follow_up_comment'].includes(k))) {
      throw invalid(MESSAGES.CLASS_ATTENDANCE);
    }
    if (!isUuid(item.student_id)) throw invalid(MESSAGES.CLASS_ATTENDANCE);
    const studentId = item.student_id.toLowerCase();
    if (seen.has(studentId)) throw invalid(MESSAGES.CLASS_ATTENDANCE);
    seen.add(studentId);
    if (typeof item.present !== 'boolean') throw invalid(MESSAGES.CLASS_ATTENDANCE);
    const absentReason = optionalText(item.absent_reason);
    if (absentReason === undefined) throw invalid(MESSAGES.CLASS_REMARK);
    if (absentReason !== null && (chars(absentReason) < 3 || chars(absentReason) > 500)) throw invalid(MESSAGES.CLASS_REMARK);
    const followUp = optionalText(item.follow_up_comment);
    if (followUp === undefined || (followUp !== null && chars(followUp) > 1000)) throw invalid(MESSAGES.CLASS_REMARK);
    return {
      student_id: studentId,
      present: item.present,
      absent_reason: absentReason,
      follow_up_comment: followUp,
    };
  });
}

/** GET /api/ess/me/batches/{id}/roster?date=YYYY-MM-DD */
function classRoster({ store, now }) {
  return asyncRoute(async (req, res) => {
    const batchId = idParam(req.params.id);
    const asked = oneQueryValue(req.query.date);
    if (asked === undefined || asked === null) throw invalid(MESSAGES.DATE_FORMAT);
    const day = readDay(asked);

    const viewer = await loadViewer(store, req);
    const batch = await loadBatch(store, batchId);
    await assertAccess({ store, req, viewer, batch, day });
    assertWindow(batch, day, istDay(now()));

    const [ctx, rows] = await Promise.all([
      rosterContext({ store, batch, day }),
      store.listClassAttendance(batch.id, day),
    ]);
    const rowBy = new Map(rows.map((r) => [r.student_id, r]));
    const students = [...ctx.eligibleIds]
      .map((id) => studentView(ctx.studentBy.get(id) || { id }, rowBy.get(id) || null))
      .sort((a, b) => String(a.full_name || '').localeCompare(String(b.full_name || '')) || String(a.id).localeCompare(String(b.id)));

    const marked = rows.length > 0;
    res.json({
      batch: { id: batch.id, name: batch.name },
      date: day,
      already_marked: marked,
      can_edit: C.isAdmin(viewer.role) ? true : !marked,
      students,
    });
  });
}

/** POST /api/ess/me/batches/{id}/attendance */
function saveClassAttendance({ store, now }) {
  return asyncRoute(async (req, res) => {
    const batchId = idParam(req.params.id);
    const body = bodyWith(req, ['date', 'attendance']);
    const day = readDay(body.date);
    const items = attendanceItems(body);
    const at = now();

    const viewer = await loadViewer(store, req);
    const batch = await loadBatch(store, batchId);
    await assertAccess({ store, req, viewer, batch, day });
    assertWindow(batch, day, istDay(at));

    const ctx = await rosterContext({ store, batch, day });
    if (items.some((i) => !ctx.eligibleIds.has(i.student_id))) throw invalid(MESSAGES.CLASS_ROSTER);

    const existing = await store.listClassAttendance(batch.id, day);
    // The lock is a teaching role's: the day is marked once. An admin may correct it.
    if (C.isTeaching(viewer.role) && existing.length) throw alreadyMarked();

    const stamp = at.toISOString();
    const rows = items.map((item) => ({
      batch_id: batch.id,
      student_id: item.student_id,
      date: day,
      is_present: item.present,
      // A present student has no absent reason or follow-up: the mark is the truth of the day.
      absent_reason: item.present ? null : item.absent_reason,
      follow_up_comment: item.present ? null : item.follow_up_comment,
      remarks_updated_by: req.auth.employee.full_name,
      remarks_updated_at: stamp,
    }));
    await store.saveClassAttendance(rows);

    const present = items.filter((i) => i.present).length;
    const absent = items.length - present;
    // Present, or absent with the reason already given: either way no 'absent_remarks_missing'
    // alert is due for this student and day. The PATCH route resolves one filled later.
    const resolvedIds = items.filter((i) => i.present || i.absent_reason !== null).map((i) => i.student_id);
    if (resolvedIds.length) {
      await store.resolveAbsentRemarkAlerts({
        batchId: batch.id,
        studentIds: resolvedIds,
        day,
        by: req.auth.employee.full_name,
        at: stamp,
      });
    }
    await recordAfter(store, req, {
      action: 'class.attendance.marked',
      // Counts only, never a student's name or id.
      details: { batch_id: batch.id, date: day, present, absent },
    });

    res.json({
      batch: { id: batch.id, name: batch.name },
      date: day,
      counts: { present, absent, total: items.length },
    });
  });
}

/** PATCH /api/ess/me/batches/{id}/attendance/{date}/remarks */
function updateClassRemark({ store, now }) {
  return asyncRoute(async (req, res) => {
    const batchId = idParam(req.params.id);
    const day = readDay(req.params.date);
    const body = bodyWith(req, ['student_id', 'absent_reason', 'follow_up_comment']);
    if (!isUuid(body.student_id)) throw invalid(MESSAGES.INVALID_ID);
    const studentId = body.student_id.toLowerCase();
    const absentReason = requiredText(body.absent_reason, { min: 3, max: 500, message: MESSAGES.CLASS_REMARK });
    const followUp = optionalText(body.follow_up_comment);
    if (followUp === undefined || (followUp !== null && chars(followUp) > 1000)) throw invalid(MESSAGES.CLASS_REMARK);
    const at = now();

    const viewer = await loadViewer(store, req);
    const batch = await loadBatch(store, batchId);
    await assertAccess({ store, req, viewer, batch, day });
    assertWindow(batch, day, istDay(at));

    const ctx = await rosterContext({ store, batch, day });
    if (!ctx.eligibleIds.has(studentId)) throw invalid(MESSAGES.CLASS_ROSTER);

    const rows = await store.listClassAttendance(batch.id, day);
    const row = rows.find((r) => r.student_id === studentId);
    // Only an absent student carries a reason; a present (or unmarked) one has nothing to change.
    if (!row || row.is_present !== false) throw notAbsent();

    const saved = await store.updateClassRemark({
      batchId: batch.id,
      studentId,
      day,
      absentReason,
      followUpComment: followUp,
      by: req.auth.employee.full_name,
      at: at.toISOString(),
    });
    if (!saved) throw notAbsent();

    // A filled reason is what the Scheduler's own alert waits for.
    await store.resolveAbsentRemarkAlerts({
      batchId: batch.id,
      studentIds: [studentId],
      day,
      by: req.auth.employee.full_name,
      at: at.toISOString(),
    });
    await recordAfter(store, req, {
      action: 'class.remark.changed',
      details: {
        batch_id: batch.id,
        date: day,
        student_id: studentId,
        before: row.absent_reason ?? null,
        after: absentReason,
      },
    });

    res.json({
      batch: { id: batch.id, name: batch.name },
      date: day,
      student: studentView(ctx.studentBy.get(studentId) || { id: studentId }, saved),
    });
  });
}

module.exports = {
  classRoster,
  saveClassAttendance,
  updateClassRemark,
  loadViewer,
  rosterContext,
  attendanceItems,
};
