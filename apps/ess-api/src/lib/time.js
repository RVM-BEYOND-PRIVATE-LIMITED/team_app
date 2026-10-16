/**
 * RVM's days turn over at midnight IST (Asia/Kolkata), whatever zone the server's clock is in.
 *
 * The same arithmetic as the Scheduler's istDay (services/attendancePunch.js:172 at c28b9ca).
 * India has no daylight saving, so a fixed +05:30 is exact and needs no time-zone database.
 */
const IST_OFFSET_MINUTES = 330;

const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;

/** The IST calendar day of an instant, as YYYY-MM-DD. */
const istDay = (instant) => new Date(instant.getTime() + IST_OFFSET_MINUTES * 60 * 1000).toISOString().slice(0, 10);

/**
 * Whether a value is a real calendar day written YYYY-MM-DD. 2026-02-30 matches the pattern
 * but is not a day; Postgres refuses it, and the Scheduler answers such a day with a 500
 * (docs/02-reconciliation.md, B1), so the ESS refuses it up front.
 */
function isCalendarDay(value) {
  if (typeof value !== 'string' || !DAY_RE.test(value)) return false;
  const t = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(t.getTime()) && t.toISOString().slice(0, 10) === value;
}

/** The Scheduler's addDays (services/attendanceRules.js:66), on YYYY-MM-DD days. */
const addDays = (day, n) => new Date(Date.parse(`${day}T00:00:00Z`) + n * 86400000).toISOString().slice(0, 10);

/** The first and last day of a day's month (services/attendanceRules.js:69-72). */
function monthBounds(day) {
  const [y, m] = day.slice(0, 7).split('-').map(Number);
  return { from: `${day.slice(0, 7)}-01`, to: new Date(Date.UTC(y, m, 0)).toISOString().slice(0, 10) };
}

/** The 1st of the month before a day's month, as the Scheduler's remarks window works it out (attendancePunchController.js:571). */
const lastMonthStart = (day) => monthBounds(addDays(`${day.slice(0, 7)}-01`, -1)).from;

/** The instant an IST day starts, so a day filter on a timestamp column means the day RVM sees. */
const istDayStart = (day) => new Date(`${day}T00:00:00+05:30`);

/**
 * The same calendar day `years` years earlier. A 29 February with no counterpart becomes the
 * 28th, so somebody born on a leap day is old enough on the 28th, never a day late.
 */
function yearsBefore(day, years) {
  const y = Number(day.slice(0, 4)) - years;
  const candidate = `${String(y).padStart(4, '0')}${day.slice(4)}`;
  return isCalendarDay(candidate) ? candidate : `${String(y).padStart(4, '0')}-02-28`;
}

module.exports = { IST_OFFSET_MINUTES, istDay, isCalendarDay, addDays, monthBounds, lastMonthStart, istDayStart, yearsBefore };
