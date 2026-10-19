const { ESCALATE_AFTER_DAYS, chainEntries, nextEscalation } = require('../policy/approvals');
const { REQUEST_TYPE_LABELS, dmy } = require('../policy/notifications');

/**
 * The approval chain's escalations (Phase 2D, task D4): one small job in the same shape as the
 * Helpdesk's (src/jobs/helpdesk.js), running inside the ESS process every hour. It walks the
 * requests that have been pending longer than ESCALATE_AFTER_DAYS and moves each one up the
 * reporting line: the first level that may decide it and has not been escalated yet is recorded
 * in hr_ess_approval_escalations and told by an 'approvals' notification. When the chain runs
 * out, HR is the fallback (the people whose portal role is `hr`, as a new request's approver is).
 *
 * The table's unique key (family, request_id, to_employee_id) is the gate: a request escalates
 * once per level, and the run that races itself is simply already recorded. A skipped level (the
 * requester themselves, not on strength, on leave) is never a target -- the next one up is.
 *
 * One instance only (ecosystem.config.cjs, fork mode), as for the other jobs.
 */

const HOUR_MS = 60 * 60 * 1000;
/** The job walks at most this many pending requests a run, per family. */
const WALK_LIMIT = 500;

/**
 * @param {object} deps
 * @param {object} deps.store
 * @param {() => Date} [deps.now]
 * @param {object} [deps.log]      console by default; tests pass a spy
 * @param {number} [deps.intervalMs]
 * @param {boolean} [deps.immediate]  run once at start (production); tests may switch it off
 */
function startApprovalsJob({ store, now = () => new Date(), log = console, intervalMs = HOUR_MS, immediate = true }) {
  let running = false;

  async function runOnce() {
    if (running) return null;
    running = true;
    try {
      const at = now();
      const today = at.toISOString().slice(0, 10);
      const beforeIso = new Date(at.getTime() - ESCALATE_AFTER_DAYS * 86400000).toISOString();

      // The chain and the day's leave are the same for every request of a run whose day is today;
      // each request's own day decides whose leave skips a level, read per request below.
      const [people, hrUserIds] = await Promise.all([
        store.listActiveEmployees(),
        store.listHrUserIds(),
      ]);
      const byId = new Map(people.map((e) => [e.id, e]));
      const hrPeople = hrUserIds.length
        ? (await store.listEmployeesByUserIds(hrUserIds.map((u) => u.id))).filter((e) => byId.has(e.id))
        : [];

      let escalated = 0;
      for (const family of ['attendance', 'leave']) {
        const rows = await store.listPendingRequestsSince(family, beforeIso, WALK_LIMIT);
        for (const row of rows) {
          const requester = byId.get(row.employee_id);
          if (!requester) continue;
          const offRows = await store.listDaysOnLeave([row.day]);
          const offOnDay = new Set(offRows.map((d) => d.employee_id));
          const entries = chainEntries(byId, requester, today, offOnDay);
          const already = new Set(
            (await store.listEscalationsFor(family, row.id)).map((e) => e.to_employee_id),
          );
          const target = nextEscalation({ entries, escalatedIds: already });
          const targets = target ? [target] : hrPeople
            .filter((e) => !already.has(e.id))
            .map((employee) => ({ employee, skipped: null }));
          for (const { employee } of targets) {
            if (employee.id === requester.id) continue;
            const saved = await store.createEscalation({
              family,
              request_id: row.id,
              from_employee_id: entries.length ? entries[0].employee.id : null,
              to_employee_id: employee.id,
              reason: `Pending since ${dmy(row.created_at.slice(0, 10))} past ${ESCALATE_AFTER_DAYS} days.`,
              escalated_at: at.toISOString(),
            });
            if (!saved) continue;
            escalated += 1;
            // Best effort, as every notification is (D6/D7): the row is the record.
            try {
              await store.createNotification({
                employee_id: employee.id,
                category: 'approvals',
                title: 'Request awaiting decision',
                body: `${requester.full_name}'s ${REQUEST_TYPE_LABELS[row.type] || row.type} request of ${dmy(row.day)} has been pending for more than ${ESCALATE_AFTER_DAYS} days.`,
                data: { request_id: row.id, request_family: family },
              });
            } catch (e) {
              log.error(`[ess] approvals job: notification failed: ${e && e.message ? e.message : e}`);
            }
          }
        }
      }
      if (escalated) log.log(`[ess] approvals job: escalated ${escalated}`);
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

module.exports = { startApprovalsJob };
