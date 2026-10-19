const { istDay } = require('../lib/time');
const { notifyAckReminder, notifyPollClosed, notifyAnnouncement } = require('../lib/wallNotify');
const { resolveAudience, waitingOn } = require('../lib/wallAudience');

/**
 * The Wall's scheduler (tasks F4, F5): one small job in the same shape as the on-duty job
 * (src/jobs/onDuty.js), running inside the ESS process. It does three things, in this order:
 *
 *   1. **Publishes scheduled announcements** whose time has arrived: the audience is resolved,
 *      its rows are written, and everybody hears. Doing it here rather than at create time is
 *      what "published now or scheduled" means (F5).
 *   2. **Reminds those who have not acknowledged** an announcement whose closing date is within
 *      the reminder window, once each (F5). Who has not: an audience row with no read row whose
 *      ack_at is set.
 *   3. **Closes polls** whose closing day has arrived, and tells those who voted (F4). The poll
 *      is "closed" as soon as its day has passed, so nothing is written to close it -- what this
 *      adds is the notification, once.
 *
 * Idempotent by construction: a published announcement is no longer due, a reminded one carries
 * reminded_at, and a closed poll is only notified while it is not (a row is written per voter as
 * the notification itself, so the job cannot notify twice).
 *
 * One instance only (ecosystem.config.cjs, fork mode), as for the on-duty and push jobs: a second
 * ESS process would run it twice, which is harmless for the data and pointless for the work.
 */

const HOUR_MS = 60 * 60 * 1000;
/** A closing date within this many days gets its reminder. */
const REMIND_WITHIN_DAYS = 2;
const REMIND_BATCH = 200;

/**
 * @param {object} deps
 * @param {object} deps.store
 * @param {() => Date} [deps.now]
 * @param {object} [deps.log]      console by default; tests pass a spy
 * @param {number} [deps.intervalMs]
 * @param {boolean} [deps.immediate]  run once at start (production); tests may switch it off
 */
function startWallJob({ store, now = () => new Date(), log = console, intervalMs = HOUR_MS, immediate = true }) {
  let running = false;

  /** Every scheduled announcement whose time has arrived is published, once. */
  async function publishDue() {
    const rows = await store.listDueAnnouncements(now().toISOString(), 50);
    let published = 0;
    for (const row of rows) {
      const at = now().toISOString();
      const saved = await store.publishAnnouncement(row.id, at);
      if (!saved) continue; // somebody else got there first
      try {
        const people = await resolveAudience(store, saved.audience);
        if (people.length) {
          await store.addAudienceRows(people.map((p) => ({ announcement_id: saved.id, employee_id: p.id })));
        }
        await notifyAnnouncement({
          store,
          announcement: saved,
          employeeIds: people.map((p) => p.id),
          needsAck: saved.needs_ack === true,
        });
        published += 1;
      } catch (e) {
        log.error(`[ess] wall job: publishing ${row.id} failed: ${e && e.message ? e.message : e}`);
      }
    }
    return published;
  }

  /** Those who have not acknowledged, on the closing day and the days just before it. */
  async function remindAcks() {
    const today = istDay(now());
    const days = [];
    for (let i = 0; i < REMIND_WITHIN_DAYS + 1; i += 1) {
      const d = new Date(Date.parse(`${today}T00:00:00Z`) + i * 86400000).toISOString().slice(0, 10);
      days.push(d);
    }
    let sent = 0;
    for (const day of days) {
      const rows = await store.listAckAnnouncementsClosingOn(day);
      for (const row of rows) {
        // Once a day is enough: the row's own stamp says the last time.
        const remindedToday = row.reminded_at && String(row.reminded_at).slice(0, 10) === today;
        if (remindedToday) continue;
        const waiting = (await waitingOn(store, row.id)).slice(0, REMIND_BATCH);
        if (!waiting.length) {
          await store.markAnnouncementReminded(row.id, now().toISOString());
          continue;
        }
        try {
          await notifyAckReminder({ store, announcement: row, employeeIds: waiting });
          await store.markAnnouncementReminded(row.id, now().toISOString());
          sent += waiting.length;
        } catch (e) {
          log.error(`[ess] wall job: reminding for ${row.id} failed: ${e && e.message ? e.message : e}`);
        }
      }
    }
    return sent;
  }

  /**
   * Polls whose closing day has arrived: their voters hear once. The notification row itself is
   * what makes it once -- a re-run writes nothing new for a voter who already has one.
   */
  async function closePolls() {
    const today = istDay(now());
    const rows = await store.listPollsClosingOn(today);
    let closed = 0;
    for (const row of rows) {
      try {
        const votes = await store.listPollVoters(row.id);
        const voters = [...new Set(votes.map((v) => v.voter_employee_id))];
        if (!voters.length) continue;
        await notifyPollClosedOnce({ store, poll: row, voterEmployeeIds: voters });
        closed += 1;
      } catch (e) {
        log.error(`[ess] wall job: closing poll ${row.id} failed: ${e && e.message ? e.message : e}`);
      }
    }
    return closed;
  }

  async function runOnce() {
    if (running) return null;
    running = true;
    try {
      const published = await publishDue().catch((e) => {
        log.error(`[ess] wall job: scheduled announcements: ${e && e.message ? e.message : e}`);
        return 0;
      });
      const reminded = await remindAcks().catch((e) => {
        log.error(`[ess] wall job: acknowledgement reminders: ${e && e.message ? e.message : e}`);
        return 0;
      });
      const polls = await closePolls().catch((e) => {
        log.error(`[ess] wall job: closing polls: ${e && e.message ? e.message : e}`);
        return 0;
      });
      if (published || reminded || polls) {
        log.log(`[ess] wall job: published ${published}, reminded ${reminded}, closed ${polls}`);
      }
      return { published, reminded, polls };
    } finally {
      running = false;
    }
  }

  const timer = setInterval(runOnce, intervalMs);
  if (typeof timer.unref === 'function') timer.unref();
  if (immediate) runOnce();

  return { runOnce, stop: () => clearInterval(timer) };
}

/**
 * 'The poll has closed' to those who voted, once each: the notification's own data key makes the
 * repeat harmless (the same poll, the same person), so a restart cannot notify twice.
 */
async function notifyPollClosedOnce({ store, poll, voterEmployeeIds }) {
  const already = await store.listNotificationsWithData(voterEmployeeIds, 'polls', 'post_id', poll.id);
  const told = new Set(already.map((n) => n.employee_id));
  await notifyPollClosed({
    store,
    poll,
    voterEmployeeIds: voterEmployeeIds.filter((id) => !told.has(id)),
  });
}

module.exports = { startWallJob, REMIND_WITHIN_DAYS };
