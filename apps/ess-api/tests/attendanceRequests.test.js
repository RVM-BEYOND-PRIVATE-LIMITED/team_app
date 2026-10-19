const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { NOW } = require('./helpers/constants');
const { MESSAGES } = require('../src/lib/errors');
const { expectRefusal, expectInvalid, quietErrors } = require('./helpers/expect');

/** Tasks C1 and C3: attendance requests — on duty, fix a day, excuse a late. */

const MINE = '/api/ess/attendance-requests';
const REQ = (n) => `7a000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

const file = (app, token, body) => request(app).post(MINE).set(bearer(token)).send(body);
const list = (app, token) => request(app).get(MINE).set(bearer(token));
const withdraw = (app, token, id) => request(app).post(`${MINE}/${id}/withdraw`).set(bearer(token));

/** A request as the tables hold it, for the worlds a test starts from. */
const attendanceRequestRow = (employeeId, n, change = {}) => ({
  id: REQ(n),
  employee_id: employeeId,
  type: 'on_duty',
  status: 'pending',
  day: '2026-10-15',
  reason: 'Client visit at the Pune centre.',
  place: 'Pune centre',
  fix_in: null,
  fix_out: null,
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

const THE_THREE = [
  ['on_duty', { type: 'on_duty', day: '2026-10-15', reason: 'Client visit at the Pune centre.', place: 'Pune centre' }],
  ['fix_a_day', { type: 'fix_a_day', day: '2026-10-15', reason: 'I forgot to punch out.', fix_out: '18:00' }],
  ['excuse_late', { type: 'excuse_late', day: '2026-10-15', reason: 'The bus broke down near the depot.' }],
];

describe('POST /api/ess/attendance-requests', () => {
  it.each(THE_THREE)('files a %s request for either sign-in, about the caller only', async (type, body) => {
    const { app, db, people } = buildApp();
    const res = await file(app, tokens.attendance(people.attendance), body);
    expect(res.status).toBe(201);
    expect(res.body).toEqual({
      request: {
        id: expect.any(String),
        family: 'attendance',
        type,
        status: 'pending',
        day: '2026-10-15',
        reason: body.reason.trim(),
        created_at: NOW.toISOString(),
        place: body.place ?? null,
        fix_in: null,
        fix_out: body.fix_out ?? null,
        decided_at: null,
        decided_by_name: null,
        decision_note: null,
        cancelled_at: null,
        cancelled_by_name: null,
        cancel_reason: null,
      },
    });
    const stored = db.tables.hr_ess_attendance_requests;
    expect(stored).toHaveLength(1);
    expect(stored[0].employee_id).toBe(people.attendance.employee.id);
    expect(stored[0].status).toBe('pending');
    // The 'filed' history row, written by the database with the employee as the actor.
    const history = db.tables.hr_ess_attendance_request_history;
    expect(history).toHaveLength(1);
    expect(history[0]).toMatchObject({
      request_id: stored[0].id,
      action: 'filed',
      actor_employee_id: people.attendance.employee.id,
      actor_name: 'Test Office Assistant',
    });
  });

  it('files for a portal login too, with the same day window', async () => {
    const { app, people } = buildApp();
    const res = await file(app, tokens.portal(people.faculty), THE_THREE[2][1]);
    expect(res.status).toBe(201);
  });

  it('takes no employee id, so nobody files in somebody else\'s name', async () => {
    const { app, people } = buildApp();
    const res = await file(app, tokens.portal(people.faculty), { ...THE_THREE[0][1], employee_id: people.hr.employee.id });
    expectInvalid(res, MESSAGES.UNKNOWN_FIELD);
  });

  it.each([
    ['no type', { day: '2026-10-15', reason: 'Client visit, please.' }, MESSAGES.ATTENDANCE_REQUEST_TYPE],
    ['work from home', { type: 'wfh', day: '2026-10-15', reason: 'Working from home today.' }, MESSAGES.ATTENDANCE_REQUEST_TYPE],
    ['short leave', { type: 'short_leave', day: '2026-10-15', reason: 'Two hours in the morning.' }, MESSAGES.ATTENDANCE_REQUEST_TYPE],
    ['no day', { type: 'on_duty', reason: 'Client visit, please.', place: 'Site' }, MESSAGES.DATE_FORMAT],
    ['a day that is not a date', { type: 'on_duty', day: '2026-02-30', reason: 'Client visit, please.', place: 'Site' }, MESSAGES.DATE_FORMAT],
    ['a short reason', { type: 'on_duty', day: '2026-10-15', reason: 'trip', place: 'Site' }, MESSAGES.REQUEST_REASON],
    ['no place on an on-duty request', { type: 'on_duty', day: '2026-10-15', reason: 'Client visit, please.' }, MESSAGES.REQUEST_PLACE],
    ['a place over 120 characters', { type: 'on_duty', day: '2026-10-15', reason: 'Client visit, please.', place: 'x'.repeat(121) }, MESSAGES.REQUEST_PLACE],
    ['a place on a fix request', { type: 'fix_a_day', day: '2026-10-15', reason: 'I forgot to punch out.', place: 'Site', fix_out: '18:00' }, MESSAGES.UNKNOWN_FIELD],
    ['times on an excuse', { type: 'excuse_late', day: '2026-10-15', reason: 'The bus broke down.', fix_in: '09:00' }, MESSAGES.UNKNOWN_FIELD],
    ['no times on a fix', { type: 'fix_a_day', day: '2026-10-15', reason: 'I forgot to punch out.' }, MESSAGES.REQUEST_TIMES_NEEDED],
    ['a time that is not HH:MM', { type: 'fix_a_day', day: '2026-10-15', reason: 'I forgot to punch out.', fix_in: '9:00' }, MESSAGES.REQUEST_TIMES],
    ['an hour that is not a clock hour', { type: 'fix_a_day', day: '2026-10-15', reason: 'I forgot to punch out.', fix_in: '24:00' }, MESSAGES.REQUEST_TIMES],
    ['an unknown field', { ...THE_THREE[0][1], note: 'extra' }, MESSAGES.UNKNOWN_FIELD],
    ['a list for a body', [THE_THREE[0][1]], MESSAGES.BODY_NOT_OBJECT],
  ])('refuses %s with 400', async (_label, body, message) => {
    const { app, people } = buildApp();
    expectInvalid(await file(app, tokens.attendance(people.attendance), body), message);
  });

  it('closes last month after the 5th, but not on the 5th itself (the default for decision 6)', async () => {
    const closed = buildApp({ now: new Date('2026-10-06T06:30:00.000Z') });
    expectRefusal(
      await file(closed.app, tokens.portal(closed.people.faculty), { type: 'on_duty', day: '2026-09-30', reason: 'Client visit, please.', place: 'Site' }),
      409, 'REQUEST_CLOSED',
    );
    const open = buildApp({ now: new Date('2026-10-05T06:30:00.000Z') });
    const res = await file(open.app, tokens.portal(open.people.faculty), { type: 'on_duty', day: '2026-09-30', reason: 'Client visit, please.', place: 'Site' });
    expect(res.status).toBe(201);
  });

  it('refuses a day before last month', async () => {
    const { app, people } = buildApp();
    const res = await file(app, tokens.attendance(people.attendance), { type: 'on_duty', day: '2026-08-31', reason: 'Client visit, please.', place: 'Site' });
    expectInvalid(res, MESSAGES.REQUEST_WINDOW);
  });

  it('refuses a fix or an excuse for a day that has not happened, and lets on duty be filed ahead', async () => {
    const { app, people } = buildApp();
    const token = tokens.attendance(people.attendance);
    expectInvalid(await file(app, token, { type: 'fix_a_day', day: '2026-10-17', reason: 'While I remember.', fix_out: '18:00' }), MESSAGES.REQUEST_FUTURE);
    expectInvalid(await file(app, token, { type: 'excuse_late', day: '2026-10-17', reason: 'Traffic, most likely.' }), MESSAGES.REQUEST_FUTURE);
    expect((await file(app, token, { type: 'on_duty', day: '2026-11-02', reason: 'College drive, planned.', place: 'Pune' })).status).toBe(201);
  });

  it('refuses a duplicate while the same type and day waits', async () => {
    const { app, people } = buildApp();
    const token = tokens.attendance(people.attendance);
    await file(app, token, THE_THREE[0][1]);
    expectRefusal(await file(app, token, THE_THREE[0][1]), 409, 'DUPLICATE_REQUEST');
  });

  it('counts the month\'s used and pending against the limit HR set, not the code\'s default', async () => {
    const { app, db, people } = buildApp();
    const token = tokens.attendance(people.attendance);
    // HR tightens fix a day to one a month (task C6): the request endpoint must read the table.
    db.tables.hr_ess_request_limits.find((l) => l.type === 'fix_a_day').limit_count = 1;
    const first = await file(app, token, { type: 'fix_a_day', day: '2026-10-15', reason: 'I forgot to punch out.', fix_out: '18:00' });
    expect(first.status).toBe(201);
    expectRefusal(
      await file(app, token, { type: 'fix_a_day', day: '2026-10-16', reason: 'I forgot to punch in.', fix_in: '09:00' }),
      409, 'LIMIT_REACHED',
    );
  });

  it('counts a request of another month against that month only', async () => {
    const { app, db, people } = buildApp();
    db.tables.hr_ess_request_limits.find((l) => l.type === 'fix_a_day').limit_count = 1;
    db.tables.hr_ess_attendance_requests = [attendanceRequestRow(people.attendance.employee.id, 1, {
      type: 'fix_a_day', status: 'approved', day: '2026-09-20', place: null, fix_out: '18:00',
      decided_by_name: 'Test Admin Manager', decided_at: '2026-09-20T06:00:00+00:00',
    })];
    const res = await file(app, tokens.attendance(people.attendance), { type: 'fix_a_day', day: '2026-10-15', reason: 'I forgot to punch out.', fix_out: '18:00' });
    expect(res.status).toBe(201);
  });

  it('answers 401 with no token and 503 UNAVAILABLE during an outage, never a 401', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    expectRefusal(await request(app).post(MINE).send(THE_THREE[0][1]), 401, 'NOT_AUTHENTICATED');
    db.outage = 'error';
    expectRefusal(await file(app, tokens.attendance(people.attendance), THE_THREE[0][1]), 503, 'UNAVAILABLE');
  });

  it('answers 503 MODULE_NOT_INSTALLED, naming the table, before its migration', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    db.dropTable('hr_ess_attendance_requests');
    const res = await file(app, tokens.attendance(people.attendance), THE_THREE[0][1]);
    expectRefusal(res, 503, 'MODULE_NOT_INSTALLED');
    expect(res.body.error).toMatch(/hr_ess_attendance_requests/);
  });

  it('refuses a session still on HR\'s first-time password, as every ESS endpoint does', async () => {
    const { app, people } = buildApp({ setup: (w) => { w.people.attendance.account.password_set_at = null; } });
    expectRefusal(await file(app, tokens.attendance(people.attendance, 'pw'), THE_THREE[0][1]), 403, 'PASSWORD_CHANGE_REQUIRED');
  });
});

describe('GET /api/ess/attendance-requests', () => {
  it('lists the caller\'s own, newest first, without the day_before or the decider\'s ids', async () => {
    const { app, db, people } = buildApp();
    const mine = people.attendance.employee.id;
    db.tables.hr_ess_attendance_requests = [
      attendanceRequestRow(mine, 1, { created_at: '2026-10-13T05:00:00+00:00' }),
      attendanceRequestRow(mine, 2, { type: 'excuse_late', place: null, status: 'rejected', decided_by_name: 'Test Admin Manager',
        decided_at: '2026-10-15T05:00:00+00:00', decision_note: 'Not a good reason.', created_at: '2026-10-14T05:00:00+00:00' }),
      attendanceRequestRow(people.faculty.employee.id, 3),
    ];
    const res = await list(app, tokens.attendance(people.attendance));
    expect(res.status).toBe(200);
    expect(res.body.requests.map((r) => r.id)).toEqual([REQ(2), REQ(1)]);
    expect(res.body.requests[0]).toEqual({
      id: REQ(2), family: 'attendance', type: 'excuse_late', status: 'rejected', day: '2026-10-15',
      reason: 'Client visit at the Pune centre.', created_at: '2026-10-14T05:00:00+00:00',
      place: null, fix_in: null, fix_out: null,
      decided_at: '2026-10-15T05:00:00+00:00', decided_by_name: 'Test Admin Manager', decision_note: 'Not a good reason.',
      cancelled_at: null, cancelled_by_name: null, cancel_reason: null,
    });
    expect(JSON.stringify(res.body)).not.toMatch(/day_before|decided_by_user/);
  });

  it('is an empty list for somebody with none', async () => {
    const { app, people } = buildApp();
    expect((await list(app, tokens.portal(people.faculty))).body).toEqual({ requests: [] });
  });
});

describe('POST /api/ess/attendance-requests/{id}/withdraw', () => {
  it('withdraws a pending request, and only once', async () => {
    const { app, db, people } = buildApp();
    const token = tokens.attendance(people.attendance);
    await file(app, token, THE_THREE[0][1]);
    const id = db.tables.hr_ess_attendance_requests[0].id;
    const res = await withdraw(app, token, id);
    expect(res.status).toBe(200);
    expect(res.body.request.status).toBe('withdrawn');
    expect(db.tables.hr_ess_attendance_request_history.map((h) => h.action)).toEqual(['filed', 'withdrawn']);
    expectRefusal(await withdraw(app, token, id), 409, 'REQUEST_NOT_PENDING');
  });

  it('answers 404 for somebody else\'s request, and leaves it alone', async () => {
    const { app, db, people } = buildApp();
    db.tables.hr_ess_attendance_requests = [attendanceRequestRow(people.faculty.employee.id, 1)];
    const res = await withdraw(app, tokens.attendance(people.attendance), REQ(1));
    expectRefusal(res, 404, 'NOT_FOUND');
    expect(db.tables.hr_ess_attendance_requests[0].status).toBe('pending');
  });

  it('refuses an id that is not one, and 503 before the table exists', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    expectInvalid(await withdraw(app, tokens.attendance(people.attendance), '42'), MESSAGES.INVALID_ID);
    db.dropTable('hr_ess_attendance_requests');
    const res = await withdraw(app, tokens.attendance(people.attendance), REQ(1));
    expectRefusal(res, 503, 'MODULE_NOT_INSTALLED');
  });
});

module.exports = { attendanceRequestRow, REQ, file };
