const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { MESSAGES } = require('../src/lib/errors');
const { expectRefusal, expectInvalid } = require('./helpers/expect');

/** Tasks E2, E8, E11: the org chain, peers, reports, department and the directory. */

const ORG = '/api/ess/me/org';
const DIR = '/api/ess/directory';

const cardFields = ['id', 'full_name', 'employee_code', 'designation', 'department', 'branch', 'email', 'phone', 'employment_status', 'notice_period'];

describe('GET /api/ess/me/org', () => {
  it('shows the chain, peers, reports and the department, with the contact rule applied', async () => {
    const { app, people } = buildApp();
    const res = await request(app).get(ORG).set(bearer(tokens.portal(people.admin_manager)));
    expect(res.status).toBe(200);
    expect(res.body.manager_chain.map((c) => c.full_name)).toEqual(['Test Head of Operations', 'Test Chief Executive Officer']);
    expect(res.body.reports_to_ceo_not_recorded).toBe(false);
    expect(res.body.peers.map((c) => c.full_name)).toEqual(['Test Branch Admin', 'Test CAD HOD']);
    expect(res.body.direct_reports.count).toBe(1);
    // The viewer is their manager: their phone comes through.
    const assistant = res.body.direct_reports.people.find((c) => c.full_name === 'Test Office Assistant');
    expect(assistant.phone).toBe('9710000050');
    expect(Object.keys(assistant).sort()).toEqual([...cardFields].sort());
    // The chain is upward: a manager's phone is not shown to their report (decision 5's default).
    expect(res.body.manager_chain[0].phone).toBe(null);
    expect(res.body.department.name).toBe('Technical Training');
    expect(res.body.department.people.map((c) => c.full_name)).toContain('Test CAD Faculty');
  });

  it('flags "Reports to the CEO (not recorded)" when the chain\'s top has no manager and is not the CEO', async () => {
    const { app, people } = buildApp({ setup: (w) => { w.people.hod.employee.manager_id = null; } });
    const res = await request(app).get(ORG).set(bearer(tokens.portal(people.faculty)));
    expect(res.body.manager_chain.map((c) => c.full_name)).toEqual(['Test CAD HOD']);
    expect(res.body.reports_to_ceo_not_recorded).toBe(true);
  });

  it('shows HR every phone, and keeps people on notice on the lists', async () => {
    const { app, people } = buildApp({ setup: (w) => { w.people.faculty.employee.employment_status = 'notice_period'; } });
    const asHr = await request(app).get(ORG).set(bearer(tokens.portal(people.hr)));
    expect(asHr.body.department.people.find((c) => c.full_name === 'Test HR Executive').phone).toBe('9710000010');
    const asHod = await request(app).get(ORG).set(bearer(tokens.portal(people.hod)));
    const report = asHod.body.direct_reports.people.find((c) => c.full_name === 'Test CAD Faculty');
    expect(report.notice_period).toBe(true);
    expect(report.employment_status).toBe('notice_period');
  });

  it('answers 401 with no token and 403 for the desk login', async () => {
    const { app, people } = buildApp();
    expectRefusal(await request(app).get(ORG), 401, 'NOT_AUTHENTICATED');
    expectRefusal(await request(app).get(ORG).set(bearer(tokens.portal(people.desk))), 403, 'NOT_LINKED');
  });
});

describe('GET /api/ess/directory', () => {
  it('searches by name or code, and filters by branch or department', async () => {
    const { app, people, db } = buildApp();
    const as = (query) => request(app).get(`${DIR}${query}`).set(bearer(tokens.attendance(people.attendance)));
    const byCode = await as('?q=RVM-011');
    expect(byCode.body.people.map((p) => p.full_name)).toEqual(['Test CAD Faculty']);
    const byName = await as('?q=pune');
    expect(byName.body.people.map((p) => p.full_name)).toEqual(['Test Pune Counsellor']);
    const byBranch = await as(`?branch_id=${people.pune.employee.branch_id}`);
    expect(byBranch.body.people.map((p) => p.full_name)).toEqual(['Test Pune Counsellor']);
    const byDept = await as(`?department_id=${people.hr.employee.department_id}`);
    expect(byDept.body.people.map((p) => p.full_name).sort()).toEqual(['Test HR Executive', 'Test HR Manager']);
    expect(byDept.body.truncated).toBe(false);
    // Nobody in their own directory; and the attendance session sees emails, never phones.
    expect((await as('')).body.people.every((p) => p.id !== people.attendance.employee.id)).toBe(true);
    const withEmail = (await as('?q=RVM-011')).body.people[0];
    expect(withEmail.email).toBe('faculty@example.test');
    expect(withEmail.phone).toBe(null);
    // HR sees the phone.
    const asHr = await request(app).get(`${DIR}?q=RVM-011`).set(bearer(tokens.portal(people.hr)));
    expect(asHr.body.people[0].phone).toBe('9710000011');
    expect(db.queries.every((q) => !q.columns.includes('performance_tag'))).toBe(true);
  });

  it.each([
    ['a query over 60 characters', `?q=${'x'.repeat(61)}`, MESSAGES.DIRECTORY_QUERY],
    ['a branch id that is not one', '?branch_id=1', MESSAGES.BRANCH_ID],
    ['a department id that is not one', '?department_id=1', MESSAGES.DEPARTMENT_ID],
  ])('refuses %s with 400', async (_label, query, message) => {
    const { app, people } = buildApp();
    expectInvalid(await request(app).get(`${DIR}${query}`).set(bearer(tokens.attendance(people.attendance))), message);
  });

  it('answers 404 for a branch or department that does not exist', async () => {
    const { app, people } = buildApp();
    const token = tokens.attendance(people.attendance);
    expectRefusal(await request(app).get(`${DIR}?branch_id=99999999-0000-4000-8000-000000000001`).set(bearer(token)), 404, 'NOT_FOUND');
    expectRefusal(await request(app).get(`${DIR}?department_id=99999999-0000-4000-8000-000000000002`).set(bearer(token)), 404, 'NOT_FOUND');
  });

  it('answers 401 with no token and 403 for the desk login', async () => {
    const { app, people } = buildApp();
    expectRefusal(await request(app).get(DIR), 401, 'NOT_AUTHENTICATED');
    expectRefusal(await request(app).get(DIR).set(bearer(tokens.portal(people.desk))), 403, 'NOT_LINKED');
  });
});
