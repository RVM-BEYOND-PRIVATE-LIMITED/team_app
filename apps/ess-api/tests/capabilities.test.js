const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { REQUEST_TYPES } = require('../src/policy/requestLimits');

/**
 * GET /api/ess/me/capabilities, role by role, against KP's decisions of 16 Oct 2026
 * (docs/03-decisions.md). The expected values are written out here rather than derived from
 * the policy module, so a change to the policy has to change this table too.
 */

const capabilities = (app, token) => request(app).get('/api/ess/me/capabilities').set(bearer(token));

const ALL_OFFERED = ['on_duty', 'fix_a_day', 'excuse_late', 'short_leave', 'leave_cl', 'leave_lwp'];
const HR_ALL = ['attendance', 'documents', 'profile_changes', 'helpdesk_hr'];
const HR_EXEC = ['documents', 'profile_changes', 'helpdesk_hr'];

/**
 * [who, work, any_request, hr_scope, announce, moderate, direct reports in the fixture]
 * The fixture's reporting lines are in tests/helpers/fixtures.js.
 */
const ROLE_TABLE = [
  ['faculty', true, false, [], false, false, 0],
  ['hod', true, false, [], false, false, 1],
  ['hod_placement', true, false, [], false, false, 0],
  ['hoo', true, false, [], false, false, 3],
  ['super_admin', true, true, [], true, false, 0],
  ['ceo', true, true, [], true, false, 6],
  ['admin', false, false, [], false, false, 0],
  ['admin_manager', false, false, [], false, false, 1],
  ['accounts_admin', false, false, [], false, false, 0],
  ['hr', false, true, HR_ALL, true, true, 0],
  ['hr_executive', false, false, HR_EXEC, false, false, 0],
  ['attendance', false, false, [], false, false, 0],
];

const tokenFor = (people, who) => (who === 'attendance' ? tokens.attendance(people.attendance) : tokens.portal(people[who]));

describe('GET /api/ess/me/capabilities, role by role', () => {
  it.each(ROLE_TABLE)('%s', async (who, work, anyRequest, hrScope, announce, moderate, reports) => {
    const { app, people } = buildApp();
    const res = await capabilities(app, tokenFor(people, who));
    expect(res.status).toBe(200);
    const body = res.body;

    // Every staff login gets all five tabs, Admin, Admin Manager and Finance Admin included.
    expect(body.tabs).toEqual(['home', 'inbox', 'wall', 'me', 'team']);
    expect(body.sections).toEqual({ time: true, helpdesk: true, documents: true, profile: true, work });
    expect(body.team).toEqual({ has_reports: reports > 0, direct_reports: reports });
    expect(body.approvals).toEqual({
      own_reports: reports > 0,
      any_request: anyRequest,
      request_types: anyRequest || reports > 0 ? ALL_OFFERED : [],
      hr_scope: hrScope,
    });
    expect(body.wall).toEqual({ post: true, announce, moderate });
    expect(body.push).toEqual({ enabled: false });
    expect(body.integrity).toEqual({ required: false });
  });

  it('answers with exactly the documented blocks', async () => {
    const { app, people } = buildApp();
    const res = await capabilities(app, tokens.portal(people.hr));
    expect(Object.keys(res.body).sort()).toEqual(['approvals', 'integrity', 'push', 'requests', 'sections', 'tabs', 'team', 'wall']);
  });
});

describe('the request table in the capability document', () => {
  it('is KP\'s list of 16 Oct, with the payroll cut-off on the 5th and one month of reach-back', async () => {
    const { app, people } = buildApp();
    const res = await capabilities(app, tokens.portal(people.faculty));
    expect(res.body.requests).toEqual({
      types: [
        { type: 'on_duty', offered: true, limit: null, unit: 'count', phase: 1 },
        { type: 'fix_a_day', offered: true, limit: 3, unit: 'count', phase: 1 },
        { type: 'excuse_late', offered: true, limit: 3, unit: 'count', phase: 1 },
        { type: 'short_leave', offered: true, limit: 180, unit: 'minutes', phase: 2 },
        { type: 'leave_cl', offered: true, limit: 1, unit: 'count', phase: 1 },
        { type: 'leave_lwp', offered: true, limit: null, unit: 'count', phase: 1 },
        { type: 'wfh', offered: false, limit: 0, unit: 'count', phase: 1 },
      ],
      payroll_cutoff_day: 5,
      reach_back_months: 1,
    });
  });

  it('comes from the one policy table the request endpoints will use', async () => {
    const { app, people } = buildApp();
    const res = await capabilities(app, tokens.portal(people.faculty));
    expect(res.body.requests.types).toEqual(REQUEST_TYPES.map((t) => ({ ...t })));
  });
});

describe('direct reports', () => {
  const report = (n, managerId, change) => ({
    id: `e0000000-0000-4000-8000-0000000006${String(n).padStart(2, '0')}`,
    full_name: `Report ${n}`,
    employee_code: `RVM-6${String(n).padStart(2, '0')}`,
    manager_id: managerId,
    employment_status: 'active',
    date_of_exit: null,
    is_archived: false,
    user_id: null,
    ...change,
  });

  it('count only people still on strength, by the same rule as sign-in', async () => {
    const { app, people } = buildApp({
      setup: (w) => {
        const m = w.people.faculty.employee.id;
        w.tables.hr_employees.push(
          report(1, m, {}),
          report(2, m, { employment_status: 'notice_period', date_of_exit: '2026-10-31' }),
          report(3, m, { employment_status: 'notice_period', date_of_exit: '2026-10-16' }),
          report(4, m, { employment_status: 'notice_period', date_of_exit: '2026-10-15' }),
          report(5, m, { employment_status: 'exited' }),
          report(6, m, { employment_status: 'fired', is_archived: true }),
          report(7, m, { is_archived: true }),
        );
      },
    });
    const res = await capabilities(app, tokens.portal(people.faculty));
    expect(res.body.team).toEqual({ has_reports: true, direct_reports: 3 });
    expect(res.body.approvals.own_reports).toBe(true);
    expect(res.body.approvals.request_types).toEqual(ALL_OFFERED);
    expect(res.body.approvals.any_request).toBe(false);
  });

  it('give approvals to anyone with a report, an attendance-only manager included', async () => {
    const { app, people } = buildApp({
      setup: (w) => w.tables.hr_employees.push(report(8, w.people.attendance.employee.id, {})),
    });
    const res = await capabilities(app, tokens.attendance(people.attendance));
    expect(res.body.team).toEqual({ has_reports: true, direct_reports: 1 });
    expect(res.body.approvals).toEqual({ own_reports: true, any_request: false, request_types: ALL_OFFERED, hr_scope: [] });
    expect(res.body.sections.work).toBe(false);
  });

  it('give an HR Executive with reports their own team\'s requests, but never anybody else\'s', async () => {
    const { app, people } = buildApp({
      setup: (w) => w.tables.hr_employees.push(report(9, w.people.hr_executive.employee.id, {})),
    });
    const res = await capabilities(app, tokens.portal(people.hr_executive));
    expect(res.body.approvals).toEqual({ own_reports: true, any_request: false, request_types: ALL_OFFERED, hr_scope: HR_EXEC });
  });
});

describe('powers that come with the portal role', () => {
  it('are not given to an attendance session, even for somebody whose portal role is HR', async () => {
    const { app, people } = buildApp({
      setup: (w) => w.tables.hr_attendance_accounts.push({
        ...w.people.attendance.account, id: '90000000-0000-4000-8000-000000000098', employee_id: w.people.hr.employee.id,
      }),
    });
    const res = await capabilities(app, tokens.attendance(people.hr));
    expect(res.body.approvals).toEqual({ own_reports: false, any_request: false, request_types: [], hr_scope: [] });
    expect(res.body.wall).toEqual({ post: true, announce: false, moderate: false });
  });

  it('follow the role on the account, changed after sign-in', async () => {
    const { app, db, people } = buildApp();
    const token = tokens.portal(people.admin);
    db.tables.users.find((u) => u.id === people.admin.user.id).role = 'hr';
    const res = await capabilities(app, token);
    expect(res.body.approvals.any_request).toBe(true);
    expect(res.body.approvals.hr_scope).toEqual(HR_ALL);
  });
});

describe('push', () => {
  const firebase = {
    FIREBASE_PROJECT_ID: 'rvm-team-test',
    FIREBASE_CLIENT_EMAIL: 'push@rvm-team-test.iam.gserviceaccount.com',
    FIREBASE_PRIVATE_KEY_B64: Buffer.from('not a real key').toString('base64'),
  };

  it('is enabled when all three FIREBASE_* settings are present', async () => {
    const { app, people } = buildApp({ env: firebase });
    expect((await capabilities(app, tokens.portal(people.faculty))).body.push).toEqual({ enabled: true });
  });

  it.each(Object.keys(firebase))('stays log-only while %s is missing', async (missing) => {
    const { app, people } = buildApp({ env: { ...firebase, [missing]: '' } });
    expect((await capabilities(app, tokens.portal(people.faculty))).body.push).toEqual({ enabled: false });
  });
});

describe('refusals', () => {
  it('uses the same sign-in checks as /me', async () => {
    const { app } = buildApp();
    const res = await request(app).get('/api/ess/me/capabilities');
    expect(res.status).toBe(401);
    expect(res.body.code).toBe('NOT_AUTHENTICATED');
  });

  it('answers 503 UNAVAILABLE when the reports cannot be read', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    const { app, db, people } = buildApp();
    const token = tokens.portal(people.hoo);
    const realFrom = db.from;
    // Sign-in reads succeed; the reports query is the one that fails.
    db.from = (table) => {
      const q = realFrom(table);
      const realEq = q.eq.bind(q);
      q.eq = (column, value) => {
        if (column === 'manager_id') db.outage = 'error';
        return realEq(column, value);
      };
      return q;
    };
    const res = await capabilities(app, token);
    expect(res.status).toBe(503);
    expect(res.body.code).toBe('UNAVAILABLE');
  });
});
