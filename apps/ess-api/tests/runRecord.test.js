const { buildApp } = require('./helpers/app');
const { periodKeyWeekly, periodKeyDaily, claimRun, finishRun } = require('../src/jobs/runRecord');
const { quietErrors } = require('./helpers/expect');

/** F-51 (team_app #49): the record that stops a restarted job repeating its period. */

describe('the run record: the period, in IST', () => {
  it('keeps a week that straddles a year end in the year its Thursday falls in', () => {
    // 31 Dec 2026 is a Thursday, so that week is 2026's 53rd; 1 Jan 2027 is the Friday after.
    expect(periodKeyWeekly(new Date('2026-12-31T12:00:00.000Z'))).toBe('2026-W53');
    expect(periodKeyWeekly(new Date('2027-01-01T12:00:00.000Z'))).toBe('2026-W53');
  });

  it('starts the week on Monday in IST, where 23:00 UTC on Sunday is already Monday', () => {
    expect(periodKeyWeekly(new Date('2026-10-18T23:00:00.000Z'))).toBe('2026-W43');
    // Half an hour earlier, still Sunday in IST, is the week that is ending.
    expect(periodKeyWeekly(new Date('2026-10-18T18:00:00.000Z'))).toBe('2026-W42');
  });

  it('names the IST day, which has already turned over at 19:00 UTC', () => {
    expect(periodKeyDaily(new Date('2026-10-16T19:00:00.000Z'))).toBe('2026-10-17');
  });
});

describe('the run record: the claim', () => {
  it('claims a period once, and finishes the row as done', async () => {
    const world = buildApp();
    expect(await claimRun(world.store, 'test_weekly', '2026-W42')).toBe(true);
    expect(await claimRun(world.store, 'test_weekly', '2026-W42')).toBe(false);
    expect(world.db.tables.hr_ess_job_runs).toHaveLength(1);
    expect(world.db.tables.hr_ess_job_runs[0]).toMatchObject({
      job: 'test_weekly', period_key: '2026-W42', status: 'running',
    });
    await finishRun(world.store, 'test_weekly', '2026-W42', 'done');
    expect(world.db.tables.hr_ess_job_runs[0]).toMatchObject({ status: 'done' });
    expect(world.db.tables.hr_ess_job_runs[0].finished_at).toBeTruthy();
  });

  it('runs as before without the table, and warns once for the whole process', async () => {
    quietErrors();
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const world = buildApp();
    // The deploy went out before KP applied db/migrations/20261211000000.
    world.db.dropTable('hr_ess_job_runs');
    expect(await claimRun(world.store, 'test_weekly', '2026-W42')).toBe(true);
    expect(await claimRun(world.store, 'test_weekly', '2026-W42')).toBe(true);
    expect(warn).toHaveBeenCalledTimes(1);
    expect(warn.mock.calls[0][0]).toContain('20261211000000_hr_ess_job_runs.sql');
  });

  it('finishes quietly when the record cannot be written', async () => {
    quietErrors();
    const world = buildApp();
    world.db.dropTable('hr_ess_job_runs');
    await expect(finishRun(world.store, 'test_weekly', '2026-W42', 'done')).resolves.toBeUndefined();
  });
});
