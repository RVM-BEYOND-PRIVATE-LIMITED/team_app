const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { MESSAGES } = require('../src/lib/errors');

/** Task H5: the leaders' overview — the whole organisation in counts only. */

const OVERVIEW = '/api/ess/leaders/overview';

const dayRow = (employeeId, day, change = {}) => ({
  id: `86000000-0000-4000-8000-${String(Math.abs(day.charCodeAt(9) * 7)).padStart(12, '0')}`,
  employee_id: employeeId, branch_id: null, day, status: 'present', leave_type: null, note: null,
  marked_by: null, marked_by_name: 'Test (self punch)', marked_at: `${day}T04:00:00+00:00`,
  updated_at: `${day}T12:00:00+00:00`, source: 'self_punch', first_in: `${day}T04:20:00+00:00`,
  last_out: `${day}T12:40:00+00:00`, worked_minutes: 500, shift_id: null, shift_start: null, shift_end: null,
  grace_minutes: null, late_minutes: null, early_exit_minutes: null, late_count: null, late_half_day: false,
  late_excused: false, late_excused_by_name: null, late_excused_reason: null, late_excused_at: null, ...change,
});

const leave = (employeeId, day) => dayRow(employeeId, day, {
  status: 'leave', source: 'override', first_in: null, last_out: null, worked_minutes: null,
});

const requestRow = (family, employeeId, id, change = {}) => ({
  id,
  employee_id: employeeId,
  type: family === 'leave' ? 'cl' : 'on_duty',
  status: 'pending',
  day: '2026-10-15',
  reason: 'Client visit at the Pune centre.',
  place: family === 'attendance' ? 'Pune centre' : null,
  fix_in: null,
  fix_out: null,
  minutes: null,
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
  created_at: '2026-10-13T05:00:00+00:00',
  updated_at: '2026-10-13T05:00:00+00:00',
  ...change,
});

describe('GET /api/ess/leaders/overview', () => {
  const seeded = (w) => {
    w.tables.hr_staff_attendance.push(
      dayRow(w.people.faculty.employee.id, '2026-10-16', { last_out: null }),
      dayRow(w.people.hod.employee.id, '2026-10-16'),
      leave(w.people.hr.employee.id, '2026-10-16'),
      dayRow(w.people.admin.employee.id, '2026-10-16', { status: 'week_off' }),
      dayRow(w.people.hoo.employee.id, '2026-10-16', { status: 'holiday' }),
      leave(w.people.accounts_admin.employee.id, '2026-10-14'),
      leave(w.people.admin_manager.employee.id, '2026-10-15'),
    );
    w.tables.hr_ess_attendance_requests = [requestRow('attendance', w.people.attendance.employee.id, '7c000000-0000-4000-8000-000000000001')];
    w.tables.hr_ess_leave_requests = [
      requestRow('leave', w.people.faculty.employee.id, '7c000000-0001-4000-8000-000000000002'),
      requestRow('leave', w.people.admin.employee.id, '7c000000-0001-4000-8000-000000000003'),
    ];
  };

  it('the CEO sees today, the week and the queue in counts only', async () => {
    const { app, people } = buildApp({ setup: seeded });
    const res = await request(app).get(OVERVIEW).set(bearer(tokens.portal(people.ceo)));
    expect(res.status).toBe(200);
    expect(res.body.attendance_today).toEqual({
      in: 1, done: 1, not_in: res.body.headcount - 5, on_leave: 1, week_off: 1, holiday: 1,
    });
    expect(res.body.headcount).toBeGreaterThan(5);
    expect(res.body.off_this_week).toBe(3);
    expect(res.body.pending).toEqual({ attendance: 1, leave: 2, total: 3, oldest_days: 2 });
    const text = JSON.stringify(res.body);
    expect(text).not.toMatch(/full_name|employee_code|reason|late_minutes|salary|performance/);
  });

  it('a super admin sees the same numbers', async () => {
    const { app, people } = buildApp({ setup: seeded });
    const res = await request(app).get(OVERVIEW).set(bearer(tokens.portal(people.super_admin)));
    expect(res.status).toBe(200);
    expect(res.body.pending.total).toBe(3);
  });

  it('every other role is refused, and an attendance session is refused as portal-only', async () => {
    const { app, people } = buildApp({ setup: seeded });
    for (const who of ['hr', 'faculty', 'admin_manager']) {
      const res = await request(app).get(OVERVIEW).set(bearer(tokens.portal(people[who])));
      expect(res.status).toBe(403);
      expect(res.body.code).toBe('HR_ACCESS_DENIED');
      expect(res.body.error).toBe(MESSAGES.HR_ACCESS_DENIED);
    }
    const punch = await request(app).get(OVERVIEW).set(bearer(tokens.attendance(people.attendance)));
    expect(punch.status).toBe(403);
    expect(punch.body.code).toBe('PORTAL_LOGIN_REQUIRED');
  });

  it('refuses a caller with no token', async () => {
    const { app } = buildApp();
    const res = await request(app).get(OVERVIEW);
    expect(res.status).toBe(401);
    expect(res.body.code).toBe('NOT_AUTHENTICATED');
  });

  it('answers 503 when the sheet cannot be read', async () => {
    const world = buildApp();
    world.db.failWhen = (q) => (q.table === 'hr_staff_attendance' ? 'error' : null);
    const res = await request(world.app).get(OVERVIEW).set(bearer(tokens.portal(world.people.ceo)));
    expect(res.status).toBe(503);
    expect(res.body.code).toBe('UNAVAILABLE');
  });
});
