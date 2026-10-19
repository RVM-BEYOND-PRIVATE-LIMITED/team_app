const { ROLES } = require('./roles');

/**
 * The Helpdesk's product rules in one place (Phase 2B, tasks G1 to G5). The routes enforce them,
 * and `GET /api/ess/helpdesk/categories` (G1) hands the app the same list, so a form and its
 * refusal can never disagree.
 *
 * The categories are FIXED in code and seeded by the migration from this list (KP, 19 Oct 2026):
 * the brief's six, plus the four non-ticket rows that link to the flows a ticket is not (leave,
 * WFH, an attendance fix, an asset request). HR's own category-editing is not built (decision 7
 * open), so a change here is a reviewed code change and a migration re-run, exactly as the Wall's
 * badges are.
 *
 * Two roles the brief names do not exist as logins, so their tickets route to the roles that do
 * (both flagged for KP): the lab has no desk role, so IT and lab tickets go to the admin roles;
 * the Internal Committee has no login, so POSH tickets go to HR.
 */

/** G2: a closed ticket may be reopened for this many days. */
const REOPEN_DAYS = 7;

/** G2: the rating the raiser may give at close. */
const RATING_MIN = 1;
const RATING_MAX = 5;

/** The ticket statuses, in lifecycle order. `withdrawn` is the raiser's own exit. */
const STATUSES = Object.freeze(['open', 'in_progress', 'on_hold', 'resolved', 'closed', 'withdrawn']);

/** The statuses the queue works on, and the ones the hourly job walks. */
const ACTIVE_STATUSES = Object.freeze(['open', 'in_progress', 'on_hold']);

const PRIORITIES = Object.freeze(['low', 'medium', 'high', 'urgent']);

/** Who may set a status to what, from which (G2's lifecycle, agent's moves). `resolved` only
 * from the three active ones; `closed` is the raiser's own act, with the rating. */
const AGENT_TRANSITIONS = Object.freeze({
  open: Object.freeze(['in_progress', 'on_hold', 'resolved']),
  in_progress: Object.freeze(['on_hold', 'resolved']),
  on_hold: Object.freeze(['in_progress', 'resolved']),
  resolved: Object.freeze([]),
  closed: Object.freeze([]),
  withdrawn: Object.freeze([]),
});

/** The statuses a raiser may close their own ticket from: any live one. */
const RAISER_CLOSES_FROM = Object.freeze(['open', 'in_progress', 'on_hold', 'resolved']);

/**
 * The categories, as the migration seeds them. `queue_roles` is exact membership (the
 * Scheduler's allowRoles reading): the CEO inherits admin duties in the Scheduler, but the
 * brief routes lab and facility tickets to "roles admin + admin_manager", so the queue shows
 * exactly those roles and nobody else.
 */
const HELPDESK_CATEGORIES = Object.freeze([
  Object.freeze({
    slug: 'it_lab', name: 'IT and lab equipment', is_ticket: true, flow: null,
    queue_roles: Object.freeze(['admin', 'admin_manager']), confidential: false, allows_hold: true,
    priority: 'medium', first_response_hours: 8, resolution_hours: 48,
  }),
  Object.freeze({
    slug: 'facility', name: 'Facility and housekeeping', is_ticket: true, flow: null,
    queue_roles: Object.freeze(['admin', 'admin_manager']), confidential: false, allows_hold: true,
    priority: 'medium', first_response_hours: 8, resolution_hours: 48,
  }),
  Object.freeze({
    slug: 'hr_documents', name: 'HR and documents', is_ticket: true, flow: null,
    queue_roles: Object.freeze(['hr', 'hr_executive']), confidential: false, allows_hold: false,
    priority: 'medium', first_response_hours: 24, resolution_hours: 72,
  }),
  Object.freeze({
    slug: 'payroll', name: 'Payroll and reimbursements', is_ticket: true, flow: null,
    queue_roles: Object.freeze(['accounts_admin']), confidential: false, allows_hold: false,
    priority: 'high', first_response_hours: 24, resolution_hours: 72,
  }),
  Object.freeze({
    slug: 'grievance', name: 'Grievance', is_ticket: true, flow: null,
    queue_roles: Object.freeze(['hr']), confidential: true, allows_hold: false,
    priority: 'high', first_response_hours: 12, resolution_hours: 48,
  }),
  Object.freeze({
    slug: 'posh', name: 'POSH complaint', is_ticket: true, flow: null,
    // KP 6 (19 Oct 2026): the committee, not HR. The role does not exist in the Scheduler yet,
    // so the queue stays empty until RVM appoints the committee (see the header).
    queue_roles: Object.freeze(['internal_committee']), confidential: true, allows_hold: false,
    priority: 'urgent', first_response_hours: 12, resolution_hours: 72,
  }),
  // The brief's "not tickets": the category list links to the flows that exist.
  Object.freeze({
    slug: 'leave_link', name: 'Leave', is_ticket: false, flow: 'leave',
    queue_roles: Object.freeze([]), confidential: false, allows_hold: false,
    priority: 'medium', first_response_hours: 24, resolution_hours: 72,
  }),
  Object.freeze({
    slug: 'wfh_link', name: 'Work from home', is_ticket: false, flow: 'wfh',
    queue_roles: Object.freeze([]), confidential: false, allows_hold: false,
    priority: 'medium', first_response_hours: 24, resolution_hours: 72,
  }),
  Object.freeze({
    slug: 'attendance_fix_link', name: 'Attendance fix', is_ticket: false, flow: 'attendance_fix',
    queue_roles: Object.freeze([]), confidential: false, allows_hold: false,
    priority: 'medium', first_response_hours: 24, resolution_hours: 72,
  }),
  Object.freeze({
    slug: 'asset_link', name: 'Asset request', is_ticket: false, flow: 'assets',
    queue_roles: Object.freeze([]), confidential: false, allows_hold: false,
    priority: 'medium', first_response_hours: 24, resolution_hours: 72,
  }),
]);

/**
 * G4: who may read a ticket.
 *   - its raiser, always;
 *   - the category's queue roles, exactly;
 *   - HR's oversight (HR, HR Executive, CEO, super admin) — but never on a confidential one,
 *     which the brief keeps to the team that answers it: hidden from the CEO and super admins'
 *     lists too (G4).
 */
const HR_OVERSIGHT_ROLES = Object.freeze([ROLES.HR, ROLES.HR_EXECUTIVE, ROLES.CEO, ROLES.SUPER_ADMIN]);

/** An anonymous ticket's raiser is seen by HR's own roles, whoever else is looking. */
const HR_ANONYMOUS_ROLES = Object.freeze([ROLES.HR, ROLES.HR_EXECUTIVE]);

/**
 * Every staff role a portal sign-in can carry — the same list the migration's category roles
 * CHECK keeps queue roles to. The Helpdesk needs no role to be read or raised, but its queue is
 * a portal screen: an attendance session (which carries no role at all) is refused with
 * PORTAL_LOGIN_REQUIRED by naming this whole set, exactly as requireRoles refuses.
 */
const PORTAL_ROLES = Object.freeze(new Set([
  ROLES.CEO, ROLES.SUPER_ADMIN, ROLES.HOO, ROLES.HOD, ROLES.HOD_PLACEMENT,
  ROLES.ADMIN_MANAGER, ROLES.ADMIN, ROLES.ACCOUNTS_ADMIN, ROLES.HR, ROLES.HR_EXECUTIVE,
  ROLES.FACULTY,
]));

const isQueueRole = (role, queueRoles) => (queueRoles || []).includes(role);

/** Whether this reader may see this ticket at all (G4). The raiser is answered before this. */
function canRead(role, ticket, category) {
  if (isQueueRole(role, category.queue_roles)) return true;
  if (category.confidential) return false;
  return HR_OVERSIGHT_ROLES.includes(role);
}

/** Whether this reader may act on the ticket in its team's queue (G5). */
const canAct = (role, category) => isQueueRole(role, category.queue_roles);

/** Whether this reader sees who raised an anonymous ticket (G4). */
const seesRaiser = (role, ticket) => !ticket.anonymous || HR_ANONYMOUS_ROLES.includes(role);

/* ── G3: working hours ──
 *
 * The build's calendar, flagged for KP: 09:00 to 17:30 IST, Monday to Saturday (Sunday off),
 * plus the hr_holidays the branch keeps (a row with no branch is everybody's). The SLA targets
 * are counted in these hours, so a ticket raised at 18:00 is due 9:00's worth of working time
 * later, and "Overdue by 3h" means three working hours.
 */

const WORK_START = '09:00';
const WORK_END = '17:30';
/** The IST_OFFSET of lib/time.js, repeated here as minutes. */
const IST_OFFSET_MINUTES = 330;

/** The IST calendar day of an instant, as lib/time.js works it out. */
const istDayOf = (instant) => new Date(instant.getTime() + IST_OFFSET_MINUTES * 60 * 1000).toISOString().slice(0, 10);

/** The instant of an IST wall-clock time on a day. */
const istTimeOn = (day, hhmm) => new Date(`${day}T${hhmm}:00+05:30`);

const isWorkingDay = (day, holidays) =>
  new Date(`${day}T00:00:00Z`).getUTCDay() !== 0 && !(holidays || []).includes(day);

/** The holidays that count for a branch: the branch's own, plus the ones kept for everybody. */
const holidaysFor = (rows, branchId) =>
  (rows || []).filter((h) => h.branch_id === null || h.branch_id === branchId).map((h) => h.day);

/**
 * The instant `minutes` working minutes after `from`, walking the calendar day by day. Sixty
 * days is more than any target needs (the longest build target is 72 working hours); past it
 * the walk answers the horizon, which the flags-for-KP note covers.
 */
function workingSpan(from, minutes, holidays) {
  let remaining = minutes;
  let cursor = new Date(from.getTime());
  for (let i = 0; i < 60 && remaining > 0; i += 1) {
    const day = istDayOf(cursor);
    if (isWorkingDay(day, holidays)) {
      const start = istTimeOn(day, WORK_START);
      const end = istTimeOn(day, WORK_END);
      const fromTime = cursor.getTime() > start.getTime() ? cursor : start;
      if (fromTime.getTime() < end.getTime()) {
        const take = Math.min(Math.floor((end.getTime() - fromTime.getTime()) / 60000), remaining);
        remaining -= take;
        if (remaining === 0) return new Date(fromTime.getTime() + take * 60000);
      }
    }
    // Next IST midnight, whatever the server's zone.
    cursor = new Date(Date.parse(`${day}T00:00:00+05:30`) + 86400000);
  }
  return cursor;
}

/** The working minutes between two instants, for an "Overdue by" label. */
function workingMinutesBetween(from, to, holidays) {
  if (to.getTime() <= from.getTime()) return 0;
  let minutes = 0;
  let cursor = new Date(from.getTime());
  for (let i = 0; i < 60 && cursor < to; i += 1) {
    const day = istDayOf(cursor);
    if (isWorkingDay(day, holidays)) {
      const start = istTimeOn(day, WORK_START);
      const end = istTimeOn(day, WORK_END);
      const fromTime = cursor.getTime() > start.getTime() ? cursor : start;
      const toTime = to.getTime() < end.getTime() ? to : end;
      if (fromTime.getTime() < toTime.getTime()) minutes += Math.floor((toTime.getTime() - fromTime.getTime()) / 60000);
    }
    cursor = new Date(Date.parse(`${day}T00:00:00+05:30`) + 86400000);
  }
  return minutes;
}

/**
 * G3: the two deadlines a new ticket carries, worked out from the calendar at once and stored on
 * the row. `first_response_hours` then `resolution_hours`, in working minutes.
 */
function dueTimes(createdAt, category, holidays) {
  return {
    first_response_due_at: workingSpan(createdAt, category.first_response_hours * 60, holidays),
    resolution_due_at: workingSpan(createdAt, category.resolution_hours * 60, holidays),
  };
}

/** Whether the first response is overdue, whatever the clock says between the two. */
const firstResponseOverdue = (row, now) =>
  row.first_response_at == null && Date.parse(row.first_response_due_at) <= now.getTime();

/** The whole rules document, for the app to build its screens from (G1). */
function helpdeskSettings(categories) {
  return {
    categories: categories.map((c) => ({
      id: c.id,
      slug: c.slug,
      name: c.name,
      is_ticket: c.is_ticket,
      flow: c.flow ?? null,
      confidential: c.confidential,
      allows_hold: c.allows_hold,
      priority: c.priority,
    })),
    reopen_days: REOPEN_DAYS,
    rating: { min: RATING_MIN, max: RATING_MAX },
    anonymous: true,
    attachments: true,
  };
}

module.exports = {
  REOPEN_DAYS,
  RATING_MIN,
  RATING_MAX,
  STATUSES,
  ACTIVE_STATUSES,
  PRIORITIES,
  AGENT_TRANSITIONS,
  RAISER_CLOSES_FROM,
  HELPDESK_CATEGORIES,
  HR_OVERSIGHT_ROLES,
  HR_ANONYMOUS_ROLES,
  PORTAL_ROLES,
  WORK_START,
  WORK_END,
  isQueueRole,
  canRead,
  canAct,
  seesRaiser,
  isWorkingDay,
  holidaysFor,
  workingSpan,
  workingMinutesBetween,
  dueTimes,
  firstResponseOverdue,
  helpdeskSettings,
};
