const { MESSAGES, asyncRoute } = require('../lib/errors');
const { oneQueryValue, invalid } = require('../lib/validate');
const { istDay } = require('../lib/time');
const { weekBounds, teamDayState } = require('../policy/me');
const { contactContext } = require('../lib/contactCards');

/**
 * Task E6 and H4: Team today and Off this week.
 *
 * Team today: the caller's direct reports; a HoO sees their whole branch instead (H4). Anyone
 * with neither gets an empty view (`scope: null`), which is what the app hides.
 * States: in / done / not_in / on_leave / week_off / holiday, plus the day's late flag.
 * The leave's TYPE and reason are never read, let alone sent.
 *
 * Off this week: who is on leave in the IST week (Monday to Sunday), for the caller's reports
 * or, with none, the peers under the same manager. Names and days only.
 */

const FILTERS = Object.freeze(['all', 'not_in', 'late', 'on_leave']);

const teamEntry = (card, row) => ({
  ...card,
  state: teamDayState(row),
  late: Boolean(row && row.late_minutes != null && !row.late_excused),
  late_minutes: row?.late_minutes ?? null,
  first_in: row?.first_in ?? null,
  last_out: row?.last_out ?? null,
});

/** GET /api/ess/team/today?filter=all|not_in|late|on_leave */
function teamToday({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { kind, role, employee } = req.auth;
    const today = istDay(now());
    const filterRaw = oneQueryValue(req.query.filter);
    const filter = filterRaw === undefined || filterRaw === '' ? 'all' : filterRaw;
    if (!FILTERS.includes(filter)) throw invalid(MESSAGES.TEAM_FILTER);

    const ctx = await contactContext({ store, viewer: employee, role, today });
    const reports = ctx.people.filter((e) => ctx.onStrength(e) && e.manager_id === employee.id);
    const isHoo = kind === 'portal' && role === 'hoo';
    let scope = null;
    let roster = [];
    // A HoO's view is their branch (H4), whether or not they also have reports.
    if (isHoo && employee.branch_id) {
      scope = 'branch';
      roster = ctx.people.filter((e) => ctx.onStrength(e) && e.branch_id === employee.branch_id);
    } else if (reports.length) {
      scope = 'reports';
      roster = reports;
    }

    const empty = { scope: null, date: today, filter, counts: { all: 0, not_in: 0, late: 0, on_leave: 0 }, people: [] };
    if (!roster.length) return res.json(empty);

    const rows = await store.listTeamDayRows(roster.map((e) => e.id), today);
    const rowBy = new Map(rows.map((r) => [r.employee_id, r]));
    const entries = roster
      .map((e) => teamEntry(ctx.card(e), rowBy.get(e.id) || null))
      .sort((a, b) => String(a.full_name || '').localeCompare(String(b.full_name || '')));

    const counts = {
      all: entries.length,
      not_in: entries.filter((x) => x.state === 'not_in').length,
      late: entries.filter((x) => x.late).length,
      on_leave: entries.filter((x) => x.state === 'on_leave').length,
    };
    const shown = entries.filter((x) => (
      filter === 'all' ? true
        : filter === 'not_in' ? x.state === 'not_in'
          : filter === 'late' ? x.late
            : x.state === 'on_leave'
    ));
    res.json({ scope, date: today, filter, counts, people: shown });
  });
}

/** GET /api/ess/team/off-this-week */
function teamOffThisWeek({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee, role } = req.auth;
    const today = istDay(now());
    const ctx = await contactContext({ store, viewer: employee, role, today });
    const week = weekBounds(today);

    const reports = ctx.people.filter((e) => ctx.onStrength(e) && e.manager_id === employee.id);
    let scope = null;
    let subjects = [];
    if (reports.length) {
      scope = 'reports';
      subjects = reports;
    } else if (employee.manager_id) {
      scope = 'peers';
      subjects = ctx.people.filter((e) => ctx.onStrength(e) && e.id !== employee.id
        && e.manager_id === employee.manager_id);
    }
    if (!subjects.length) return res.json({ week, scope: null, people: [] });

    const days = await store.listLeaveDaysBetween(subjects.map((e) => e.id), week.from, week.to);
    const byEmployee = new Map();
    for (const d of days) {
      if (!byEmployee.has(d.employee_id)) byEmployee.set(d.employee_id, []);
      byEmployee.get(d.employee_id).push(d.day);
    }
    const people = subjects
      .filter((e) => byEmployee.has(e.id))
      .sort((a, b) => String(a.full_name || '').localeCompare(String(b.full_name || '')))
      .map((e) => ({ ...ctx.card(e), days: byEmployee.get(e.id).sort() }));
    res.json({ week, scope, people });
  });
}

module.exports = { teamToday, teamOffThisWeek, FILTERS };
