const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const { invalid, oneQueryValue } = require('../lib/validate');
const { istDay, isCalendarDay, monthBounds, lastMonthStart } = require('../lib/time');

/**
 * Task B1: GET /api/ess/attendance/day?date=YYYY-MM-DD, the three things the Scheduler's punch
 * screen (GET /api/hr/my-attendance, attendancePunchController.js:199-288) does not send and will
 * not be changed to send (ADR-0018): the server's clock, the day's note and HR's remark.
 *
 * It reads the same rows that screen reads, for the caller only:
 *   the day         hr_staff_attendance, the punch screen's columns (attendancePunchController.js:178-179)
 *   the note        hr_staff_attendance.note: an override's reason, a past-day sheet reason,
 *                   "No punch", "No punch-out" or the holiday's name (docs/02-reconciliation.md, B1)
 *   HR's remark     hr_attendance_remarks, which only HR's own screens read today
 *   my remarks      hr_attendance_employee_remarks, the person's own word on the day
 *
 * The day is today (IST) by default, and may be any day of this month or last month: the window
 * the person can also write a remark in (attendancePunchController.js:570-574), extended to the
 * month's end so a CL HR recorded ahead shows too. The tables come with migrations
 * 20261015000004 to 20261023000000, which are not confirmed in production; a missing table or
 * column is 503 MODULE_NOT_INSTALLED, never a day that looks empty.
 */

/** The stored day as the Scheduler stores it, without the note, which has its own field. */
const dayView = (r) => ({
  status: r.status,
  leave_type: r.leave_type ?? null,
  source: r.source ?? null,
  first_in: r.first_in ?? null,
  last_out: r.last_out ?? null,
  worked_minutes: r.worked_minutes ?? null,
  late_minutes: r.late_minutes ?? null,
  early_exit_minutes: r.early_exit_minutes ?? null,
  late_count: r.late_count ?? null,
  late_half_day: Boolean(r.late_half_day),
  late_excused: Boolean(r.late_excused),
  shift_start: r.shift_start ?? null,
  shift_end: r.shift_end ?? null,
});

function attendanceDayRoute({ store, now }) {
  return asyncRoute(async (req, res) => {
    const at = now();
    const today = istDay(at);
    const asked = oneQueryValue(req.query.date);
    if (asked !== undefined && (asked === null || !isCalendarDay(asked))) throw invalid(MESSAGES.DATE_FORMAT);
    const date = asked ?? today;
    if (date < lastMonthStart(today) || date > monthBounds(today).to) {
      throw new HttpError(400, 'DAY_OUT_OF_RANGE', MESSAGES.DAY_OUT_OF_RANGE);
    }

    const employeeId = req.auth.employee.id;
    const [row, hrRemark, mine] = await Promise.all([
      store.getDayRow(employeeId, date),
      store.getHrRemark(employeeId, date),
      store.listMyRemarks(employeeId, date),
    ]);
    res.json({
      // The moment this was answered, so the app can tell how far off the phone's clock is.
      server_now: at.toISOString(),
      date,
      day: row ? dayView(row) : null,
      note: row ? row.note ?? null : null,
      hr_remark: hrRemark ? { remarks: hrRemark.remarks, updated_at: hrRemark.updated_at } : null,
      my_remarks: mine.map((r) => ({ day: r.day, remarks: r.remarks, updated_at: r.updated_at })),
    });
  });
}

module.exports = { attendanceDayRoute };
