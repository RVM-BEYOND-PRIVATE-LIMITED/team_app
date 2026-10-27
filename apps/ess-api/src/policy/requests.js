const { PAYROLL_CUTOFF_DAY, REQUEST_TYPES, requestType } = require('./requestLimits');
const { monthBounds, lastMonthStart } = require('../lib/time');
const { ATTENDANCE_OVERRIDE_ROLES } = require('./hrPolicy');

/**
 * The rules the request endpoints share (tasks C1 to C12): the reach-back window and the cut-off,
 * the monthly counters every form shows, the approver rule, and the wire shape of a request.
 *
 * The window. A request may be for a day this month or last month (the brief). Last month's
 * requests close at the payroll cut-off on the 5th (KP, 16 Oct). The one thing still open is
 * decision 6 -- whether the 5th itself counts, and whether a pending request for last month may
 * still be decided after the cut-off. The build's default, in ONE place: the 5th itself is open
 * (the IST day of month is 5 or less), for raising and for deciding alike. Change
 * `lastMonthOpen` here, and the same rule in db/migrations/20261106000004 (extract day > 5).
 *
 * The counter, as the brief words it: allowed, used, remaining, pending included. For the
 * attendance types a request counts as used once approved; for leave, the day the sheet records
 * is what counts (an approval writes it at once, so an approved CL is a written CL day), and
 * pending requests count on top. Remaining never goes below zero.
 *
 * The approver (decision 1): the manager on the HR record, with HR as fallback; HR, the CEO and
 * super admins may decide ANY request (ATTENDANCE_OVERRIDE_ROLES -- never HR_ROLES, which
 * includes hr_executive, whose powers exclude attendance and leave). An hr_executive still
 * approves their own team, as any manager does.
 */

/** The families the inbox and the decide route work with. */
const FAMILIES = Object.freeze(['attendance', 'leave']);

/** The offered types of each family in this phase (wfh is offered per employee, by HR). */
const ATTENDANCE_TYPES = Object.freeze(['on_duty', 'fix_a_day', 'excuse_late', 'short_leave']);
const LEAVE_TYPES = Object.freeze(['cl', 'lwp', 'wfh']);

const STATUSES = Object.freeze(['pending', 'approved', 'rejected', 'withdrawn', 'cancelled']);

/** The types of one family, offered or not: what `type` may be at all. */
const typesOfFamily = (family) => (family === 'attendance' ? ATTENDANCE_TYPES : family === 'leave' ? LEAVE_TYPES : []);

/** Whether this sign-in may decide anybody's request, recorded as HR's (ATTENDANCE_OVERRIDE_ROLES). */
const canDecideAny = (kind, role) => kind === 'portal' && ATTENDANCE_OVERRIDE_ROLES.has(role);

/** Whether this sign-in is the requester's manager on the HR record. */
const isManagerOf = (callerEmployeeId, requesterEmployee) =>
  Boolean(requesterEmployee && requesterEmployee.manager_id && requesterEmployee.manager_id === callerEmployeeId);

/** Whether this sign-in may decide this one request: HR-wide, or the person's own manager. */
const canDecideRequest = ({ kind, role, employee }, requesterEmployee) =>
  canDecideAny(kind, role) || isManagerOf(employee.id, requesterEmployee);

/**
 * Whether last month is still open for this IST day: the cut-off day itself included (the
 * default for decision 6; see the note at the top).
 */
const lastMonthOpen = (today) => Number(today.slice(8, 10)) <= PAYROLL_CUTOFF_DAY;

/**
 * The window check for a request's day. Answers null when it is inside the window, or the code
 * of the refusal: REQUEST_WINDOW (before last month) or REQUEST_CLOSED (last month, past the
 * cut-off). The message for each code is in lib/errors.js MESSAGES, keyed by the same name.
 */
function windowProblem(day, today) {
  if (day < lastMonthStart(today)) return 'REQUEST_WINDOW';
  if (day < monthBounds(today).from && !lastMonthOpen(today)) return 'REQUEST_CLOSED';
  return null;
}

/** The month of `day`, checked to be the IST month or the one before it -- what balances show. */
function monthProblem(month, today) {
  const thisMonth = today.slice(0, 7);
  const lastMonth = lastMonthStart(today).slice(0, 7);
  return month === thisMonth || month === lastMonth ? null : 'DAY_OUT_OF_RANGE';
}

/**
 * The requests of one type counted for a month: the ones that count as used (approved) and the
 * ones still pending. `rows` are request rows of one family for the month; `written` is how many
 * days of that type the sheet already records (leave only, where the sheet is the ledger).
 */
function countForMonth(rows, type, { written = 0, unit = 'count', month = null } = {}) {
  const step = (r) => {
    if (unit !== 'days') return 1;
    // A range may cross a month boundary: count only the days in this month. Old rows have no
    // working_days, so their stored day_count is the fallback.
    if (r.portion && r.portion !== 'full') return 0.5;
    if (month && Array.isArray(r.working_days) && r.working_days.length) {
      return r.working_days.filter((d) => String(d).slice(0, 7) === month).length;
    }
    return Number(r.day_count ?? 1);
  };
  let approved = 0;
  let pending = 0;
  for (const r of rows) {
    if (r.type !== type) continue;
    if (r.status === 'approved') approved += step(r);
    else if (r.status === 'pending') pending += step(r);
  }
  // An approved leave request has already written its days to the sheet. Count the ledger and
  // the approved requests once, not twice: the larger of the two is the month's used days.
  const used = unit === 'days' ? Math.max(Number(written) || 0, approved) : written + approved;
  return { used, pending };
}

/**
 * C3: short leave counts by minutes, not by requests. `rows` are attendance request rows of the
 * month carrying `minutes` (the attendance facts read), counted as the other counters are: the
 * approved minutes are used and the pending ones wait on top, so a form shows both the way the
 * day-based counters do.
 */
function minutesForMonth(rows, type) {
  let used = 0;
  let pending = 0;
  for (const r of rows) {
    if (r.type !== type || r.minutes == null) continue;
    if (r.status === 'approved') used += r.minutes;
    else if (r.status === 'pending') pending += r.minutes;
  }
  return { used, pending };
}

/** The three numbers a form shows, from the counts and the limit (`allowed`; null means none). */
function balanceOf(allowed, { used, pending }) {
  return {
    allowed: allowed ?? null,
    used,
    pending,
    remaining: allowed == null ? null : Math.max(0, allowed - used - pending),
  };
}

/** '09:00:00' or '09:00' -> '09:00'; null stays null. */
const hhmm = (t) => (t ? String(t).slice(0, 5) : null);

const employeeCardView = (e) => (e ? { id: e.id, full_name: e.full_name, employee_code: e.employee_code ?? null } : null);

/**
 * One request as the app reads it. `family` says which table it is; the decided and cancelled
 * fields are the 4W's the employee and the approver read; nothing internal (day_before, the
 * decider's account id) is sent.
 */
function requestView(r, family, { employee = null } = {}) {
  const view = {
    id: r.id,
    family,
    type: r.type,
    status: r.status,
    day: r.day,
    reason: r.reason,
    created_at: r.created_at,
    decided_at: r.decided_at ?? null,
    decided_by_name: r.decided_by_name ?? null,
    decision_note: r.decision_note ?? null,
    cancelled_at: r.cancelled_at ?? null,
    cancelled_by_name: r.cancelled_by_name ?? null,
    cancel_reason: r.cancel_reason ?? null,
  };
  if (family === 'leave') {
    view.end_day = r.end_day ?? r.day;
    view.portion = r.portion ?? 'full';
    view.day_count = Number(r.day_count ?? 1);
    view.working_days = Array.isArray(r.working_days) ? r.working_days : [r.day];
    view.requires_final_approval = Boolean(r.requires_final_approval);
    view.stage = r.stage ?? 'manager';
    view.admin_manager_employee_id = r.admin_manager_employee_id ?? null;
    view.admin_manager_name = r.admin_manager_name ?? null;
    view.is_teaching = Boolean(r.is_teaching);
    view.final_approver_employee_id = r.final_approver_employee_id ?? null;
    view.final_approver_name = r.final_approver_name ?? null;
    view.substitute_faculty_id = r.substitute_faculty_id ?? null;
    view.substitute_faculty_name = r.substitute_faculty_name ?? null;
    view.class_timing = r.class_timing ?? null;
    view.manager_approved_by_name = r.manager_approved_by_name ?? null;
    view.manager_approved_at = r.manager_approved_at ?? null;
    view.manager_remark = r.manager_remark ?? null;
  }
  if (family === 'attendance') {
    view.place = r.place ?? null;
    view.fix_in = hhmm(r.fix_in);
    view.fix_out = hhmm(r.fix_out);
    view.minutes = r.minutes ?? null;
  }
  if (employee) view.employee = employeeCardView(employee);
  return view;
}

/** The request types and limits document, for a form: the policy table, never the raw rows. */
const requestTypesPolicy = () => REQUEST_TYPES.map((t) => ({ ...t }));

module.exports = {
  FAMILIES,
  ATTENDANCE_TYPES,
  LEAVE_TYPES,
  STATUSES,
  typesOfFamily,
  canDecideAny,
  isManagerOf,
  canDecideRequest,
  lastMonthOpen,
  windowProblem,
  monthProblem,
  countForMonth,
  minutesForMonth,
  balanceOf,
  hhmm,
  employeeCardView,
  requestView,
  requestTypesPolicy,
  requestType,
};
