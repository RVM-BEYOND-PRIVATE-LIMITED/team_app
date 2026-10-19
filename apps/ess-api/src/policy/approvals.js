const { chainOf } = require('./me');
const { isActive } = require('./employment');
const { canDecideAny } = require('./requests');

/**
 * Phase 2D (task D4): the request's approval chain, the levels it skips, and the escalation the
 * hourly job records (db/migrations/20261111000002_hr_ess_approval_escalations.sql).
 *
 * The chain is the reporting line (decision 1), walked manager_id upward, exactly as the org view
 * walks it (policy/me.js chainOf). Two things move a request up it:
 *
 * - A skipped level is one that cannot decide that day: the person is the requester themselves,
 *   no longer on strength (isActive), or the sheet records them on leave that day. The FIRST
 *   level that is not skipped may decide at once; a level below it may not, and HR, the CEO and
 *   super admins still decide anything (ATTENDANCE_OVERRIDE_ROLES, as always).
 *
 * - Time-based escalation: a request still pending after ESCALATE_AFTER_DAYS is escalated by the
 *   job (src/jobs/approvals.js) to the next level of the chain that has not been escalated yet,
 *   falling back to HR when the chain runs out. The escalation is recorded once per person (the
 *   table's unique key), and the person is told by a notification in the 'approvals' category.
 *
 *   KP to confirm: two IST days is the build's default, judged on created_at (the IST day
 *   difference), and one escalation a level. "Configurable chains per request type" is NOT built
 *   (docs/06-backend-phases.md, Phase 2D) -- it needs KP's rule first.
 */

const ESCALATE_AFTER_DAYS = 2;

/**
 * Why this level cannot decide the request today, or null when it may. `offOnDay` is the set of
 * employee ids the sheet records on leave for the request's day.
 */
function skipReason({ approver, requesterId, today, offOnDay }) {
  if (approver.id === requesterId) return 'same_person';
  if (!isActive(approver, today)) return 'not_active';
  if (offOnDay && offOnDay.has(approver.id)) return 'on_leave';
  return null;
}

/**
 * The reporting line above `requester`, first manager first, each with the reason it is skipped
 * (or null) for `today`. `byId` is the directory's map (store.listActiveEmployees); the
 * requester's own row is spliced in first, so a person mid-chain works even when the directory
 * would leave them out.
 */
function chainEntries(byId, requester, today, offOnDay) {
  const map = new Map(byId);
  map.set(requester.id, requester);
  return chainOf(map, requester.id).map((employee) => ({
    employee,
    skipped: skipReason({ approver: employee, requesterId: requester.id, today, offOnDay }),
  }));
}

/** The first level that may decide now, or null when every level is skipped. */
function firstUnskipped(entries) {
  return entries.find((e) => !e.skipped) || null;
}

/**
 * Whether this sign-in may decide this request: HR-wide (ATTENDANCE_OVERRIDE_ROLES), or the
 * first unskipped level of the requester's line. A lower level may not decide past an unskipped
 * one, and when every level is skipped only HR-wide may -- which is also the rule when the
 * requester has no manager at all.
 */
function mayDecide({ auth, entries }) {
  if (canDecideAny(auth.kind, auth.role)) return true;
  const first = firstUnskipped(entries);
  return Boolean(auth.employee && first && first.employee.id === auth.employee.id);
}

/**
 * The escalation target: the first unskipped level that no escalation has been recorded for yet,
 * or null when the chain is exhausted (the job then falls back to HR).
 */
function nextEscalation({ entries, escalatedIds }) {
  return entries.find((e) => !e.skipped && !escalatedIds.has(e.employee.id)) || null;
}

module.exports = {
  ESCALATE_AFTER_DAYS,
  skipReason,
  chainEntries,
  firstUnskipped,
  mayDecide,
  nextEscalation,
};
