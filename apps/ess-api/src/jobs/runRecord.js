const { istDay } = require('../lib/time');

/**
 * The job run record (team_app #49, F-51): the row in hr_ess_job_runs that says a job has
 * already done this period's work. Every deploy restarts the ESS process, and each job runs once
 * at boot as well as on its timer (src/server.js); the weekly missing-documents reminder would
 * otherwise tell the whole staff again after every deploy.
 *
 * The claim is an insert of (job, period_key), which the table's primary key makes unique: the
 * first process to insert does the work, and every process started later in the same period
 * finds the row and skips. The period is worked out in IST (India time, UTC+5:30), because that
 * is the day RVM's staff live by: the ISO week for a weekly job, the day for a daily one.
 *
 * Before the migration is applied, the store answers 503 MODULE_NOT_INSTALLED; the job then runs
 * exactly as before and one warning per process names the migration (merges deploy at once and KP
 * applies migrations by hand afterwards, ADR-0011, ADR-0021).
 */

/** One warning per process, however many times a job asks before the migration is applied. */
let warnedMissingTable = false;

/** Postgres's and PostgREST's own "there is no such table" codes. */
const MISSING_TABLE_CODES = new Set(['PGRST205', '42P01']);

/** Whether a store failure means hr_ess_job_runs has not been created yet. */
function isMissingTable(e) {
  if (!e) return false;
  if (e.code === 'MODULE_NOT_INSTALLED') return true;
  if (MISSING_TABLE_CODES.has(e.code)) return true;
  return /does not exist/i.test(String(e.message || ''));
}

/**
 * The ISO week of an instant, in IST, as 'YYYY-Www'. Monday starts the week, and a week belongs
 * to the year its Thursday falls in, so 31 Dec 2026 and 1 Jan 2027 are one week ('2026-W53').
 */
function periodKeyWeekly(date) {
  const day = istDay(date);
  const thursday = new Date(`${day}T00:00:00Z`);
  // ISO weekday: Monday is 1 and Sunday is 7, where getUTCDay() calls Sunday 0.
  const weekday = thursday.getUTCDay() || 7;
  // Move to this week's Thursday: its year is the ISO week's year, whatever the day's own is.
  thursday.setUTCDate(thursday.getUTCDate() + 4 - weekday);
  const year = thursday.getUTCFullYear();
  const week = Math.ceil(((thursday.getTime() - Date.UTC(year, 0, 1)) / 86400000 + 1) / 7);
  return `${year}-W${String(week).padStart(2, '0')}`;
}

/** The IST calendar day of an instant, as 'YYYY-MM-DD', for a job that runs daily. */
function periodKeyDaily(date) {
  return istDay(date);
}

/**
 * Claim this period's run. true when the job may do its work: the row was inserted, or this
 * process cannot record runs at all (the migration is pending, or the database answered
 * something unexpected). false when another run already holds the period, which is the whole
 * point: a restarted process sends nothing.
 *
 * @param {object} store
 * @param {string} job        'documents_weekly', and the like
 * @param {string} periodKey  'YYYY-Www' or 'YYYY-MM-DD'
 * @returns {Promise<boolean>}
 */
async function claimRun(store, job, periodKey) {
  try {
    return (await store.createJobRun({ job, period_key: periodKey })) !== false;
  } catch (e) {
    if (isMissingTable(e)) {
      if (!warnedMissingTable) {
        warnedMissingTable = true;
        console.warn(`[ess] job runs are not recorded: apply db/migrations/20261211000000_hr_ess_job_runs.sql (the ${job} job runs as before).`);
      }
      return true;
    }
    // A database hiccup must not silence the reminder for the whole period: the job runs as it
    // did before the record existed, with the same duplicate risk as a second process.
    console.error(`[ess] job run ${job} ${periodKey} could not be claimed; running anyway: ${e && e.message ? e.message : e}`);
    return true;
  }
}

/**
 * Set how the run ended. Never throws: the work is done either way, and a row left 'running'
 * still holds the period against a second run.
 *
 * @param {object} store
 * @param {string} job
 * @param {string} periodKey
 * @param {'done'|'failed'} status
 */
async function finishRun(store, job, periodKey, status) {
  try {
    await store.finishJobRun(job, periodKey, { status, finished_at: new Date().toISOString() });
  } catch {
    // Nothing to do: the store has logged why, and the claim stands.
  }
}

module.exports = { periodKeyWeekly, periodKeyDaily, claimRun, finishRun };
