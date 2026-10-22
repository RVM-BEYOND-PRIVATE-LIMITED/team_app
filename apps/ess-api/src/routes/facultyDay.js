const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const { invalid, oneQueryValue } = require('../lib/validate');
const { istDay, isCalendarDay, monthBounds, lastMonthStart } = require('../lib/time');
const F = require('../policy/facultyDay');

/**
 * Task H7 (Phase 2D): GET /api/ess/me/faculty-day?date=YYYY-MM-DD, the faculty "my day" and the
 * indicators card, read from the Scheduler's teaching tables (docs/02-reconciliation.md, H7).
 *
 * A portal login whose account carries a faculty record (`users.faculty_id`); anybody else is 403
 * NOT_FACULTY, an attendance session included -- teaching roles sign in at the portal, as they do
 * on the web. The day is today (IST) by default, in the same window as the attendance day read.
 *
 * Today's sessions are the batches that run this weekday inside their dates, owned or covered by
 * a substitution -- substitution batches are not branch-filtered, as the Scheduler's own report
 * leaves them (attendanceController.js:539). A session is marked when any student_attendance row
 * exists for that batch and date. The card counts: students joined and not on hold, the sessions
 * marked today and this month, and the remarks still due.
 *
 * Nothing here reads a student's name, phone, remarks or fee: the card counts, it does not list.
 */

/** Rows here are the teaching tables; a missing one is 503, never a day that looks empty. */
function facultyDayRoute({ store, now }) {
  return asyncRoute(async (req, res) => {
    const at = now();
    const today = istDay(at);
    const user = req.auth.kind === 'portal' ? await store.getUser(req.auth.userId) : null;
    if (!user || !user.faculty_id) throw new HttpError(403, 'NOT_FACULTY', MESSAGES.NOT_FACULTY);

    const asked = oneQueryValue(req.query.date);
    if (asked !== undefined && (asked === null || !isCalendarDay(asked))) throw invalid(MESSAGES.DATE_FORMAT);
    const date = asked ?? today;
    if (date < lastMonthStart(today) || date > monthBounds(today).to) {
      throw new HttpError(400, 'DAY_OUT_OF_RANGE', MESSAGES.DAY_OUT_OF_RANGE);
    }

    const facultyId = user.faculty_id;
    const [own, substitutions] = await Promise.all([
      store.listBatchesForFaculty(facultyId),
      store.listSubstitutionsForSubstitute(facultyId),
    ]);
    const ownIds = new Set(own.map((b) => b.id));
    const coveredIds = [...new Set(substitutions.filter((s) => F.coversOn(s, date)).map((s) => s.batch_id))]
      .filter((id) => !ownIds.has(id));
    const covered = coveredIds.length ? await store.listBatchesByIds(coveredIds) : [];
    const coveredSet = new Set(coveredIds);
    const batches = [...own, ...covered];
    const batchIds = batches.map((b) => b.id);

    const month = { from: monthBounds(date).from, to: date };
    const [links, attendance, alerts, locations] = await Promise.all([
      store.listBatchStudents(batchIds),
      store.listAttendanceForBatchesBetween(batchIds, month.from, date),
      store.listPendingRemarksFor(batchIds, date),
      store.listLocations(),
    ]);
    const locationName = new Map(locations.map((l) => [l.id, l.name]));

    const joinedLinks = links.filter((l) => l.joined_at);
    const joinedIds = [...new Set(joinedLinks.map((l) => l.student_id))];
    const admissions = joinedIds.length ? await store.listAdmissionsJoined(joinedIds) : [];
    // A roster link is not a join: admissions.joined must agree, unless the student has no
    // admissions record at all (legacy/direct adds), exactly as utils/attendanceEligibility.js:55-89.
    const anyJoined = new Set(admissions.filter((a) => a.joined === true).map((a) => a.student_id));
    const notJoined = new Set(admissions.filter((a) => a.joined !== true).map((a) => a.student_id));
    for (const id of anyJoined) notJoined.delete(id);
    const joined = joinedLinks.filter((l) => !notJoined.has(l.student_id));
    const studentIds = [...new Set(links.map((l) => l.student_id))];
    const [periods, onHoldRows] = studentIds.length
      ? await Promise.all([store.listHoldPeriods(studentIds), store.listStudentsOnHold(studentIds)])
      : [[], []];
    const periodsBy = new Map();
    for (const p of periods) {
      if (!periodsBy.has(p.student_id)) periodsBy.set(p.student_id, []);
      periodsBy.get(p.student_id).push(p);
    }
    const holdRowBy = new Map(onHoldRows.map((s) => [s.id, s]));
    const isActive = (studentId) => !F.onHoldOn({
      periods: periodsBy.get(studentId) || [],
      student: holdRowBy.get(studentId) || null,
      day: date,
    });

    const joinedByBatch = new Map();
    for (const l of joined) joinedByBatch.set(l.batch_id, (joinedByBatch.get(l.batch_id) || 0) + 1);
    const marked = new Set(attendance.map((a) => `${a.batch_id}:${a.date}`));

    const expectedOn = (batch, day) => F.batchActiveOn(batch, day);
    let monthExpected = 0;
    let monthMarked = 0;
    for (const batch of batches) {
      for (const day of F.daysBetween(month.from, month.to)) {
        if (!expectedOn(batch, day)) continue;
        monthExpected += 1;
        if (marked.has(`${batch.id}:${day}`)) monthMarked += 1;
      }
    }

    const sessions = batches
      .filter((b) => expectedOn(b, date))
      .map((b) => ({
        id: b.id,
        name: b.name,
        start_time: b.start_time ?? null,
        end_time: b.end_time ?? null,
        location_id: b.location_id ?? null,
        location_name: locationName.get(b.location_id) ?? null,
        covered: coveredSet.has(b.id),
        students: joinedByBatch.get(b.id) || 0,
        marked: marked.has(`${b.id}:${date}`),
      }))
      .sort((a, b) => String(a.start_time ?? '').localeCompare(String(b.start_time ?? '')) || a.name.localeCompare(b.name));

    const activeStudents = joined.filter((l) => isActive(l.student_id)).length;
    const markedToday = sessions.filter((s) => s.marked).length;
    const withoutAttendance = sessions.filter((s) => !s.marked).length;

    res.json({
      date,
      faculty_id: facultyId,
      sessions,
      pending_remarks: alerts.length,
      indicators: {
        sessions_today: sessions.length,
        marked_today: markedToday,
        today_percentage: F.percentage(markedToday, sessions.length),
        month_expected: monthExpected,
        month_marked: monthMarked,
        month_percentage: F.percentage(monthMarked, monthExpected),
        active_students: activeStudents,
        total_students: studentIds.length,
        sessions_without_attendance: withoutAttendance,
      },
    });
  });
}

module.exports = { facultyDayRoute };
