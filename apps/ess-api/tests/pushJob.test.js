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
  read_at: null, pushed_at: null, push_mode: null, push_attempts: 0, push_error: null,
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
