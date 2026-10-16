const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const { bodyWith, requiredText, optionalText, chars, idParam, invalid, oneQueryValue } = require('../lib/validate');
const { recordAfter } = require('../lib/audit');
const { LIST_LIMITS } = require('../lib/store');

/**
 * Task A8: "Request correction or deletion of my data" in Me, routed to HR (brief p.33;
 * docs/02-reconciliation.md, A8). The employee files a request; HR marks it done or rejected
 * with a note. The request only records what was asked and what HR answered: HR makes the
 * change itself, in the Scheduler's HR tools, so nothing here edits an HR record.
 */

const KINDS = ['correct', 'delete'];
const RESOLUTIONS = ['done', 'rejected'];
const STATUS_FILTERS = ['open', 'done', 'rejected', 'all'];

/**
 * Enough open requests to cover a real need; more is a stuck button or a flood for HR. The same
 * number is in db/migrations/20261105000001_hr_ess_data_requests.sql, which enforces it: change both.
 */
const MAX_OPEN_REQUESTS = 5;

/** The employee's own view: what they asked and HR's answer, without HR's account details. */
const ownView = (r) => ({
  id: r.id,
  kind: r.kind,
  details: r.details,
  status: r.status,
  created_at: r.created_at,
  resolved_at: r.resolved_at ?? null,
  resolution_note: r.resolution_note ?? null,
});

const card = (e) => (e ? { id: e.id, full_name: e.full_name, employee_code: e.employee_code ?? null } : null);

const hrView = (r, employee) => ({
  ...ownView(r),
  resolved_by_name: r.resolved_by_name ?? null,
  employee: card(employee),
});

/** POST /api/ess/me/data-requests { kind, details }: file a request about my own data. */
function createMyDataRequest({ store }) {
  return asyncRoute(async (req, res) => {
    const body = bodyWith(req, ['kind', 'details']);
    if (!KINDS.includes(body.kind)) throw invalid(MESSAGES.DATA_REQUEST_KIND);
    const details = requiredText(body.details, { min: 5, max: 2000, message: MESSAGES.DATA_REQUEST_DETAILS });
    const { employee } = req.auth;
    const tooMany = () => new HttpError(409, 'TOO_MANY_OPEN_REQUESTS', MESSAGES.TOO_MANY_OPEN_REQUESTS);
    if (await store.countOpenDataRequests(employee.id) >= MAX_OPEN_REQUESTS) throw tooMany();
    // The count above is a courtesy: requests sent in parallel all pass it. The database counts
    // again as the row goes in, under a lock per employee (hr_ess_data_requests_open_limit), and
    // that count is the one that holds.
    const created = await store.createDataRequest({ employee_id: employee.id, kind: body.kind, details });
    if (!created) throw tooMany();
    res.status(201).json({ request: ownView(created) });
  });
}

/** GET /api/ess/me/data-requests: my own requests, newest first. */
function listMyDataRequests({ store }) {
  return asyncRoute(async (req, res) => {
    const rows = await store.listMyDataRequests(req.auth.employee.id);
    res.json({ requests: rows.map(ownView) });
  });
}

/** GET /api/ess/hr/data-requests?status=open|done|rejected|all (open by default): HR's queue. */
function listDataRequests({ store }) {
  return asyncRoute(async (req, res) => {
    const raw = oneQueryValue(req.query.status);
    const status = raw === undefined ? 'open' : raw;
    if (!STATUS_FILTERS.includes(status)) throw invalid(MESSAGES.DATA_REQUEST_STATUS_FILTER);
    const rows = await store.listDataRequests({ status: status === 'all' ? null : status });
    const truncated = rows.length > LIST_LIMITS.dataRequests;
    const shown = rows.slice(0, LIST_LIMITS.dataRequests);
    const people = new Map((await store.listEmployeeCards(shown.map((r) => r.employee_id))).map((e) => [e.id, e]));
    res.json({ requests: shown.map((r) => hrView(r, people.get(r.employee_id))), truncated });
  });
}

/**
 * PATCH /api/ess/hr/data-requests/:id { status: 'done'|'rejected', note }.
 *
 * Nobody resolves a request about their own data (409 OWN_REQUEST): an HR person who wants
 * their own record corrected asks a colleague, as anybody else does. A rejection needs a note,
 * because the employee is owed the reason.
 */
function resolveDataRequest({ store, now }) {
  return asyncRoute(async (req, res) => {
    const id = idParam(req.params.id);
    const body = bodyWith(req, ['status', 'note']);
    if (!RESOLUTIONS.includes(body.status)) throw invalid(MESSAGES.RESOLVE_STATUS);
    const note = optionalText(body.note);
    if (note === undefined || (note && chars(note) > 1000)) throw invalid(MESSAGES.RESOLVE_NOTE);
    if (body.status === 'rejected' && (!note || chars(note) < 3)) throw invalid(MESSAGES.REJECT_NOTE_REQUIRED);

    const existing = await store.getDataRequest(id);
    if (!existing) throw new HttpError(404, 'NOT_FOUND', MESSAGES.DATA_REQUEST_NOT_FOUND);
    if (existing.employee_id === req.auth.employee.id) throw new HttpError(409, 'OWN_REQUEST', MESSAGES.OWN_REQUEST);
    if (existing.status !== 'open') throw new HttpError(409, 'ALREADY_RESOLVED', MESSAGES.ALREADY_RESOLVED);

    const resolved = await store.resolveDataRequest(id, {
      status: body.status,
      resolved_at: now().toISOString(),
      resolved_by_user_id: req.auth.userId,
      resolved_by_name: req.auth.employee.full_name,
      resolution_note: note,
    });
    // Somebody else resolved it between the read and the write.
    if (!resolved) throw new HttpError(409, 'ALREADY_RESOLVED', MESSAGES.ALREADY_RESOLVED);

    await recordAfter(store, req, {
      action: 'data_request.resolved',
      targetEmployeeId: resolved.employee_id,
      details: { request_id: resolved.id, kind: resolved.kind, status: resolved.status },
    });
    res.json({ request: hrView(resolved, await store.getEmployeeCard(resolved.employee_id)) });
  });
}

module.exports = {
  createMyDataRequest,
  listMyDataRequests,
  listDataRequests,
  resolveDataRequest,
  MAX_OPEN_REQUESTS,
};
