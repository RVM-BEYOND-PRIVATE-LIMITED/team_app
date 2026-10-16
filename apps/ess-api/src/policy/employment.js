/**
 * Whether somebody is still on strength, by the Scheduler's own rule
 * (controllers/hr/attendancePunchController.js:88-90 at c28b9ca), so that a person who can no
 * longer punch can no longer use the app either.
 *
 * Archived, exited, or past the last working day means no. The day of exit itself still counts:
 * the last working day is a working day. 'fired' and 'terminated' need no test of their own,
 * because hr_set_employment_status archives them in the same transaction
 * (supabase/migrations/20260917000000_hr_employment_lifecycle.sql), which the Scheduler's rule
 * relies on too.
 *
 * `today` is the IST day (lib/time.js istDay); date_of_exit arrives from PostgREST as
 * YYYY-MM-DD, so comparing the two strings compares the dates.
 */
const isActive = (employee, today) =>
  !employee.is_archived
  && employee.employment_status !== 'exited'
  && !(employee.date_of_exit && employee.date_of_exit < today);

module.exports = { isActive };
