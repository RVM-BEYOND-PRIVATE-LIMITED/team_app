/**
 * The ESS's audit trail, hr_ess_audit: who did what to whose data (task 6; DPDP: who looked at
 * whose personal details). Not readable through the API yet.
 *
 * `details` carries ids, counts and the reason HR typed, never the personal data itself: a
 * trail of who read whose date of birth must not become a second copy of the dates of birth.
 * The Scheduler learnt the same about its own trail (docs/02-reconciliation.md, E9: the CEO
 * audit view shows hr_activity_events values verbatim).
 *
 * Two ways to write it, because a read and a write fail differently:
 *
 *   recordBefore  for HR reading someone's personal details. The row is written before the
 *                 data leaves the server, and a failure refuses the read (503), so nobody sees
 *                 personal data without the trail saying so.
 *   recordAfter   for HR changing something. The change is made first, so the row can say what
 *                 changed (which phones were reset). If the row then cannot be written, the
 *                 change stands and the whole entry goes to the pm2 log instead, marked so it
 *                 can be found: refusing after the change was made would only make the app try
 *                 again and find the work already done.
 */

/** The audit row for an action by the signed-in HR person. */
function entry(req, { action, targetEmployeeId = null, details = {} }) {
  const { userId, employee } = req.auth;
  return {
    actor_user_id: userId ?? null,
    actor_employee_id: employee.id,
    actor_name: employee.full_name,
    action,
    target_employee_id: targetEmployeeId,
    details,
  };
}

const recordBefore = (store, req, what) => store.writeAudit(entry(req, what));

async function recordAfter(store, req, what) {
  const row = entry(req, what);
  try {
    await store.writeAudit(row);
  } catch {
    // The store has already logged why. Ids, counts and HR's reason only: no token, no secret.
    console.error(`[ess] AUDIT NOT WRITTEN, keep this line: ${JSON.stringify(row)}`);
  }
}

module.exports = { recordBefore, recordAfter, auditEntry: entry };
