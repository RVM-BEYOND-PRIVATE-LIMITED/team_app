const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const { bodyWith, requiredText, optionalText, chars, idParam, invalid } = require('../lib/validate');
const { istDay, isCalendarDay, monthBounds } = require('../lib/time');
const { effectiveLimit, requestType } = require('../policy/requestLimits');
const { ATTENDANCE_TYPES, windowProblem, countForMonth, requestView } = require('../policy/requests');

/**
 * Tasks C1 and C3: the employee's attendance requests — on duty, fix a day, excuse a late.
 * Work from home is refused, and short leave is Phase 2 (docs/06-backend-phases.md, Phase 1C).
 *
 * The route validates the form and the month's window and counter, then writes the row; the
 * decision itself (the day, the late, the CL) is the SQL function's, called by the decide route,
 * because a form cannot write a day and a request in one transaction.
 */

const TIME_RE = /^([01]\d|2[0-3]):[0-5]\d$/;

/** 'HH:MM' -> 'HH:MM'; absent or blank -> null; anything else -> undefined (the caller refuses). */
function timeOf(v) {
  if (v === undefined || v === null) return null;
  if (typeof v !== 'string') return undefined;
  const s = v.trim();
  if (s === '') return null;
  return TIME_RE.test(s) ? s : undefined;
}

/** POST /api/ess/attendance-requests { type, day, reason, place?, fix_in?, fix_out? } */
function createMyAttendanceRequest({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const body = bodyWith(req, ['type', 'day', 'reason', 'place', 'fix_in', 'fix_out']);
    if (!ATTENDANCE_TYPES.includes(body.type)) throw invalid(MESSAGES.ATTENDANCE_REQUEST_TYPE);
    if (!isCalendarDay(body.day)) throw invalid(MESSAGES.DATE_FORMAT);
    const day = body.day;
    const reason = requiredText(body.reason, { min: 5, max: 1000, message: MESSAGES.REQUEST_REASON });

    // Each type takes exactly its own fields: a field of another type is refused, never ignored.
    const place = optionalText(body.place);
    const fixIn = timeOf(body.fix_in);
    const fixOut = timeOf(body.fix_out);
    if (fixIn === undefined || fixOut === undefined) throw invalid(MESSAGES.REQUEST_TIMES);
    if (body.type === 'on_duty') {
      if (place === undefined || !place || chars(place) > 120) throw invalid(MESSAGES.REQUEST_PLACE);
      if (fixIn || fixOut) throw invalid(MESSAGES.UNKNOWN_FIELD);
    } else {
      if (place !== null) throw invalid(MESSAGES.UNKNOWN_FIELD);
      if (body.type === 'fix_a_day' && !fixIn && !fixOut) throw invalid(MESSAGES.REQUEST_TIMES_NEEDED);
      if (body.type === 'excuse_late' && (fixIn || fixOut)) throw invalid(MESSAGES.UNKNOWN_FIELD);
    }

    const today = istDay(now());
    const problem = windowProblem(day, today);
    if (problem) {
      throw problem === 'REQUEST_CLOSED'
        ? new HttpError(409, problem, MESSAGES[problem])
        : invalid(MESSAGES[problem]);
    }
    // A fix or an excuse is about a day that has happened; on duty may be filed ahead.
    if (day > today && body.type !== 'on_duty') throw invalid(MESSAGES.REQUEST_FUTURE);

    if (await store.countPendingRequests({ family: 'attendance', employeeId: employee.id, type: body.type, day }) > 0) {
      throw new HttpError(409, 'DUPLICATE_REQUEST', MESSAGES.DUPLICATE_REQUEST);
    }

    // The month's counter, as the form shows it: pending + approved against the limit HR set.
    const limits = await store.getRequestLimits();
    const type = requestType(body.type);
    const { from, to } = monthBounds(day);
    const rows = await store.listMyRequestFacts('attendance', employee.id, from, to);
    const { used, pending } = countForMonth(rows, body.type);
    const allowed = effectiveLimit(type, limits);
    if (allowed != null && used + pending >= allowed) {
      throw new HttpError(409, 'LIMIT_REACHED', MESSAGES.LIMIT_REACHED);
    }

    const created = await store.createAttendanceRequest({
      employee_id: employee.id,
      type: body.type,
      day,
      reason,
      place: body.type === 'on_duty' ? place : null,
      fix_in: body.type === 'fix_a_day' ? fixIn : null,
      fix_out: body.type === 'fix_a_day' ? fixOut : null,
    });
    res.status(201).json({ request: requestView(created, 'attendance') });
  });
}

/** GET /api/ess/attendance-requests: my own, newest first, at most 100. */
function listMyAttendanceRequests({ store }) {
  return asyncRoute(async (req, res) => {
    const rows = await store.listMyAttendanceRequests(req.auth.employee.id);
    res.json({ requests: rows.map((r) => requestView(r, 'attendance')) });
  });
}

/** POST /api/ess/attendance-requests/:id/withdraw: while it is still pending, mine only. */
function withdrawMyAttendanceRequest({ store, now }) {
  return asyncRoute(async (req, res) => {
    const id = idParam(req.params.id);
    const out = await store.withdrawAttendanceRequest({
      p_request_id: id,
      p_employee_id: req.auth.employee.id,
      p_now: now().toISOString(),
    });
    const outcome = out && out.outcome;
    if (outcome === 'not_found') throw new HttpError(404, 'NOT_FOUND', MESSAGES.REQUEST_NOT_FOUND);
    if (outcome === 'not_pending') throw new HttpError(409, 'REQUEST_NOT_PENDING', MESSAGES.REQUEST_NOT_PENDING);
    const fresh = await store.getAttendanceRequest(id);
    res.json({ request: requestView(fresh, 'attendance') });
  });
}

module.exports = { createMyAttendanceRequest, listMyAttendanceRequests, withdrawMyAttendanceRequest };
