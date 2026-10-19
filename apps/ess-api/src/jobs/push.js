const { createFcm } = require('../lib/fcm');
const { isQuietHours, dmy } = require('../policy/notifications');

/**
 * The push worker (tasks D2, D7, D8): turns notifications into phone pushes, and imports the
 * Scheduler's newly assigned priority tasks as notifications of their own.
 *
 * Every minute (and once at boot):
 *   1. priority tasks: a task assigned to one person in the last 48 hours and not yet turned
 *      into a notification for them becomes one. The 48-hour window means a restart loses
 *      nothing; the unique key (and the check here) means a re-run notifies nobody twice.
 *      Broadcast tasks (`assigned_to` NULL) are not pushed: their recipients are the Scheduler's
 *      own admin set, resolved in its code (docs/06-backend-phases.md, D2).
 *   2. delivery: every notification not yet pushed, oldest first. A category the person turned
 *      off, or no registered phone, marks it skipped. With the FIREBASE_* settings present, FCM
 *      sends it; without them it is written to the log (ADR-0016). A token FCM says belongs to no
 *      install is revoked. A send that fails is retried, up to 3 attempts.
 *
 * Nothing is pushed between 21:00 and 08:00 IST; the rows wait for the morning. Failures are
 * logged and never stop the next notification.
 *
 * One process only (ecosystem.config.cjs, fork mode), as for the on-duty job.
 */

const MINUTE_MS = 60 * 1000;
const PRIORITY_WINDOW_MS = 48 * 60 * 60 * 1000;
const MAX_ATTEMPTS = 3;
const BATCH = 50;

/**
 * @param {object} deps
 * @param {object} deps.store
 * @param {object} deps.config   config.js loadConfig, for the FIREBASE_* settings
 * @param {() => Date} [deps.now]
 * @param {object} [deps.log]
 * @param {number} [deps.intervalMs]
 * @param {Function} [deps.fetchImpl]  the tests pass a stub, so nothing leaves the machine
 * @param {boolean} [deps.immediate]
 */
function startPushJob({ store, config, now = () => new Date(), log = console, intervalMs = MINUTE_MS, fetchImpl, immediate = true }) {
  let running = false;
  const fcm = config && config.push && config.push.enabled
    ? createFcm({ ...config.firebase, fetchImpl, now })
    : null;

  /** Newly assigned priority tasks become notifications, once each. */
  async function syncPriorityTasks() {
    const at = now();
    const sinceIso = new Date(at.getTime() - PRIORITY_WINDOW_MS).toISOString();
    const tasks = await store.listNewPriorityTasks({ sinceIso, limit: 100 });
    if (!tasks.length) return 0;
    const userIds = [...new Set(tasks.map((t) => t.assigned_to).filter(Boolean))];
    const byUser = new Map((await store.listEmployeesByUserIds(userIds)).map((e) => [e.user_id, e.id]));
    let created = 0;
    for (const task of tasks) {
      const employeeId = byUser.get(task.assigned_to);
      if (!employeeId) continue;
      const existing = await store.listTaskNotifications(employeeId, sinceIso);
      if (existing.some((n) => n.data && n.data.task_id === task.id)) continue;
      try {
        await store.createNotification({
          employee_id: employeeId,
          category: 'priority_tasks',
          title: 'New priority task',
          body: `${task.title}${task.due_date ? ` Due ${dmy(task.due_date)}.` : ''}`,
          data: { task_id: task.id },
        });
        created += 1;
      } catch (e) {
        log.error(`[ess] push job: the notification for task ${task.id} failed: ${e && e.message ? e.message : e}`);
      }
    }
    return created;
  }

  /** One notification across the person's live phones. Answers how it ended. */
  async function deliverOne(row, devices, disabled, at) {
    if (disabled.has(row.category) || !devices.length) {
      await store.markNotificationPushed(row.id, { pushed_at: at, push_mode: 'skipped', push_error: null });
      return 'skipped';
    }
    if (!fcm) {
      log.log(`[ess] push (log-only): ${row.category} to ${row.employee_id}: ${row.title}`);
      await store.markNotificationPushed(row.id, { pushed_at: at, push_mode: 'log', push_error: null });
      return 'logged';
    }
    let lastError = null;
    for (const device of devices) {
      const out = await fcm.send({
        token: device.token,
        title: row.title,
        body: row.body,
        data: { category: row.category, ...(row.data || {}) },
      });
      if (out.ok) {
        await store.markNotificationPushed(row.id, { pushed_at: at, push_mode: 'fcm', push_error: null });
        return 'sent';
      }
      lastError = out.error || 'the push failed';
      if (out.invalidToken) await store.revokePushDeviceRow(device.id, at);
    }
    const attempts = (row.push_attempts || 0) + 1;
    const error = String(lastError || '').slice(0, 500);
    if (attempts >= MAX_ATTEMPTS) {
      // Give up on this one, so the queue cannot jam on a phone that never takes a message.
      await store.markNotificationPushed(row.id, { pushed_at: at, push_mode: 'skipped', push_attempts: attempts, push_error: error });
      return 'skipped';
    }
    await store.markNotificationPushed(row.id, { push_attempts: attempts, push_error: error });
    return 'failed';
  }

  async function deliver() {
    if (isQuietHours(now())) return { held: true };
    const rows = await store.listUndeliveredNotifications(BATCH);
    if (!rows.length) return { sent: 0, logged: 0, skipped: 0, failed: 0 };
    const employeeIds = [...new Set(rows.map((r) => r.employee_id))];
    const [settings, devices] = await Promise.all([
      store.notificationSettingsFor(employeeIds),
      store.listPushDevicesFor(employeeIds),
    ]);
    const disabledBy = new Map(settings.map((s) => [s.employee_id, new Set(s.disabled_categories || [])]));
    const devicesBy = new Map();
    for (const d of devices) {
      if (!devicesBy.has(d.employee_id)) devicesBy.set(d.employee_id, []);
      devicesBy.get(d.employee_id).push(d);
    }
    const counts = { sent: 0, logged: 0, skipped: 0, failed: 0 };
    for (const row of rows) {
      const at = now().toISOString();
      try {
        const outcome = await deliverOne(row, devicesBy.get(row.employee_id) || [], disabledBy.get(row.employee_id) || new Set(), at);
        counts[outcome] += 1;
      } catch (e) {
        log.error(`[ess] push job: notification ${row.id} failed: ${e && e.message ? e.message : e}`);
        counts.failed += 1;
      }
    }
    return counts;
  }

  async function runOnce() {
    if (running) return null;
    running = true;
    try {
      let created = 0;
      try {
        created = await syncPriorityTasks();
      } catch (e) {
        log.error(`[ess] push job: priority tasks: ${e && e.message ? e.message : e}`);
      }
      let delivery = {};
      try {
        delivery = (await deliver()) || {};
      } catch (e) {
        log.error(`[ess] push job: delivery: ${e && e.message ? e.message : e}`);
      }
      return { created, ...delivery };
    } finally {
      running = false;
    }
  }

  const timer = setInterval(runOnce, intervalMs);
  if (typeof timer.unref === 'function') timer.unref();
  if (immediate) runOnce();

  return { runOnce, stop: () => clearInterval(timer) };
}

module.exports = { startPushJob, MAX_ATTEMPTS, PRIORITY_WINDOW_MS };
