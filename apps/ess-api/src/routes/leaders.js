const { asyncRoute } = require('../lib/errors');
const { istDay } = require('../lib/time');
const { teamDayState, weekBounds } = require('../policy/me');

/**
 * Phase 2D (task H5): the leaders' overview. One read of the whole organisation, in counts only
 * -- the attendance states of today, how many are off this week, and what waits in the approval
 * queue. No names, no pay, no performance: a number cannot leak what a card would (H5's brief).
 * A person the sheet has no row for reads as not in, exactly as Team today reads one.
 */

/** How many pending requests the queue count reads before it stops; 1,000 is far past any queue. */
const PENDING_LIMIT = 1000;

/** GET /api/ess/leaders/overview */
function leadersOverview({ store, now }) {
  return asyncRoute(async (req, res) => {
    const today = istDay(now());
    const people = await store.listActiveEmployees();
    const ids = people.map((e) => e.id);

    const dayRows = await store.listTeamDayRows(ids, today);
    const rowBy = new Map(dayRows.map((r) => [r.employee_id, r]));
    const attendanceToday = { in: 0, done: 0, not_in: 0, on_leave: 0, week_off: 0, holiday: 0 };
    for (const e of people) attendanceToday[teamDayState(rowBy.get(e.id) || null)] += 1;

    const week = weekBounds(today);
    const offDays = await store.listLeaveDaysBetween(ids, week.from, week.to);
    const offThisWeek = new Set(offDays.map((d) => d.employee_id)).size;

    const [pendingAttendance, pendingLeave] = await Promise.all([
      store.listPendingRequestsSince('attendance', now().toISOString(), PENDING_LIMIT),
      store.listPendingRequestsSince('leave', now().toISOString(), PENDING_LIMIT),
    ]);
    const oldest = [...pendingAttendance, ...pendingLeave]
      .map((r) => Date.parse(r.created_at))
      .sort((a, b) => a - b)[0];
    const pending = {
      attendance: pendingAttendance.length,
      leave: pendingLeave.length,
    };
    pending.total = pending.attendance + pending.leave;
    pending.oldest_days = oldest === undefined
      ? null
      : Math.max(0, Math.floor((Date.parse(`${today}T00:00:00+05:30`) - oldest) / 86400000));

    res.json({
      headcount: people.length,
      attendance_today: attendanceToday,
      off_this_week: offThisWeek,
      pending,
    });
  });
}

module.exports = { leadersOverview };
