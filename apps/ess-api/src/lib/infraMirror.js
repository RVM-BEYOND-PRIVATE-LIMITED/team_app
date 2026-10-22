const { istDay } = require('./time');

/**
 * G6 (Phase 2D; KP, 22 Oct 2026): the Admin Manager's infra register mirror.
 *
 * A lab or facility helpdesk ticket also gets one summary row in the Scheduler's infra_tickets
 * (supabase/migrations/20260804000003:113-130), linked to the ticket through hr_ess_infra_links
 * (migration 20261112000001). The register has no thread and no in-progress state, so the
 * helpdesk stays the system of record and the register gets the summary the Admin Manager audits.
 *
 * The mapping is the one docs/02-reconciliation.md, G6, asks for:
 *   it_lab   -> audit_type A (IT & PCs)
 *   facility -> audit_type D (facility/maintenance/AMC)
 *   branch   -> locations by name (the two vocabularies differ)
 *   anonymous tickets carry no identity (raised_by and owner null)
 *   punch-only raisers have no users row, so raised_by is null and the name goes to owner
 *
 * The mirror is best effort: a register that cannot be written never fails the raise. The link
 * records why (`skipped`), and the hourly job retries it once the data is fixed. Closing syncs
 * both ways without a Scheduler change: the ESS closes the register row when the ticket closes,
 * and the job resolves the ticket when the Admin Manager closes the register row.
 */

const AUDIT_TYPES = Object.freeze({ it_lab: 'A', facility: 'D' });
const SYNCS = Object.freeze({ linked: 'linked', skipped: 'skipped' });

const auditTypeOf = (category) => (category ? AUDIT_TYPES[category.slug] || null : null);

/** The `locations.id` whose name matches the ticket's branch, or null (the two vocabularies). */
async function locationIdForBranch(store, branchId) {
  if (!branchId) return null;
  const branch = await store.getBranch(branchId);
  if (!branch || !branch.name) return null;
  const want = String(branch.name).trim().toLowerCase();
  const locations = await store.listLocations();
  const found = locations.find((l) => String(l.name || '').trim().toLowerCase() === want);
  return found ? found.id : null;
}

/** The summary line the register holds: the reference and the subject, never the thread. */
const issueOf = (ticket) => `${ticket.ref}: ${ticket.subject}`;

/**
 * Make the register row and the link. Called once at raise and again by the job for a skipped
 * link. It never deletes anything; a link is unique per ticket, and the job updates it in place.
 */
async function insertMirror({ store, ticket, category, raiser, raiserUserId, at }) {
  const auditType = auditTypeOf(category);
  if (!auditType) return null;
  const locationId = await locationIdForBranch(store, ticket.branch_id);
  if (!locationId) {
    await store.updateInfraLink((await store.getInfraLinkForTicket(ticket.id)).id,
      { state: SYNCS.skipped, reason: 'branch_not_mapped', last_synced_at: at });
    return { state: SYNCS.skipped, reason: 'branch_not_mapped' };
  }
  const anonymous = ticket.anonymous === true;
  const infra = await store.createInfraTicket({
    location_id: locationId,
    raised_on: istDay(new Date(at)),
    audit_type: auditType,
    issue: issueOf(ticket),
    owner: !anonymous && raiser ? raiser.full_name ?? null : null,
    deadline: ticket.resolution_due_at ? istDay(new Date(ticket.resolution_due_at)) : null,
    raised_by: !anonymous && raiserUserId ? raiserUserId : null,
  });
  const link = await store.getInfraLinkForTicket(ticket.id);
  await store.updateInfraLink(link.id, {
    infra_ticket_id: infra.id,
    state: SYNCS.linked,
    reason: null,
    last_synced_at: at,
  });
  return { state: SYNCS.linked, infra };
}

/**
 * At raise: create the link row first (so a failure is retryable), then the register row.
 * Returns null for a category that is not mirrored, and never throws.
 */
async function mirrorRaised({ store, ticket, category, raiser, raiserUserId = null, at, log = console }) {
  if (!auditTypeOf(category)) return null;
  try {
    await store.createInfraLink({ ticket_id: ticket.id, state: SYNCS.skipped, reason: 'mirror_pending', created_at: at });
  } catch (e) {
    log.error(`[ess] infra link failed for ticket ${ticket.id}: ${e && e.message ? e.message : e}`);
    return null;
  }
  try {
    return await insertMirror({ store, ticket, category, raiser, raiserUserId, at });
  } catch (e) {
    log.error(`[ess] infra mirror failed for ticket ${ticket.id}: ${e && e.message ? e.message : e}`);
    await store.updateInfraLink((await store.getInfraLinkForTicket(ticket.id)).id,
      { state: SYNCS.skipped, reason: 'mirror_failed', last_synced_at: at }).catch(() => null);
    return null;
  }
}

/** The ESS -> register direction: the ticket closed, so its register row closes too. */
async function closeRegisterForTicket({ store, ticketId, at, log = console }) {
  try {
    const link = await store.getInfraLinkForTicket(ticketId);
    if (!link || link.state !== SYNCS.linked || !link.infra_ticket_id) return null;
    const infra = await store.getInfraTicket(link.infra_ticket_id);
    if (!infra || infra.status === 'closed') return null;
    const closed = await store.closeInfraTicket(infra.id, istDay(new Date(at)));
    await store.updateInfraLink(link.id, { last_synced_at: new Date(at).toISOString() });
    return closed;
  } catch (e) {
    log.error(`[ess] closing infra ticket for ${ticketId} failed: ${e && e.message ? e.message : e}`);
    return null;
  }
}

/**
 * The job's retry of a skipped link, and its read of a linked one. `retrySkipped` reloads the
 * ticket and category and, if the branch now maps, makes the register row and updates the link.
 */
async function retrySkipped({ store, link, at, log = console }) {
  try {
    const ticket = await store.getHelpdeskTicket(link.ticket_id);
    if (!ticket) return null;
    const category = await store.getHelpdeskCategoryById(ticket.category_id);
    if (!auditTypeOf(category)) {
      await store.updateInfraLink(link.id, { reason: 'not_mirrored', last_synced_at: at });
      return null;
    }
    const raiser = ticket.anonymous ? null : await store.getEmployeeById(ticket.created_by);
    const linkRow = ticket.anonymous ? null : await store.getEmployeeLink(ticket.created_by);
    return await insertMirror({
      store, ticket, category, raiser, raiserUserId: linkRow ? linkRow.user_id : null, at,
    });
  } catch (e) {
    log.error(`[ess] retrying infra mirror for ${link.ticket_id} failed: ${e && e.message ? e.message : e}`);
    return null;
  }
}

module.exports = {
  AUDIT_TYPES,
  auditTypeOf,
  locationIdForBranch,
  mirrorRaised,
  closeRegisterForTicket,
  retrySkipped,
};
