const { HttpError } = require('../lib/errors');

/**
 * The attendance rules the request decisions need on the Node side, mirroring the Scheduler's
 * own services/attendanceRules.js where it is used after an override:
 *
 *   ensureShiftSnapshot  the shift a day is judged by, copied onto the day row when it has none
 *                        (ensureSnapshot, attendanceRules.js:214-236). The Scheduler's controller
 *                        runs it right after hr_attendance_apply_override; the ESS's decide route
 *                        runs this right after the decision function, so a day a fix a day created
 *                        is judged late/early like any punched day.
 *   recomputeMonth       hr_attendance_recompute for the month of the day ("the month is recomputed
 *                        after", docs/06-backend-phases.md Phase 1C).
 *
 * Everything here is a best effort: the Scheduler treats missing rules columns or functions as
 * "the rules are off", never as a failed punch (attendanceRules.js:20-22), and a decision that
 * already wrote its day and its history must not fail because a later read found the shifts
 * migration unapplied.
 */

/** The Scheduler's default half-day threshold (services/attendancePunch.js:20). */
const HALF_DAY_MINUTES = 240;

/** 0 = Sunday ... 6 = Saturday, for a YYYY-MM-DD (attendanceRules.js:64). */
const weekday = (day) => new Date(`${day}T00:00:00Z`).getUTCDay();

/** The shift a day is judged by: Saturday uses the Saturday shift when assigned, and so on. */
function shiftIdFor(shifts, day) {
  if (!shifts) return null;
  const wd = weekday(day);
  if (wd === 6) return shifts.saturday_shift_id || shifts.shift_id || null;
  if (wd === 0) return shifts.sunday_shift_id || shifts.shift_id || null;
  return shifts.shift_id || null;
}

/** The holiday covering a person that day; a branch's own holiday wins over a company one. */
function holidayFor(holidays, day, branchId) {
  const same = (holidays || []).filter((h) => h.day === day);
  return same.find((h) => h.branch_id && h.branch_id === branchId) || same.find((h) => !h.branch_id) || null;
}

/**
 * Copy the shift onto the person's day row when it has none yet. Nothing happens for somebody
 * HR has not put on a shift, for a row that already carries a shift, or when the columns are not
 * there yet; a week off or a holiday gets the empty snapshot (nobody is late on a day off).
 *
 * @returns whether the row was written
 */
async function ensureShiftSnapshot({ store, employeeId, branchId, day }) {
  try {
    const row = await store.getDaySnapshotState(employeeId, day);
    if (!row || row.shift_start) return false;
    const shifts = await store.getEmployeeShifts(employeeId);
    const onAnyShift = !!shifts && !!(shifts.shift_id || shifts.saturday_shift_id || shifts.sunday_shift_id);
    if (!onAnyShift) return false;
    const weekOffs = Array.isArray(shifts.week_off_days) ? shifts.week_off_days : [0];
    const holidays = await store.listHolidays(day, day);
    let snapshot = { shift_id: null, shift_start: null, shift_end: null, grace_minutes: null };
    if (!holidayFor(holidays, day, branchId) && !weekOffs.includes(weekday(day))) {
      const shiftId = shiftIdFor(shifts, day);
      const shift = shiftId ? await store.getShift(shiftId) : null;
      if (shift) {
        snapshot = { shift_id: shift.id, shift_start: shift.start_time, shift_end: shift.end_time, grace_minutes: shift.grace_minutes };
      }
    }
    await store.setDaySnapshot(row.id, snapshot);
    return true;
  } catch (e) {
    // The rules being absent is the deploy window, not a failure (attendanceRules.js:20-22); the
    // nightly settle re-counts the month anyway. Anything else is logged and still not raised:
    // the decision the caller made stands.
    if (!(e instanceof HttpError && e.code === 'MODULE_NOT_INSTALLED')) {
      console.error(`[ess] shift snapshot for ${day} failed: ${e && e.message ? e.message : e}`);
    }
    return false;
  }
}

/** Recompute late/early/the third-late half day for the month of `day`, best effort. */
async function recomputeMonth({ store, employeeId, day, today }) {
  try {
    await store.recomputeAttendance({ employeeIds: [employeeId], day, today, halfDayMinutes: HALF_DAY_MINUTES });
  } catch (e) {
    console.error(`[ess] recompute for ${day} failed: ${e && e.message ? e.message : e}`);
  }
}

module.exports = { HALF_DAY_MINUTES, weekday, shiftIdFor, holidayFor, ensureShiftSnapshot, recomputeMonth };
