const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { MESSAGES } = require('../src/lib/errors');
const { expectRefusal, expectInvalid, quietErrors } = require('./helpers/expect');
const { TODAY } = require('./helpers/constants');
const { uuid } = require('./helpers/fixtures');

/**
 * Work from home (KP, 22 Oct 2026): HR enables it for selected employees and fixes each one's
 * monthly limit. WFH itself is a leave request type; the allowance is its only limit, and an
 * approval writes the day present with the WFH note through the Scheduler's override function.
 */

const ALLOWANCES = '/api/ess/hr/wfh-allowances';
const MINE = '/api/ess/me/wfh';
const LEAVE = '/api/ess/leave-requests';
const BALANCES = '/api/ess/leave/balances';
const APPROVALS = '/api/ess/approvals';
const REQ = (n) => `7f000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

const listAllowances = (app, token, query = '') => request(app).get(`${ALLOWANCES}${query}`).set(bearer(token));
const setAllowance = (app, token, employeeId, body) => request(app).put(`${ALLOWANCES}/${employeeId}`).set(bearer(token)).send(body);
const myWfh = (app, token) => request(app).get(MINE).set(bearer(token));
const fileLeave = (app, token, body) => request(app).post(LEAVE).set(bearer(token)).send(body);
const withdraw = (app, token, id) => request(app).post(`${LEAVE}/${id}/withdraw`).set(bearer(token));
const decide = (app, token, id, body) => request(app).post(`${APPROVALS}/leave/${id}/decide`).set(bearer(token)).send(body);
const cancelLeave = (app, token, id, body) => request(app).post(`/api/ess/hr/leave-requests/${id}/cancel`).set(bearer(token)).send(body);
const balances = (app, token) => request(app).get(BALANCES).set(bearer(token));
const capabilities = (app, token) => request(app).get('/api/ess/me/capabilities').set(bearer(token));

const allowanceRow = (employeeId, change = {}) => ({
  employee_id: employeeId,
  is_enabled: true,
  monthly_limit_days: 4,
  note: null,
  set_by_user_id: null,
  set_by_name: 'Test HR Manager',
  created_at: '2026-10-22T06:30:00+00:00',
  updated_at: '2026-10-22T06:30:00+00:00',
  ...change,
});

const wfhRow = (employeeId, n, change = {}) => ({
  id: REQ(n),
  employee_id: employeeId,
  type: 'wfh',
  status: 'pending',
  day: '2026-10-20',
  end_day: '2026-10-20',
  portion: 'full',
  day_count: 1,
  working_days: ['2026-10-20'],
  days_before: null,
  reason: 'The centre is being painted, so I am working from home.',
  day_before: null,
  day_written_at: null,
  decided_by_employee_id: null,
  decided_by_user_id: null,
  decided_by_name: null,
  decided_at: null,
  decision_note: null,
  cancelled_by_user_id: null,
  cancelled_by_name: null,
  cancelled_at: null,
  cancel_reason: null,
  created_at: '2026-10-14T05:00:00+00:00',
  updated_at: '2026-10-14T05:00:00+00:00',
  ...change,
});

const withAllowance = (change = {}) => (w) => {
  w.tables.hr_ess_wfh_allowances = [allowanceRow(w.people.faculty.employee.id, change)];
};

const facultyDay = (db, employeeId) => db.tables.hr_staff_attendance.find((d) => d.employee_id === employeeId && d.day === '2026-10-15');

describe('HR sets a work-from-home allowance', () => {
  it('creates the row, returns the employee card, and audits only the numbers', async () => {
    const { app, db, people } = buildApp();
    const faculty = people.faculty.employee.id;
    const res = await setAllowance(app, tokens.portal(people.hr), faculty, {
      enabled: true, monthly_limit_days: 4, note: 'Two days a week while the centre is being painted.',
    });
    expect(res.status).toBe(200);
    expect(res.body.allowance).toMatchObject({
      employee_id: faculty,
      employee: {
        id: faculty,
        full_name: 'Test CAD Faculty',
        employee_code: 'RVM-011',
        branch: { name: 'Faridabad' },
        department: { name: 'Technical Training' },
      },
      enabled: true,
      monthly_limit_days: 4,
      note: 'Two days a week while the centre is being painted.',
      set_by_name: 'Test HR Manager',
    });
    expect(db.tables.hr_ess_wfh_allowances).toHaveLength(1);
    const audit = db.tables.hr_ess_audit.at(-1);
    expect(audit).toMatchObject({
      action: 'wfh.allowance.changed',
      target_employee_id: faculty,
      details: { before: null, after: { enabled: true, monthly_limit_days: 4 } },
    });
    expect(JSON.stringify(audit.details)).not.toContain('painted');
  });

  it('updates and disables the same row, keeping the limit and recording before and after', async () => {
    const { app, db, people } = buildApp({ setup: withAllowance() });
    const faculty = people.faculty.employee.id;
    const res = await setAllowance(app, tokens.portal(people.ceo), faculty, { enabled: false, monthly_limit_days: 6 });
    expect(res.status).toBe(200);
    expect(res.body.allowance).toMatchObject({ enabled: false, monthly_limit_days: 6, note: null });
    expect(db.tables.hr_ess_wfh_allowances).toHaveLength(1);
    expect(db.tables.hr_ess_audit.at(-1).details).toEqual({
      before: { enabled: true, monthly_limit_days: 4 },
      after: { enabled: false, monthly_limit_days: 6 },
    });
  });

  it.each([
    ['hr_executive', 403, 'ATTENDANCE_OVERRIDE_DENIED'],
    ['admin_manager', 403, 'ATTENDANCE_OVERRIDE_DENIED'],
    ['faculty', 403, 'ATTENDANCE_OVERRIDE_DENIED'],
  ])('refuses %s', async (who, status, code) => {
    const { app, people } = buildApp();
    expectRefusal(await setAllowance(app, tokens.portal(people[who]), people.faculty.employee.id, {
      enabled: true, monthly_limit_days: 4,
    }), status, code);
  });

  it.each([
    ['without enabled', { monthly_limit_days: 4 }],
    ['with enabled not a boolean', { enabled: 'yes', monthly_limit_days: 4 }],
    ['with a limit of 0', { enabled: true, monthly_limit_days: 0 }],
    ['with a limit of 32', { enabled: true, monthly_limit_days: 32 }],
    ['with a fractional limit', { enabled: true, monthly_limit_days: 2.5 }],
    ['with a note over 300 characters', { enabled: true, monthly_limit_days: 4, note: 'x'.repeat(301) }],
  ])('refuses a body %s', async (_label, body) => {
    const { app, people } = buildApp();
    expectInvalid(await setAllowance(app, tokens.portal(people.hr), people.faculty.employee.id, body), MESSAGES.WFH_ALLOWANCE);
  });

  it('refuses a field the server does not take', async () => {
    const { app, people } = buildApp();
    expectInvalid(await setAllowance(app, tokens.portal(people.hr), people.faculty.employee.id, {
      enabled: true, monthly_limit_days: 4, reason: 'Because.',
    }), MESSAGES.UNKNOWN_FIELD);
  });

  it('refuses a missing id, an unknown employee and somebody who has left', async () => {
    const { app, people } = buildApp({
      setup: (w) => { w.people.pune.employee.employment_status = 'exited'; },
    });
    const token = tokens.portal(people.hr);
    expectInvalid(await setAllowance(app, token, 'not-an-id', { enabled: true, monthly_limit_days: 4 }), MESSAGES.INVALID_ID);
    expectRefusal(await setAllowance(app, token, '8f000000-0000-4000-8000-000000000099', {
      enabled: true, monthly_limit_days: 4,
    }), 404, 'EMPLOYEE_NOT_FOUND');
    expectRefusal(await setAllowance(app, token, people.pune.employee.id, {
      enabled: true, monthly_limit_days: 4,
    }), 404, 'EMPLOYEE_NOT_FOUND');
  });

  it('lists who has it, joined to the employee card, with a search', async () => {
    const { app, people } = buildApp({ setup: withAllowance() });
    const res = await listAllowances(app, tokens.portal(people.hr));
    expect(res.status).toBe(200);
    expect(res.body.truncated).toBe(false);
    expect(res.body.allowances).toHaveLength(1);
    expect(res.body.allowances[0]).toMatchObject({
      employee_id: people.faculty.employee.id,
      employee: { full_name: 'Test CAD Faculty', employee_code: 'RVM-011', branch: { name: 'Faridabad' } },
      enabled: true,
      monthly_limit_days: 4,
    });
    // The attendance-only employee has no row: simply absent, not a blank entry.
    expect((await listAllowances(app, tokens.portal(people.hr), '?q=Office')).body.allowances).toEqual([]);
    expect((await listAllowances(app, tokens.portal(people.hr), '?q=CAD')).body.allowances).toHaveLength(1);
    expectRefusal(await listAllowances(app, tokens.portal(people.hr), `?q=${'x'.repeat(61)}`), 400, 'VALIDATION_FAILED');
    expectRefusal(await listAllowances(app, tokens.portal(people.hr_executive)), 403, 'ATTENDANCE_OVERRIDE_DENIED');
  });

  it('cuts the list at 200 and says so', async () => {
    const { app, db, people } = buildApp();
    db.tables.hr_ess_wfh_allowances = Array.from({ length: 201 }, (_, i) => allowanceRow(uuid('e', 1000 + i)));
    const res = await listAllowances(app, tokens.portal(people.hr));
    expect(res.status).toBe(200);
    expect(res.body.allowances).toHaveLength(200);
    expect(res.body.truncated).toBe(true);
  });

  it('answers 401 with no token and 503 before its table exists', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    expectRefusal(await request(app).get(ALLOWANCES), 401, 'NOT_AUTHENTICATED');
    expectRefusal(await request(app).put(`${ALLOWANCES}/${people.faculty.employee.id}`)
      .send({ enabled: true, monthly_limit_days: 4 }), 401, 'NOT_AUTHENTICATED');
    db.dropTable('hr_ess_wfh_allowances');
    expectRefusal(await listAllowances(app, tokens.portal(people.hr)), 503, 'MODULE_NOT_INSTALLED');
    expectRefusal(await myWfh(app, tokens.portal(people.faculty)), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('filing a WFH request', () => {
  it('is refused without an allowance, and again when HR has switched it off', async () => {
    const { app, people } = buildApp();
    expectRefusal(await fileLeave(app, tokens.portal(people.faculty), {
      type: 'wfh', day: '2026-10-20', reason: 'Working from home today.',
    }), 409, 'WFH_NOT_ALLOWED');

    const off = buildApp({ setup: withAllowance({ is_enabled: false }) });
    expectRefusal(await fileLeave(off.app, tokens.portal(off.people.faculty), {
      type: 'wfh', day: '2026-10-20', reason: 'Working from home today.',
    }), 409, 'WFH_NOT_ALLOWED');
  });

  it('counts approved and pending days and refuses over the month\'s limit', async () => {
    const { app, db, people } = buildApp({ setup: withAllowance({ monthly_limit_days: 2 }) });
    const faculty = people.faculty.employee.id;
    db.tables.hr_ess_leave_requests = [
      wfhRow(faculty, 1, { status: 'approved', day: '2026-10-05', decided_at: '2026-10-04T05:00:00+00:00', decided_by_name: 'Test HR Manager' }),
      wfhRow(faculty, 2, { day: '2026-10-06' }),
    ];
    expectRefusal(await fileLeave(app, tokens.portal(people.faculty), {
      type: 'wfh', day: '2026-10-20', reason: 'Working from home today.',
    }), 409, 'WFH_LIMIT');
    // Last month's WFH days do not count against this month's allowance.
    const other = buildApp({ setup: withAllowance({ monthly_limit_days: 1 }) });
    other.db.tables.hr_ess_leave_requests = [wfhRow(other.people.faculty.employee.id, 3, {
      status: 'approved', day: '2026-09-20', decided_at: '2026-09-19T05:00:00+00:00', decided_by_name: 'Test HR Manager',
    })];
    expect((await fileLeave(other.app, tokens.portal(other.people.faculty), {
      type: 'wfh', day: '2026-10-20', reason: 'Working from home today.',
    })).status).toBe(201);
  });

  it('files a day and can withdraw it while pending', async () => {
    const { app, db, people } = buildApp({ setup: withAllowance() });
    const res = await fileLeave(app, tokens.portal(people.faculty), {
      type: 'wfh', day: '2026-10-20', reason: 'Working from home today.',
    });
    expect(res.status).toBe(201);
    expect(res.body.request).toMatchObject({ family: 'leave', type: 'wfh', status: 'pending', day: '2026-10-20' });
    const id = res.body.request.id;
    expect(db.tables.hr_ess_leave_requests[0].employee_id).toBe(people.faculty.employee.id);
    expect(db.tables.hr_ess_leave_request_history[0].action).toBe('filed');
    const out = await withdraw(app, tokens.portal(people.faculty), id);
    expect(out.status).toBe(200);
    expect(out.body.request.status).toBe('withdrawn');
  });

  it('refuses a malformed WFH form with 400', async () => {
    const { app, people } = buildApp({ setup: withAllowance() });
    expectInvalid(await fileLeave(app, tokens.portal(people.faculty), {
      type: 'wfh', day: '2026-02-30', reason: 'Working from home today.',
    }), MESSAGES.DATE_FORMAT);
    expectInvalid(await fileLeave(app, tokens.portal(people.faculty), {
      type: 'wfh', day: '2026-10-20', reason: 'home',
    }), MESSAGES.REQUEST_REASON);
  });
});

describe('deciding and cancelling a WFH day', () => {
  it('re-checks a disabled allowance at approval time', async () => {
    const { app, db, people } = buildApp({ setup: withAllowance({ is_enabled: false }) });
    db.tables.hr_ess_leave_requests = [wfhRow(people.faculty.employee.id, 1)];
    expectRefusal(await decide(app, tokens.portal(people.hr), REQ(1), { decision: 'approve' }),
      409, 'WFH_NOT_ALLOWED');
    expect(db.tables.hr_ess_leave_requests[0].status).toBe('pending');
  });

  it('re-checks the month\'s limit at approval time, so two approvals cannot both win', async () => {
    const { app, db, people } = buildApp({ setup: withAllowance({ monthly_limit_days: 1 }) });
    const faculty = people.faculty.employee.id;
    db.tables.hr_ess_leave_requests = [
      wfhRow(faculty, 1, { status: 'approved', day: '2026-10-05', decided_at: '2026-10-04T05:00:00+00:00', decided_by_name: 'Test HR Manager' }),
      wfhRow(faculty, 2, { day: '2026-10-20' }),
    ];
    expectRefusal(await decide(app, tokens.portal(people.hr), REQ(2), { decision: 'approve' }),
      409, 'WFH_LIMIT');
    expect(db.tables.hr_ess_leave_requests.find((r) => r.id === REQ(2)).status).toBe('pending');
  });

  it('writes the day present with the WFH note and keeps the times it recorded', async () => {
    const { app, db, people } = buildApp({ setup: withAllowance() });
    const faculty = people.faculty.employee.id;
    const before = { ...facultyDay(db, faculty) };
    db.tables.hr_ess_leave_requests = [wfhRow(faculty, 1, { day: '2026-10-15' })];
    const res = await decide(app, tokens.portal(people.hr), REQ(1), { decision: 'approve' });
    expect(res.status).toBe(200);
    expect(res.body.request.status).toBe('approved');
    const day = facultyDay(db, faculty);
    expect(day.status).toBe('present');
    expect(day.leave_type).toBeNull();
    expect(day.note).toBe('Work from home: The centre is being painted, so I am working from home.');
    expect(day.source).toBe('override');
    expect(day.first_in).toBe(before.first_in);
    expect(day.last_out).toBe(before.last_out);
    expect(day.worked_minutes).toBe(before.worked_minutes);
  });

  it('restores the day exactly when HR cancels the approved request', async () => {
    const { app, db, people } = buildApp({ setup: withAllowance() });
    const faculty = people.faculty.employee.id;
    const before = { ...facultyDay(db, faculty) };
    db.tables.hr_ess_leave_requests = [wfhRow(faculty, 1, { day: '2026-10-15' })];
    expect((await decide(app, tokens.portal(people.hr), REQ(1), { decision: 'approve' })).status).toBe(200);

    const out = await cancelLeave(app, tokens.portal(people.hr), REQ(1), { reason: 'The centre stayed open.' });
    expect(out.status).toBe(200);
    expect(out.body.request.status).toBe('cancelled');
    const day = facultyDay(db, faculty);
    expect(day.status).toBe(before.status);
    expect(day.source).toBe(before.source);
    expect(day.note).toBe(before.note);
    expect(day.first_in).toBe(before.first_in);
    expect(day.last_out).toBe(before.last_out);
    expect(day.worked_minutes).toBe(before.worked_minutes);
  });

  it('takes away a day the approval created when there was no row', async () => {
    const { app, db, people } = buildApp({ setup: withAllowance() });
    const faculty = people.faculty.employee.id;
    db.tables.hr_ess_leave_requests = [wfhRow(faculty, 1, { day: '2026-10-21' })];
    expect((await decide(app, tokens.portal(people.hr), REQ(1), { decision: 'approve' })).status).toBe(200);
    expect(db.tables.hr_staff_attendance.some((d) => d.employee_id === faculty && d.day === '2026-10-21')).toBe(true);
    expect((await cancelLeave(app, tokens.portal(people.hr), REQ(1), { reason: 'Not needed.' })).status).toBe(200);
    expect(db.tables.hr_staff_attendance.some((d) => d.employee_id === faculty && d.day === '2026-10-21')).toBe(false);
  });
});

describe('what the employee sees', () => {
  it('shows the allowance, used and pending in the balances', async () => {
    const { app, db, people } = buildApp({ setup: withAllowance() });
    const faculty = people.faculty.employee.id;
    db.tables.hr_ess_leave_requests = [
      wfhRow(faculty, 1, { status: 'approved', day: '2026-10-05', decided_at: '2026-10-04T05:00:00+00:00', decided_by_name: 'Test HR Manager' }),
      wfhRow(faculty, 2, { status: 'approved', day: '2026-10-06', decided_at: '2026-10-05T05:00:00+00:00', decided_by_name: 'Test HR Manager' }),
      wfhRow(faculty, 3, { day: '2026-10-20' }),
    ];
    const res = await balances(app, tokens.portal(people.faculty));
    expect(res.status).toBe(200);
    expect(res.body.types.find((t) => t.type === 'wfh')).toEqual({
      type: 'wfh', offered: true, unit: 'count', phase: 1, allowed: 4, used: 2, pending: 1, remaining: 1,
    });
    const off = buildApp();
    const none = await balances(off.app, tokens.portal(off.people.faculty));
    expect(none.body.types.find((t) => t.type === 'wfh')).toEqual({
      type: 'wfh', offered: false, unit: 'count', phase: 1, allowed: 0, used: 0, pending: 0, remaining: 0,
    });
  });

  it('keeps the other balances working before the WFH migration is applied', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    db.dropTable('hr_ess_wfh_allowances');
    const res = await balances(app, tokens.portal(people.faculty));
    expect(res.status).toBe(200);
    expect(res.body.types.find((t) => t.type === 'wfh')).toEqual({
      type: 'wfh', offered: false, unit: 'count', phase: 1, allowed: 0, used: 0, pending: 0, remaining: 0,
    });
    expect(res.body.types.find((t) => t.type === 'leave_cl').offered).toBe(true);
  });

  it('puts the allowance in the capabilities document, and leaves it off without one', async () => {
    const { app, people } = buildApp({ setup: withAllowance({ monthly_limit_days: 4 }) });
    const res = await capabilities(app, tokens.portal(people.faculty));
    expect(res.body.requests.types.find((t) => t.type === 'wfh')).toEqual({
      type: 'wfh', offered: true, limit: 4, unit: 'count', phase: 1,
    });
    const off = buildApp();
    const none = await capabilities(off.app, tokens.portal(off.people.faculty));
    expect(none.body.requests.types.find((t) => t.type === 'wfh')).toEqual({
      type: 'wfh', offered: false, limit: 0, unit: 'count', phase: 1,
    });
  });

  it('answers GET /me/wfh with this month\'s numbers', async () => {
    const { app, db, people } = buildApp({ setup: withAllowance({ monthly_limit_days: 4 }) });
    const faculty = people.faculty.employee.id;
    db.tables.hr_ess_leave_requests = [
      wfhRow(faculty, 1, { status: 'approved', day: '2026-10-05', decided_at: '2026-10-04T05:00:00+00:00', decided_by_name: 'Test HR Manager' }),
      wfhRow(faculty, 2, { day: '2026-10-20' }),
      wfhRow(faculty, 3, { status: 'approved', day: '2026-09-20', decided_at: '2026-09-19T05:00:00+00:00', decided_by_name: 'Test HR Manager' }),
    ];
    const res = await myWfh(app, tokens.portal(people.faculty));
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ month: TODAY.slice(0, 7), enabled: true, monthly_limit_days: 4, used: 1, pending: 1, remaining: 2 });

    const off = buildApp();
    expect((await myWfh(off.app, tokens.portal(off.people.faculty))).body).toEqual({
      month: TODAY.slice(0, 7), enabled: false, monthly_limit_days: 0, used: 0, pending: 0, remaining: 0,
    });
    // An attendance session sees the same answer.
    expect((await myWfh(off.app, tokens.attendance(off.people.attendance))).status).toBe(200);
  });

  it('shows zero remaining when a week of pending and approved days already meets the limit', async () => {
    const { app, db, people } = buildApp({ setup: withAllowance({ monthly_limit_days: 2 }) });
    const faculty = people.faculty.employee.id;
    db.tables.hr_ess_leave_requests = [
      wfhRow(faculty, 1, { status: 'approved', day: '2026-10-05', decided_at: '2026-10-04T05:00:00+00:00', decided_by_name: 'Test HR Manager' }),
      wfhRow(faculty, 2, { day: '2026-10-20' }),
    ];
    expect((await myWfh(app, tokens.portal(people.faculty))).body).toEqual({
      month: TODAY.slice(0, 7), enabled: true, monthly_limit_days: 2, used: 1, pending: 1, remaining: 0,
    });
  });
});
