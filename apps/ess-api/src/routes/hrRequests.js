const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const { bodyWith, requiredText, idParam, invalid } = require('../lib/validate');
const { REQUEST_TYPES, requestType } = require('../policy/requestLimits');
const { requestView } = require('../policy/requests');
const { recordAfter } = require('../lib/audit');

/**
 * HR's own tools for requests (tasks C6, C8, H6): cancelling an approved request by restoring
 * the day it wrote, and the monthly limits HR can change. The role guard (ATTENDANCE_ROLES: hr,
 * the CEO, super admins; never an HR Executive, whose powers exclude attendance and leave) is
 * attached in app.js, before these handlers.
 */

const KNOWN_TYPES = REQUEST_TYPES.map((t) => t.type);

const limitView = (r) => ({
  type: r.type,
  limit_count: r.limit_count ?? null,
  limit_minutes: r.limit_minutes ?? null,
  updated_at: r.updated_at,
  updated_by_name: r.updated_by_name ?? null,
});

/** One cancel, mapped from the function's outcome; both families share it. */
async function cancel({ store, now, req, res, family }) {
  const id = idParam(req.params.id);
  const body = bodyWith(req, ['reason']);
  const reason = requiredText(body.reason, { min: 3, max: 200, message: MESSAGES.CANCEL_REASON });
  const args = {
    p_request_id: id,
    p_by_employee_id: req.auth.employee.id,
    p_by_user_id: req.auth.userId ?? null,
    p_by_name: req.auth.employee.full_name,
    p_reason: reason,
    p_now: now().toISOString(),
  };
  const out = family === 'leave'
    ? await store.cancelLeaveRequest(args)
    : await store.cancelAttendanceRequest(args);
  const outcome = out && out.outcome;
  if (outcome === 'not_found') throw new HttpError(404, 'NOT_FOUND', MESSAGES.REQUEST_NOT_FOUND);
  if (outcome === 'not_approved') throw new HttpError(409, 'CANNOT_CANCEL', MESSAGES.CANNOT_CANCEL);

  // The day's new state and the request are both read back: the reply is what HR now sees.
  const fresh = family === 'leave' ? await store.getLeaveRequest(id) : await store.getAttendanceRequest(id);
  await recordAfter(store, req, {
    action: family === 'leave' ? 'leave_request.cancelled' : 'attendance_request.cancelled',
    targetEmployeeId: fresh.employee_id,
    details: { request_id: id, day: fresh.day },
  });
  res.json({ request: requestView(fresh, family) });
}

/** POST /api/ess/hr/attendance-requests/:id/cancel { reason } — after an approval, HR only. */
function cancelAttendanceRequest({ store, now }) {
  return asyncRoute(async (req, res) => cancel({ store, now, req, res, family: 'attendance' }));
}

/** POST /api/ess/hr/leave-requests/:id/cancel { reason } — after an approval, HR only. */
function cancelLeaveRequest({ store, now }) {
  return asyncRoute(async (req, res) => cancel({ store, now, req, res, family: 'leave' }));
}

/** GET /api/ess/hr/request-limits: every type and the number HR set. */
function listRequestLimits({ store }) {
  return asyncRoute(async (_req, res) => {
    const rows = await store.getRequestLimits();
    res.json({ limits: rows.map(limitView) });
  });
}

/**
 * PUT /api/ess/hr/request-limits/:type { limit_count } or { limit_minutes }.
 * Exactly the type's own unit: a count type takes limit_count, short leave limit_minutes, and
 * null means no limit. The change is audited; the number is what every form and balance reads.
 */
function setRequestLimit({ store, now }) {
  return asyncRoute(async (req, res) => {
    const type = String(req.params.type);
    if (!KNOWN_TYPES.includes(type)) throw invalid(MESSAGES.LIMIT_TYPE);
    const spec = requestType(type);
    const minutes = spec.unit === 'minutes';
    const body = bodyWith(req, minutes ? ['limit_minutes'] : ['limit_count']);
    const value = minutes ? body.limit_minutes : body.limit_count;
    if (value === undefined) throw invalid(MESSAGES.LIMIT_VALUE);
    if (value !== null && (!Number.isInteger(value) || value < 0)) throw invalid(MESSAGES.LIMIT_VALUE);

    const patch = {
      updated_at: now().toISOString(),
      updated_by_user_id: req.auth.userId ?? null,
      updated_by_name: req.auth.employee.full_name,
    };
    if (minutes) patch.limit_minutes = value;
    else patch.limit_count = value;
    const saved = await store.setRequestLimit(type, patch);
    if (!saved) throw new HttpError(404, 'NOT_FOUND', MESSAGES.NOT_FOUND);
    await recordAfter(store, req, {
      action: 'request_limits.set',
      details: { type, limit_count: saved.limit_count ?? null, limit_minutes: saved.limit_minutes ?? null },
    });
    res.json({ limit: limitView(saved) });
  });
}

module.exports = { cancelAttendanceRequest, cancelLeaveRequest, listRequestLimits, setRequestLimit };
