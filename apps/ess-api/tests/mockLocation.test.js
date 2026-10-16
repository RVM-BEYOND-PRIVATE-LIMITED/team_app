const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { NOW } = require('./helpers/constants');
const { BRANCH_ID, BRANCH_PUNE_ID } = require('./helpers/fixtures');
const { MESSAGES } = require('../src/lib/errors');
const { DEFAULT_LIMITS } = require('../src/middleware/rateLimit');
const { expectRefusal, expectInvalid, quietErrors, CALLERS, guardOutcome } = require('./helpers/expect');

/** Task B14: the phone reports a mocked location it refused to punch with; HR, the CEO and super admins read the reports. */

const REPORT = '/api/ess/attendance/mock-location';
const LIST = '/api/ess/hr/mock-location-reports';
const ATTENDANCE_ROLES = ['hr', 'ceo', 'super_admin'];

const FIX = {
  kind: 'punch', latitude: 28.40912, longitude: 77.31801, accuracy_m: 0,
  client_at: '2026-10-16T11:59:00.000+05:30', provider: 'gps', app_version: '1.0.0+3', install_id: 'install-3f9a',
};

const report = (app, token, body = FIX) => request(app).post(REPORT).set(bearer(token)).send(body);

/** A stored report, as if filed earlier. */
const stored = (employeeId, branchId, reportedAt, n) => ({
  id: `60000000-0000-4000-8000-${String(n).padStart(12, '0')}`,
  employee_id: employeeId, branch_id: branchId, reported_at: reportedAt, client_at: null, kind: 'punch',
  latitude: 28.4, longitude: 77.3, accuracy_m: 0, provider: 'gps', app_version: '1.0.0', install_id: `install-${n}`,
});

describe('POST /api/ess/attendance/mock-location', () => {
  it.each([['a portal login', (p) => tokens.portal(p.faculty), 'faculty'], ['an attendance session', (p) => tokens.attendance(p.attendance), 'attendance']])(
    'stores the report for %s, with the server\'s time and the branch the person is at',
    async (_label, token, who) => {
      const { app, db, people } = buildApp();
      const res = await report(app, token(people));
      expect(res.status).toBe(201);
      expect(res.body).toEqual({ report: { id: expect.any(String), reported_at: NOW.toISOString() } });
      expect(db.tables.hr_ess_mock_location_reports).toEqual([{
        id: res.body.report.id,
        employee_id: people[who].employee.id,
        branch_id: BRANCH_ID,
        reported_at: NOW.toISOString(),
        client_at: '2026-10-16T06:29:00.000Z',
        kind: 'punch',
        latitude: 28.40912,
        longitude: 77.31801,
        accuracy_m: 0,
        provider: 'gps',
        app_version: '1.0.0+3',
        install_id: 'install-3f9a',
      }]);
    },
  );

  it('takes a report with no location, and keeps an unreadable phone clock as null rather than refusing it', async () => {
    const { app, db, people } = buildApp();
    const res = await report(app, tokens.attendance(people.attendance), { kind: 'punch', client_at: 'yesterday-ish' });
    expect(res.status).toBe(201);
    expect(db.tables.hr_ess_mock_location_reports[0]).toMatchObject({ latitude: null, longitude: null, accuracy_m: null, client_at: null, provider: null });
  });

  it('takes no employee or branch from the body, so nobody can report in somebody else\'s name', async () => {
    const { app, people } = buildApp();
    expectInvalid(await report(app, tokens.portal(people.faculty), { ...FIX, employee_id: people.hr.employee.id }), MESSAGES.UNKNOWN_FIELD);
    expectInvalid(await report(app, tokens.portal(people.faculty), { ...FIX, branch_id: BRANCH_PUNE_ID }), MESSAGES.UNKNOWN_FIELD);
  });

  it.each([
    ['no kind', { latitude: 1, longitude: 1 }, MESSAGES.MOCK_KIND],
    ['a mocked ping, which is not reported yet', { ...FIX, kind: 'ping' }, MESSAGES.MOCK_KIND],
    ['a latitude out of range', { ...FIX, latitude: 91 }, MESSAGES.MOCK_LOCATION],
    ['a longitude out of range', { ...FIX, longitude: -181 }, MESSAGES.MOCK_LOCATION],
    ['a latitude as text', { ...FIX, latitude: '28.4' }, MESSAGES.MOCK_LOCATION],
    ['a latitude with no longitude', { kind: 'punch', latitude: 28.4 }, MESSAGES.MOCK_LOCATION],
    ['a negative accuracy', { ...FIX, accuracy_m: -1 }, MESSAGES.MOCK_LOCATION],
    ['a provider over 80 characters', { ...FIX, provider: 'x'.repeat(81) }, MESSAGES.MOCK_TEXT],
    ['an app version over 40 characters', { ...FIX, app_version: 'x'.repeat(41) }, MESSAGES.MOCK_TEXT],
    ['an install id over 128 characters', { ...FIX, install_id: 'x'.repeat(129) }, MESSAGES.MOCK_TEXT],
    ['an install id that is not text', { ...FIX, install_id: 42 }, MESSAGES.MOCK_TEXT],
  ])('refuses %s with 400', async (_label, body, message) => {
    const { app, db, people } = buildApp();
    expectInvalid(await report(app, tokens.portal(people.faculty), body), message);
    expect(db.tables.hr_ess_mock_location_reports || []).toEqual([]);
  });

  it('refuses a person past their daily allowance with 429 RATE_LIMITED, and only that person', async () => {
    const { app, people } = buildApp({ limits: { mockReports: { windowMs: 24 * 3600 * 1000, limit: 2 } } });
    const token = tokens.attendance(people.attendance);
    expect((await report(app, token)).status).toBe(201);
    expect((await report(app, token)).status).toBe(201);
    const res = await report(app, token);
    expectRefusal(res, 429, 'RATE_LIMITED');
    expect(res.body.error).toBe(MESSAGES.REPORTS_RATE_LIMITED);
    expect(Number(res.headers['retry-after'])).toBeGreaterThan(0);
    expect((await report(app, tokens.portal(people.faculty))).status).toBe(201);
    // The allowance is for reports only: the person's other requests still work.
    expect((await request(app).get('/api/ess/me').set(bearer(token))).status).toBe(200);
  });

  it('allows a few dozen reports a day in production', () => {
    expect(DEFAULT_LIMITS.mockReports).toEqual({ windowMs: 24 * 60 * 60 * 1000, limit: 30 });
  });

  it('answers 503 MODULE_NOT_INSTALLED, naming the table, before the migration', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    db.dropTable('hr_ess_mock_location_reports');
    const res = await report(app, tokens.portal(people.faculty));
    expectRefusal(res, 503, 'MODULE_NOT_INSTALLED');
    expect(res.body.error).toMatch(/hr_ess_mock_location_reports/);
  });

  it('answers 401 with no token', async () => {
    const { app } = buildApp();
    expectRefusal(await request(app).post(REPORT).send(FIX), 401, 'NOT_AUTHENTICATED');
  });
});

describe('GET /api/ess/hr/mock-location-reports', () => {
  /** Reports at both branches, in and out of the default 30 days. */
  const withReports = () => buildApp({
    setup: (w) => {
      w.tables.hr_ess_mock_location_reports = [
        stored(w.people.attendance.employee.id, BRANCH_ID, '2026-10-16T05:00:00.000Z', 1),
        stored(w.people.pune.employee.id, BRANCH_PUNE_ID, '2026-10-10T05:00:00.000Z', 2),
        // 00:10 IST on 1 Oct is 1 Oct in IST, though still 30 Sept in UTC.
        stored(w.people.faculty.employee.id, BRANCH_ID, '2026-09-30T18:40:00.000Z', 3),
        stored(w.people.faculty.employee.id, BRANCH_ID, '2026-09-01T05:00:00.000Z', 4),
      ];
    },
  });

  it.each(CALLERS)('%s', async (who, token) => {
    const { app, people } = withReports();
    const res = await request(app).get(LIST).set(bearer(token(people)));
    // HR Executive has HR's powers without attendance, and the Admin Manager does not see the trail.
    const refused = guardOutcome(who, ATTENDANCE_ROLES, 'ATTENDANCE_OVERRIDE_DENIED');
    if (refused) {
      expectRefusal(res, 403, refused);
      expect(JSON.stringify(res.body)).not.toMatch(/install-/);
    } else {
      expect(res.status).toBe(200);
    }
  });

  it('lists the last 30 days by default, newest first, with whose report each is', async () => {
    const { app, people } = withReports();
    const res = await request(app).get(LIST).set(bearer(tokens.portal(people.hr)));
    expect(res.body.from).toBe('2026-09-16');
    expect(res.body.to).toBe('2026-10-16');
    expect(res.body.truncated).toBe(false);
    expect(res.body.reports.map((r) => r.install_id)).toEqual(['install-1', 'install-2', 'install-3']);
    expect(res.body.reports[0]).toEqual({
      id: '60000000-0000-4000-8000-000000000001', reported_at: '2026-10-16T05:00:00.000Z', client_at: null, kind: 'punch',
      latitude: 28.4, longitude: 77.3, accuracy_m: 0, provider: 'gps', app_version: '1.0.0', install_id: 'install-1',
      employee: { id: people.attendance.employee.id, full_name: 'Test Office Assistant', employee_code: 'RVM-050' },
      branch: { id: BRANCH_ID, name: 'Faridabad' },
    });
    expect(JSON.stringify(res.body)).not.toMatch(/9710000|@example/);
  });

  it('takes from and to as IST days', async () => {
    const { app, people } = withReports();
    const oct = await request(app).get(`${LIST}?from=2026-10-01&to=2026-10-01`).set(bearer(tokens.portal(people.ceo)));
    expect(oct.body.reports.map((r) => r.install_id)).toEqual(['install-3']);
    const sept = await request(app).get(`${LIST}?from=2026-09-01&to=2026-09-30`).set(bearer(tokens.portal(people.ceo)));
    expect(sept.body.reports.map((r) => r.install_id)).toEqual(['install-4']);
  });

  it('filters by the branch where the report was made', async () => {
    const { app, people } = withReports();
    const res = await request(app).get(`${LIST}?branch_id=${BRANCH_PUNE_ID}`).set(bearer(tokens.portal(people.super_admin)));
    expect(res.body.reports.map((r) => r.install_id)).toEqual(['install-2']);
    expect(res.body.reports[0].branch).toEqual({ id: BRANCH_PUNE_ID, name: 'Pune' });
  });

  it('says when the list was cut at 500', async () => {
    const { app, people } = buildApp({
      setup: (w) => {
        w.tables.hr_ess_mock_location_reports = Array.from({ length: 501 }, (_, i) =>
          stored(w.people.attendance.employee.id, BRANCH_ID, new Date(NOW.getTime() - i * 60000).toISOString(), i + 1));
      },
    });
    const res = await request(app).get(LIST).set(bearer(tokens.portal(people.hr)));
    expect(res.body.reports).toHaveLength(500);
    expect(res.body.truncated).toBe(true);
  });

  it.each([
    ['from=2026-13-01', MESSAGES.DATE_FORMAT],
    ['to=16-10-2026', MESSAGES.DATE_FORMAT],
    ['from=2026-10-10&from=2026-10-11', MESSAGES.DATE_FORMAT],
    ['from=2026-10-10&to=2026-10-09', MESSAGES.DATE_RANGE],
    ['from=2025-01-01&to=2026-10-16', MESSAGES.DATE_RANGE],
    ['branch_id=pune', MESSAGES.BRANCH_ID],
  ])('refuses ?%s with 400', async (query, message) => {
    const { app, people } = buildApp();
    expectInvalid(await request(app).get(`${LIST}?${query}`).set(bearer(tokens.portal(people.hr))), message);
  });

  it('answers 404 NOT_FOUND for a branch that is not there', async () => {
    const { app, people } = buildApp();
    expectRefusal(await request(app).get(`${LIST}?branch_id=b0000000-0000-4000-8000-000000000999`).set(bearer(tokens.portal(people.hr))), 404, 'NOT_FOUND');
  });

  it('answers 503 MODULE_NOT_INSTALLED before the migration', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    db.dropTable('hr_ess_mock_location_reports');
    expectRefusal(await request(app).get(LIST).set(bearer(tokens.portal(people.hr))), 503, 'MODULE_NOT_INSTALLED');
  });
});
