const { HELPDESK_CATEGORIES } = require('../../src/policy/helpdesk');

/**
 * The Helpdesk's own fixtures for the Phase 2B tests (tasks G1 to G5): the categories as the
 * migration seeds them, a ticket row of any state, and a thread row. Fixed ids, so a failing test
 * is easy to read.
 *
 * The rows are written as db/migrations/20261109000001 declares them, defaults included, so a
 * route under test reads the same shapes the database would hand it. The categories come from
 * policy/helpdesk.js itself, so a test cannot drift from the rules it tests.
 */

/** 'ca1', 7 -> ca100000-0000-4000-8000-000000000007: a valid uuid, and easy to read in a failure. */
const uuid = (prefix, n) => `${prefix.padEnd(8, '0').slice(0, 8)}-0000-4000-8000-${String(n).padStart(12, '0')}`;

const CATEGORY_ID = (n) => uuid('ca', n);
const TICKET_ID = (n) => uuid('cb', n);
const MESSAGE_ID = (n) => uuid('cc', n);

/** The fixture's raise time: 16 Oct 2026, 10:30 IST — inside the working window, a Friday. */
const AT = '2026-10-16T05:00:00+00:00';

/** The id the seed gives a category, by slug (the brief's six, then the four links). */
const CAT = (slug) => CATEGORY_ID(HELPDESK_CATEGORIES.findIndex((c) => c.slug === slug) + 1);

/** The categories, as db/migrations/20261109000001 seeds them from policy/helpdesk.js. */
function categoryRows() {
  return HELPDESK_CATEGORIES.map((c, i) => ({
    id: CATEGORY_ID(i + 1),
    slug: c.slug,
    name: c.name,
    is_ticket: c.is_ticket,
    flow: c.flow ?? null,
    queue_roles: [...c.queue_roles],
    confidential: c.confidential,
    allows_hold: c.allows_hold,
    priority: c.priority,
    first_response_hours: c.first_response_hours,
    resolution_hours: c.resolution_hours,
    is_active: true,
    created_at: AT,
    updated_at: AT,
  }));
}

/** The categories into a fresh world, before the app sees it. */
const seedCategories = (w) => {
  w.tables.hr_ess_helpdesk_categories = categoryRows();
};

/** The SLA deadlines a ticket raised at AT carries (it_lab's: 8 and 48 working hours). */
const FIRST_RESPONSE_DUE = '2026-10-17T04:00:00+00:00';
const RESOLUTION_DUE = '2026-10-22T09:30:00+00:00';

/**
 * One hr_ess_helpdesk_tickets row: raised by RVM-011 (the faculty fixture) in IT and lab
 * equipment, open, unassigned, on time, unless a test says otherwise.
 */
function ticketRow(raiserId, n, change = {}) {
  return {
    id: TICKET_ID(n),
    ref: `HD-${String(n).padStart(4, '0')}`,
    created_by: raiserId,
    category_id: CAT('it_lab'),
    priority: 'medium',
    subject: 'The lab PCs will not start.',
    body: 'Six machines in Lab 2 stay on the boot screen; the morning batch is waiting.',
    attachments: [],
    anonymous: false,
    branch_id: null,
    status: 'open',
    assignee_id: null,
    claimed_at: null,
    first_response_at: null,
    first_response_due_at: FIRST_RESPONSE_DUE,
    resolution_due_at: RESOLUTION_DUE,
    resolved_at: null,
    closed_at: null,
    closed_by_employee_id: null,
    closing_reason: null,
    rating: null,
    reopened_at: null,
    escalation_level: 0,
    created_at: AT,
    updated_at: AT,
    ...change,
  };
}

/** One hr_ess_helpdesk_messages row: a comment by default, or an event with `event` set. */
function messageRow(ticketId, n, employeeId, change = {}) {
  return {
    id: MESSAGE_ID(n),
    ticket_id: ticketId,
    employee_id: employeeId ?? null,
    kind: employeeId ? 'comment' : 'event',
    body: employeeId ? 'Checked the switch; two ports are dead.' : null,
    event: employeeId ? null : 'opened',
    details: {},
    created_at: AT,
    ...change,
  };
}

module.exports = {
  uuid,
  CATEGORY_ID,
  TICKET_ID,
  MESSAGE_ID,
  AT,
  CAT,
  FIRST_RESPONSE_DUE,
  RESOLUTION_DUE,
  categoryRows,
  seedCategories,
  ticketRow,
  messageRow,
};
