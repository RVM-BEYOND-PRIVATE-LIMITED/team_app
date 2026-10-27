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
  end_day: '2026-10-20',
  portion: 'full',
  day_count: 1,
  working_days: ['2026-10-20'],
  days_before: null,
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
        end_day: day,
        portion: 'full',
        day_count: 1,
        working_days: [day],
        requires_final_approval: false,
        stage: 'manager',
        manager_approved_by_name: null,
        manager_approved_at: null,
        manager_remark: null,
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
    expect(by.leave_cl).toEqual({ type: 'leave_cl', offered: true, unit: 'days', phase: 1, allowed: 1, used: 1, pending: 1, remaining: 0 });
    expect(by.leave_lwp).toEqual({ type: 'leave_lwp', offered: true, unit: 'days', phase: 1, allowed: null, used: 1, pending: 0, remaining: null });
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

describe('half days, single days and ranges', () => {
  it('files a half day, counts it as 0.5, and leaves the other half', async () => {
    const { app, db, people } = buildApp();
    const res = await file(app, tokens.portal(people.faculty), {
      type: 'cl', day: '2026-10-20', portion: 'first_half', reason: 'Bank work in the morning.',
    });
    expect(res.status).toBe(201);
    expect(res.body.request).toMatchObject({
      day: '2026-10-20', end_day: '2026-10-20', portion: 'first_half', day_count: 0.5,
    });
    expect(db.tables.hr_ess_leave_requests[0]).toMatchObject({ day_count: 0.5, portion: 'first_half' });

    const balances = await request(app).get(BALANCES).set(bearer(tokens.portal(people.faculty)));
    const cl = balances.body.types.find((t) => t.type === 'leave_cl');
    expect(cl).toMatchObject({ allowed: 1, used: 0, pending: 0.5, remaining: 0.5 });
  });

  it('counts a range of working days and skips Sunday', async () => {
    const { app, db, people } = buildApp();
    const res = await file(app, tokens.portal(people.faculty), {
      type: 'lwp', day: '2026-10-23', end_day: '2026-10-26', reason: 'Family function out of town.',
    });
    expect(res.status).toBe(201);
    // Friday 23, Saturday 24 and Monday 26; Sunday 25 is the weekly off.
    expect(res.body.request).toMatchObject({
      day: '2026-10-23', end_day: '2026-10-26', day_count: 3,
      working_days: ['2026-10-23', '2026-10-24', '2026-10-26'],
    });
    expect(db.tables.hr_ess_leave_requests[0].day_count).toBe(3);
  });

  it('refuses a range that overlaps a pending request', async () => {
    const { app, people } = buildApp();
    expect((await file(app, tokens.portal(people.faculty), {
      type: 'lwp', day: '2026-10-20', end_day: '2026-10-22', reason: 'Family function out of town.',
    })).status).toBe(201);
    expectRefusal(await file(app, tokens.portal(people.faculty), {
      type: 'lwp', day: '2026-10-22', end_day: '2026-10-24', reason: 'The same trip, longer.',
    }), 409, 'DUPLICATE_REQUEST');
  });

  it('writes every working day on approval and restores them on HR cancel', async () => {
    const { app, db, people } = buildApp();
    const filed = await file(app, tokens.portal(people.faculty), {
      type: 'lwp', day: '2026-10-23', end_day: '2026-10-26', reason: 'Family function out of town.',
    });
    const id = filed.body.request.id;
    const decided = await request(app).post(`/api/ess/approvals/leave/${id}/decide`)
      .set(bearer(tokens.portal(people.hr)))
      .send({ decision: 'approve', note: 'Approved; cover arranged.' });
    expect(decided.status).toBe(200);
    expect(decided.body.request).toMatchObject({ status: 'approved', decision_note: 'Approved; cover arranged.' });

    const written = () => db.tables.hr_staff_attendance
      .filter((d) => d.employee_id === people.faculty.employee.id && d.day >= '2026-10-23');
    expect(written().map((d) => d.day)).toEqual(['2026-10-23', '2026-10-24', '2026-10-26']);
    expect(written().every((d) => d.status === 'leave' && d.leave_type === 'lwp')).toBe(true);

    const cancelled = await request(app).post(`/api/ess/hr/leave-requests/${id}/cancel`)
      .set(bearer(tokens.portal(people.hr)))
      .send({ reason: 'The trip was called off.' });
    expect(cancelled.status).toBe(200);
    expect(written()).toHaveLength(0);
  });

  it('takes a faculty request through the manager and then HR final approval', async () => {
    const { app, db, people } = buildApp();
    const filed = await file(app, tokens.portal(people.faculty), {
      type: 'cl', day: '2026-10-20', reason: 'Family function at home.',
    });
    expect(filed.status).toBe(201);
    expect(filed.body.request).toMatchObject({ requires_final_approval: true, stage: 'manager' });
    const id = filed.body.request.id;

    const manager = await request(app).post(`/api/ess/approvals/leave/${id}/decide`)
      .set(bearer(tokens.portal(people.hod)))
      .send({ decision: 'approve', note: 'Approved by the HOD; please finalise.' });
    expect(manager.status).toBe(200);
    expect(manager.body.request).toMatchObject({
      status: 'pending', stage: 'final', manager_approved_by_name: 'Test CAD HOD',
      manager_remark: 'Approved by the HOD; please finalise.',
    });
    // The manager's round writes no day and does not consume the CL.
    expect(db.tables.hr_staff_attendance.filter((d) => d.employee_id === people.faculty.employee.id
      && d.day === '2026-10-20')).toHaveLength(0);

    // The manager cannot take the final round, and the refusal says why.
    const lockedOut = await request(app).post(`/api/ess/approvals/leave/${id}/decide`)
      .set(bearer(tokens.portal(people.hod)))
      .send({ decision: 'approve' });
    expectRefusal(lockedOut, 403, 'NOT_AN_APPROVER');
    expect(lockedOut.body.error).toBe(MESSAGES.FINAL_APPROVAL_ONLY);

    const final = await request(app).post(`/api/ess/approvals/leave/${id}/decide`)
      .set(bearer(tokens.portal(people.hr)))
      .send({ decision: 'approve', note: 'Final approval by HR.' });
    expect(final.status).toBe(200);
    expect(final.body.request).toMatchObject({ status: 'approved', decision_note: 'Final approval by HR.' });
    expect(db.tables.hr_staff_attendance.find((d) => d.employee_id === people.faculty.employee.id
      && d.day === '2026-10-20')).toMatchObject({ status: 'leave', leave_type: 'cl' });
  });

  it('lets two half days use the one-day CL allowance and refuses a third', async () => {
    const { app, people } = buildApp();
    expect((await file(app, tokens.portal(people.faculty), {
      type: 'cl', day: '2026-10-20', portion: 'first_half', reason: 'Bank work in the morning.',
    })).status).toBe(201);
    expect((await file(app, tokens.portal(people.faculty), {
      type: 'cl', day: '2026-10-21', portion: 'second_half', reason: 'Bank work in the afternoon.',
    })).status).toBe(201);
    expectRefusal(await file(app, tokens.portal(people.faculty), {
      type: 'cl', day: '2026-10-22', portion: 'first_half', reason: 'One more morning.',
    }), 409, 'LIMIT_REACHED');
  });
});

module.exports = { leaveRequestRow, leaveDayRow, REQ };
