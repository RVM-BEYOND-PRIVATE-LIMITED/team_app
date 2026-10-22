const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const { bodyWith, optionalText, chars, idParam, oneQueryValue, invalid } = require('../lib/validate');
const { istDay } = require('../lib/time');
const { LIST_LIMITS } = require('../lib/store');
const { isActive } = require('../policy/employment');
const { recordAfter } = require('../lib/audit');

/**
 * Work from home (KP, 22 Oct 2026): HR enables it for selected employees only, each with a
 * monthly limit of days. WFH itself is a leave request type (`wfh`, routes/leaveRequests.js), so
 * this file is only HR's side of the allowance and the employee's own reading of it.
 *
 * The allowance row is the limit: there is no hr_ess_request_limits row for wfh. A disabled
 * allowance keeps HR's agreed number but offers nothing until HR switches it on again.
 */

const MAX_QUERY = 60;

/** The employee card the allowance list shows: name, code, branch and department only. */
function employeeCard(employee, branches, departments) {
  if (!employee) return null;
  const branch = branches.get(employee.branch_id) || null;
  const department = departments.get(employee.department_id) || null;
  return {
    id: employee.id,
    full_name: employee.full_name,
    employee_code: employee.employee_code ?? null,
    branch: branch ? { id: branch.id, name: branch.name } : null,
    department: department ? { id: department.id, name: department.name } : null,
  };
}

/** One allowance as both HR's list and the save read it. */
function allowanceView(row, employee, branches, departments) {
  return {
    employee_id: row.employee_id,
    employee: employeeCard(employee, branches, departments),
    enabled: row.is_enabled,
    monthly_limit_days: row.monthly_limit_days,
    note: row.note ?? null,
    set_by_name: row.set_by_name ?? null,
    updated_at: row.updated_at,
  };
}

/** The refs a response needs, read once. */
async function cardRefs(store) {
  const [branches, departments] = await Promise.all([store.listAllBranches(), store.listAllDepartments()]);
  return {
    branches: new Map(branches.map((b) => [b.id, b])),
    departments: new Map(departments.map((d) => [d.id, d])),
  };
}

/** GET /api/ess/hr/wfh-allowances?q= — HR's list of who has WFH, newest change first. */
function listWfhAllowances({ store }) {
  return asyncRoute(async (req, res) => {
    const raw = oneQueryValue(req.query.q);
    if (raw === null || (raw !== undefined && raw !== '' && chars(raw) > MAX_QUERY)) throw invalid(MESSAGES.WFH_QUERY);
    const q = (raw || '').toLowerCase();

    // The search is by name or employee code, over the people still on the record. An employee
    // without an allowance row is simply not in the list.
    let employeeIds = null;
    if (q) {
      const people = await store.listActiveEmployees();
      employeeIds = people
        .filter((e) => String(e.full_name || '').toLowerCase().includes(q)
          || String(e.employee_code || '').toLowerCase().includes(q))
        .map((e) => e.id);
      if (!employeeIds.length) return res.json({ allowances: [], truncated: false });
    }

    const rows = await store.listWfhAllowances({ employeeIds });
    const truncated = rows.length > LIST_LIMITS.wfhAllowances;
    const shown = rows.slice(0, LIST_LIMITS.wfhAllowances);
    if (!shown.length) return res.json({ allowances: [], truncated });

    const [employees, refs] = await Promise.all([
      store.listWfhEmployees(shown.map((r) => r.employee_id)),
      cardRefs(store),
    ]);
    const byId = new Map(employees.map((e) => [e.id, e]));
    res.json({
      allowances: shown.map((r) => allowanceView(r, byId.get(r.employee_id) ?? null, refs.branches, refs.departments)),
      truncated,
    });
  });
}

/**
 * PUT /api/ess/hr/wfh-allowances/{employeeId} { enabled, monthly_limit_days, note? }.
 * The upsert changes exactly one employee's row; the audit carries the before and after numbers
 * only, never the note or any personal data.
 */
function setWfhAllowance({ store, now }) {
  return asyncRoute(async (req, res) => {
    const employeeId = idParam(req.params.employeeId);
    const today = istDay(now());
    const employee = await store.getEmployeeById(employeeId);
    if (!employee || !isActive(employee, today)) {
      throw new HttpError(404, 'EMPLOYEE_NOT_FOUND', MESSAGES.EMPLOYEE_NOT_FOUND);
    }

    const form = bodyWith(req, ['enabled', 'monthly_limit_days', 'note']);
    const limit = form.monthly_limit_days;
    const note = optionalText(form.note);
    if (typeof form.enabled !== 'boolean'
      || !Number.isInteger(limit) || limit < 1 || limit > 31
      || note === undefined || (note !== null && chars(note) > 300)) {
      throw invalid(MESSAGES.WFH_ALLOWANCE);
    }

    const before = await store.getWfhAllowance(employeeId);
    const saved = await store.upsertWfhAllowance({
      employee_id: employeeId,
      is_enabled: form.enabled,
      monthly_limit_days: limit,
      note,
      set_by_user_id: req.auth.userId ?? null,
      set_by_name: req.auth.employee.full_name,
      updated_at: now().toISOString(),
    });

    await recordAfter(store, req, {
      action: 'wfh.allowance.changed',
      targetEmployeeId: employeeId,
      details: {
        before: before ? { enabled: before.is_enabled, monthly_limit_days: before.monthly_limit_days } : null,
        after: { enabled: saved.is_enabled, monthly_limit_days: saved.monthly_limit_days },
      },
    });

    const refs = await cardRefs(store);
    res.json({ allowance: allowanceView(saved, employee, refs.branches, refs.departments) });
  });
}

/** GET /api/ess/me/wfh — my allowance and this month's numbers, whether or not I have one. */
function myWfh({ store, now }) {
  return asyncRoute(async (req, res) => {
    const employeeId = req.auth.employee.id;
    const month = istDay(now()).slice(0, 7);
    const allowance = await store.getWfhAllowance(employeeId);
    const [used, pending] = await Promise.all([
      store.countWfhDays({ employeeId, month, statuses: ['approved'] }),
      store.countWfhDays({ employeeId, month, statuses: ['pending'] }),
    ]);
    const enabled = Boolean(allowance && allowance.is_enabled);
    const limit = enabled ? allowance.monthly_limit_days : 0;
    res.json({
      month,
      enabled,
      monthly_limit_days: limit,
      used,
      pending,
      remaining: enabled ? Math.max(0, limit - used - pending) : 0,
    });
  });
}

module.exports = { listWfhAllowances, setWfhAllowance, myWfh };
