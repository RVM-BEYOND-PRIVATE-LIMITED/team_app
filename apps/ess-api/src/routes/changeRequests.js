const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const { bodyWith, requiredText, optionalText, idParam, oneQueryValue, chars } = require('../lib/validate');
const { LIST_LIMITS } = require('../lib/store');

/**
 * Profile-change requests (Phase 2C, E3): a person asks for their date of birth, address or
 * legal name to be corrected; HR answers it. The ESS records the DECISION only (KP, 19 Oct 2026)
 * — it never writes hr_employees, because the Scheduler's HR record stays the system of record
 * (ADR-0003) and the ESS writes its own tables (ADR-0021). HR applies an approved change in the
 * Scheduler by hand; the request row is the paper trail.
 *
 * One open request per field per person: the route checks first, and the database's partial
 * unique index (hr_ess_change_requests_open_field_key) is the backstop for two saves made at
 * once — both answer 409 CHANGE_ALREADY_OPEN.
 */

/** The fields a request may be about, and the words each takes in a reply. */
const FIELDS = Object.freeze(['date_of_birth', 'address', 'legal_name']);

const invalid = (message) => new HttpError(400, 'VALIDATION_FAILED', message);
const notFound = (message) => new HttpError(404, 'NOT_FOUND', message);

/** One request as every read shows it: the ask and the answer, never the decider's user id. */
const changeRequestView = (row) => ({
  id: row.id,
  employee_id: row.employee_id,
  field: row.field,
  old_value: row.old_value ?? null,
  new_value: row.new_value,
  reason: row.reason,
  status: row.status,
  decided_by_name: row.decided_by_name ?? null,
  decided_at: row.decided_at ?? null,
  decision_note: row.decision_note ?? null,
  created_at: row.created_at,
  updated_at: row.updated_at,
});

/** GET /api/ess/me/change-requests — my asks, newest first (E3). */
function listMyChangeRequests({ store }) {
  return asyncRoute(async (req, res) => {
    const rows = await store.listMyChangeRequests(req.auth.employee.id);
    res.json({ requests: rows.slice(0, LIST_LIMITS.changeRequests).map(changeRequestView) });
  });
}

/** POST /api/ess/me/change-requests { field, old_value?, new_value, reason } — ask for a correction (E3). */
function createMyChangeRequest({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const form = bodyWith(req, ['field', 'old_value', 'new_value', 'reason']);

    const field = form.field;
    if (!FIELDS.includes(field)) throw invalid(MESSAGES.CHANGE_FIELD);

    // "I do not know what it says": old_value may be left out, or null.
    const oldValue = optionalText(form.old_value);
    if (oldValue === undefined) throw invalid(MESSAGES.CHANGE_OLD_VALUE);
    if (oldValue && chars(oldValue) > 500) throw invalid(MESSAGES.CHANGE_OLD_VALUE);

    const newValue = typeof form.new_value === 'string' ? form.new_value.trim() : '';
    if (!newValue || chars(newValue) > 500) throw invalid(MESSAGES.CHANGE_NEW_VALUE);

    const reason = requiredText(form.reason, { min: 5, max: 1000, message: MESSAGES.CHANGE_REASON });

    // The route's own check first, so the usual case never reaches the database's index.
    const mine = await store.listMyChangeRequests(employee.id);
    if (mine.some((r) => r.status === 'open' && r.field === field)) {
      throw new HttpError(409, 'CHANGE_ALREADY_OPEN', MESSAGES.CHANGE_ALREADY_OPEN);
    }

    const at = now().toISOString();
    const created = await store.createChangeRequest({
      employee_id: employee.id,
      field,
      old_value: oldValue,
      new_value: newValue,
      reason,
      created_at: at,
      updated_at: at,
    });
    res.status(201).json({ request: changeRequestView(created) });
  });
}

/** The `?status=` filter HR's queue takes: null for 'all' or no value, or the one status. */
function changeStatusFilter(value) {
  if (value === undefined || value === null || value === '' || value === 'all') return null;
  if (!['open', 'approved', 'rejected'].includes(value)) throw invalid(MESSAGES.CHANGE_STATUS_FILTER);
  return [value];
}

/** GET /api/ess/hr/change-requests?status= — HR's queue, newest first (E3). */
function listChangeRequests({ store }) {
  return asyncRoute(async (req, res) => {
    const rows = await store.listChangeRequests(changeStatusFilter(oneQueryValue(req.query.status)));
    res.json({ requests: rows.slice(0, LIST_LIMITS.hrChangeRequests).map(changeRequestView) });
  });
}

/** POST /api/ess/hr/change-requests/:id/decide { decision, note? } — HR answers it (E3). */
function decideChangeRequest({ store, now }) {
  return asyncRoute(async (req, res) => {
    const form = bodyWith(req, ['decision', 'note']);
    const approve = form.decision === 'approved';
    if (!approve && form.decision !== 'rejected') throw invalid(MESSAGES.CHANGE_DECISION);

    // A rejection says why in the employee's own copy; an approval's note stays optional.
    let note = optionalText(form.note);
    if (note === undefined) throw invalid(MESSAGES.CHANGE_NOTE);
    if (!approve) {
      if (!note || chars(note) < 3) throw invalid(MESSAGES.CHANGE_REJECT_NOTE);
      if (chars(note) > 1000) throw invalid(MESSAGES.CHANGE_NOTE);
    } else if (note && chars(note) > 1000) {
      throw invalid(MESSAGES.CHANGE_NOTE);
    }

    const row = await store.getChangeRequest(idParam(req.params.id));
    if (!row) throw notFound(MESSAGES.CHANGE_NOT_FOUND);

    // Records the decision only: never a write to hr_employees (the header).
    const at = now().toISOString();
    const updated = await store.decideChangeRequest(row.id, {
      status: approve ? 'approved' : 'rejected',
      decided_by_user_id: req.auth.userId,
      decided_by_name: req.auth.employee.full_name,
      decided_at: at,
      decision_note: note || null,
      updated_at: at,
    });
    if (!updated) throw new HttpError(409, 'ALREADY_DECIDED', MESSAGES.ALREADY_DECIDED);
    res.json({ request: changeRequestView(updated) });
  });
}

module.exports = {
  listMyChangeRequests,
  createMyChangeRequest,
  listChangeRequests,
  decideChangeRequest,
};
