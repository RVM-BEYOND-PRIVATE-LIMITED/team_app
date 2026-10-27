const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { uuid } = require('./helpers/fixtures');

/** Issue #31: the additive organisation tree on GET /me/org. */

const ORG = '/api/ess/me/org';

const get = (app, person) => request(app).get(ORG).set(bearer(tokens.portal(person)));

const flatten = (nodes) => nodes.flatMap((node) => [node, ...flatten(node.children || [])]);

const find = (nodes, id) => flatten(nodes).find((node) => node.id === id) || null;

function maxDepth(nodes, depth = 1) {
  return nodes.reduce((max, node) => Math.max(max, depth, maxDepth(node.children || [], depth + 1)), 0);
}

describe('GET /api/ess/me/org — tree', () => {
  it('keeps every existing key and adds tree', async () => {
    const { app, people } = buildApp();
    const res = await get(app, people.faculty);
    expect(res.status).toBe(200);
    expect(Object.keys(res.body).sort()).toEqual([
      'department', 'direct_reports', 'manager_chain', 'peers', 'reports_to_ceo_not_recorded', 'tree',
    ]);
    expect(Array.isArray(res.body.tree)).toBe(true);
  });

  it('gives a role on KP\'s list the full tree, with phone null everywhere and is_me on me', async () => {
    const { app, people } = buildApp();
    const res = await get(app, people.hr);
    expect(res.status).toBe(200);
    const all = flatten(res.body.tree);
    expect(all.length).toBeGreaterThan(10);
    expect(all.every((node) => node.phone === null)).toBe(true);
    expect(find(res.body.tree, people.hr.employee.id).is_me).toBe(true);
    expect(find(res.body.tree, people.faculty.employee.id)).not.toBeNull();
    // The two no-manager people are both roots: the CEO and the Pune counsellor.
    expect(res.body.tree.map((node) => node.full_name)).toEqual(expect.arrayContaining([
      'Test Chief Executive Officer', 'Test Pune Counsellor',
    ]));
    expect(find(res.body.tree, people.faculty.employee.id).children).toEqual([]);
  });

  it('gives anyone with a direct report the full tree even without a listed role', async () => {
    const { app, people } = buildApp({
      setup: (w) => { w.people.attendance.employee.manager_id = w.people.faculty.employee.id; },
    });
    const res = await get(app, people.faculty);
    expect(res.status).toBe(200);
    const all = flatten(res.body.tree);
    expect(all).toHaveLength(13);
    expect(find(res.body.tree, people.attendance.employee.id)).not.toBeNull();
  });

  it('gives a non-manager only the top-root path and their peers at their level', async () => {
    const { app, people } = buildApp({
      setup: (w) => { w.people.attendance.employee.manager_id = w.people.hod.employee.id; },
    });
    const res = await get(app, people.faculty);
    expect(res.status).toBe(200);
    expect(res.body.tree).toHaveLength(1);
    const root = res.body.tree[0];
    expect(root.full_name).toBe('Test Chief Executive Officer');
    expect(root.is_me).toBe(false);
    const path = [];
    let at = root;
    while (at) {
      path.push(at.full_name);
      at = at.children.find((node) => node.full_name !== 'Test Office Assistant');
    }
    expect(path).toEqual([
      'Test Chief Executive Officer',
      'Test Head of Operations',
      'Test CAD HOD',
      'Test CAD Faculty',
    ]);
    const hod = find(res.body.tree, people.hod.employee.id);
    expect(hod.children.map((node) => node.full_name).sort()).toEqual(['Test CAD Faculty', 'Test Office Assistant']);
    expect(hod.children.find((node) => node.full_name === 'Test CAD Faculty').is_me).toBe(true);
    expect(hod.children.find((node) => node.full_name === 'Test Office Assistant').is_me).toBe(false);
    expect(flatten(res.body.tree).every((node) => node.phone === null)).toBe(true);
  });

  it('stops a hand-edited cycle without hanging', async () => {
    const { app, people } = buildApp({
      setup: (w) => { w.people.faculty.employee.manager_id = w.people.faculty.employee.id; },
    });
    const res = await get(app, people.hr);
    expect(res.status).toBe(200);
    expect(find(res.body.tree, people.faculty.employee.id)).not.toBeNull();
  });

  it('caps the tree at 20 levels', async () => {
    const { app, people } = buildApp({
      setup: (w) => {
        let manager = w.people.faculty.employee.id;
        for (let i = 0; i < 25; i += 1) {
          const id = uuid('e', 100 + i);
          w.tables.hr_employees.push({
            id,
            employee_code: `RVM-${100 + i}`,
            full_name: `Deep Person ${i + 1}`,
            designation: 'Trainee',
            department_id: w.people.faculty.employee.department_id,
            branch_id: w.people.faculty.employee.branch_id,
            manager_id: manager,
            email: null,
            phone: null,
            date_of_joining: '2025-01-01',
            date_of_exit: null,
            employment_status: 'active',
            is_archived: false,
            user_id: null,
          });
          manager = id;
        }
      },
    });
    const res = await get(app, people.hr);
    expect(res.status).toBe(200);
    expect(maxDepth(res.body.tree)).toBeLessThanOrEqual(20);
  });

  it('answers 401 with no token and 403 for the desk login', async () => {
    const { app, people } = buildApp();
    expect((await request(app).get(ORG)).status).toBe(401);
    expect((await request(app).get(ORG).set(bearer(tokens.portal(people.desk)))).status).toBe(403);
  });
});
