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
 *   2. delivery: every normal notification not yet pushed, oldest first. A category the person
 *      turned off, or no registered phone, marks it skipped. With the FIREBASE_* settings
 *      present, FCM sends it; without them it is written to the log (ADR-0016). A token FCM says
 *      belongs to no install is revoked. A send that fails is retried, up to 3 attempts.
 *
 * Every five seconds, on its own guard (team_app #59, TA-P-01):
 *   3. the urgent lane: unpushed rows with priority 'urgent', oldest first, up to 50. It ignores
 *      the quiet hours -- a CRM callback cannot wait until morning -- and a row older than its
 *      60-second TTL is marked skipped rather than rung hours late. The minute loop never sends
 *      an urgent row, so a backlog of 200 normal notifications cannot delay one.
 *
 * Nothing else is pushed between 21:00 and 08:00 IST; the rows wait for the morning. Failures are
 * logged and never stop the next notification.
 *
 * Reliability (team_app #92 to #95):
 *   - an urgent push carries a collapse key (the lead or call it is about), so one sent again
 *     replaces the first on the phone (#94); a row dropped for age is marked push_error 'too_late';
 *   - each loop writes its run record in hr_ess_worker_runs ('push_minute' every run, 'push_urgent'
 *     when it did something or once a minute), so a stopped loop shows (#92);
 *   - with PUSH_URGENT_ALERT=on, the minute loop tells the Super Admins, at most once in 30 minutes,
 *     when urgent rows wait over a minute or were dropped as too late (#93);
 *   - a priority task's notification carries a dedupe key, so a re-run cannot write it twice (#95).
 *
 * Before the priority migration, the urgent lane sends nothing and says so once per process; the
 * minute loop keeps its old queue, so notifications work exactly as they did.
 *
 * One process only (ecosystem.config.cjs, fork mode), as for the on-duty job.
 */

const MINUTE_MS = 60 * 1000;
const PRIORITY_WINDOW_MS = 48 * 60 * 60 * 1000;
const MAX_ATTEMPTS = 3;
const BATCH = 50;
const URGENT_INTERVAL_MS = 5 * 1000;
const URGENT_TTL_MS = 60 * 1000;
const URGENT_BATCH = 50;
const ALERT_EVERY_MS = 30 * 60 * 1000;
const LATE_WINDOW_MS = 10 * 60 * 1000;
const URGENT_RECORD_EVERY_MS = 60 * 1000;

/** #94: what an urgent push is about, so a second one about the same thing replaces the first. */
function collapseKeyFor(row) {
  const d = row.data || {};
  const about = d.lead_id ? `lead:${d.lead_id}` : d.call_id ? `call:${d.call_id}` : d.inbound_call_id ? `inbound:${d.inbound_call_id}` : `row:${row.id}`;
  return `${row.category}:${about}`.slice(0, 100);
}

/** A missing column is the priority migration not applied yet, not a broken row. */
const isMissingPriority = (e) => Boolean(e && e.code === 'MODULE_NOT_INSTALLED');

/**
 * @param {object} deps
 * @param {object} deps.store
 * @param {object} deps.config   config.js loadConfig, for the FIREBASE_* settings
 * @param {() => Date} [deps.now]
 * @param {object} [deps.log]
 * @param {number} [deps.intervalMs]
 * @param {number} [deps.urgentIntervalMs]
 * @param {Function} [deps.fetchImpl]  the tests pass a stub, so nothing leaves the machine
 * @param {boolean} [deps.immediate]
 */
function startPushJob({
  store, config, now = () => new Date(), log = console,
  intervalMs = MINUTE_MS, urgentIntervalMs = URGENT_INTERVAL_MS, fetchImpl, immediate = true,
}) {
  let running = false;
  let urgentRunning = false;
  // 'unknown' until the first query that needs the priority column answers; then 'present' or
  // 'missing'. Shared by both loops, so the migration is probed once per process.
  let priorityState = 'unknown';
  let missingPriorityLogged = false;
  // #92: the run record, per loop. 'missing' once the table is not there (the migration not applied).
  let runsTable = 'unknown';
  const runCounts = { push_minute: { runs: 0, failures: 0 }, push_urgent: { runs: 0, failures: 0 } };
  let urgentRecordedAt = 0;
  // #93: when the Super Admins were last told.
  let alertedAt = 0;
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
          dedupe_key: `priority_task:${task.id}`,
        });
        created += 1;
      } catch (e) {
        log.error(`[ess] push job: the notification for task ${task.id} failed: ${e && e.message ? e.message : e}`);
      }
    }
    return created;
  }

  /** One notification across the person's live phones. Answers how it ended. */
  async function deliverOne(row, devices, disabled, at, urgent = false) {
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
        urgent,
        collapseKey: urgent ? collapseKeyFor(row) : null,
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

  /** The settings and live phones of everybody a batch of rows is for. */
  async function recipients(rows) {
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
    return { disabledBy, devicesBy };
  }

  /**
   * The minute loop's queue. Once the priority column exists, the urgent rows are left to their
   * own loop; before it does, this is exactly the query the worker always ran.
   */
  async function normalRows() {
    if (priorityState === 'missing') return store.listUndeliveredNotifications(BATCH);
    try {
      const rows = await store.listNormalNotifications(BATCH);
      priorityState = 'present';
      return rows;
    } catch (e) {
      if (!isMissingPriority(e)) throw e;
      priorityState = 'missing';
      return store.listUndeliveredNotifications(BATCH);
    }
  }

  /** The urgent loop's queue, or null when the priority migration has not been applied. */
  async function urgentRows() {
    if (priorityState === 'missing') return null;
    try {
      const rows = await store.listUrgentNotifications(URGENT_BATCH);
      priorityState = 'present';
      return rows;
    } catch (e) {
      if (!isMissingPriority(e)) throw e;
      priorityState = 'missing';
      if (!missingPriorityLogged) {
        missingPriorityLogged = true;
        log.error('[ess] push job: urgent notifications are off until the priority migration is applied.');
      }
      return null;
    }
  }

  async function deliver() {
    if (isQuietHours(now())) return { held: true };
    const rows = await normalRows();
    if (!rows.length) return { sent: 0, logged: 0, skipped: 0, failed: 0 };
    const { disabledBy, devicesBy } = await recipients(rows);
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

  /** The urgent lane: the same delivery, ignoring the quiet hours, with a 60-second TTL. */
  async function deliverUrgent() {
    const rows = await urgentRows();
    if (!rows) return { missing: true };
    if (!rows.length) return { sent: 0, logged: 0, skipped: 0, failed: 0 };
    const { disabledBy, devicesBy } = await recipients(rows);
    const counts = { sent: 0, logged: 0, skipped: 0, failed: 0 };
    for (const row of rows) {
      const at = now();
      const atIso = at.toISOString();
      try {
        const age = at.getTime() - Date.parse(row.created_at);
        if (Number.isFinite(age) && age > URGENT_TTL_MS) {
          // Too old to be useful: a callback rung an hour late is worse than one not rung.
          await store.markNotificationPushed(row.id, { pushed_at: atIso, push_mode: 'skipped', push_error: 'too_late' });
          counts.skipped += 1;
          counts.too_late = (counts.too_late || 0) + 1;
          continue;
        }
        const outcome = await deliverOne(
          row, devicesBy.get(row.employee_id) || [], disabledBy.get(row.employee_id) || new Set(), atIso, true,
        );
        counts[outcome] += 1;
      } catch (e) {
        log.error(`[ess] push job: urgent notification ${row.id} failed: ${e && e.message ? e.message : e}`);
        counts.failed += 1;
      }
    }
    return counts;
  }

  /** #92: one loop's run record. Never fails the run; a missing table is said once and then left alone. */
  async function record(worker, startedAt, ok, counts) {
    if (runsTable === 'missing' || typeof store.recordWorkerRun !== 'function') return;
    const c = runCounts[worker];
    c.runs += 1;
    if (!ok) c.failures += 1;
    try {
      await store.recordWorkerRun(worker, {
        last_started_at: startedAt.toISOString(), last_finished_at: now().toISOString(), last_ok: ok,
        last_counts: counts && typeof counts === 'object' ? counts : {}, runs: c.runs, failures: c.failures, updated_at: now().toISOString(),
      });
      runsTable = 'present';
    } catch (e) {
      if (e && e.code === 'MODULE_NOT_INSTALLED') {
        runsTable = 'missing';
        log.error('[ess] push job: runs are not recorded until db/migrations/20261231100000_hr_ess_push_reliability.sql is applied.');
      }
    }
  }

  /** #93: tell the Super Admins, at most once in 30 minutes, that urgent pushes are late. */
  async function alertIfLate() {
    if (!(config && config.push && config.push.urgentAlert)) return null;
    const at = now();
    if (at.getTime() - alertedAt < ALERT_EVERY_MS) return null;
    let late;
    try {
      late = await store.countLateUrgent({
        olderThanIso: new Date(at.getTime() - URGENT_TTL_MS).toISOString(),
        sinceIso: new Date(at.getTime() - LATE_WINDOW_MS).toISOString(),
      });
    } catch (e) {
      return null;
    }
    if (!late || (late.waiting + late.late) === 0) return { late: 0 };
    alertedAt = at.getTime();
    const userIds = (await store.listFinalDeciderUserIds()).map((u) => u.id);
    const employees = await store.listEmployeesByUserIds(userIds);
    const bucket = Math.floor(at.getTime() / ALERT_EVERY_MS);
    let told = 0;
    for (const e of employees) {
      try {
        const out = await store.createNotification({
          employee_id: e.id,
          category: 'crm_alert',
          title: 'Callback pushes are late',
          body: `${late.waiting} urgent push(es) waiting over a minute, ${late.late} dropped as too late in the last 10 minutes. Check the Team app's push worker.`,
          data: { kind: 'push_urgent_late', count: late.waiting + late.late },
          dedupe_key: `push_urgent_late:${bucket}`,
        });
        if (out) told += 1;
      } catch (err) {
        log.error(`[ess] push job: the late-push alert failed: ${err && err.message ? err.message : err}`);
      }
    }
    return { late: late.waiting + late.late, told };
  }

  async function runOnce() {
    if (running) return null;
    running = true;
    const startedAt = now();
    let ok = true;
    let result = null;
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
        ok = false;
        log.error(`[ess] push job: delivery: ${e && e.message ? e.message : e}`);
      }
      let alert = null;
      try {
        alert = await alertIfLate();
      } catch (e) {
        log.error(`[ess] push job: late-push check: ${e && e.message ? e.message : e}`);
      }
      result = { created, ...delivery, ...(alert && alert.told ? { alerted: alert.told } : {}) };
      return result;
    } finally {
      await record('push_minute', startedAt, ok, result || {});
      running = false;
    }
  }

  async function runUrgentOnce() {
    if (urgentRunning) return null;
    urgentRunning = true;
    const startedAt = now();
    let ok = true;
    let result = null;
    try {
      result = await deliverUrgent();
      return result;
    } catch (e) {
      ok = false;
      log.error(`[ess] push job: urgent delivery: ${e && e.message ? e.message : e}`);
      return null;
    } finally {
      // Every five seconds is too often to write: a run that did something, failed, or a minute's beat.
      const busy = result && Object.entries(result).some(([k, v]) => k !== 'missing' && Number(v) > 0);
      if (!ok || busy || startedAt.getTime() - urgentRecordedAt >= URGENT_RECORD_EVERY_MS) {
        urgentRecordedAt = startedAt.getTime();
        await record('push_urgent', startedAt, ok, result || {});
      }
      urgentRunning = false;
    }
  }

  const timer = setInterval(runOnce, intervalMs);
  if (typeof timer.unref === 'function') timer.unref();
  const urgentTimer = setInterval(runUrgentOnce, urgentIntervalMs);
  if (typeof urgentTimer.unref === 'function') urgentTimer.unref();
  if (immediate) {
    // The urgent lane probes the priority column first, so the minute loop's first run already
    // knows whether to filter urgent rows out.
    runUrgentOnce().finally(() => runOnce());
  }

  return {
    runOnce,
    runUrgentOnce,
    stop: () => {
      clearInterval(timer);
      clearInterval(urgentTimer);
    },
  };
}

module.exports = { startPushJob, collapseKeyFor, MAX_ATTEMPTS, PRIORITY_WINDOW_MS, URGENT_INTERVAL_MS, URGENT_TTL_MS };
