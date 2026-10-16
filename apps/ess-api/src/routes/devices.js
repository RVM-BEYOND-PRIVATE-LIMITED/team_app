const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const { bodyWith, requiredText, invalid, isUuid, oneQueryValue } = require('../lib/validate');
const { recordAfter } = require('../lib/audit');
const { LIST_LIMITS } = require('../lib/store');

/**
 * Task B8, decision 11 (KP, 16 Oct): phones registered from the browser move to the app by an HR
 * bulk reset, branch by branch, at go-live. The Scheduler only resets one phone at a time
 * (POST /api/hr/attendance-admin/devices/:id/revoke), so the ESS adds the bulk action, writing
 * exactly the rows that reset writes (lib/store.js revokeActiveDevices). It is the one write the
 * ESS makes to a Scheduler table.
 *
 * Only HR, the CEO and super admins, the Scheduler's ATTENDANCE_OVERRIDE_ROLES for its own reset
 * (routes/hr.js:206,212), and only from a portal login: revoked_by references users.id
 * (20261020000000_hr_attendance_punch.sql:87), which an attendance session does not have
 * (middleware/requireRoles.js).
 *
 * After a reset, the person's next accepted punch from any phone with no registration registers
 * it, while the reset phone can never punch again (attendancePunchController.js:150-154,365-368).
 */

const STATUS_FILTERS = ['active', 'revoked', 'all'];
const MAX_EMPLOYEE_IDS = 500;

const card = (e) => (e ? { id: e.id, full_name: e.full_name, employee_code: e.employee_code ?? null } : null);

/** A branch_id query or body value: a UUID, lower-cased, or a 400. */
function branchIdOf(v) {
  if (!isUuid(v)) throw invalid(MESSAGES.BRANCH_ID);
  return v.toLowerCase();
}

async function existingBranch(store, branchId) {
  const branch = await store.getBranch(branchId);
  if (!branch) throw new HttpError(404, 'NOT_FOUND', MESSAGES.BRANCH_NOT_FOUND);
  return branch;
}

/**
 * GET /api/ess/hr/devices?branch_id=&status=active|revoked|all (active by default).
 *
 * A branch is the employee's branch on the HR record: the phone rows carry none.
 */
function listDevices({ store }) {
  return asyncRoute(async (req, res) => {
    const raw = oneQueryValue(req.query.status);
    const status = raw === undefined ? 'active' : raw;
    if (!STATUS_FILTERS.includes(status)) throw invalid(MESSAGES.DEVICE_STATUS_FILTER);
    const branchParam = oneQueryValue(req.query.branch_id);
    let employeeIds = null;
    if (branchParam !== undefined) {
      const branchId = branchIdOf(branchParam);
      await existingBranch(store, branchId);
      employeeIds = await store.listEmployeeIdsInBranch(branchId);
    }
    const rows = await store.listDevices({ status: status === 'all' ? null : status, employeeIds });
    const truncated = rows.length > LIST_LIMITS.devices;
    const shown = rows.slice(0, LIST_LIMITS.devices);
    const people = new Map((await store.listEmployeeCards(shown.map((d) => d.employee_id))).map((e) => [e.id, e]));
    const branches = new Map((await store.listBranches([...people.values()].map((e) => e.branch_id))).map((b) => [b.id, b]));
    res.json({
      devices: shown.map((d) => {
        const person = people.get(d.employee_id);
        const branch = person && person.branch_id ? branches.get(person.branch_id) : null;
        return {
          id: d.id,
          status: d.status,
          bound_at: d.bound_at,
          last_seen_at: d.last_seen_at ?? null,
          revoked_at: d.revoked_at ?? null,
          revoked_by_name: d.revoked_by_name ?? null,
          revoke_reason: d.revoke_reason ?? null,
          employee: card(person),
          branch: branch ? { id: branch.id, name: branch.name } : null,
        };
      }),
      truncated,
    });
  });
}

/**
 * POST /api/ess/hr/devices/reset { branch_id } or { employee_ids: [...] }, with { reason }.
 *
 * Exactly one of the two: a whole branch at go-live, or a list of people. Ids nobody has, and
 * people with no active phone, are simply not counted. Answers how many phones were reset and
 * which, and records the reset in hr_ess_audit.
 */
function resetDevices({ store, now }) {
  return asyncRoute(async (req, res) => {
    const body = bodyWith(req, ['branch_id', 'employee_ids', 'reason']);
    const byBranch = body.branch_id !== undefined;
    const byList = body.employee_ids !== undefined;
    if (byBranch === byList) throw invalid(MESSAGES.RESET_TARGET);
    let branchId = null;
    let employeeIds;
    if (byBranch) {
      branchId = branchIdOf(body.branch_id);
      // Checked before the reason, so a wrong branch is not reported as a missing reason.
      await existingBranch(store, branchId);
    } else {
      const list = body.employee_ids;
      if (!Array.isArray(list) || list.length < 1 || list.length > MAX_EMPLOYEE_IDS || !list.every(isUuid)) {
        throw invalid(MESSAGES.RESET_TARGET);
      }
      employeeIds = [...new Set(list.map((id) => id.toLowerCase()))];
    }
    const reason = requiredText(body.reason, { min: 3, max: 200, message: MESSAGES.RESET_REASON });
    if (byBranch) employeeIds = await store.listEmployeeIdsInBranch(branchId);

    // The Scheduler's own reset names the actor by username (attendanceAdminController.js:18,287).
    const login = await store.getUserLogin(req.auth.userId);
    const reset = await store.revokeActiveDevices(employeeIds, {
      revoked_at: now().toISOString(),
      revoked_by: req.auth.userId,
      revoked_by_name: (login && login.username) || 'unknown',
      revoke_reason: reason,
    });
    const deviceIds = reset.map((d) => d.id);

    await recordAfter(store, req, {
      action: 'devices.reset',
      details: {
        branch_id: branchId,
        employees_asked: employeeIds.length,
        reset: deviceIds.length,
        device_ids: deviceIds,
        employee_ids: [...new Set(reset.map((d) => d.employee_id))],
        reason,
      },
    });
    res.json({ reset: deviceIds.length, device_ids: deviceIds });
  });
}

module.exports = { listDevices, resetDevices, MAX_EMPLOYEE_IDS };
