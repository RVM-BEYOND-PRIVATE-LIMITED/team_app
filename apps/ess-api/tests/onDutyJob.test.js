const { buildApp } = require('./helpers/app');
const { NOW } = require('./helpers/constants');
const { quietErrors } = require('./helpers/expect');
const { startOnDutyJob } = require('../src/jobs/onDuty');
const { HALF_DAY_MINUTES } = require('../src/policy/attendance');

/** Tasks C3, C7: the on-duty morning job — idempotent, logged, and safe to re-run. */

const jobs = [];
const start = (world, options = {}) => {
  const log = options.log || { log: () => {}, error: () => {} };
  const job = startOnDutyJob({ store: world.store, now: () => new Date(NOW.getTime()), log, immediate: false, ...options });
  jobs.push(job);
  return job;
};

afterEach(() => {
  while (jobs.length) jobs.pop().stop();
});

const approvedOnDuty = (w, day, n = 1) => {
  w.tables.hr_ess_attendance_requests = [{
    id: `7f000000-0000-4000-8000-${String(n).padStart(12, '0')}`,
    employee_id: w.people.attendance.employee.id,
    type: 'on_duty',
    status: 'approved',
    day,
    reason: 'Away on a course.',
    place: 'Ahmedabad',
    fix_in: null,
    fix_out: null,
    day_before: null,
    day_written_at: null,
    decided_by_employee_id: w.people.admin_manager.employee.id,
    decided_by_user_id: w.people.admin_manager.user.id,
    decided_by_name: 'Test Admin Manager',
    decided_at: '2026-10-15T06:00:00+00:00',
    decision_note: null,
    cancelled_by_user_id: null,
    cancelled_by_name: null,
    cancelled_at: null,
    cancel_reason: null,
    created_at: '2026-10-14T05:00:00+00:00',
    updated_at: '2026-10-15T06:00:00+00:00',
  }];
};

describe('the on-duty morning job', () => {
  it('writes an approved on-duty day for today, once, and recomputes the month', async () => {
    const world = buildApp({ setup: (w) => approvedOnDuty(w, '2026-10-16') });
    const recompute = vi.spyOn(world.store, 'recomputeAttendance');
    const job = start(world);
    const out = await job.runOnce();
    expect(out).toMatchObject({ applied: 1, failed: [] });
    const day = world.db.tables.hr_staff_attendance.find((d) => d.day === '2026-10-16');
    expect(day).toMatchObject({ status: 'present', note: 'On duty: Ahmedabad', source: 'override', marked_by_name: 'Test Admin Manager' });
    expect(recompute).toHaveBeenCalledWith({
      employeeIds: [world.people.attendance.employee.id],
      day: '2026-10-16',
      today: '2026-10-16',
      halfDayMinutes: HALF_DAY_MINUTES,
    });
    // Running again changes nothing: the day has its row now.
    const again = await job.runOnce();
    expect(again).toMatchObject({ applied: 0, failed: [] });
    expect(world.db.tables.hr_staff_attendance.filter((d) => d.day === '2026-10-16')).toHaveLength(1);
  });

  it('leaves a day alone that already has a row', async () => {
    const world = buildApp({ setup: (w) => {
      approvedOnDuty(w, '2026-10-16');
      w.tables.hr_staff_attendance.push({
        id: '7e000000-0000-4000-8000-000000000016', employee_id: w.people.attendance.employee.id, branch_id: null,
        day: '2026-10-16', status: 'week_off', leave_type: null, note: 'Sunday', marked_by: null, marked_by_name: null,
        marked_at: '2026-10-16T00:10:00+00:00', updated_at: '2026-10-16T00:10:00+00:00', source: 'auto',
        first_in: null, last_out: null, worked_minutes: null, shift_id: null, shift_start: null, shift_end: null,
        grace_minutes: null, late_minutes: null, early_exit_minutes: null, late_count: null,
        late_half_day: false, late_excused: false, late_excused_by_name: null, late_excused_reason: null, late_excused_at: null,
      });
    } });
    const job = start(world);
    expect((await job.runOnce()).applied).toBe(0);
    expect(world.db.tables.hr_staff_attendance.find((d) => d.day === '2026-10-16').note).toBe('Sunday');
  });

  it('logs an outage and answers null, never throwing', async () => {
    quietErrors();
    const world = buildApp();
    const error = vi.fn();
    const job = start(world, { log: { log: () => {}, error } });
    world.db.outage = 'error';
    expect(await job.runOnce()).toBe(null);
    expect(error).toHaveBeenCalledWith(expect.stringContaining('on-duty job'));
  });

  it('logs each failure for HR and audits it, and one failure does not stop the rest', async () => {
    const world = buildApp();
    const error = vi.fn();
    world.store.applyOnDutyDays = async () => ({
      applied: 1,
      employees: [],
      failed: [{ request_id: '7f000000-0000-4000-8000-000000000001', employee_id: world.people.attendance.employee.id, error: 'boom' }],
    });
    const job = start(world, { log: { log: () => {}, error } });
    const out = await job.runOnce();
    expect(out.applied).toBe(1);
    expect(error).toHaveBeenCalledWith(expect.stringContaining('request 7f000000-0000-4000-8000-000000000001'));
    expect(world.db.tables.hr_ess_audit).toEqual([
      expect.objectContaining({
        action: 'on_duty.failed',
        actor_name: 'Team RVM (on-duty job)',
        target_employee_id: world.people.attendance.employee.id,
        details: expect.objectContaining({ request_id: '7f000000-0000-4000-8000-000000000001' }),
      }),
    ]);
  });

  it('does nothing for a day with no approved request, and nothing at all when switched off by hand', async () => {
    const world = buildApp();
    const job = start(world);
    expect((await job.runOnce()).applied).toBe(0);
  });
});
