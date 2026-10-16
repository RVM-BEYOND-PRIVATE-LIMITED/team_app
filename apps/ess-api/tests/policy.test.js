const { isActive } = require('../src/policy/employment');
const { istDay } = require('../src/lib/time');
const { sessionProblem } = require('../src/middleware/employeeAuth');
const limits = require('../src/policy/requestLimits');
const { capabilitiesFor } = require('../src/policy/capabilities');
const Scheduler = require('./helpers/schedulerRules');

/**
 * The pure rules, each held against the Scheduler's verbatim copy where one exists
 * (tests/helpers/schedulerRules.js), so the ESS decides every case the way the Scheduler does.
 */

describe('istDay', () => {
  it('turns over at midnight IST, not midnight UTC', () => {
    expect(istDay(new Date('2026-10-16T18:29:59.999Z'))).toBe('2026-10-16');
    expect(istDay(new Date('2026-10-16T18:30:00.000Z'))).toBe('2026-10-17');
    expect(istDay(new Date('2026-12-31T18:30:00.000Z'))).toBe('2027-01-01');
  });

  it('agrees with the Scheduler\'s at every hour of a year', () => {
    const start = Date.parse('2026-01-01T00:00:00.000Z');
    for (let h = 0; h < 366 * 24; h++) {
      const t = new Date(start + h * 3600 * 1000 + 29 * 60 * 1000);
      expect(istDay(t)).toBe(Scheduler.istDay(t));
    }
  });
});

describe('isActive', () => {
  const today = '2026-10-16';
  const base = { is_archived: false, employment_status: 'active', date_of_exit: null };

  it.each([
    ['active', {}, true],
    ['serving notice', { employment_status: 'notice_period', date_of_exit: '2026-11-15' }, true],
    ['on the last working day', { employment_status: 'notice_period', date_of_exit: '2026-10-16' }, true],
    ['the day after the last working day', { employment_status: 'notice_period', date_of_exit: '2026-10-15' }, false],
    ['exited', { employment_status: 'exited' }, false],
    ['archived', { is_archived: true }, false],
    ['fired, which is archived at once', { employment_status: 'fired', is_archived: true }, false],
  ])('%s -> %s', (_label, change, expected) => {
    expect(isActive({ ...base, ...change }, today)).toBe(expected);
  });

  it('agrees with the Scheduler\'s on the real clock', () => {
    const now = new Date();
    const day = (offset) => istDay(new Date(now.getTime() + offset * 86400 * 1000));
    const cases = [
      base,
      { ...base, is_archived: true },
      { ...base, employment_status: 'exited' },
      { ...base, employment_status: 'resigned' },
      { ...base, employment_status: 'notice_period', date_of_exit: day(-1) },
      { ...base, employment_status: 'notice_period', date_of_exit: day(0) },
      { ...base, employment_status: 'notice_period', date_of_exit: day(1) },
      { ...base, date_of_exit: day(-400) },
    ];
    for (const emp of cases) expect(isActive(emp, istDay(now))).toBe(Scheduler.isActive(emp));
  });
});

describe('sessionProblem', () => {
  const issuedAt = Date.parse('2026-10-16T05:00:00.000Z');
  const accounts = [
    null,
    { status: 'disabled', sessions_valid_from: '2026-10-01T00:00:00+00:00' },
    { status: 'active', sessions_valid_from: null },
    { status: 'active', sessions_valid_from: '2026-10-16T04:59:59.999+00:00' },
    { status: 'active', sessions_valid_from: '2026-10-16T05:00:00.000+00:00' },
    { status: 'active', sessions_valid_from: '2026-10-16T05:00:00.999999+00:00' },
    { status: 'active', sessions_valid_from: '2026-10-16T05:00:01.000+00:00' },
    { status: 'active', sessions_valid_from: '2026-10-16T10:30:01+05:30' },
    { status: 'active', sessions_valid_from: '2026-10-17T00:00:00+00:00' },
  ];

  it('decides every case as the Scheduler\'s does', () => {
    for (const account of accounts) {
      const ours = sessionProblem({ issuedAt }, account);
      const theirs = Scheduler.sessionProblem({ issuedAt }, account);
      expect(ours ? { status: ours.status, code: ours.code, message: ours.message } : null, JSON.stringify(account)).toEqual(theirs);
    }
  });

  it('refuses a cut-off it cannot read without signing anybody out, where the Scheduler would let every old session in', () => {
    const problem = sessionProblem({ issuedAt }, { status: 'active', sessions_valid_from: 'not a time' });
    expect(problem).toMatchObject({ status: 503, code: 'UNAVAILABLE' });
  });
});

describe('the request limits', () => {
  it('are KP\'s decisions of 16 Oct', () => {
    const byType = Object.fromEntries(limits.REQUEST_TYPES.map((t) => [t.type, t]));
    expect(byType.wfh).toMatchObject({ offered: false, limit: 0 });
    expect(byType.on_duty).toMatchObject({ offered: true, limit: null });
    expect(byType.fix_a_day.limit).toBe(3);
    expect(byType.excuse_late.limit).toBe(3);
    expect(byType.short_leave).toMatchObject({ limit: 180, unit: 'minutes', phase: 2 });
    expect(byType.leave_cl.limit).toBe(1);
    expect(byType.leave_lwp.limit).toBeNull();
    expect(limits.PAYROLL_CUTOFF_DAY).toBe(5);
    expect(limits.REACH_BACK_MONTHS).toBe(1);
  });

  it('offer every type but work from home', () => {
    expect(limits.offeredRequestTypes()).toEqual(['on_duty', 'fix_a_day', 'excuse_late', 'short_leave', 'leave_cl', 'leave_lwp']);
  });

  it('look a type up by name', () => {
    expect(limits.requestType('fix_a_day')).toMatchObject({ limit: 3 });
    expect(limits.requestType('overtime')).toBeNull();
  });

  it('cannot be changed by whoever reads them', () => {
    expect(Object.isFrozen(limits.REQUEST_TYPES)).toBe(true);
    expect(limits.REQUEST_TYPES.every((t) => Object.isFrozen(t))).toBe(true);
    const copy = limits.requestPolicy();
    copy.types[1].limit = 99;
    expect(limits.requestType('fix_a_day').limit).toBe(3);
  });
});

describe('capabilitiesFor', () => {
  it('gives a role it has never heard of the ordinary staff menu and nothing more', () => {
    const caps = capabilitiesFor({ kind: 'portal', role: 'some_future_role', directReports: 0, pushEnabled: false });
    expect(caps.sections.work).toBe(false);
    expect(caps.approvals).toEqual({ own_reports: false, any_request: false, request_types: [], hr_scope: [] });
    expect(caps.wall).toEqual({ post: true, announce: false, moderate: false });
    expect(caps.tabs).toHaveLength(5);
  });

  it('ignores the role for an attendance session', () => {
    const caps = capabilitiesFor({ kind: 'attendance', role: 'ceo', directReports: 0, pushEnabled: false });
    expect(caps.sections.work).toBe(false);
    expect(caps.approvals.any_request).toBe(false);
  });

  it('hands out fresh arrays, so one reply cannot change the next', () => {
    const a = capabilitiesFor({ kind: 'portal', role: 'hr', directReports: 0, pushEnabled: false });
    a.tabs.push('x');
    a.approvals.hr_scope.push('x');
    const b = capabilitiesFor({ kind: 'portal', role: 'hr', directReports: 0, pushEnabled: false });
    expect(b.tabs).toHaveLength(5);
    expect(b.approvals.hr_scope).toEqual(['attendance', 'documents', 'profile_changes', 'helpdesk_hr']);
  });
});
