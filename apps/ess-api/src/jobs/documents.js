/**
 * The weekly missing-documents reminder (Phase 2C, KP 1): one job in the shape of the Helpdesk's
 * escalations (src/jobs/helpdesk.js), running inside the ESS process. It walks the people still
 * on strength and reminds anybody whose record is missing a mandatory document — the types the
 * migration seeds with is_mandatory (identity, offer, joining), read from the database so KP can
 * turn one off with one UPDATE.
 *
 * One notification per person per run, category `documents` (the migration's CHECK widened with
 * it), which the person can turn off in the notification settings like any other. The push
 * worker delivers it; nothing here pushes by itself.
 *
 * Weekly: the timer fires every seven days, plus once at boot (production), in the shape of the
 * other jobs. One instance only (ecosystem.config.cjs, fork mode).
 */

const WEEK_MS = 7 * 24 * 60 * 60 * 1000;

/** @param {object} deps  { store, now?, log?, intervalMs?, immediate? } */
function startDocumentsJob({ store, now = () => new Date(), log = console, intervalMs = WEEK_MS, immediate = true }) {
  let running = false;

  async function runOnce() {
    if (running) return null;
    running = true;
    try {
      const types = (await store.listDocumentTypes()).filter((t) => t.is_mandatory === true);
      if (!types.length) return { reminded: 0 };
      const mandatory = new Set(types.map((t) => t.slug));

      // One read of the pointers (who holds what), one of the people still on strength; the
      // missing set is worked out in memory, exactly as the celebration cards do. A person is
      // asked for the types they personally lack, so one held letter does not hide the rest.
      const heldBy = new Map();
      for (const d of await store.listDocumentEmployeeTypes()) {
        if (!mandatory.has(d.doc_type)) continue;
        if (!heldBy.has(d.employee_id)) heldBy.set(d.employee_id, new Set());
        heldBy.get(d.employee_id).add(d.doc_type);
      }
      const people = await store.listAudienceEmployees();
      const missing = [];
      for (const person of people) {
        const held = heldBy.get(person.id) || new Set();
        const lacking = types.filter((t) => !held.has(t.slug));
        if (lacking.length) missing.push({ person, names: lacking.map((t) => t.name).join(', ') });
      }
      if (!missing.length) return { reminded: 0 };

      const at = now().toISOString();
      let reminded = 0;
      for (const { person, names } of missing) {
        try {
          await store.createNotification({
            employee_id: person.id,
            category: 'documents',
            title: 'Documents missing',
            body: `Your record is missing: ${names}. Upload them in My Documents.`,
            data: {},
            created_at: at,
          });
          reminded += 1;
        } catch (e) {
          log.error(`[ess] documents job: reminder for ${person.id} failed: ${e && e.message ? e.message : e}`);
        }
      }
      if (reminded) log.log(`[ess] documents job: reminded ${reminded}`);
      return { reminded };
    } finally {
      running = false;
    }
  }

  const timer = setInterval(runOnce, intervalMs);
  if (typeof timer.unref === 'function') timer.unref();
  if (immediate) runOnce();

  return { runOnce, stop: () => clearInterval(timer) };
}

module.exports = { startDocumentsJob };
