const { HR_RECORD_ROLES } = require('./hrAccess');

/**
 * Phase 1E's rules (tasks E1-E12): the timeline, the contact rule, the org chain, the week and
 * the team's day.
 *
 * - Timeline: an allowlist of employee event types, mapped to one plain line each. HR remarks
 *   (EMPLOYEE_REMARK_ADDED), archiving and anything not on the list never appear; the values
 *   (before/after) are never read, so pay that passed through an event cannot leak.
 * - Contact rule (E8, decision: "email to everyone; phone to the manager chain and HR"): email is
 *   on every colleague card; a phone is shown to HR's roles, to the person themselves, and to
 *   their managers up the chain. Decision 5 (whether a report also sees their manager's phone)
 *   is answered NO by default: the chain view shows no phones unless the viewer is HR.
 * - The chain walks manager_id upward with a cycle guard (the Scheduler's own guard prevents
 *   cycles on write; the guard here means a hand-edited row cannot hang a request).
 * - Notice: the statuses the Scheduler writes for somebody serving notice.
 */

const NOTICE_STATUSES = new Set(['notice_period', 'serving_notice']);

const isNotice = (employee) => NOTICE_STATUSES.has(employee.employment_status);

/** Walk from `employeeId` up the reporting line; at most 20 steps, repeated ids stop it. */
function chainOf(byId, employeeId) {
  const out = [];
  const seen = new Set([employeeId]);
  let at = byId.get(employeeId);
  let guard = 20;
  while (at && at.manager_id && guard > 0) {
    const next = byId.get(at.manager_id);
    if (!next || seen.has(next.id)) break;
    out.push(next);
    seen.add(next.id);
    at = next;
    guard -= 1;
  }
  return out;
}

/** Whether `ancestorId` is above `ofId` in the reporting line. */
function isAncestor(byId, ancestorId, ofId) {
  return chainOf(byId, ofId).some((e) => e.id === ancestorId);
}

/**
 * Whether the viewer may see this colleague's phone. Self and HR's roles always; otherwise only
 * a manager above them. A colleague with no phone recorded has nothing to show.
 */
function canSeePhone({ viewer, colleague, role, byId }) {
  if (!colleague.phone) return false;
  if (viewer.id === colleague.id) return true;
  if (role && HR_RECORD_ROLES.has(role)) return true;
  return isAncestor(byId, viewer.id, colleague.id);
}

/** One colleague as the directory and the org views show them (E8's contact rule applied). */
function personCard({ employee, department, branch, phone }) {
  return {
    id: employee.id,
    full_name: employee.full_name,
    employee_code: employee.employee_code ?? null,
    designation: employee.designation ?? null,
    department: department ? { id: department.id, name: department.name } : null,
    branch: branch ? { id: branch.id, name: branch.name } : null,
    email: employee.email ?? null,
    phone: phone ?? null,
    employment_status: employee.employment_status ?? null,
    notice_period: isNotice(employee),
  };
}

/** The IST week around a day: Monday to Sunday (the week-off is Sunday; Monday opens the week). */
function weekBounds(today) {
  const at = new Date(`${today}T00:00:00Z`);
  const weekday = at.getUTCDay(); // 0 Sunday
  const back = (weekday + 6) % 7; // days since Monday
  const from = new Date(at.getTime() - back * 86400000).toISOString().slice(0, 10);
  const to = new Date(Date.parse(`${from}T00:00:00Z`) + 6 * 86400000).toISOString().slice(0, 10);
  return { from, to };
}

/**
 * Event types the Timeline may show: one stable machine `kind` and one plain line each.
 * `kind` is what clients filter on; `title` is the staff-facing wording and never changes with
 * it. Anything not on this list is dropped.
 */
const TIMELINE_EVENTS = Object.freeze({
  EMPLOYEE_CREATED: Object.freeze({ kind: 'JOINING_RECORDED', title: 'Joined RVM' }),
  EMPLOYEE_PROMOTED: Object.freeze({ kind: 'PROMOTED', title: 'Promoted' }),
  EMPLOYEE_STATUS_CHANGED: Object.freeze({ kind: 'STATUS_CHANGED', title: 'Employment status changed' }),
  EMPLOYEE_MANAGER_CHANGED: Object.freeze({ kind: 'REPORTING_LINE_CHANGED', title: 'Reporting line changed' }),
  EMPLOYEE_CODE_ISSUED: Object.freeze({ kind: 'CODE_ISSUED', title: 'Employee code issued' }),
  EMPLOYEE_CODE_ASSIGNED: Object.freeze({ kind: 'CODE_ASSIGNED', title: 'Employee code set' }),
  INCREMENT_DATE_CHANGED: Object.freeze({ kind: 'INCREMENT_RECORDED', title: 'Increment date recorded' }),
});

/** The title-only view of the same table, for callers that only need the line. */
const TIMELINE_TITLES = Object.freeze(Object.fromEntries(
  Object.entries(TIMELINE_EVENTS).map(([eventType, event]) => [eventType, event.title]),
));

/** The kind and line for one employee event, or null when the Timeline never shows it. */
function timelineEntry(eventType, changedKeys) {
  if (TIMELINE_EVENTS[eventType]) return TIMELINE_EVENTS[eventType];
  if (eventType === 'EMPLOYEE_UPDATED') {
    const keys = Array.isArray(changedKeys) ? changedKeys : [];
    if (keys.includes('designation')) return { kind: 'DESIGNATION_CHANGED', title: 'Designation changed' };
    if (keys.includes('branch_id')) return { kind: 'BRANCH_CHANGED', title: 'Branch changed' };
    if (keys.includes('date_of_joining')) return { kind: 'JOINING_RECORDED', title: 'Joining date recorded' };
    return { kind: 'TRIVIAL_UPDATE', title: 'Details updated' };
  }
  return null;
}

/** The line for one employee event, or null when the Timeline never shows it. */
function timelineTitle(eventType, changedKeys) {
  return timelineEntry(eventType, changedKeys)?.title ?? null;
}

/**
 * One person's day, as Team today shows it: the sheet's own row when there is one.
 *  on_leave  the sheet records leave that day
 *  week_off / holiday  the sheet records the day off
 *  not_in    nobody has punched in yet
 *  in / done punched in; in again, or finished for the day
 * The late flag is the day's own late mark, excused lates included (the app can say so).
 */
function teamDayState(dayRow) {
  if (!dayRow) return 'not_in';
  if (dayRow.status === 'leave') return 'on_leave';
  if (dayRow.status === 'week_off') return 'week_off';
  if (dayRow.status === 'holiday') return 'holiday';
  if (!dayRow.first_in) return 'not_in';
  return dayRow.last_out ? 'done' : 'in';
}

module.exports = {
  NOTICE_STATUSES,
  isNotice,
  chainOf,
  isAncestor,
  canSeePhone,
  personCard,
  weekBounds,
  TIMELINE_EVENTS,
  TIMELINE_TITLES,
  timelineEntry,
  timelineTitle,
  teamDayState,
};
