const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { BRANCH_ID, DEPT_TECH_ID } = require('./helpers/fixtures');

/** GET /api/ess/me: exactly the spec's fields, and nothing else from the HR record. */

const me = (app, token) => request(app).get('/api/ess/me').set(bearer(token));

describe('GET /api/ess/me', () => {
  it('describes a portal login and its employee, field for field', async () => {
    const { app, people } = buildApp();
    const res = await me(app, tokens.portal(people.faculty));
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/^application\/json/);
    expect(res.body).toEqual({
      employee: {
        id: people.faculty.employee.id,
        full_name: 'Test CAD Faculty',
        employee_code: people.faculty.employee.employee_code,
        designation: 'CAD Faculty',
        employment_status: 'active',
        branch: { id: BRANCH_ID, name: 'Faridabad' },
        department: { id: DEPT_TECH_ID, name: 'Technical Training' },
        manager: { id: people.hod.employee.id, full_name: 'Test CAD HOD' },
      },
      login: { kind: 'portal', role: 'faculty', user_id: people.faculty.user.id },
    });
  });

  it('describes an attendance session', async () => {
    const { app, people } = buildApp();
    const res = await me(app, tokens.attendance(people.attendance));
    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      employee: {
        id: people.attendance.employee.id,
        full_name: 'Test Office Assistant',
        employee_code: 'RVM-050',
        designation: 'Office Assistant',
        employment_status: 'active',
        branch: { id: BRANCH_ID, name: 'Faridabad' },
        department: { id: DEPT_TECH_ID, name: 'Technical Training' },
        manager: { id: people.admin_manager.employee.id, full_name: 'Test Admin Manager' },
      },
      login: { kind: 'attendance', role: null, user_id: null },
    });
  });

  it('answers null for a branch, department and manager that are not set', async () => {
    const { app, people } = buildApp({
      setup: (w) => Object.assign(w.people.ceo.employee, { branch_id: null, department_id: null, manager_id: null, employee_code: null, designation: null }),
    });
    const res = await me(app, tokens.portal(people.ceo));
    expect(res.status).toBe(200);
    expect(res.body.employee).toMatchObject({ branch: null, department: null, manager: null, employee_code: null, designation: null });
  });

  it('answers null for a branch, department and manager that point at rows that are gone', async () => {
    const { app, people } = buildApp({
      setup: (w) => {
        w.tables.hr_branches = [];
        w.tables.hr_departments = [];
        w.people.faculty.employee.manager_id = 'e0000000-0000-4000-8000-000000000777';
      },
    });
    const res = await me(app, tokens.portal(people.faculty));
    expect(res.status).toBe(200);
    expect(res.body.employee).toMatchObject({ branch: null, department: null, manager: null });
  });

  it('shows a notice-period status as it is', async () => {
    const { app, people } = buildApp({
      setup: (w) => Object.assign(w.people.hr.employee, { employment_status: 'notice_period', date_of_exit: '2026-11-30' }),
    });
    const res = await me(app, tokens.portal(people.hr));
    expect(res.body.employee.employment_status).toBe('notice_period');
  });

  it('never carries anything else from the HR record or the account', async () => {
    const { app, people } = buildApp();
    const res = await me(app, tokens.portal(people.hr));
    expect(Object.keys(res.body).sort()).toEqual(['employee', 'login']);
    expect(Object.keys(res.body.employee).sort()).toEqual(
      ['branch', 'department', 'designation', 'employee_code', 'employment_status', 'full_name', 'id', 'manager'],
    );
    expect(Object.keys(res.body.login).sort()).toEqual(['kind', 'role', 'user_id']);
    const text = JSON.stringify(res.body);
    for (const leak of ['password', 'hash', 'phone', 'email', 'photo', 'archive', 'performance', 'date_of_exit']) {
      expect(text).not.toContain(leak);
    }
  });

  it('reads only named columns, and never a password hash', async () => {
    const { app, db, people } = buildApp();
    await me(app, tokens.attendance(people.attendance));
    await me(app, tokens.portal(people.hr));
    expect(db.queries.length).toBeGreaterThan(0);
    for (const q of db.queries) {
      expect(q.columns).not.toContain('*');
      expect(q.columns).not.toContain('password_hash');
    }
  });
});
