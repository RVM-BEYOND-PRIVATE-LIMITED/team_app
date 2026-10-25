/**
 * The request types and their monthly limits: KP's decisions of 16 Oct 2026
 * (docs/03-decisions.md, "Request limits").
 *
 * One table, so that the request endpoints count against the same numbers the app shows. Limits
 * are per employee per calendar month. HR is to be able to change them later (task C6); until
 * then this file is where they live.
 *
 *   limit null   no monthly limit (each request still needs approval)
 *   unit         'count' counts requests; 'minutes' adds up the minutes asked for in the month
 *   phase        the build phase that ships the request type (ADR-0013)
 *
 * Work from home is offered only to the employees HR selects, each with their own monthly limit
 * (KP, 22 Oct 2026): there is no generic row for it, and the allowance in hr_ess_wfh_allowances is
 * the limit. The table's own row stays switched off here, with limit 0, so a caller without an
 * allowance gets exactly the old answer. Leave without pay has no limit until KP sets one (still
 * open).
 */
const REQUEST_TYPES = Object.freeze([
  { type: 'on_duty', offered: true, limit: null, unit: 'count', phase: 1 },
  { type: 'fix_a_day', offered: true, limit: 3, unit: 'count', phase: 1 },
  { type: 'excuse_late', offered: true, limit: 3, unit: 'count', phase: 1 },
  { type: 'short_leave', offered: true, limit: 180, unit: 'minutes', phase: 2 },
  // One CL day a month until HR changes it. A half day costs 0.5, so two half days fit.
  { type: 'leave_cl', offered: true, limit: 1, unit: 'days', phase: 1 },
  { type: 'leave_lwp', offered: true, limit: null, unit: 'days', phase: 1 },
  { type: 'wfh', offered: false, limit: 0, unit: 'count', phase: 1 },
].map((t) => Object.freeze(t)));

/** Last month's requests close on the 5th of this month: payroll is run from them after that. */
const PAYROLL_CUTOFF_DAY = 5;

/** A request may be for a day this month or last month, never earlier. */
const REACH_BACK_MONTHS = 1;

const requestType = (type) => REQUEST_TYPES.find((t) => t.type === type) || null;

const offeredRequestTypes = () => REQUEST_TYPES.filter((t) => t.offered).map((t) => t.type);

/**
 * The effective limit of one type: the number from hr_ess_request_limits when the table has the
 * row (task C6; HR changes them through the HR endpoint), and this file's default otherwise --
 * before the migration, or for a row somebody deleted by hand. Null means no limit.
 */
function effectiveLimit(t, limitRows = null) {
  const row = (limitRows || []).find((r) => r.type === t.type);
  if (!row) return t.limit;
  return t.unit === 'minutes' ? (row.limit_minutes ?? null) : (row.limit_count ?? null);
}

/**
 * The `requests` block of the capability document and of the balances reply, as fresh objects so
 * a caller cannot edit the table. With `limitRows` (hr_ess_request_limits), the numbers are the
 * ones HR set; without them (a caller that could not read the table), this file's defaults.
 */
const requestPolicy = (limitRows = null) => ({
  types: REQUEST_TYPES.map((t) => ({ ...t, limit: effectiveLimit(t, limitRows) })),
  payroll_cutoff_day: PAYROLL_CUTOFF_DAY,
  reach_back_months: REACH_BACK_MONTHS,
});

module.exports = {
  REQUEST_TYPES,
  PAYROLL_CUTOFF_DAY,
  REACH_BACK_MONTHS,
  requestType,
  offeredRequestTypes,
  effectiveLimit,
  requestPolicy,
};
