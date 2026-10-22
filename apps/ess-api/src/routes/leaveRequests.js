const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const { bodyWith, requiredText, idParam, oneQueryValue, invalid } = require('../lib/validate');
const { istDay, isCalendarDay, monthBounds } = require('../lib/time');
const { REQUEST_TYPES, effectiveLimit } = require('../policy/requestLimits');
const { LEAVE_TYPES, windowProblem, monthProblem, countForMonth, minutesForMonth, balanceOf, requestView } = require('../policy/requests');
const { notifyApprovers } = require('../lib/notify');

/**
 * Tasks C2, C4 and C5: casual leave (one a month, the Scheduler's own rule) and leave without
 * pay, and the balances every form shows — allowed, used, remaining, pending included.
 *
 * Leave may be filed AHEAD (a planned CL); the decision writes the day through the Scheduler's
 * override function, which accepts a future day for leave and nothing else. A half-day leave is
 * not offered in this phase.
 */

/** POST /api/ess/leave-requests { type: cl|lwp|wfh, day, reason } */
function createMyLeaveRequest({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const body = bodyWith(req, ['type', 'day', 'reason']);
    if (!LEAVE_TYPES.includes(body.type)) throw invalid(MESSAGES.LEAVE_REQUEST_TYPE);
    if (!isCalendarDay(body.day)) throw invalid(MESSAGES.DATE_FORMAT);
    const day = body.day;
    const reason = requiredText(body.reason, { min: 5, max: 1000, message: MESSAGES.REQUEST_REASON });

    const today = istDay(now());
    const problem = windowProblem(day, today);
    if (problem) {
      throw problem === 'REQUEST_CLOSED'
        ? new HttpError(409, problem, MESSAGES[problem])
        : invalid(MESSAGES[problem]);
    }

    if (await store.countPendingRequests({ family: 'leave', employeeId: employee.id, type: body.type, day }) > 0) {
      throw new HttpError(409, 'DUPLICATE_REQUEST', MESSAGES.DUPLICATE_REQUEST);
    }

    // WFH (KP, 22 Oct): the employee's own allowance IS the limit. HR enables it per person; the
    // month's approved and pending WFH days count, whether they came from here or another row.
    if (body.type === 'wfh') {
      const allowance = await store.getWfhAllowance(employee.id);
      if (!allowance || !allowance.is_enabled) {
        throw new HttpError(409, 'WFH_NOT_ALLOWED', MESSAGES.WFH_NOT_ALLOWED);
      }
      const taken = await store.countWfhDays({
        employeeId: employee.id, month: day.slice(0, 7), statuses: ['approved', 'pending'],
      });
      if (taken >= allowance.monthly_limit_days) {
        throw new HttpError(409, 'WFH_LIMIT', MESSAGES.WFH_LIMIT);
      }
    } else {
      // The month's counter. For leave the sheet's own days count too, so a request cannot be
      // filed around a CL or an unpaid day somebody recorded by hand.
      const limits = await store.getRequestLimits();
      const type = REQUEST_TYPES.find((t) => t.type === `leave_${body.type}`);
      const { from, to } = monthBounds(day);
      const rows = await store.listMyRequestFacts('leave', employee.id, from, to);
      const leaveDays = await store.listMyLeaveDays(employee.id, from, to);
      const written = leaveDays.filter((d) => d.leave_type === body.type).length;
      const { used, pending } = countForMonth(rows, body.type, { written });
      const allowed = effectiveLimit(type, limits);
      if (allowed != null && used + pending >= allowed) {
        throw new HttpError(409, 'LIMIT_REACHED', MESSAGES.LIMIT_REACHED);
      }
    }

    const created = await store.createLeaveRequest({ employee_id: employee.id, type: body.type, day, reason });
    // The approver hears about it (best effort; D6/D7).
    await notifyApprovers({ store, requester: employee, request: created, family: 'leave' });
    res.status(201).json({ request: requestView(created, 'leave') });
  });
}

/** GET /api/ess/leave-requests: my own, newest first, at most 100. */
function listMyLeaveRequests({ store }) {
  return asyncRoute(async (req, res) => {
    const rows = await store.listMyLeaveRequests(req.auth.employee.id);
    res.json({ requests: rows.map((r) => requestView(r, 'leave')) });
  });
}

/** POST /api/ess/leave-requests/:id/withdraw: while it is still pending, mine only. */
function withdrawMyLeaveRequest({ store, now }) {
  return asyncRoute(async (req, res) => {
    const id = idParam(req.params.id);
    const out = await store.withdrawLeaveRequest({
      p_request_id: id,
      p_employee_id: req.auth.employee.id,
      p_now: now().toISOString(),
    });
    const outcome = out && out.outcome;
    if (outcome === 'not_found') throw new HttpError(404, 'NOT_FOUND', MESSAGES.REQUEST_NOT_FOUND);
    if (outcome === 'not_pending') throw new HttpError(409, 'REQUEST_NOT_PENDING', MESSAGES.REQUEST_NOT_PENDING);
    const fresh = await store.getLeaveRequest(id);
    res.json({ request: requestView(fresh, 'leave') });
  });
}

/** GET /api/ess/leave/balances?month=YYYY-MM (this month by default, or last month). */
function myLeaveBalances({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const today = istDay(now());
    const raw = oneQueryValue(req.query.month);
    // A month given more than once arrives as a list: refused, never quietly taking one value.
    if (raw !== undefined && (raw === null || !/^\d{4}-\d{2}$/.test(raw))) {
      throw invalid(MESSAGES.BALANCES_MONTH);
    }
    const month = raw === undefined || raw === '' ? today.slice(0, 7) : raw;
    if (monthProblem(month, today)) {
      throw new HttpError(400, 'DAY_OUT_OF_RANGE', MESSAGES.BALANCES_MONTH);
    }
    const { from, to } = monthBounds(`${month}-01`);

    const limits = await store.getRequestLimits();
    // WFH's allowance arrives with migration 29. Before it, the other balances still answer.
    let allowance = null;
    try {
      allowance = await store.getWfhAllowance(employee.id);
    } catch (e) {
      if (!(e && e.code === 'MODULE_NOT_INSTALLED')) throw e;
    }
    const attendanceFacts = await store.listMyRequestFacts('attendance', employee.id, from, to);
    const leaveFacts = await store.listMyRequestFacts('leave', employee.id, from, to);
    const days = await store.listMyLeaveDays(employee.id, from, to);
    const written = {
      leave_cl: days.filter((d) => d.leave_type === 'cl').length,
      leave_lwp: days.filter((d) => d.leave_type === 'lwp').length,
    };
    const wfhUsed = await store.countWfhDays({ employeeId: employee.id, month, statuses: ['approved'] });
    const wfhPending = await store.countWfhDays({ employeeId: employee.id, month, statuses: ['pending'] });

    const types = REQUEST_TYPES.map((t) => {
      let counts = { used: 0, pending: 0 };
      if (t.type === 'on_duty' || t.type === 'fix_a_day' || t.type === 'excuse_late') {
        counts = countForMonth(attendanceFacts, t.type);
      } else if (t.type === 'short_leave') {
        // C3: short leave counts by minutes, and the balance shows the minutes used and waiting.
        counts = minutesForMonth(attendanceFacts, t.type);
      } else if (t.type === 'leave_cl' || t.type === 'leave_lwp') {
        counts = countForMonth(leaveFacts, t.type.slice('leave_'.length), { written: written[t.type] });
      } else if (t.type === 'wfh') {
        // WFH's limit is the employee's own allowance, never a generic request-limit row.
        const enabled = Boolean(allowance && allowance.is_enabled);
        return {
          type: 'wfh',
          offered: enabled,
          unit: 'count',
          phase: 1,
          ...balanceOf(enabled ? allowance.monthly_limit_days : 0, { used: wfhUsed, pending: wfhPending }),
        };
      }
      return {
        type: t.type,
        offered: t.offered,
        unit: t.unit,
        phase: t.phase,
        ...balanceOf(effectiveLimit(t, limits), counts),
      };
    });
    res.json({ month, types });
  });
}

module.exports = { createMyLeaveRequest, listMyLeaveRequests, withdrawMyLeaveRequest, myLeaveBalances };
