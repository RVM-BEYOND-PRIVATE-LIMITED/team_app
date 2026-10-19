const { buildApp, tokens, bearer } = require('./helpers/app');
const { startWallJob } = require('../src/jobs/wall');
const { istDay } = require('../src/lib/time');
const request = require('supertest');
const W = require('./helpers/wallFixtures');

/** Tasks F4 and F5's clock: scheduled announcements, acknowledgement reminders, polls closing. */

/** The app's own clock, so the job and the routes see the same day. */
const at = (world, when) => startWallJob({
  store: world.store,
  now: () => when,
  log: { log: () => {}, error: () => {} },
  immediate: false,
  intervalMs: 60 * 60 * 1000,
});

describe('the Wall job: scheduled announcements', () => {
  it('publishes a scheduled one when its time arrives, resolves its audience and notifies once', async () => {
    const world = buildApp({ setup: (w) => {
      w.tables.hr_ess_announcements = [W.announcementRow(w.people.hr.employee.id, 1, {
        published_at: null, publish_at: '2026-10-16T05:00:00+00:00', title: 'Diwali holiday',
      })];
    } });
    const job = at(world, new Date('2026-10-16T06:30:00.000Z'));
    const out = await job.runOnce();
    expect(out.published).toBe(1);
    const row = world.db.tables.hr_ess_announcements[0];
    expect(row.published_at).toBe('2026-10-16T06:30:00.000Z');
    expect(world.db.rows('hr_ess_announcement_audience')).toHaveLength(13);
    expect(world.db.tables.hr_ess_notifications.filter((n) => n.category === 'announcements')).toHaveLength(13);
    // A second run changes nothing: it is no longer due.
    const again = await job.runOnce();
    expect(again.published).toBe(0);
    expect(world.db.tables.hr_ess_notifications.filter((n) => n.category === 'announcements')).toHaveLength(13);
  });

  it('leaves a scheduled one alone until its time', async () => {
    const world = buildApp({ setup: (w) => {
      w.tables.hr_ess_announcements = [W.announcementRow(w.people.hr.employee.id, 1, { published_at: null, publish_at: '2026-11-01T04:00:00+00:00' })];
    } });
    const job = at(world, new Date('2026-10-16T06:30:00.000Z'));
    const out = await job.runOnce();
    expect(out.published).toBe(0);
    expect(world.db.tables.hr_ess_announcements[0].published_at).toBe(null);
    expect(world.db.rows('hr_ess_announcement_audience')).toEqual([]);
  });

  it('asks for acknowledgement with the announcement when it needs one', async () => {
    const world = buildApp({ setup: (w) => {
      w.tables.hr_ess_announcements = [W.announcementRow(w.people.hr.employee.id, 1, {
        published_at: null, publish_at: '2026-10-16T05:00:00+00:00', needs_ack: true, closes_on: '2026-11-05',
      })];
    } });
    const job = at(world, new Date('2026-10-16T06:30:00.000Z'));
    await job.runOnce();
    const categories = world.db.rows('hr_ess_notifications').map((n) => n.category);
    expect(categories.filter((c) => c === 'announcements')).toHaveLength(13);
    expect(categories.filter((c) => c === 'acknowledgements')).toHaveLength(13);
  });
});

describe('the Wall job: acknowledgement reminders', () => {
  const seeded = (change = {}) => (w) => {
    w.tables.hr_ess_announcements = [W.announcementRow(w.people.hr.employee.id, 1, {
      needs_ack: true, closes_on: '2026-10-17', ...change,
    })];
    w.tables.hr_ess_announcement_audience = [
      W.audienceRow(W.ANNOUNCEMENT_ID(1), w.people.faculty.employee.id),
      W.audienceRow(W.ANNOUNCEMENT_ID(1), w.people.hod.employee.id),
    ];
    w.tables.hr_ess_announcement_reads = [W.readRow(W.ANNOUNCEMENT_ID(1), w.people.faculty.employee.id, { ack_at: '2026-10-16T05:30:00+00:00' })];
  };

  it('reminds those who have not acknowledged, once a day, and the row says when', async () => {
    const world = buildApp({ setup: seeded() });
    const job = at(world, new Date('2026-10-16T06:30:00.000Z'));
    const out = await job.runOnce();
    expect(out.reminded).toBe(1);
    const reminders = world.db.tables.hr_ess_notifications.filter((n) => n.category === 'acknowledgements');
    expect(reminders).toHaveLength(1);
    expect(reminders[0].employee_id).toBe(world.people.hod.employee.id);
    expect(world.db.tables.hr_ess_announcements[0].reminded_at).toBe('2026-10-16T06:30:00.000Z');
    // The same day again: nothing more.
    expect((await job.runOnce()).reminded).toBe(0);
  });

  it('says nothing once everybody has acknowledged', async () => {
    const world = buildApp({ setup: (w) => {
      seeded()(w);
      w.tables.hr_ess_announcement_reads.push(W.readRow(W.ANNOUNCEMENT_ID(1), w.people.hod.employee.id, { ack_at: '2026-10-16T05:45:00+00:00' }));
    } });
    const job = at(world, new Date('2026-10-16T06:30:00.000Z'));
    expect((await job.runOnce()).reminded).toBe(0);
    expect(world.db.tables.hr_ess_announcements[0].reminded_at).toBe('2026-10-16T06:30:00.000Z');
  });

  it('leaves an announcement whose close is further away until the window opens', async () => {
    const world = buildApp({ setup: seeded({ closes_on: '2026-11-05' }) });
    const job = at(world, new Date('2026-10-16T06:30:00.000Z'));
    expect((await job.runOnce()).reminded).toBe(0);
    expect(world.db.tables.hr_ess_announcements[0].reminded_at).toBe(null);
  });
});

describe('the Wall job: polls closing', () => {
  const seeded = (closes) => (w) => {
    w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1, {
      kind: 'poll', body: 'Lunch?', poll_closes_on: closes, options_locked_at: W.AT,
    })];
    w.tables.hr_ess_wall_poll_options = [W.optionRow(W.POST_ID(1), 1, 'Chaat', 0), W.optionRow(W.POST_ID(1), 2, 'Dosa', 1)];
    w.tables.hr_ess_wall_poll_votes = [
      W.voteRow(W.POST_ID(1), W.OPTION_ID(1), w.people.hr.employee.id),
      W.voteRow(W.POST_ID(1), W.OPTION_ID(1), w.people.hod.employee.id),
    ];
  };

  it('tells those who voted, once, on the closing day', async () => {
    const world = buildApp({ setup: seeded('2026-10-16') });
    const job = at(world, new Date('2026-10-16T06:30:00.000Z'));
    const out = await job.runOnce();
    expect(out.polls).toBe(1);
    const told = world.db.tables.hr_ess_notifications.filter((n) => n.category === 'polls');
    expect(told.map((n) => n.employee_id).sort()).toEqual([world.people.hod.employee.id, world.people.hr.employee.id].sort());
    // A second run does not tell them twice.
    await job.runOnce();
    expect(world.db.tables.hr_ess_notifications.filter((n) => n.category === 'polls')).toHaveLength(2);
  });

  it('says nothing before the closing day', async () => {
    const world = buildApp({ setup: seeded('2026-11-01') });
    const job = at(world, new Date('2026-10-16T06:30:00.000Z'));
    expect((await job.runOnce()).polls).toBe(0);
    expect(world.db.rows('hr_ess_notifications')).toEqual([]);
  });
});

describe('the Wall job on a database that is not there yet', () => {
  it('logs and answers null rather than failing the process', async () => {
    const world = buildApp();
    world.db.outage = 'error';
    const lines = [];
    const job = startWallJob({
      store: world.store,
      now: () => new Date('2026-10-16T06:30:00.000Z'),
      log: { log: () => {}, error: (m) => lines.push(String(m)) },
      immediate: false,
      intervalMs: 60 * 60 * 1000,
    });
    const out = await job.runOnce();
    expect(out).toMatchObject({ published: 0, reminded: 0, polls: 0 });
    expect(lines.join('\n')).toMatch(/scheduled announcements/);
  });

  it('stops its timer without touching anything', async () => {
    const world = buildApp();
    const job = startWallJob({ store: world.store, now: () => new Date('2026-10-16T06:30:00.000Z'), log: { log: () => {}, error: () => {} }, immediate: false });
    expect(typeof job.stop).toBe('function');
    job.stop();
    // The app still serves: the job is a clock beside it, never a condition of it.
    const res = await request(world.app).get('/api/ess/wall/settings').set(bearer(tokens.portal(world.people.hr)));
    expect(res.status).toBe(200);
    expect(istDay(new Date('2026-10-16T06:30:00.000Z'))).toBe('2026-10-16');
  });
});
