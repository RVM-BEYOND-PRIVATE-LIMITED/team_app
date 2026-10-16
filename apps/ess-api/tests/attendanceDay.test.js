const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { NOW } = require('./helpers/constants');
const { MESSAGES } = require('../src/lib/errors');
const { expectRefusal, expectInvalid, quietErrors } = require('./helpers/expect');

/** Task B1: one of my days, with the server's clock, the day's note and HR's remark. */

const DAY = '/api/ess/attendance/day';
const day = (app, token, query = '') => request(app).get(`${DAY}${query}`).set(bearer(token));

describe('GET /api/ess/attendance/day', () => {
  it('answers the caller\'s day as the Scheduler stores it, with the note and both remarks', async () => {
    const { app, people } = buildApp();
    const res = await day(app, tokens.attendance(people.attendance), '?date=2026-10-15');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      server_now: NOW.toISOString(),
      date: '2026-10-15',
      day: {
        status: 'present', leave_type: null, source: 'self_punch',
        first_in: '2026-10-15T04:20:00+00:00', last_out: '2026-10-15T12:40:00+00:00', worked_minutes: 500,
        late_minutes: 20, early_exit_minutes: 20, late_count: 1, late_half_day: false, late_excused: false,
        shift_start: '09:30:00', shift_end: '18:30:00',
      },
      note: 'Bus was late',
      hr_remark: { remarks: 'Spoke to him about the bus.', updated_at: '2026-10-15T09:00:00+00:00' },
      my_remarks: [{ day: '2026-10-15', remarks: 'The bus broke down.', updated_at: '2026-10-15T05:00:00+00:00' }],
    });
  });

  it('reads the caller\'s rows only, whoever else has a row that day', async () => {
    const { app, db, people } = buildApp();
    await day(app, tokens.attendance(people.attendance), '?date=2026-10-15');
    const reads = db.queries.filter((q) => ['hr_staff_attendance', 'hr_attendance_remarks', 'hr_attendance_employee_remarks'].includes(q.table));
    expect(reads).toHaveLength(3);
    for (const q of reads) expect(q.filters).toEqual([['employee_id', people.attendance.employee.id], ['day', '2026-10-15']]);
    // The faculty member's own day says nothing of the attendance employee's.
    const res = await day(app, tokens.portal(people.faculty), '?date=2026-10-15');
    expect(res.body.note).toBe('Faculty note, not for anybody else');
    expect(JSON.stringify(res.body)).not.toMatch(/bus/i);
  });

  it('takes no employee id: the caller is the only person it answers about', async () => {
    const { app, people } = buildApp();
    const res = await day(app, tokens.portal(people.faculty), `?date=2026-10-15&employee_id=${people.attendance.employee.id}`);
    expect(res.body.note).toBe('Faculty note, not for anybody else');
  });

  it('answers today in IST by default, with nulls for a day nothing has been written on', async () => {
    const { app, people } = buildApp();
    const res = await day(app, tokens.attendance(people.attendance));
    expect(res.body).toEqual({ server_now: NOW.toISOString(), date: '2026-10-16', day: null, note: null, hr_remark: null, my_remarks: [] });
  });

  it('turns over at midnight IST', async () => {
    const at = new Date('2026-10-16T18:30:00.000Z');
    const { app, people } = buildApp({ now: at });
    const res = await day(app, tokens.attendance(people.attendance, 'otp', new Date(at.getTime() - 60000)));
    expect(res.body.date).toBe('2026-10-17');
  });

  it('shows an override as HR left it: a CL from last month, with HR\'s note', async () => {
    const { app, people } = buildApp();
    const res = await day(app, tokens.attendance(people.attendance), '?date=2026-09-20');
    expect(res.body.day).toMatchObject({ status: 'leave', leave_type: 'cl', source: 'override', first_in: null, late_minutes: null });
    expect(res.body.note).toBe('CL approved by HR');
  });

  it.each([['2026-09-01'], ['2026-10-31']])('takes %s, at the ends of the window', async (date) => {
    const { app, people } = buildApp();
    expect((await day(app, tokens.portal(people.faculty), `?date=${date}`)).status).toBe(200);
  });

  it.each([['2026-08-31'], ['2026-11-01'], ['2025-10-16']])('refuses %s with 400 DAY_OUT_OF_RANGE', async (date) => {
    const { app, people } = buildApp();
    const res = await day(app, tokens.portal(people.faculty), `?date=${date}`);
    expectRefusal(res, 400, 'DAY_OUT_OF_RANGE');
    expect(res.body.error).toBe(MESSAGES.DAY_OUT_OF_RANGE);
  });

  it('works out last month from the 1st of January too', async () => {
    const at = new Date('2027-01-01T06:30:00.000Z');
    const { app, people } = buildApp({ now: at });
    const token = tokens.portal(people.faculty, new Date(at.getTime() - 60000));
    expect((await day(app, token, '?date=2026-12-01')).status).toBe(200);
    expectRefusal(await day(app, token, '?date=2026-11-30'), 400, 'DAY_OUT_OF_RANGE');
  });

  it.each([['2026-10-32'], ['2026-02-30'], ['16-10-2026'], [''], ['2026-10-15&date=2026-10-14']])('refuses ?date=%s with 400', async (date) => {
    const { app, people } = buildApp();
    expectInvalid(await day(app, tokens.portal(people.faculty), `?date=${date}`), MESSAGES.DATE_FORMAT);
  });

  it.each([['hr_staff_attendance'], ['hr_attendance_remarks'], ['hr_attendance_employee_remarks']])(
    'answers 503 MODULE_NOT_INSTALLED, naming %s, when that table is missing',
    async (table) => {
      quietErrors();
      const { app, db, people } = buildApp();
      db.dropTable(table);
      const res = await day(app, tokens.attendance(people.attendance), '?date=2026-10-15');
      expectRefusal(res, 503, 'MODULE_NOT_INSTALLED');
      expect(res.body.error).toContain(table);
    },
  );

  it.each([['note'], ['late_minutes'], ['source']])('answers 503 MODULE_NOT_INSTALLED when hr_staff_attendance has no %s column yet', async (column) => {
    quietErrors();
    const { app, db, people } = buildApp();
    db.dropColumn('hr_staff_attendance', column);
    expectRefusal(await day(app, tokens.attendance(people.attendance), '?date=2026-10-15'), 503, 'MODULE_NOT_INSTALLED');
  });

  it('answers 503 UNAVAILABLE during an outage, never a 401', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    const token = tokens.attendance(people.attendance);
    const realFrom = db.from;
    db.from = (table) => {
      if (table === 'hr_staff_attendance') db.outage = 'error';
      return realFrom(table);
    };
    expectRefusal(await day(app, token, '?date=2026-10-15'), 503, 'UNAVAILABLE');
  });

  it('answers 401 with no token, and refuses a leaver like every ESS endpoint', async () => {
    const { app } = buildApp();
    expectRefusal(await request(app).get(DAY), 401, 'NOT_AUTHENTICATED');
    const left = buildApp({ setup: (w) => { w.people.attendance.employee.employment_status = 'exited'; } });
    expectRefusal(await day(left.app, tokens.attendance(left.people.attendance)), 403, 'NOT_ACTIVE');
  });
});
