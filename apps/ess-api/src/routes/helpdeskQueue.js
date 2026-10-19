const { MESSAGES, asyncRoute } = require('../lib/errors');
const { oneQueryValue, invalid } = require('../lib/validate');
const { LIST_LIMITS } = require('../lib/store');
const {
  activeCategories, statusFilter, ticketView, overdueMinutesOf, categoryView,
} = require('../lib/helpdeskKit');
const { isQueueRole, seesRaiser, holidaysFor } = require('../policy/helpdesk');

/**
 * G5, the team's queue: the tickets of the categories the caller's own role serves, newest
 * first, with the "overdue by" the SLA carries. Membership is exact (policy/helpdesk.js): the
 * queue shows the roles named in `queue_roles` and nobody else — the CEO and super admins see
 * nothing here unless a category names them, and a confidential category is seen only by the
 * team it is routed to.
 *
 * A role that serves no category (the CEO's, most staff's) is answered an empty queue, not a
 * refusal: the screen simply has nothing to show. An attendance session, which carries no portal
 * role at all, is refused with PORTAL_LOGIN_REQUIRED by the role guard app.js mounts (G5).
 */

/** The statuses a queue page may be held to. `withdrawn` is the raiser's own exit, not work. */
const QUEUE_STATUSES = Object.freeze(['open', 'in_progress', 'on_hold', 'resolved', 'closed']);

/** The queue's front page is the work that is still live (G2's lifecycle). */
const LIVE_STATUSES = Object.freeze(['open', 'in_progress', 'on_hold']);

/** GET /api/ess/helpdesk/queue?status=&category= — the categories my role serves, and their tickets. */
function listQueue({ store, now }) {
  return asyncRoute(async (req, res) => {
    const role = req.auth.role;
    const serving = (await activeCategories(store))
      .filter((c) => c.is_ticket && isQueueRole(role, c.queue_roles));

    // ?category= narrows the queue to one of the caller's own categories.
    const slug = oneQueryValue(req.query.category);
    let mine = serving;
    if (slug) {
      const one = serving.find((c) => c.slug === slug);
      if (!one) throw invalid(MESSAGES.HELPDESK_CATEGORY);
      mine = [one];
    }

    // ?status= holds the queue to one of its statuses; with no value it is the live work.
    const asked = oneQueryValue(req.query.status);
    const statuses = asked && asked !== 'all'
      ? statusFilter(asked, QUEUE_STATUSES, MESSAGES.HELPDESK_QUEUE_STATUS)
      : (asked === 'all' ? null : [...LIVE_STATUSES]);

    const rows = mine.length
      ? await store.listHelpdeskQueue(mine.map((c) => c.id), statuses || QUEUE_STATUSES, LIST_LIMITS.helpdeskQueue)
      : [];
    const byId = new Map(mine.map((c) => [c.id, c]));
    const nowDate = now();

    // The holidays once for the oldest row forwards, then each row on its own branch's calendar.
    const oldest = rows.length
      ? rows.reduce((min, r) => (r.created_at < min ? r.created_at : min), rows[0].created_at)
      : null;
    const holidayRows = oldest
      ? await store.listHolidays(String(oldest).slice(0, 10), nowDate.toISOString().slice(0, 10))
      : [];

    const peopleIds = [...new Set(rows.flatMap((r) => [r.created_by, r.assignee_id]).filter(Boolean))];
    const people = await store.listEmployeeCards(peopleIds);
    const byPerson = new Map(people.map((p) => [p.id, p]));

    const tickets = [];
    for (const row of rows) {
      tickets.push(await ticketView(store, row, {
        category: byId.get(row.category_id),
        raiser: byPerson.get(row.created_by) || null,
        assignee: row.assignee_id ? (byPerson.get(row.assignee_id) || null) : null,
        me: req.auth.employee.id,
        seesName: !row.anonymous || row.created_by === req.auth.employee.id || seesRaiser(role, row),
        overdueMinutes: overdueMinutesOf(row, nowDate, holidaysFor(holidayRows, row.branch_id ?? null)),
      }));
    }
    res.json({
      tickets,
      // The categories the role serves, so the app's filter chips need no second call.
      categories: serving.map(categoryView),
    });
  });
}

module.exports = { listQueue, QUEUE_STATUSES };
