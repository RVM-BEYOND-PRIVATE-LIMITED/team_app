const { personCard, canSeePhone } = require('../policy/me');
const { isActive } = require('../policy/employment');

/**
 * What the org views share (tasks E2, E6, E8): the active staff, their departments and branches,
 * and one card builder with the contact rule already applied. About a hundred rows at RVM's
 * size, so everything is read once and worked out in memory — no query per colleague.
 */
async function contactContext({ store, viewer, role, today }) {
  const [people, departments, branches] = await Promise.all([
    store.listActiveEmployees(),
    store.listAllDepartments(),
    store.listAllBranches(),
  ]);
  const byId = new Map(people.map((e) => [e.id, e]));
  const deptById = new Map(departments.map((d) => [d.id, d]));
  const branchById = new Map(branches.map((b) => [b.id, b]));
  const card = (employee) => personCard({
    employee,
    department: deptById.get(employee.department_id) || null,
    branch: branchById.get(employee.branch_id) || null,
    phone: canSeePhone({ viewer, colleague: employee, role, byId }) ? employee.phone : null,
  });
  const onStrength = (employee) => isActive(employee, today);
  const byName = (a, b) => String(a.full_name || '').localeCompare(String(b.full_name || ''));
  return { people, byId, deptById, branchById, card, onStrength, byName };
}

module.exports = { contactContext };
