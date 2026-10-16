const { asyncRoute } = require('../lib/errors');

/**
 * GET /api/ess/me: who the app is signed in as.
 *
 * Built field by field from the row employeeAuth loaded, so nothing else on the HR record (pay,
 * HR remarks, phone, archive details) can reach the reply by being added to a query later.
 * A branch, department or manager that the record points at but that no longer exists comes
 * back as null rather than failing the whole screen.
 */
function meRoute({ store }) {
  return asyncRoute(async (req, res) => {
    const { kind, userId, role, employee } = req.auth;
    const [branch, department, manager] = await Promise.all([
      employee.branch_id ? store.getBranch(employee.branch_id) : null,
      employee.department_id ? store.getDepartment(employee.department_id) : null,
      employee.manager_id ? store.getEmployeeName(employee.manager_id) : null,
    ]);
    res.json({
      employee: {
        id: employee.id,
        full_name: employee.full_name,
        employee_code: employee.employee_code ?? null,
        designation: employee.designation ?? null,
        employment_status: employee.employment_status,
        branch: branch ? { id: branch.id, name: branch.name } : null,
        department: department ? { id: department.id, name: department.name } : null,
        manager: manager ? { id: manager.id, full_name: manager.full_name } : null,
      },
      login: { kind, role: role ?? null, user_id: userId ?? null },
    });
  });
}

module.exports = { meRoute };
