/**
 * Phase 2D (task H7): the faculty "my day" read and the indicators card. The rules the Scheduler's
 * own report applies, copied where the app needs them and cited where they are his:
 *
 *   a session      a batch runs on a weekday its `days_of_week` names or its `schedule` numbers
 *                  (public_schema_backup.sql:1474-1490), inside its start and end dates
 *                  (controllers/attendanceController.js:637-676), owned or covered by a
 *                  substitution whose range includes the day (attendanceController.js:537-547)
 *   a marked day   any row in student_attendance for that batch and date
 *                  (attendanceController.js:608-621)
 *   a joined student  batch_students.joined_at set (utils/attendanceEligibility.js:23-53)
 *   on hold        a hold_periods row covering the day (utils/attendanceEligibility.js:55-80),
 *                  or students.is_on_hold with no period recorded yet
 *                  (attendanceController.js:564-586)
 *   pending remarks   unresolved pending_alerts of type 'absent_remarks_missing' for the day
 *                  (controllers/attendanceController.js:149-162)
 *
 * The percentages are the report's: marked sessions over expected sessions, in whole percent, and
 * zero when nothing was expected -- never a division by nothing. Nothing here reads a student's
 * name, phone or remarks: the card counts, it does not list.
 */

const DAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

/** The IST calendar day as a UTC date, for weekday arithmetic only. */
const asUtc = (day) => new Date(`${day}T00:00:00Z`);

/** 1 Monday to 7 Sunday, as batches.schedule numbers them ({1..6} by default). */
function isoWeekday(day) {
  const d = asUtc(day).getUTCDay();
  return d === 0 ? 7 : d;
}

function dayName(day) {
  return DAY_NAMES[asUtc(day).getUTCDay()];
}

/** Is the batch running on this day at all: inside its dates and on one of its weekdays. */
function batchActiveOn(batch, day) {
  if (batch.start_date && day < batch.start_date) return false;
  if (batch.end_date && day > batch.end_date) return false;
  const names = (batch.days_of_week || []).map((s) => String(s).trim().toLowerCase());
  const schedule = Array.isArray(batch.schedule) ? batch.schedule.map(Number) : [];
  const iso = isoWeekday(day);
  return names.includes(dayName(day).toLowerCase())
    || schedule.includes(iso)
    || (iso === 7 && schedule.includes(0));
}

/** Does the substitution cover this day? */
const coversOn = (substitution, day) => substitution.start_date <= day && substitution.end_date >= day;

/** A hold_periods row covering the day, or the students.is_on_hold row with no period yet. */
function onHoldOn({ periods, student, day }) {
  for (const p of periods) {
    if (p.hold_start <= day && (!p.hold_end || p.hold_end >= day)) return true;
  }
  if (student && student.is_on_hold) {
    const applied = student.hold_applied_at ? String(student.hold_applied_at).slice(0, 10) : null;
    return !applied || applied <= day;
  }
  return false;
}

/** Every day from `from` to `to`, both ends included. */
function daysBetween(from, to) {
  const out = [];
  for (let d = asUtc(from); d <= asUtc(to); d.setUTCDate(d.getUTCDate() + 1)) {
    out.push(d.toISOString().slice(0, 10));
  }
  return out;
}

/** Marked over expected, in whole percent; nothing expected is zero, never a division by nothing. */
const percentage = (marked, expected) => (expected > 0 ? Math.round((marked / expected) * 100) : 0);

module.exports = {
  isoWeekday,
  dayName,
  batchActiveOn,
  coversOn,
  onHoldOn,
  daysBetween,
  percentage,
};
