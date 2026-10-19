const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { NOW } = require('./helpers/constants');
const { MESSAGES } = require('../src/lib/errors');
const { expectRefusal, expectInvalid, quietErrors } = require('./helpers/expect');

/** Tasks C2, C4 and C5: leave requests (CL, LWP) and the balances every form shows. */

const MINE = '/api/ess/leave-requests';
const BALANCES = '/api/ess/leave/balances';
const REQ = (n) => `7b000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

const file = (app, token, body) => request(app).post(MINE).set(bearer(token)).send(body);
const list = (app, token) => request(app).get(MINE).set(bearer(token));
const withdraw = (app, token, id) => request(app).post(`${MINE}/${id}/withdraw`).set(bearer(token));
const balances = (app, token, query = '') => request(app).get(`${BALANCES}${query}`).set(bearer(token));

const leaveRequestRow = (employeeId, n, change = {}) => ({
  id: REQ(n),
  employee_id: employeeId,
  type: 'cl',
  status: 'pending',
  day: '2026-10-20',
  reason: 'Family function at home.',
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

/** A day the sheet records as leave, for the "written counts too" cases. */
const leaveDayRow = (employeeId, day, leaveType, change = {}) => ({
  id: `7c000000-0000-4000-8000-${String(Math.abs(day.length + day.charCodeAt(9))).padStart(12, '0')}`,
  employee_id: employeeId,
  branch_id: null,
  day,
  status: 'leave',
  leave_type: leaveType,
  note: null,
  marked_by: null,
  marked_by_name: 'Test HR Manager',
  marked_at: `${day}T05:00:00+00:00`,
  updated_at: `${day}T05:00:00+00:00`,
  source: 'override',
  first_in: null,
  last_out: null,
  worked_minutes: null,
  shift_id: null,
  shift_start: null,
  shift_end: null,
  grace_minutes: null,
  late_minutes: null,
  early_exit_minutes: null,
  late_count: null,
  late_half_day: false,
  late_excused: false,
  late_excused_by_name: null,
  late_excused_reason: null,
  late_excused_at: null,
  ...change,
});

describe('POST /api/ess/leave-requests', () => {
  it.each([['cl', '2026-10-20'], ['lwp', '2026-10-21']])('files a %s request, for either sign-in', async (type, day) => {
    const { app, db, people } = buildApp();
    const res = await file(app, tokens.attendance(people.attendance), { type, day, reason: 'Family function at home.' });
    expect(res.status).toBe(201);
    expect(res.body).toEqual({
      request: {
        id: expect.any(String),
        family: 'leave',
        type,
        status: 'pending',
        day,
        reason: 'Family function at home.',
        created_at: NOW.toISOString(),
        decided_at: null,
        decided_by_name: null,
        decision_note: null,
        cancelled_at: null,
        cancelled_by_name: null,
        cancel_reason: null,
      },
    });
    expect(db.tables.hr_ess_leave_requests[0].employee_id).toBe(people.attendance.employee.id);
    expect(db.tables.hr_ess_leave_request_history[0]).toMatchObject({ action: 'filed' });
  });

  it.each([
    ['no type', { day: '2026-10-20', reason: 'Family function at home.' }, MESSAGES.LEAVE_REQUEST_TYPE],
    ['sick leave', { type: 'sick', day: '2026-10-20', reason: 'Down with a fever, staying in.' }, MESSAGES.LEAVE_REQUEST_TYPE],
    ['a short reason', { type: 'cl', day: '2026-10-20', reason: 'home' }, MESSAGES.REQUEST_REASON],
    ['an unknown field', { type: 'cl', day: '2026-10-20', reason: 'Family function at home.', place: 'Site' }, MESSAGES.UNKNOWN_FIELD],
  ])('refuses %s with 400', async (_label, body, message) => {
    const { app, people } = buildApp();
    expectInvalid(await file(app, tokens.portal(people.faculty), body), message);
  });

  it('counts a CL day the sheet already records as used, so a second CL cannot be filed', async () => {
    const { app, db, people } = buildApp();
    db.tables.hr_staff_attendance.push(leaveDayRow(people.faculty.employee.id, '2026-10-10', 'cl'));
    const res = await file(app, tokens.portal(people.faculty), { type: 'cl', day: '2026-10-20', reason: 'Family function at home.' });
    expectRefusal(res, 409, 'LIMIT_REACHED');
    // Leave without pay has no limit set: it still goes.
    expect((await file(app, tokens.portal(people.faculty), { type: 'lwp', day: '2026-10-20', reason: 'Unpaid days at home.' })).status).toBe(201);
  });

  it('answers 401 with no token and 503 MODULE_NOT_INSTALLED before the table exists', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    expectRefusal(await request(app).post(MINE).send({ type: 'cl', day: '2026-10-20', reason: 'Family function at home.' }), 401, 'NOT_AUTHENTICATED');
    db.dropTable('hr_ess_leave_requests');
    const res = await file(app, tokens.attendance(people.attendance), { type: 'cl', day: '2026-10-20', reason: 'Family function at home.' });
    expectRefusal(res, 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('GET /api/ess/leave-requests and the withdraw', () => {
  it('lists the caller\'s own and lets them withdraw a pending one', async () => {
    const { app, db, people } = buildApp();
    db.tables.hr_ess_leave_requests = [
      leaveRequestRow(people.attendance.employee.id, 1),
      leaveRequestRow(people.faculty.employee.id, 2),
    ];
    const token = tokens.attendance(people.attendance);
    const listed = await list(app, token);
    expect(listed.body.requests.map((r) => r.id)).toEqual([REQ(1)]);
    const res = await withdraw(app, token, REQ(1));
    expect(res.status).toBe(200);
    expect(res.body.request.status).toBe('withdrawn');
    expectRefusal(await withdraw(app, token, REQ(1)), 409, 'REQUEST_NOT_PENDING');
    expectRefusal(await withdraw(app, token, REQ(2)), 404, 'NOT_FOUND');
  });
});

describe('GET /api/ess/leave/balances', () => {
  it('shows allowed, used, pending and remaining for every type, from the records themselves', async () => {
    const { app, db, people } = buildApp();
    const mine = people.attendance.employee.id;
    db.tables.hr_ess_attendance_requests = [
      { ...leaveRequestRow(mine, 9), type: 'on_duty', day: '2026-10-15', status: 'approved', decided_by_name: 'Test Admin Manager', decided_at: '2026-10-14T05:00:00+00:00', reason: 'Client visit.' },
    ];
    db.tables.hr_ess_leave_requests = [
      leaveRequestRow(mine, 1, { type: 'cl', status: 'pending' }),
      leaveRequestRow(mine, 2, { type: 'lwp', status: 'approved', decided_by_name: 'Test HR Manager', decided_at: '2026-10-15T05:00:00+00:00' }),
    ];
    db.tables.hr_staff_attendance.push(leaveDayRow(mine, '2026-10-05', 'cl'));
    const res = await balances(app, tokens.attendance(people.attendance));
    expect(res.status).toBe(200);
    expect(res.body.month).toBe('2026-10');
    const by = Object.fromEntries(res.body.types.map((t) => [t.type, t]));
    expect(by.fix_a_day).toEqual({ type: 'fix_a_day', offered: true, unit: 'count', phase: 1, allowed: 3, used: 0, pending: 0, remaining: 3 });
    expect(by.on_duty).toEqual({ type: 'on_duty', offered: true, unit: 'count', phase: 1, allowed: null, used: 1, pending: 0, remaining: null });
    // The CL on the sheet counts as used even though no request wrote it; the pending request counts too.
    expect(by.leave_cl).toEqual({ type: 'leave_cl', offered: true, unit: 'count', phase: 1, allowed: 1, used: 1, pending: 1, remaining: 0 });
    expect(by.leave_lwp).toEqual({ type: 'leave_lwp', offered: true, unit: 'count', phase: 1, allowed: null, used: 1, pending: 0, remaining: null });
    expect(by.wfh.offered).toBe(false);
  });

  it('takes last month by name, refuses older ones, and shows another month on its own', async () => {
    const { app, people } = buildApp();
    // The faculty member has nothing on leave in September, so last month is all zeroes.
    const token = tokens.portal(people.faculty);
    const last = await balances(app, token, '?month=2026-09');
    expect(last.status).toBe(200);
    expect(last.body.month).toBe('2026-09');
    for (const type of last.body.types) expect(type.used).toBe(0);
    expectRefusal(await balances(app, token, '?month=2026-08'), 400, 'DAY_OUT_OF_RANGE');
    expectInvalid(await balances(app, token, '?month=26-10'), MESSAGES.BALANCES_MONTH);
    // Given twice: never quietly taking one value.
    expectInvalid(await balances(app, token, '?month=2026-10&month=2026-09'), MESSAGES.BALANCES_MONTH);
  });

  it('reads the numbers HR changed, not the code\'s defaults', async () => {
    const { app, db, people } = buildApp();
    db.tables.hr_ess_request_limits.find((l) => l.type === 'leave_cl').limit_count = 3;
    const res = await balances(app, tokens.portal(people.faculty));
    expect(res.body.types.find((t) => t.type === 'leave_cl').allowed).toBe(3);
  });

  it('answers 503 MODULE_NOT_INSTALLED before the limits table exists', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    db.dropTable('hr_ess_request_limits');
    expectRefusal(await balances(app, tokens.attendance(people.attendance)), 503, 'MODULE_NOT_INSTALLED');
  });
});

module.exports = { leaveRequestRow, leaveDayRow, REQ };
