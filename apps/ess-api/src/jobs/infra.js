const { retrySkipped } = require('../lib/infraMirror');
const { notifyStatus } = require('../lib/helpdeskNotify');
const { eventRow } = require('../lib/helpdeskKit');

/**
 * The infra register's close-sync (Phase 2D, G6; KP, 22 Oct 2026). One small job in the same
 * shape as the Helpdesk's and the Wall's, inside the ESS process every hour:
 *
 *   register -> helpdesk   a linked ticket whose register row is now closed is resolved, with a
 *                          system event and the raiser told. This is the "both ways" half the
 *                          reconciliation asks for, done without changing the Scheduler's own
 *                          closeInfraTicket (ADR-0018).
 *   retry                  a link that was skipped (branch not mapped, register unreachable) is
 *                          retried; the link row is updated in place, so a retry is idempotent.
 *
 * One instance only (ecosystem.config.cjs, fork mode), as for the other jobs.
 */

const HOUR_MS = 60 * 60 * 1000;
const LIMIT = 500;

function startInfraJob({ store, now = () => new Date(), log = console, intervalMs = HOUR_MS, immediate = true }) {
  let running = false;

  async function runOnce() {
    if (running) return null;
    running = true;
    try {
      const at = now().toISOString();
      let resolved = 0;
      let linked = 0;

      const links = await store.listLinkedInfraLinks(LIMIT);
      const infras = await store.listInfraTicketsByIds(links.map((l) => l.infra_ticket_id).filter(Boolean));
      const byId = new Map(infras.map((i) => [i.id, i]));
      for (const link of links) {
        const infra = byId.get(link.infra_ticket_id);
        if (!infra || infra.status !== 'closed') continue;
        const ticket = await store.getHelpdeskTicketOwn(link.ticket_id);
        if (!ticket || !['open', 'in_progress', 'on_hold'].includes(ticket.status)) continue;
        const updated = await store.updateHelpdeskTicket(ticket.id, {
          status: 'resolved', resolved_at: at, updated_at: at,
        });
        await store.createHelpdeskMessage(eventRow(ticket.id, 'register_closed', {
          infra_ticket_id: infra.id, infra_ticket_no: infra.ticket_no ?? null,
        }, at));
        // Best effort, as every notification is (D6/D7): the row is the record.
        try {
          await notifyStatus({
            store, ticket: updated, raiserId: ticket.created_by, status: 'resolved', byName: 'the Admin Manager',
          });
        } catch (e) {
          log.error(`[ess] infra job: notification failed: ${e && e.message ? e.message : e}`);
        }
        await store.updateInfraLink(link.id, { last_synced_at: at });
        resolved += 1;
      }

      const skipped = await store.listSkippedInfraLinks(LIMIT);
      for (const link of skipped) {
        const out = await retrySkipped({ store, link, at, log });
        if (out && out.state === 'linked') linked += 1;
      }

      if (resolved || linked) log.log(`[ess] infra job: ${resolved} resolved from the register, ${linked} linked`);
      return { resolved, linked };
    } catch (e) {
      // A missing link table (before migration 27) or an outage is logged and retried next hour;
      // the process must never go down because the register is unreachable.
      log.error(`[ess] infra job: ${e && e.message ? e.message : e}`);
      return null;
    } finally {
      running = false;
    }
  }

  const timer = setInterval(runOnce, intervalMs);
  if (typeof timer.unref === 'function') timer.unref();
  if (immediate) runOnce();

  return { runOnce, stop: () => clearInterval(timer) };
}

module.exports = { startInfraJob };
