const request = require('supertest');
const jwt = require('jsonwebtoken');
const { buildApp, tokens, bearer } = require('./helpers/app');
const S = require('./helpers/schedulerTokens');
const { SIGNED_AT, TEST_JWT_SECRET } = require('./helpers/constants');
const { PORTAL_PEOPLE } = require('./helpers/fixtures');

/**
 * employeeAuth (task A1), exercised through GET /api/ess/me: every refusal in the spec, in the
 * Scheduler's order, with tokens signed by the Scheduler's own code (tests/helpers).
 */

const me = (app, headers = {}) => request(app).get('/api/ess/me').set(headers);

const expectRefusal = (res, status, code) => {
  expect(res.status).toBe(status);
  expect(res.body).toEqual({ error: expect.any(String), code });
  expect(res.body.error.length).toBeGreaterThan(10);
};

describe('a portal login', () => {
  it.each(PORTAL_PEOPLE.map(([key, role]) => [key, role]))('%s is let in with its own role', async (key, role) => {
    const { app, people } = buildApp();
    const res = await me(app, bearer(tokens.portal(people[key])));
    expect(res.status).toBe(200);
    expect(res.body.login).toEqual({ kind: 'portal', role, user_id: people[key].user.id });
    expect(res.body.employee.id).toBe(people[key].employee.id);
  });

  it('is let in with the token from a two-factor sign-in too', async () => {
    const { app, people } = buildApp();
    const res = await me(app, bearer(tokens.twoFactor(people.hr)));
    expect(res.status).toBe(200);
    expect(res.body.login.role).toBe('hr');
  });

  it('takes the role from the account, not from the token', async () => {
    const { app, db, people } = buildApp();
    const token = tokens.portal(people.admin);
    db.tables.users.find((u) => u.id === people.admin.user.id).role = 'admin_manager';
    const res = await me(app, bearer(token));
    expect(res.status).toBe(200);
    expect(res.body.login.role).toBe('admin_manager');
  });

  it('is refused with 401 once the account has been deleted', async () => {
    const { app, db, people } = buildApp();
    const token = tokens.portal(people.admin);
    db.tables.users = db.tables.users.filter((u) => u.id !== people.admin.user.id);
    expectRefusal(await me(app, bearer(token)), 401, 'NOT_AUTHENTICATED');
  });

  it.each([
    ['nobody', null],
    ['another faculty record', 'f0000000-0000-4000-8000-000000000999'],
  ])('is refused with 401 once its faculty id leads to %s', async (_label, facultyId) => {
    // auth.js resolves a teaching token by that id, so it would act as another account or refuse.
    const { app, db, people } = buildApp();
    const token = tokens.portal(people.faculty);
    db.tables.users.find((u) => u.id === people.faculty.user.id).faculty_id = facultyId;
    expectRefusal(await me(app, bearer(token)), 401, 'NOT_AUTHENTICATED');
  });

  it('answers 403 NOT_LINKED when no HR record carries it', async () => {
    const { app, people } = buildApp();
    expectRefusal(await me(app, bearer(tokens.portal(people.desk))), 403, 'NOT_LINKED');
  });

  it.each([['unlinked', false], ['linked to an HR record', true]])(
    'answers 403 NOT_AN_EMPLOYEE for the connector identity, %s',
    async (_label, linked) => {
      const { app, people } = buildApp({
        setup: (w) => { if (linked) w.people.attendance.employee.user_id = w.people.bot.user.id; },
      });
      expectRefusal(await me(app, bearer(tokens.portal(people.bot))), 403, 'NOT_AN_EMPLOYEE');
    },
  );
});

describe('leavers', () => {
  const left = [
    ['archived', { is_archived: true }],
    ['exited', { employment_status: 'exited' }],
    ['past their last working day', { employment_status: 'notice_period', date_of_exit: '2026-10-15' }],
  ];

  it.each(left)('a portal login of somebody %s answers 403 NOT_ACTIVE', async (_label, change) => {
    const { app, people } = buildApp({ setup: (w) => Object.assign(w.people.faculty.employee, change) });
    expectRefusal(await me(app, bearer(tokens.portal(people.faculty))), 403, 'NOT_ACTIVE');
  });

  it.each(left)('an attendance session of somebody %s answers 403 NOT_ACTIVE', async (_label, change) => {
    const { app, people } = buildApp({ setup: (w) => Object.assign(w.people.attendance.employee, change) });
    expectRefusal(await me(app, bearer(tokens.attendance(people.attendance))), 403, 'NOT_ACTIVE');
  });

  it('are still let in on their last working day and while serving notice', async () => {
    const { app, people } = buildApp({
      setup: (w) => Object.assign(w.people.faculty.employee, { employment_status: 'notice_period', date_of_exit: '2026-10-16' }),
    });
    const res = await me(app, bearer(tokens.portal(people.faculty)));
    expect(res.status).toBe(200);
    expect(res.body.employee.employment_status).toBe('notice_period');
  });

  it('turn into leavers at midnight IST, not midnight UTC', async () => {
    const lastDay = (w) => { w.people.faculty.employee.date_of_exit = '2026-10-16'; };
    const signed = new Date('2026-10-16T18:00:00.000Z');
    // 23:59:59.999 IST on the last working day: still on strength.
    const before = buildApp({ setup: lastDay, now: new Date('2026-10-16T18:29:59.999Z') });
    expect((await me(before.app, bearer(tokens.portal(before.people.faculty, signed)))).status).toBe(200);
    // 00:00 IST the next day, still 16 Oct in UTC: gone.
    const after = buildApp({ setup: lastDay, now: new Date('2026-10-16T18:30:00.000Z') });
    expectRefusal(await me(after.app, bearer(tokens.portal(after.people.faculty, signed))), 403, 'NOT_ACTIVE');
  });
});

describe('an attendance session', () => {
  it.each(['otp', 'pw'])('earned by %s is let in, with no portal role', async (method) => {
    const { app, people } = buildApp();
    const res = await me(app, bearer(tokens.attendance(people.attendance, method)));
    expect(res.status).toBe(200);
    expect(res.body.login).toEqual({ kind: 'attendance', role: null, user_id: null });
    expect(res.body.employee.id).toBe(people.attendance.employee.id);
  });

  describe('signed in with the password HR gave, before the person chose their own', () => {
    // HR can give a whole batch one first-time password, and the employee code is on the ID
    // card, so such a session proves nothing about who holds the phone (passwordChangeDue,
    // attendancePunchController.js:190-197).
    const firstTime = (w) => { w.people.attendance.account.password_set_at = null; };

    it.each([['/api/ess/me'], ['/api/ess/me/capabilities']])('is refused with 403 PASSWORD_CHANGE_REQUIRED on %s', async (path) => {
      const { app, people } = buildApp({ setup: firstTime });
      const res = await request(app).get(path).set(bearer(tokens.attendance(people.attendance, 'pw')));
      expectRefusal(res, 403, 'PASSWORD_CHANGE_REQUIRED');
      expect(res.body.error).toBe('Set your own password first. The password HR gave you only works once.');
    });

    it('is let in once the person has chosen their own password', async () => {
      const { app, people } = buildApp({ setup: (w) => { w.people.attendance.account.password_set_at = '2026-10-16T05:00:00+00:00'; } });
      expect((await me(app, bearer(tokens.attendance(people.attendance, 'pw')))).status).toBe(200);
    });

    it('does not hold back a code session: a code proves the person holds the phone', async () => {
      const { app, people } = buildApp({ setup: firstTime });
      expect((await me(app, bearer(tokens.attendance(people.attendance, 'otp')))).status).toBe(200);
    });

    it('comes after the leaver, login and cut-off checks, as in the Scheduler', async () => {
      const left = buildApp({ setup: (w) => { firstTime(w); w.people.attendance.employee.employment_status = 'exited'; } });
      expectRefusal(await me(left.app, bearer(tokens.attendance(left.people.attendance, 'pw'))), 403, 'NOT_ACTIVE');
      const off = buildApp({ setup: (w) => { firstTime(w); w.people.attendance.account.status = 'disabled'; } });
      expectRefusal(await me(off.app, bearer(tokens.attendance(off.people.attendance, 'pw'))), 403, 'NO_ATTENDANCE_LOGIN');
      const signed = new Date('2026-10-16T05:00:00.000Z');
      const old = buildApp({ setup: (w) => { firstTime(w); w.people.attendance.account.sessions_valid_from = '2026-10-16T06:00:00+00:00'; } });
      expectRefusal(await me(old.app, bearer(tokens.attendance(old.people.attendance, 'pw', signed))), 401, 'NOT_AUTHENTICATED');
    });
  });

  it('is refused with 401 once its employee has been deleted', async () => {
    const { app, db, people } = buildApp();
    const token = tokens.attendance(people.attendance);
    db.tables.hr_employees = db.tables.hr_employees.filter((e) => e.id !== people.attendance.employee.id);
    expectRefusal(await me(app, bearer(token)), 401, 'NOT_AUTHENTICATED');
  });

  it('answers 403 NO_ATTENDANCE_LOGIN when the login is missing', async () => {
    const { app, people } = buildApp({ setup: (w) => { w.tables.hr_attendance_accounts = []; } });
    const res = await me(app, bearer(tokens.attendance(people.attendance)));
    expectRefusal(res, 403, 'NO_ATTENDANCE_LOGIN');
    expect(res.body.error).toMatch(/do not have an attendance login/);
  });

  it('answers 403 NO_ATTENDANCE_LOGIN when HR has switched the login off', async () => {
    const { app, people } = buildApp({ setup: (w) => { w.people.attendance.account.status = 'disabled'; } });
    const res = await me(app, bearer(tokens.attendance(people.attendance)));
    expectRefusal(res, 403, 'NO_ATTENDANCE_LOGIN');
    expect(res.body.error).toMatch(/turned off/);
  });

  it('checks the leaver before the login, as the Scheduler does', async () => {
    const { app, people } = buildApp({
      setup: (w) => {
        w.people.attendance.employee.employment_status = 'exited';
        w.tables.hr_attendance_accounts = [];
      },
    });
    expectRefusal(await me(app, bearer(tokens.attendance(people.attendance))), 403, 'NOT_ACTIVE');
  });

  describe('against the login\'s sessions_valid_from, in whole seconds', () => {
    const signed = new Date('2026-10-16T05:00:00.000Z');
    const run = async (cutoff) => {
      const { app, people } = buildApp({ setup: (w) => { w.people.attendance.account.sessions_valid_from = cutoff; } });
      return me(app, bearer(tokens.attendance(people.attendance, 'pw', signed)));
    };

    it('lets in a session issued in the same second as the cut-off', async () => {
      expect((await run('2026-10-16T05:00:00.999+00:00')).status).toBe(200);
    });

    it('lets in a session issued after the cut-off', async () => {
      expect((await run('2026-10-16T04:59:59.000+00:00')).status).toBe(200);
    });

    it('signs out a session issued in the second before the cut-off', async () => {
      const res = await run('2026-10-16T05:00:01.000+00:00');
      expectRefusal(res, 401, 'NOT_AUTHENTICATED');
      expect(res.body.error).toBe('Your password was changed. Please sign in again.');
    });

    it('reads PostgREST\'s microsecond timestamps', async () => {
      expect((await run('2026-10-16T05:00:00.999999+00:00')).status).toBe(200);
      expect((await run('2026-10-16T10:30:01.000001+05:30')).status).toBe(401);
    });
  });

  it('opens nothing more for somebody who also has a portal login', async () => {
    const { app, people } = buildApp({
      setup: (w) => w.tables.hr_attendance_accounts.push({ ...w.people.attendance.account, id: '90000000-0000-4000-8000-000000000099', employee_id: w.people.hr.employee.id }),
    });
    const res = await me(app, bearer(tokens.attendance(people.hr)));
    expect(res.status).toBe(200);
    expect(res.body.login).toEqual({ kind: 'attendance', role: null, user_id: null });
  });
});

describe('tokens that are absent or no good: 401, before any database read', () => {
  const cases = [
    ['no Authorization header', () => ({})],
    ['an empty bearer', () => ({ Authorization: 'Bearer ' })],
    ['another scheme', () => ({ Authorization: 'Basic dXNlcjpwYXNz' })],
    ['a lower-case scheme, which the Scheduler refuses too', (p) => ({ Authorization: `bearer ${tokens.portal(p.hr)}` })],
    ['a token that is not a JWT', () => bearer('not-a-token')],
    ['the wrong secret', (p) => bearer(jwt.sign({ userId: p.hr.user.id, role: 'hr' }, 'some-other-secret-of-the-right-length-000'))],
    ['alg none', (p) => bearer(jwt.sign({ userId: p.hr.user.id, role: 'hr' }, null, { algorithm: 'none' }))],
    ['HS384 with the right secret', (p) => bearer(jwt.sign({ userId: p.hr.user.id, role: 'hr' }, TEST_JWT_SECRET, { algorithm: 'HS384' }))],
    ['an attendance session signed with the wrong secret', (p) => bearer(jwt.sign(
      { k: 'punch', e: p.attendance.employee.id, m: 'otp' }, 'f'.repeat(64), { algorithm: 'HS256', audience: 'rvm-punch', expiresIn: '30d' },
    ))],
    ['an attendance session whose employee id is not a UUID', () => bearer(jwt.sign(
      { k: 'punch', e: 'emp-1', m: 'otp' }, S.punchSessionKey(), { algorithm: 'HS256', audience: 'rvm-punch', expiresIn: '30d' },
    ))],
  ];

  it.each(cases)('%s', async (_label, headers) => {
    const { app, db, people } = buildApp();
    const res = await me(app, headers(people));
    expectRefusal(res, 401, 'NOT_AUTHENTICATED');
    expect(res.headers['www-authenticate']).toBe('Bearer');
    expect(db.queries).toHaveLength(0);
  });

  it('an expired portal token (64 hours)', async () => {
    const { app, people } = buildApp({ now: new Date(SIGNED_AT.getTime() + 64 * 3600 * 1000 + 1000) });
    const res = await me(app, bearer(tokens.portal(people.hr)));
    expectRefusal(res, 401, 'NOT_AUTHENTICATED');
    expect(res.body.error).toMatch(/expired/);
  });

  it('a portal token one second short of its 64 hours is still good', async () => {
    const { app, people } = buildApp({ now: new Date(SIGNED_AT.getTime() + 64 * 3600 * 1000 - 1000) });
    expect((await me(app, bearer(tokens.portal(people.hr)))).status).toBe(200);
  });

  it('an expired attendance session (30 days)', async () => {
    const { app, people } = buildApp({ now: new Date(SIGNED_AT.getTime() + 30 * 86400 * 1000 + 1000) });
    expectRefusal(await me(app, bearer(tokens.attendance(people.attendance))), 401, 'NOT_AUTHENTICATED');
  });
});

describe('valid tokens that are not staff logins: 403 NOT_AN_EMPLOYEE, before any database read', () => {
  // Signed at the fixed test time, so the app's fixed clock finds them all unexpired.
  const signed = (payload, options) => S.signedAt(SIGNED_AT, () => jwt.sign(payload, TEST_JWT_SECRET, options));
  const cases = [
    ['a student token', () => tokens.student()],
    ['an admission-undertaking token', () => tokens.undertaking()],
    ['a token with the attendance audience signed with JWT_SECRET itself', (p) => signed(
      { k: 'punch', e: p.attendance.employee.id, m: 'otp' }, { audience: 'rvm-punch', expiresIn: '1h' },
    )],
    ['the same look-alike carrying a userId as well', (p) => signed(
      { k: 'punch', e: p.attendance.employee.id, userId: p.hr.user.id, role: 'hr' }, { audience: 'rvm-punch', expiresIn: '1h' },
    )],
    ['a JWT_SECRET token with a userId and a scope', (p) => signed({ userId: p.hr.user.id, role: 'hr', scope: 'export' }, { expiresIn: '1h' })],
    ['a JWT_SECRET token with a userId and an issuer', (p) => signed({ userId: p.hr.user.id, role: 'hr' }, { issuer: 'somebody-else', expiresIn: '1h' })],
    ['a JWT_SECRET token with no userId', () => signed({ role: 'hr' }, { expiresIn: '1h' })],
    ['a JWT_SECRET token whose userId is not a UUID', () => signed({ userId: 'hr-1', role: 'hr' }, { expiresIn: '1h' })],
    ['a student-role token that also carries a userId', (p) => signed({ userId: p.hr.user.id, role: 'student' }, { expiresIn: '1h' })],
  ];

  it.each(cases)('%s', async (_label, token) => {
    const { app, db, people } = buildApp();
    const res = await me(app, bearer(token(people)));
    expectRefusal(res, 403, 'NOT_AN_EMPLOYEE');
    expect(db.queries).toHaveLength(0);
  });
});

describe('the database is down or not migrated: 503, never 401', () => {
  beforeEach(() => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
  });

  it.each([['error'], ['throw']])('a portal login gets 503 UNAVAILABLE when the client returns %s', async (outage) => {
    const { app, db, people } = buildApp();
    db.outage = outage;
    expectRefusal(await me(app, bearer(tokens.portal(people.hr))), 503, 'UNAVAILABLE');
  });

  it.each([['error'], ['throw']])('an attendance session gets 503 UNAVAILABLE when the client returns %s', async (outage) => {
    const { app, db, people } = buildApp();
    db.outage = outage;
    expectRefusal(await me(app, bearer(tokens.attendance(people.attendance))), 503, 'UNAVAILABLE');
  });

  it('a missing attendance-login table is 503 MODULE_NOT_INSTALLED', async () => {
    const { app, db, people } = buildApp();
    db.dropTable('hr_attendance_accounts');
    const res = await me(app, bearer(tokens.attendance(people.attendance)));
    expectRefusal(res, 503, 'MODULE_NOT_INSTALLED');
    expect(res.body.error).toMatch(/hr_attendance_accounts/);
  });

  it('a missing hr_employees.user_id column is 503 MODULE_NOT_INSTALLED', async () => {
    const { app, db, people } = buildApp();
    db.dropColumn('hr_employees', 'user_id');
    expectRefusal(await me(app, bearer(tokens.portal(people.hr))), 503, 'MODULE_NOT_INSTALLED');
  });

  it('a forged token is still a 401 during an outage, because it never reaches the database', async () => {
    const { app, db } = buildApp();
    db.outage = 'error';
    expectRefusal(await me(app, bearer('forged.token.value')), 401, 'NOT_AUTHENTICATED');
  });
});
