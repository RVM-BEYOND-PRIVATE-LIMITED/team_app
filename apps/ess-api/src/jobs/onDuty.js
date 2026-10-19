const { istDay } = require('../lib/time');
const { HALF_DAY_MINUTES } = require('../policy/attendance');

/**
 * The on-duty morning job (tasks C3, C7): every approved on_duty request for today whose day has
 * no row yet is written as present, with the place as its note -- through the Scheduler's
 * override function, so the day is locked exactly as HR's own override locks it. A future day is
 * never written at approval time (an override would lock a day that has not happened; ADR-0020),
 * so this is what puts the day in the sheet on the day itself.
 *
 * It runs once at boot and then hourly; it is idempotent (the SQL only matches requests whose day
 * still has no row) and re-runnable by hand. Failures are logged for HR: each goes to the pm2 log
 * and to hr_ess_audit as 'on_duty.failed', best effort, and the month of each written day is
 * recomputed like the decide route's (late, early, the third-late half day).
 *
 * One instance only (ecosystem.config.cjs, fork mode): two ESS processes would run it twice,
 * which is safe but pointless.
 */

const HOUR_MS = 60 * 60 * 1000;

/**
 * @param {object} deps
 * @param {object} deps.store      the store (applyOnDutyDays, recomputeAttendance, writeAudit)
 * @param {() => Date} [deps.now]
 * @param {object} [deps.log]      console by default; tests pass a spy
 * @param {number} [deps.intervalMs]
 * @param {boolean} [deps.immediate]  run once at start (production); tests may switch it off
 * @returns {{ runOnce: () => Promise<object|null>, stop: () => void }}
 */
function startOnDutyJob({ store, now = () => new Date(), log = console, intervalMs = HOUR_MS, immediate = true }) {
  let running = false;

  async function runOnce() {
    if (running) return null;
    running = true;
    try {
      const today = istDay(now());
      const out = await store.applyOnDutyDays(today, now().toISOString());
      if (!out) return null;
      const applied = Number(out.applied) || 0;
      const failed = Array.isArray(out.failed) ? out.failed : [];
      const employees = Array.isArray(out.employees) ? out.employees : [];
      if (applied > 0) {
        log.log(`[ess] on-duty job: wrote ${applied} day(s) for ${today}`);
        for (const employeeId of employees) {
          try {
            await store.recomputeAttendance({ employeeIds: [employeeId], day: today, today, halfDayMinutes: HALF_DAY_MINUTES });
          } catch (e) {
            log.error(`[ess] on-duty job: recompute for ${employeeId} failed: ${e && e.message ? e.message : e}`);
          }
        }
      }
      for (const f of failed) {
        const where = `request ${f.request_id || '-'} (${f.employee_id || '-'}): ${f.error || 'unknown'}`;
        log.error(`[ess] on-duty job failed for ${where}`);
        try {
          await store.writeAudit({
            actor_user_id: null,
            actor_employee_id: null,
            actor_name: 'Team RVM (on-duty job)',
            action: 'on_duty.failed',
            target_employee_id: f.employee_id ?? null,
            details: { request_id: f.request_id ?? null, error: String(f.error || '').slice(0, 300) },
          });
        } catch {
          // The store has already logged why; the pm2 line above is the record.
        }
      }
      return out;
    } catch (e) {
      // A missing function or table (the deploy window) lands here too: logged, retried next hour.
      log.error(`[ess] on-duty job: ${e && e.message ? e.message : e}`);
      return null;
    } finally {
      running = false;
    }
  }

  const timer = setInterval(runOnce, intervalMs);
  if (typeof timer.unref === 'function') timer.unref();
  // And once at boot, so a restart after 00:30 does not wait an hour to catch up.
  if (immediate) runOnce();

  return { runOnce, stop: () => clearInterval(timer) };
}

module.exports = { startOnDutyJob };
