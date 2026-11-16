const crypto = require('crypto');
const { buildApp } = require('./helpers/app');
const { NOW } = require('./helpers/constants');
const { quietErrors } = require('./helpers/expect');
const { startPushJob } = require('../src/jobs/push');

/** Tasks D2, D7, D8: the push worker — priority tasks in, notifications out. */

const { privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const FIREBASE_KEY = Buffer.from(privateKey.export({ type: 'pkcs8', format: 'pem' })).toString('base64');

const jobs = [];
const start = (world, options = {}) => {
  const log = options.log || { log: () => {}, error: () => {} };
  const job = startPushJob({
    store: world.store,
    config: world.config,
    now: options.now || (() => new Date(NOW.getTime())),
    log,
    immediate: false,
    fetchImpl: options.fetchImpl,
    intervalMs: options.intervalMs,
  });
  jobs.push(job);
  return job;
};

afterEach(() => {
  while (jobs.length) jobs.pop().stop();
});

const NID = (n) => `82000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const DID = (n) => `83000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

const notificationRow = (employeeId, n, change = {}) => ({
  id: NID(n), employee_id: employeeId, category: 'decisions', title: 'Request approved',
  body: 'Your request was approved.', data: { request_id: '7a000000-0000-4000-8000-000000000001' },
  read_at: null, pushed_at: null, push_mode: null, push_attempts: 0, push_error: null, priority: 'normal',
  created_at: `2026-10-16T0${n}:00:00+00:00`, ...change,
});

const deviceRow = (employeeId, n, change = {}) => ({
  id: DID(n), employee_id: employeeId, token: `device-token-${n}-${'x'.repeat(30)}`, platform: 'android',
  device_label: null, install_id: null, created_at: '2026-10-16T05:00:00+00:00',
  updated_at: '2026-10-16T05:00:00+00:00', last_seen_at: '2026-10-16T05:00:00+00:00', revoked_at: null, ...change,
});

const fcmStub = ({ send } = {}) => {
  const calls = [];
  const fetchImpl = async (url, options) => {
    calls.push({ url, options });
    if (url === 'https://oauth2.googleapis.com/token') {
      return { ok: true, status: 200, json: async () => ({ access_token: 'access-1', expires_in: 3600 }) };
    }
    return send || { ok: true, status: 200, json: async () => ({ name: 'ok' }) };
  };
  return { fetchImpl, calls };
};

describe('the push worker', () => {
  it('without Firebase, logs each push and marks the row', async () => {
    const world = buildApp({ setup: (w) => {
      w.tables.hr_ess_push_devices = [deviceRow(w.people.attendance.employee.id, 1)];
      w.tables.hr_ess_notifications = [notificationRow(w.people.attendance.employee.id, 1)];
    } });
    const log = vi.fn();
    const job = start(world, { log: { log, error: () => {} } });
    expect(await job.runOnce()).toMatchObject({ logged: 1 });
    expect(world.db.tables.hr_ess_notifications[0]).toMatchObject({ push_mode: 'log', push_error: null });
    expect(world.db.tables.hr_ess_notifications[0].pushed_at).toEqual(expect.any(String));
    expect(log).toHaveBeenCalledWith(expect.stringContaining('push (log-only)'));
  });

  it('skips a category the person turned off, and a person with no phone, without logging a push', async () => {
    const world = buildApp({ setup: (w) => {
      w.tables.hr_ess_push_devices = [deviceRow(w.people.attendance.employee.id, 1)];
      w.tables.hr_ess_notification_settings = [{ employee_id: w.people.attendance.employee.id, disabled_categories: ['decisions'], updated_at: '2026-10-16T05:00:00+00:00' }];
      w.tables.hr_ess_notifications = [
        notificationRow(w.people.attendance.employee.id, 1),
        notificationRow(w.people.faculty.employee.id, 2),
      ];
    } });
    const log = vi.fn();
    const job = start(world, { log: { log, error: () => {} } });
    const out = await job.runOnce();
    expect(out).toMatchObject({ skipped: 2, logged: 0 });
    for (const row of world.db.tables.hr_ess_notifications) expect(row.push_mode).toBe('skipped');
    expect(log).not.toHaveBeenCalled();
  });

  it('holds every push between 21:00 and 08:00 IST, and sends after', async () => {
    const world = buildApp({ setup: (w) => {
      w.tables.hr_ess_push_devices = [deviceRow(w.people.attendance.employee.id, 1)];
      w.tables.hr_ess_notifications = [notificationRow(w.people.attendance.employee.id, 1)];
    } });
    // 23:00 IST.
    const night = start(world, { now: () => new Date('2026-10-16T17:30:00.000Z') });
    expect(await night.runOnce()).toMatchObject({ held: true });
    expect(world.db.tables.hr_ess_notifications[0].pushed_at).toBe(null);
    // 08:00 IST the next morning.
    const morning = start(world, { now: () => new Date('2026-10-17T02:30:00.000Z') });
    expect(await morning.runOnce()).toMatchObject({ logged: 1 });
  });

  it('sends through FCM when the three settings are there, and marks the row', async () => {
    const world = buildApp({
      env: { FIREBASE_PROJECT_ID: 'team-rvm', FIREBASE_CLIENT_EMAIL: 'push@example.test', FIREBASE_PRIVATE_KEY_B64: FIREBASE_KEY },
      setup: (w) => {
        w.tables.hr_ess_push_devices = [deviceRow(w.people.attendance.employee.id, 1)];
        w.tables.hr_ess_notifications = [notificationRow(w.people.attendance.employee.id, 1)];
      },
    });
    const { fetchImpl, calls } = fcmStub();
    const job = start(world, { fetchImpl });
    expect(await job.runOnce()).toMatchObject({ sent: 1 });
    expect(world.db.tables.hr_ess_notifications[0]).toMatchObject({ push_mode: 'fcm', push_error: null });
    const sent = calls.find((c) => c.url.includes('messages:send'));
    expect(JSON.parse(sent.options.body).message.token).toBe(world.db.tables.hr_ess_push_devices[0].token);
    // A normal push is exactly what it always was.
    expect(JSON.parse(sent.options.body).message.android).toEqual({ priority: 'high' });
  });

  it('revokes a token FCM says belongs to no install', async () => {
    const world = buildApp({
      env: { FIREBASE_PROJECT_ID: 'team-rvm', FIREBASE_CLIENT_EMAIL: 'push@example.test', FIREBASE_PRIVATE_KEY_B64: FIREBASE_KEY },
      setup: (w) => {
        w.tables.hr_ess_push_devices = [deviceRow(w.people.attendance.employee.id, 1)];
        w.tables.hr_ess_notifications = [notificationRow(w.people.attendance.employee.id, 1)];
      },
    });
    const { fetchImpl } = fcmStub({ send: { ok: false, status: 404, json: async () => ({ error: { status: 'NOT_FOUND', details: [{ errorCode: 'UNREGISTERED' }] } }) } });
    const job = start(world, { fetchImpl });
    expect(await job.runOnce()).toMatchObject({ failed: 1 });
    expect(world.db.tables.hr_ess_push_devices[0].revoked_at).toEqual(expect.any(String));
    // With no live phone left, the next run gives up on it cleanly.
    expect(await job.runOnce()).toMatchObject({ skipped: 1 });
    expect(world.db.tables.hr_ess_notifications[0]).toMatchObject({ push_mode: 'skipped', push_attempts: 1 });
  });

  it('retries a failing send three times, then gives up', async () => {
    const world = buildApp({
      env: { FIREBASE_PROJECT_ID: 'team-rvm', FIREBASE_CLIENT_EMAIL: 'push@example.test', FIREBASE_PRIVATE_KEY_B64: FIREBASE_KEY },
      setup: (w) => {
        w.tables.hr_ess_push_devices = [deviceRow(w.people.attendance.employee.id, 1)];
        w.tables.hr_ess_notifications = [notificationRow(w.people.attendance.employee.id, 1)];
      },
    });
    const { fetchImpl } = fcmStub({ send: { ok: false, status: 500, json: async () => ({}) } });
    const job = start(world, { fetchImpl });
    expect(await job.runOnce()).toMatchObject({ failed: 1 });
    expect(world.db.tables.hr_ess_notifications[0]).toMatchObject({ push_attempts: 1, push_mode: null });
    expect(await job.runOnce()).toMatchObject({ failed: 1 });
    expect(await job.runOnce()).toMatchObject({ skipped: 1 });
    expect(world.db.tables.hr_ess_notifications[0]).toMatchObject({ push_mode: 'skipped', push_attempts: 3 });
  });

  it('turns a newly assigned priority task into one notification, once', async () => {
    const world = buildApp({ setup: (w) => {
      w.tables.priority_tasks = [{
        id: '84000000-0000-4000-8000-000000000001', location_id: 1, task_date: '2026-10-16', title: 'Check the lab PCs',
        notes: null, priority: 'high', due_date: '2026-10-20', assigned_to: w.people.hod.user.id,
        assigned_by: w.people.hoo.user.id, assigned_by_name: 'Test Head of Operations', assigned_by_role: 'hoo',
        status: 'open', created_at: '2026-10-16T05:00:00+00:00', updated_at: '2026-10-16T05:00:00+00:00',
      }];
    } });
    const job = start(world);
    expect(await job.runOnce()).toMatchObject({ created: 1 });
    const rows = world.db.tables.hr_ess_notifications;
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      employee_id: world.people.hod.employee.id,
      category: 'priority_tasks',
      title: 'New priority task',
      body: 'Check the lab PCs Due 20 Oct.',
      data: { task_id: '84000000-0000-4000-8000-000000000001' },
    });
    expect(await job.runOnce()).toMatchObject({ created: 0 });
    expect(world.db.tables.hr_ess_notifications).toHaveLength(1);
  });

  it('ignores a task assigned to somebody with no HR record, and a missing priority-tasks table', async () => {
    quietErrors();
    const world = buildApp({ setup: (w) => {
      w.tables.priority_tasks = [{
        id: '84000000-0000-4000-8000-000000000002', location_id: 1, task_date: '2026-10-16', title: 'Nobody\'s task',
        notes: null, priority: 'normal', due_date: null, assigned_to: 'a0000000-0000-4000-8000-000000000090',
        assigned_by: w.people.hoo.user.id, assigned_by_name: 'Test Head of Operations', assigned_by_role: 'hoo',
        status: 'open', created_at: '2026-10-16T05:00:00+00:00', updated_at: '2026-10-16T05:00:00+00:00',
      }];
    } });
    expect(await start(world).runOnce()).toMatchObject({ created: 0 });
    expect(world.db.tables.hr_ess_notifications || []).toHaveLength(0);
    world.db.dropTable('priority_tasks');
    const error = vi.fn();
    expect(await start(world, { log: { log: () => {}, error } }).runOnce()).not.toBe(null);
    expect(error).toHaveBeenCalledWith(expect.stringContaining('priority tasks'));
  });
});

/** TA-P-01 (team_app #59): the urgent lane, its 60-second TTL, and the world before the migration. */
describe('the urgent lane', () => {
  const urgentRow = (employeeId, n, change = {}) => notificationRow(employeeId, n, {
    category: 'crm_callback',
    title: 'Callback promised',
    body: 'A parent asked to be called back about the admission.',
    priority: 'urgent',
    ...change,
  });

  const worldWith = (rows) => buildApp({ setup: (w) => {
    w.tables.hr_ess_push_devices = [deviceRow(w.people.attendance.employee.id, 1)];
    w.tables.hr_ess_notifications = rows(w.people.attendance.employee.id);
  } });

  it('sends an urgent row at 22:30 IST, and leaves the normal row for 08:00', async () => {
    const world = worldWith((id) => [
      urgentRow(id, 1, { created_at: '2026-10-16T16:59:30+00:00' }),
      notificationRow(id, 2, { created_at: '2026-10-16T16:59:30+00:00' }),
    ]);
    const log = vi.fn();
    // 22:30 IST.
    const night = start(world, { now: () => new Date('2026-10-16T17:00:00.000Z'), log: { log, error: () => {} } });
    expect(await night.runUrgentOnce()).toMatchObject({ logged: 1 });
    expect(world.db.tables.hr_ess_notifications[0]).toMatchObject({ push_mode: 'log' });
    expect(world.db.tables.hr_ess_notifications[1].pushed_at).toBe(null);
    expect(await night.runOnce()).toMatchObject({ held: true });
    expect(log).toHaveBeenCalledWith(expect.stringContaining('push (log-only): crm_callback'));
    // 08:00 IST the next morning: the normal row goes, and only it.
    const morning = start(world, { now: () => new Date('2026-10-17T02:30:00.000Z') });
    expect(await morning.runOnce()).toMatchObject({ logged: 1 });
    expect(world.db.tables.hr_ess_notifications[1]).toMatchObject({ push_mode: 'log' });
  });

  it('runs every five seconds, and only when its five seconds are up', async () => {
    const world = worldWith((id) => [urgentRow(id, 1, { created_at: '2026-10-16T16:59:30+00:00' })]);
    vi.useFakeTimers();
    try {
      start(world, { now: () => new Date('2026-10-16T17:00:00.000Z'), immediate: false });
      await vi.advanceTimersByTimeAsync(4999);
      expect(world.db.tables.hr_ess_notifications[0].pushed_at).toBe(null);
      await vi.advanceTimersByTimeAsync(1);
      expect(world.db.tables.hr_ess_notifications[0]).toMatchObject({ push_mode: 'log' });
    } finally {
      vi.useRealTimers();
    }
  });

  it('is not delayed by 200 queued normal rows', async () => {
    const world = worldWith((id) => [
      ...Array.from({ length: 200 }, (_, i) => notificationRow(id, 100 + i, { created_at: '2026-10-16T04:00:00+00:00' })),
      urgentRow(id, 1, { created_at: '2026-10-16T16:59:30+00:00' }),
    ]);
    const job = start(world, { now: () => new Date('2026-10-16T17:00:00.000Z') });
    expect(await job.runUrgentOnce()).toMatchObject({ logged: 1 });
    const rows = world.db.tables.hr_ess_notifications;
    expect(rows.find((r) => r.priority === 'urgent')).toMatchObject({ push_mode: 'log' });
    for (const row of rows.filter((r) => r.priority === 'normal')) expect(row.pushed_at).toBe(null);
  });

  it('marks an urgent row older than 60 seconds skipped, and does not send it', async () => {
    const world = worldWith((id) => [urgentRow(id, 1, { created_at: '2026-10-16T09:58:59+00:00' })]);
    const log = vi.fn();
    const job = start(world, { now: () => new Date('2026-10-16T10:00:00.000Z'), log: { log, error: () => {} } });
    expect(await job.runUrgentOnce()).toMatchObject({ skipped: 1 });
    // #93: a row dropped for age says so, so the late-push check can count it.
    expect(world.db.tables.hr_ess_notifications[0]).toMatchObject({ push_mode: 'skipped', push_error: 'too_late' });
    expect(world.db.tables.hr_ess_notifications[0].pushed_at).toEqual(expect.any(String));
    expect(log).not.toHaveBeenCalled();
  });

  it('does not send a row already sent, after a restart', async () => {
    const world = worldWith((id) => [urgentRow(id, 1, { created_at: '2026-10-16T16:59:30+00:00' })]);
    const log = vi.fn();
    const first = start(world, { now: () => new Date('2026-10-16T17:00:00.000Z'), log: { log, error: () => {} } });
    expect(await first.runUrgentOnce()).toMatchObject({ logged: 1 });
    first.stop();
    const second = start(world, { now: () => new Date('2026-10-16T17:00:02.000Z'), log: { log, error: () => {} } });
    expect(await second.runUrgentOnce()).toMatchObject({ sent: 0, logged: 0, skipped: 0, failed: 0 });
    expect(log).toHaveBeenCalledTimes(1);
  });

  it('before the migration logs once, sends nothing urgent, and leaves the minute loop as it was', async () => {
    quietErrors();
    const world = worldWith((id) => [notificationRow(id, 1, { created_at: '2026-10-16T05:00:00+00:00' })]);
    world.db.dropColumn('hr_ess_notifications', 'priority');
    const error = vi.fn();
    const log = vi.fn();
    const job = start(world, { log: { log, error } });
    expect(await job.runUrgentOnce()).toEqual({ missing: true });
    expect(await job.runUrgentOnce()).toEqual({ missing: true });
    expect(error).toHaveBeenCalledTimes(1);
    expect(error).toHaveBeenCalledWith(expect.stringContaining('priority'));
    expect(log).not.toHaveBeenCalled();
    // The minute loop's queue is the one it always had.
    expect(await job.runOnce()).toMatchObject({ logged: 1 });
    expect(world.db.tables.hr_ess_notifications[0]).toMatchObject({ push_mode: 'log' });
  });

  it('sends an urgent push on the urgent channel with a 60-second TTL, and a normal one unchanged', async () => {
    // The world has the FIREBASE_* settings, so both sends go through the stub.
    const withPush = buildApp({
      env: { FIREBASE_PROJECT_ID: 'team-rvm', FIREBASE_CLIENT_EMAIL: 'push@example.test', FIREBASE_PRIVATE_KEY_B64: FIREBASE_KEY },
      setup: (w) => {
        w.tables.hr_ess_push_devices = [deviceRow(w.people.attendance.employee.id, 1)];
        w.tables.hr_ess_notifications = [
          urgentRow(w.people.attendance.employee.id, 1, { created_at: '2026-10-16T06:29:30+00:00' }),
          notificationRow(w.people.attendance.employee.id, 2, { created_at: '2026-10-16T06:29:30+00:00' }),
        ];
      },
    });
    const { fetchImpl, calls } = fcmStub();
    const job = start(withPush, { fetchImpl, now: () => new Date('2026-10-16T06:30:00.000Z') });
    expect(await job.runUrgentOnce()).toMatchObject({ sent: 1 });
    expect(await job.runOnce()).toMatchObject({ sent: 1 });
    const sent = calls.filter((c) => c.url.includes('messages:send')).map((c) => JSON.parse(c.options.body).message);
    expect(sent).toHaveLength(2);
    // #94: the collapse key says what the push is about, so a second one replaces the first on the phone.
    expect(sent[0].android).toEqual({
      priority: 'high',
      ttl: '60s',
      notification: { channel_id: 'team_rvm_urgent', tag: `crm_callback:row:${NID(1)}` },
      collapse_key: `crm_callback:row:${NID(1)}`,
    });
    expect(sent[1].android).toEqual({ priority: 'high' });
  });
});

describe('push reliability (team_app #92 to #95)', () => {
  const { collapseKeyFor } = require('../src/jobs/push');

  it('#94: the collapse key is the lead, the call or the row the push is about', () => {
    expect(collapseKeyFor({ id: 'r1', category: 'crm_callback', data: { lead_id: 41 } })).toBe('crm_callback:lead:41');
    expect(collapseKeyFor({ id: 'r2', category: 'crm_call', data: { call_id: 9 } })).toBe('crm_call:call:9');
    expect(collapseKeyFor({ id: 'r3', category: 'crm_callback', data: {} })).toBe('crm_callback:row:r3');
  });

  it('#95: a second row with the same key for the same person is refused and answers null; another person gets theirs', async () => {
    const world = buildApp();
    const a = world.people.attendance.employee.id;
    const b = world.people.hr.employee.id;
    const row = (employeeId) => ({ employee_id: employeeId, category: 'decisions', title: 'Request approved', body: 'Approved.', data: {}, dedupe_key: 'decision:leave:r-1:approved' });
    expect(await world.store.createNotification(row(a))).toMatchObject({ employee_id: a });
    expect(await world.store.createNotification(row(a))).toBe(null);
    expect(await world.store.createNotification(row(b))).toMatchObject({ employee_id: b });
    expect(world.db.tables.hr_ess_notifications.filter((r) => r.dedupe_key === 'decision:leave:r-1:approved')).toHaveLength(2);
  });

  it('#95: before the migration the key is left off and the row is written as before', async () => {
    quietErrors();
    const world = buildApp();
    world.db.dropColumn('hr_ess_notifications', 'dedupe_key');
    const id = world.people.attendance.employee.id;
    const row = { employee_id: id, category: 'decisions', title: 'Request approved', body: 'Approved.', data: {}, dedupe_key: 'k-123' };
    expect(await world.store.createNotification(row)).toMatchObject({ employee_id: id });
    expect(await world.store.createNotification(row)).toMatchObject({ employee_id: id });
  });

  it('#92: each minute run writes its record; the urgent loop writes when it did something or once a minute', async () => {
    const world = buildApp({ setup: (w) => {
      w.tables.hr_ess_notifications = [
        notificationRow(w.people.attendance.employee.id, 1, { created_at: '2026-10-16T05:00:00+00:00' }),
      ];
    } });
    let t = new Date('2026-10-16T06:30:00.000Z').getTime();
    const job = start(world, { now: () => new Date(t) });
    await job.runOnce();
    const runs = () => world.db.tables.hr_ess_worker_runs || [];
    expect(runs().find((r) => r.worker === 'push_minute')).toMatchObject({ last_ok: true, runs: 1, failures: 0, last_counts: expect.objectContaining({ skipped: 1 }) });
    await job.runUrgentOnce();
    expect(runs().find((r) => r.worker === 'push_urgent')).toMatchObject({ runs: 1 });
    t += 5000;
    await job.runUrgentOnce();
    expect(runs().find((r) => r.worker === 'push_urgent').runs).toBe(1); // idle, inside the minute: not written
    t += 60000;
    await job.runUrgentOnce();
    expect(runs().find((r) => r.worker === 'push_urgent').runs).toBe(2);
  });

  it('#93: off by default; on, it tells each Super Admin once in 30 minutes when urgent rows are late', async () => {
    const lateRows = (id) => [
      notificationRow(id, 1, { category: 'crm_callback', priority: 'urgent', created_at: '2026-10-16T06:28:00+00:00' }),
    ];
    const off = buildApp({ setup: (w) => { w.tables.hr_ess_notifications = lateRows(w.people.attendance.employee.id); } });
    const at = () => new Date('2026-10-16T06:30:00.000Z');
    expect(await start(off, { now: at }).runOnce()).not.toHaveProperty('alerted');

    const on = buildApp({ env: { PUSH_URGENT_ALERT: 'on' }, setup: (w) => { w.tables.hr_ess_notifications = lateRows(w.people.attendance.employee.id); } });
    const job = start(on, { now: at });
    const first = await job.runOnce();
    expect(first.alerted).toBeGreaterThanOrEqual(1);
    const alerts = on.db.tables.hr_ess_notifications.filter((r) => r.category === 'crm_alert');
    expect(alerts.length).toBe(first.alerted);
    expect(alerts[0]).toMatchObject({ title: 'Callback pushes are late', priority: 'normal', data: { kind: 'push_urgent_late', count: 1 } });
    expect(JSON.stringify(alerts)).not.toMatch(/9\d{9}/);
    expect(await job.runOnce()).not.toHaveProperty('alerted');
  });
});
