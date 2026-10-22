const { HttpError, MESSAGES } = require('./errors');
const { invalid } = require('./validate');
const { filesOf, authorView } = require('../routes/wallViews');
const { holidaysFor, workingMinutesBetween } = require('../policy/helpdesk');

/**
 * The helpers the Helpdesk's routes share (Phase 2B, tasks G1 to G5), built as the Wall's are:
 * attachments base64 in and signed links out (lib/wallKit.js), person cards and file links the
 * same views the feed uses (routes/wallViews.js), and one shape a ticket or a thread row comes
 * back in whichever list or screen is reading it.
 *
 * The rules themselves (who may read or act, the lifecycle, the SLA calendar) live in
 * policy/helpdesk.js; the store stays policy-free. Everything here works on rows the store
 * answered and categories the caller has already resolved.
 */

/** A 404 in the Helpdesk's words: a ticket somebody may not see is one they cannot find (G4). */
const notFound = (message) => new HttpError(404, 'NOT_FOUND', message);

/** One category as G1 hands it over: what a raise form and a queue screen read. */
function categoryView(c) {
  return {
    id: c.id,
    slug: c.slug,
    name: c.name,
    is_ticket: c.is_ticket === true,
    flow: c.flow ?? null,
    confidential: c.confidential === true,
    allows_hold: c.allows_hold === true,
    priority: c.priority,
    first_response_hours: c.first_response_hours,
    resolution_hours: c.resolution_hours,
  };
}

/**
 * One ticket as every read shows it (G2, G4). `category` is the row's category resolved by the
 * caller; `me` is who is reading, so `mine` is decided once here; `seesName` is the anonymity
 * rule answered (policy/helpdesk.js seesRaiser): an anonymous ticket's raiser is hidden from the
 * team that answers, and shown to HR's own roles and to the raiser themself.
 *
 * `overdueMinutes` is the working minutes a live ticket is past the deadline it is now breaching
 * (first response, then resolution), or null when it is on time — the queue's "Overdue by"
 * without the client re-deriving working hours.
 */
async function ticketView(store, row, {
  category, raiser = null, assignee = null, me = null, seesName = true, overdueMinutes = null, infra = null,
}) {
  return {
    id: row.id,
    ref: row.ref,
    category: categoryView(category),
    priority: row.priority,
    subject: row.subject,
    body: row.body,
    status: row.status,
    anonymous: row.anonymous === true,
    raised_by: seesName ? authorView(raiser) : null,
    assignee: assignee ? authorView(assignee) : null,
    attachments: await filesOf(store, row.attachments),
    first_response_at: row.first_response_at ?? null,
    first_response_due_at: row.first_response_due_at,
    resolution_due_at: row.resolution_due_at,
    resolved_at: row.resolved_at ?? null,
    closed_at: row.closed_at ?? null,
    closing_reason: row.closing_reason ?? null,
    rating: row.rating ?? null,
    reopened_at: row.reopened_at ?? null,
    escalation_level: row.escalation_level ?? 0,
    overdue_minutes: overdueMinutes,
    infra,
    created_at: row.created_at,
    updated_at: row.updated_at,
    mine: Boolean(me && row.created_by === me),
  };
}

/** One thread row: a comment somebody wrote, or an event the server wrote as the ticket moved. */
function messageView(row, { author = null } = {}) {
  return {
    id: row.id,
    ticket_id: row.ticket_id,
    kind: row.kind,
    body: row.body ?? null,
    event: row.event ?? null,
    details: row.details || {},
    author: author ? authorView(author) : null,
    created_at: row.created_at,
  };
}

/** The 'event' row a status change, a claim, a withdrawal or a close leaves in the thread. */
function eventRow(ticketId, event, details, at, employeeId = null) {
  return {
    ticket_id: ticketId,
    employee_id: employeeId ?? null,
    kind: 'event',
    body: null,
    event,
    details: details || {},
    created_at: at,
  };
}

/** The 'comment' row an agent or a raiser leaves in the thread. */
function commentRow(ticketId, employeeId, body, at) {
  return {
    ticket_id: ticketId,
    employee_id: employeeId,
    kind: 'comment',
    body,
    event: null,
    details: {},
    created_at: at,
  };
}

/**
 * G3: the working minutes a live ticket is past the deadline it is now breaching — first
 * response while none has come, then resolution once it has. Null when it is on time, so the
 * app can show nothing at all rather than "overdue by 0".
 */
function overdueMinutesOf(row, now, holidays) {
  const from = row.first_response_at == null && Date.parse(row.first_response_due_at) < now.getTime()
    ? new Date(row.first_response_due_at)
    : (row.first_response_at != null && Date.parse(row.resolution_due_at) < now.getTime()
      ? new Date(row.resolution_due_at)
      : null);
  if (!from) return null;
  const minutes = workingMinutesBetween(from, now, holidays);
  return minutes > 0 ? minutes : null;
}

/* ── the reads the routes share ──
 *
 * One query per kind of thing, never one per row: the categories come back once as a map, a
 * ticket's two people in one read, and the holidays between two instants once for the whole
 * list a screen is showing.
 */

/** The active categories, as the raise form and the queue read them. */
async function activeCategories(store) {
  return (await store.listHelpdeskCategories()).filter((c) => c.is_active !== false);
}

/** The categories by id, for the category a ticket names. */
async function categoriesById(store) {
  const rows = await activeCategories(store);
  return new Map(rows.map((c) => [c.id, c]));
}

/**
 * One ticket with its category, or the 404 every may-not-see answer is (G4): a ticket somebody
 * may not read is one they cannot find.
 */
async function loadTicket(store, id) {
  const row = await store.getHelpdeskTicket(id);
  if (!row) throw notFound(MESSAGES.HELPDESK_TICKET_NOT_FOUND);
  const category = (await categoriesById(store)).get(row.category_id);
  if (!category) throw notFound(MESSAGES.HELPDESK_TICKET_NOT_FOUND);
  return { row, category };
}

/** A ticket's raiser and assignee, read once: the two people a view names. */
async function peopleForTicket(store, row) {
  const people = await store.listEmployeeCards([row.created_by, row.assignee_id].filter(Boolean));
  const byId = new Map(people.map((p) => [p.id, p]));
  return { raiser: byId.get(row.created_by) || null, assignee: row.assignee_id ? (byId.get(row.assignee_id) || null) : null };
}

/**
 * The holidays between two instants, worked out for one ticket's branch: the branch's own days
 * plus the ones kept for everybody (policy/helpdesk.js holidaysFor). `from` to `to` covers the
 * span the dues and the overdue label walk.
 */
async function holidaysBetween(store, fromISO, toISO, branchId) {
  const rows = await store.listHolidays(String(fromISO).slice(0, 10), String(toISO).slice(0, 10));
  return holidaysFor(rows, branchId ?? null);
}

/** The `?status=` filter a list query names: null for 'all' or no value, or the one status. */
function statusFilter(value, allowed, message) {
  if (value === undefined || value === null || value === '' || value === 'all') return null;
  if (!allowed.includes(value)) throw invalid(message);
  return [value];
}

module.exports = {
  notFound,
  categoryView,
  ticketView,
  messageView,
  eventRow,
  commentRow,
  overdueMinutesOf,
  activeCategories,
  categoriesById,
  loadTicket,
  peopleForTicket,
  holidaysBetween,
  statusFilter,
};
