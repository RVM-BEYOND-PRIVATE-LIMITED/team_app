const { ACTIVE_STATUSES } = require('../policy/helpdesk');
const { workingSpan, holidaysFor, firstResponseOverdue } = require('../policy/helpdesk');
const { ROLES } = require('../policy/roles');
const { notifyEscalation } = require('../lib/helpdeskNotify');

/**
 * The Helpdesk's escalations (task G3): one small job in the same shape as the Wall's
 * (src/jobs/wall.js), running inside the ESS process every hour. It walks the tickets still
 * being worked on and escalates each stage once, the row's escalation_level being the gate:
 *
 *   level 1  no first response past its deadline: the category's queue roles are told;
 *   level 2  unresolved past its resolution deadline: the HoO is told;
 *   level 3  unresolved a full resolution span past the deadline (working hours): the CEO is told.
 *
 * The deadlines are the ones stored at raise (G3), judged against the clock here, not worked out
 * again. One run may carry a badly neglected ticket through more than one stage, but each stage
 * notifies once: the stamp is written after the notifications are sent (best effort, as every
 * notification is), so a crash between the two can repeat one stage's words, never lose them.
 *
 * One instance only (ecosystem.config.cjs, fork mode), as for the Wall's job.
 */

const HOUR_MS = 60 * 60 * 1000;
/** The job walks at most this many live tickets an hour; the queue's own limit is far smaller. */
const WALK_LIMIT = 500;

/**
 * @param {object} deps
 * @param {object} deps.store
 * @param {() => Date} [deps.now]
 * @param {object} [deps.log]      console by default; tests pass a spy
 * @param {number} [deps.intervalMs]
 * @param {boolean} [deps.immediate]  run once at start (production); tests may switch it off
 */
function startHelpdeskJob({ store, now = () => new Date(), log = console, intervalMs = HOUR_MS, immediate = true }) {
  let running = false;

  /** The employee ids behind a set of portal roles, for one stage's recipients. */
  async function peopleForRoles(roles) {
    try {
      return await store.listEmployeeIdsForRoles(roles);
    } catch (e) {
      log.error(`[ess] helpdesk job: recipients for ${roles.join(', ')} failed: ${e && e.message ? e.message : e}`);
      return [];
    }
  }

  async function runOnce() {
    if (running) return null;
    running = true;
    try {
      const nowDate = now();
      const at = nowDate.toISOString();
      const rows = await store.listActiveHelpdeskTickets([...ACTIVE_STATUSES], WALK_LIMIT);
      const categories = new Map(
        (await store.listHelpdeskCategories()).map((c) => [c.id, c]),
      );
      // The holidays from today forwards: the level-3 span is counted in working hours.
      const holidayRows = await store.listHolidays(at.slice(0, 10),
        new Date(nowDate.getTime() + 60 * 86400000).toISOString().slice(0, 10));

      let escalated = 0;
      for (const row of rows) {
        const category = categories.get(row.category_id);
        if (!category) continue;
        const holidays = holidaysFor(holidayRows, row.branch_id ?? null);
        for (const level of [1, 2, 3]) {
          if ((row.escalation_level || 0) >= level) continue;
          const due = level === 1 ? row.first_response_due_at : row.resolution_due_at;
          const overdue = level === 1
            ? firstResponseOverdue(row, nowDate)
            : Date.parse(due) <= nowDate.getTime();
          if (!overdue) continue;
          if (level === 3) {
            // A full resolution span past the deadline, in working hours (G3).
            const finalBy = workingSpan(new Date(due), category.resolution_hours * 60, holidays);
            if (finalBy.getTime() > nowDate.getTime()) continue;
          }
          const recipients = await peopleForRoles(
            level === 1 ? (category.queue_roles || []) : [level === 2 ? ROLES.HOO : ROLES.CEO],
          );
          await notifyEscalation({ store, ticket: row, level, recipients });
          const saved = await store.updateHelpdeskTicket(row.id, { escalation_level: level, updated_at: at });
          if (saved) row.escalation_level = level;
          escalated += 1;
        }
      }
      if (escalated) log.log(`[ess] helpdesk job: escalated ${escalated}`);
      return { escalated };
    } finally {
      running = false;
    }
  }

  const timer = setInterval(runOnce, intervalMs);
  if (typeof timer.unref === 'function') timer.unref();
  if (immediate) runOnce();

  return { runOnce, stop: () => clearInterval(timer) };
}

module.exports = { startHelpdeskJob };
