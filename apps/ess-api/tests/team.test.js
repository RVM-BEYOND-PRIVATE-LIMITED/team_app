const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { MESSAGES } = require('../src/lib/errors');
const { expectRefusal, expectInvalid } = require('./helpers/expect');

/** Tasks E6, H4: Team today (reports, or the HoO's branch) and Off this week. */

const TODAY = '/api/ess/team/today';
const OFF = '/api/ess/team/off-this-week';

const dayRow = (employeeId, day, change = {}) => ({
  id: `86000000-0000-4000-8000-${String(Math.abs(day.charCodeAt(9) * 7)).padStart(12, '0')}`,
  employee_id: employeeId, branch_id: null, day, status: 'present', leave_type: null, note: null,
  marked_by: null, marked_by_name: 'Test (self punch)', marked_at: `${day}T04:00:00+00:00`,
  updated_at: `${day}T12:00:00+00:00`, source: 'self_punch', first_in: `${day}T04:20:00+00:00`,
  last_out: `${day}T12:40:00+00:00`, worked_minutes: 500, shift_id: null, shift_start: null, shift_end: null,
  grace_minutes: null, late_minutes: null, early_exit_minutes: null, late_count: null, late_half_day: false,
  late_excused: false, late_excused_by_name: null, late_excused_reason: null, late_excused_at: null, ...change,
});

describe('GET /api/ess/team/today', () => {
  it('a manager sees their reports, with states, the late flag and the counts', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      w.people.admin.employee.manager_id = w.people.admin_manager.employee.id;
      w.tables.hr_staff_attendance.push(dayRow(w.people.attendance.employee.id, '2026-10-16', {
        first_in: '2026-10-16T04:20:00+00:00', last_out: null, late_minutes: 25, late_count: 2,
      }));
    } });
    const res = await request(app).get(TODAY).set(bearer(tokens.portal(people.admin_manager)));
    expect(res.status).toBe(200);
    expect(res.body.scope).toBe('reports');
    expect(res.body.date).toBe('2026-10-16');
    expect(res.body.counts).toEqual({ all: 2, not_in: 1, late: 1, on_leave: 0 });
    expect(res.body.people.map((p) => p.full_name)).toEqual(['Test Branch Admin', 'Test Office Assistant']);
    const assistant = res.body.people[1];
    expect(assistant).toMatchObject({ state: 'in', late: true, late_minutes: 25, first_in: '2026-10-16T04:20:00+00:00', last_out: null });
    expect(assistant.phone).toBe('9710000050');
    expect(JSON.stringify(res.body)).not.toMatch(/leave_type|reason/);

    const late = await request(app).get(`${TODAY}?filter=late`).set(bearer(tokens.portal(people.admin_manager)));
    expect(late.body.people.map((p) => p.full_name)).toEqual(['Test Office Assistant']);
    const notIn = await request(app).get(`${TODAY}?filter=not_in`).set(bearer(tokens.portal(people.admin_manager)));
    expect(notIn.body.people.map((p) => p.full_name)).toEqual(['Test Branch Admin']);
  });

  it('shows on leave and finished states, and filters by them', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      w.people.admin.employee.manager_id = w.people.admin_manager.employee.id;
      w.tables.hr_staff_attendance.push(
        dayRow(w.people.attendance.employee.id, '2026-10-16', { status: 'leave', source: 'override', first_in: null, last_out: null, worked_minutes: null }),
        dayRow(w.people.admin.employee.id, '2026-10-16', { last_out: '2026-10-16T13:00:00+00:00' }),
      );
    } });
    const res = await request(app).get(TODAY).set(bearer(tokens.portal(people.admin_manager)));
    const states = Object.fromEntries(res.body.people.map((p) => [p.full_name, p.state]));
    expect(states).toEqual({ 'Test Branch Admin': 'done', 'Test Office Assistant': 'on_leave' });
    expect(res.body.counts).toEqual({ all: 2, not_in: 0, late: 0, on_leave: 1 });
    const leave = await request(app).get(`${TODAY}?filter=on_leave`).set(bearer(tokens.portal(people.admin_manager)));
    expect(leave.body.people.map((p) => p.full_name)).toEqual(['Test Office Assistant']);
    expect(JSON.stringify(leave.body)).not.toMatch(/leave_type/);
  });

  it('a HoO sees the whole branch', async () => {
    const { app, people } = buildApp();
    const res = await request(app).get(TODAY).set(bearer(tokens.portal(people.hoo)));
    expect(res.status).toBe(200);
    expect(res.body.scope).toBe('branch');
    expect(res.body.counts.all).toBeGreaterThanOrEqual(10);
    expect(res.body.people.some((p) => p.full_name === 'Test CAD Faculty')).toBe(true);
    // The phone rule follows the chain, not the roster: faculty (under the HoO) is visible,
    // the super admin (a peer of the HoO, under the CEO) is not.
    expect(res.body.people.find((p) => p.full_name === 'Test CAD Faculty').phone).toBe('9710000011');
    expect(res.body.people.find((p) => p.full_name === 'Test Super Admin').phone).toBe(null);
  });

  it('is an empty view for somebody with no reports, and refuses a filter it does not know', async () => {
    const { app, people } = buildApp();
    const empty = await request(app).get(TODAY).set(bearer(tokens.portal(people.faculty)));
    expect(empty.body).toEqual({ scope: null, date: '2026-10-16', filter: 'all', counts: { all: 0, not_in: 0, late: 0, on_leave: 0 }, people: [] });
    expectInvalid(await request(app).get(`${TODAY}?filter=wfh`).set(bearer(tokens.portal(people.faculty))), MESSAGES.TEAM_FILTER);
  });

  it('answers 401 with no token and 403 for the desk login', async () => {
    const { app, people } = buildApp();
    expectRefusal(await request(app).get(TODAY), 401, 'NOT_AUTHENTICATED');
    expectRefusal(await request(app).get(TODAY).set(bearer(tokens.portal(people.desk))), 403, 'NOT_LINKED');
  });
});

describe('GET /api/ess/team/off-this-week', () => {
  it('a manager sees their reports\' leave days this week, names and days only', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      w.tables.hr_staff_attendance.push(
        dayRow(w.people.attendance.employee.id, '2026-10-15', { status: 'leave', source: 'override', first_in: null, last_out: null }),
        // Next week: outside the window.
        dayRow(w.people.admin.employee.id, '2026-10-20', { status: 'leave', source: 'override', first_in: null, last_out: null }),
      );
    } });
    const res = await request(app).get(OFF).set(bearer(tokens.portal(people.admin_manager)));
    expect(res.status).toBe(200);
    expect(res.body.week).toEqual({ from: '2026-10-12', to: '2026-10-18' });
    expect(res.body.scope).toBe('reports');
    expect(res.body.people).toEqual([
      expect.objectContaining({ full_name: 'Test Office Assistant', days: ['2026-10-15'] }),
    ]);
    expect(JSON.stringify(res.body)).not.toMatch(/leave_type|reason/);
  });

  it('works from reports when they exist, falls back to peers, and is empty without either', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      w.tables.hr_staff_attendance.push(
        dayRow(w.people.faculty.employee.id, '2026-10-15', { status: 'leave', source: 'override', first_in: null, last_out: null }),
        dayRow(w.people.hoo.employee.id, '2026-10-15', { status: 'leave', source: 'override', first_in: null, last_out: null }),
      );
    } });
    const reports = await request(app).get(OFF).set(bearer(tokens.portal(people.hod)));
    expect(reports.body.scope).toBe('reports');
    expect(reports.body.people.map((p) => p.full_name)).toEqual(['Test CAD Faculty']);
    // hr manages nobody: Home falls back to the peers under the same manager (the CEO's team).
    const peers = await request(app).get(OFF).set(bearer(tokens.portal(people.hr)));
    expect(peers.body.scope).toBe('peers');
    expect(peers.body.people.map((p) => p.full_name)).toEqual(['Test Head of Operations']);
    const none = await request(app).get(OFF).set(bearer(tokens.portal(people.faculty)));
    expect(none.body).toEqual({ week: { from: '2026-10-12', to: '2026-10-18' }, scope: null, people: [] });
  });

  it('answers 401 with no token and 403 for the desk login', async () => {
    const { app, people } = buildApp();
    expectRefusal(await request(app).get(OFF), 401, 'NOT_AUTHENTICATED');
    expectRefusal(await request(app).get(OFF).set(bearer(tokens.portal(people.desk))), 403, 'NOT_LINKED');
  });
});
