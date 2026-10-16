const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const { bodyWith, optionalText, chars, invalid, isUuid, oneQueryValue } = require('../lib/validate');
const { istDay, isCalendarDay, addDays, istDayStart } = require('../lib/time');
const { LIST_LIMITS } = require('../lib/store');

/**
 * Task B14, decision 6 (KP, 16 Oct): the app refuses a punch whose location the phone says is
 * mocked, and reports the attempt here for HR. The Scheduler's punch API cannot take a mock flag
 * without a change (ADR-0018), so HR learns of it from this table instead of the punch log.
 *
 * Punches only: whether mocked pings are reported too is still open (docs/04-build-plan.md,
 * decision owed 4), so `kind` takes 'punch' alone until KP decides.
 *
 * HR reads the reports with the location trail's roles: HR, the CEO and super admins
 * (policy/hrAccess.js ATTENDANCE_ROLES), as today (docs/03-decisions.md).
 */

const KINDS = ['punch'];

/** How far back HR's list goes when no dates are given: the Scheduler's override history default (attendanceAdminController.js:173-174). */
const DEFAULT_DAYS = 30;
/** The longest span one list covers. */
const MAX_RANGE_DAYS = 366;

/**
 * The days a list may ask for. Postgres cannot take every day JavaScript can: year 0 and anything
 * BC as a timestamptz (22008, 22007), and 9999-12-31 runs into year 10000 a day later, which
 * JavaScript writes as +010000. Reports began in 2026, so these bounds lose nothing.
 */
const FIRST_LIST_DAY = '2000-01-01';
const LAST_LIST_DAY = '2099-12-31';

/**
 * The phone clocks kept. JavaScript reads years 0 to 275760, and BC ones, that Postgres will not
 * store (22008, 22007, 22009); a report must not be lost for its phone's clock. Anything outside
 * these is stored as null, as an unreadable clock is. 1970 is kept: a phone whose clock was reset
 * says so, and that is worth seeing.
 */
const FIRST_CLIENT_AT = Date.parse('1970-01-01T00:00:00Z');
const END_CLIENT_AT = Date.parse('2100-01-01T00:00:00Z');

/** A coordinate, or null when not sent; undefined when sent but unusable. */
function coordinate(v, limit) {
  if (v === undefined || v === null) return null;
  return typeof v === 'number' && Number.isFinite(v) && v >= -limit && v <= limit ? v : undefined;
}

/**
 * POST /api/ess/attendance/mock-location
 *   { kind: 'punch', latitude?, longitude?, accuracy_m?, client_at?, provider?, app_version?, install_id? }
 *
 * The location is the mocked one the phone reported, kept because where a fake fix pretends to
 * be is itself evidence. client_at is the phone's clock: kept beside the server's reported_at and
 * never trusted, and an unreadable value is stored as null rather than refused, as the
 * Scheduler's punch does with its own client_at (attendancePunchController.js:331). Unlike there,
 * a time Postgres cannot store counts as unreadable (FIRST_CLIENT_AT), so the report still goes in.
 */
function reportMockLocation({ store }) {
  return asyncRoute(async (req, res) => {
    const body = bodyWith(req, ['kind', 'latitude', 'longitude', 'accuracy_m', 'client_at', 'provider', 'app_version', 'install_id']);
    if (!KINDS.includes(body.kind)) throw invalid(MESSAGES.MOCK_KIND);

    const latitude = coordinate(body.latitude, 90);
    const longitude = coordinate(body.longitude, 180);
    const accuracy = body.accuracy_m === undefined || body.accuracy_m === null ? null
      : (typeof body.accuracy_m === 'number' && Number.isFinite(body.accuracy_m) && body.accuracy_m >= 0 && body.accuracy_m <= 1e6 ? body.accuracy_m : undefined);
    if (latitude === undefined || longitude === undefined || accuracy === undefined || (latitude === null) !== (longitude === null)) {
      throw invalid(MESSAGES.MOCK_LOCATION);
    }

    const short = (v, max) => {
      const s = optionalText(v);
      if (s === undefined || (s && chars(s) > max)) throw invalid(MESSAGES.MOCK_TEXT);
      return s;
    };
    const provider = short(body.provider, 80);
    const appVersion = short(body.app_version, 40);
    const installId = short(body.install_id, 128);

    const clientMs = typeof body.client_at === 'string' ? Date.parse(body.client_at) : NaN;
    const clientAt = clientMs >= FIRST_CLIENT_AT && clientMs < END_CLIENT_AT ? new Date(clientMs).toISOString() : null;

    const { employee } = req.auth;
    const created = await store.createMockReport({
      employee_id: employee.id,
      // The branch the person belonged to when it happened, as a punch row keeps its own
      // (20261020000000_hr_attendance_punch.sql:103), so a later move does not carry it away.
      branch_id: employee.branch_id ?? null,
      kind: body.kind,
      client_at: clientAt,
      latitude,
      longitude,
      accuracy_m: accuracy,
      provider,
      app_version: appVersion,
      install_id: installId,
    });
    res.status(201).json({ report: { id: created.id, reported_at: created.reported_at } });
  });
}

/** The IST days a list covers, from ?from and ?to, defaulting to the last DEFAULT_DAYS days. */
function dayRange(query, today) {
  const rawFrom = oneQueryValue(query.from);
  const rawTo = oneQueryValue(query.to);
  for (const v of [rawFrom, rawTo]) {
    if (v !== undefined && (v === null || !isCalendarDay(v))) throw invalid(MESSAGES.DATE_FORMAT);
    if (v !== undefined && (v < FIRST_LIST_DAY || v > LAST_LIST_DAY)) throw invalid(MESSAGES.DATE_OUT_OF_RANGE);
  }
  const to = rawTo ?? today;
  const from = rawFrom ?? addDays(to, -DEFAULT_DAYS);
  if (from > to || addDays(from, MAX_RANGE_DAYS) < to) throw invalid(MESSAGES.DATE_RANGE);
  return { from, to };
}

/** GET /api/ess/hr/mock-location-reports?from=&to=&branch_id=: newest first, with whose report each is. */
function listMockLocationReports({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { from, to } = dayRange(req.query, istDay(now()));
    const branchParam = oneQueryValue(req.query.branch_id);
    if (branchParam !== undefined && !isUuid(branchParam)) throw invalid(MESSAGES.BRANCH_ID);
    const branchId = branchParam ? branchParam.toLowerCase() : null;
    if (branchId && !(await store.getBranch(branchId))) throw new HttpError(404, 'NOT_FOUND', MESSAGES.BRANCH_NOT_FOUND);

    const rows = await store.listMockReports({
      fromIso: istDayStart(from).toISOString(),
      toIso: istDayStart(addDays(to, 1)).toISOString(),
      branchId,
    });
    const truncated = rows.length > LIST_LIMITS.mockReports;
    const shown = rows.slice(0, LIST_LIMITS.mockReports);
    const people = new Map((await store.listEmployeeCards(shown.map((r) => r.employee_id))).map((e) => [e.id, e]));
    const branches = new Map((await store.listBranches(shown.map((r) => r.branch_id))).map((b) => [b.id, b]));
    res.json({
      from,
      to,
      reports: shown.map((r) => {
        const person = people.get(r.employee_id);
        const branch = r.branch_id ? branches.get(r.branch_id) : null;
        return {
          id: r.id,
          reported_at: r.reported_at,
          client_at: r.client_at ?? null,
          kind: r.kind,
          latitude: r.latitude ?? null,
          longitude: r.longitude ?? null,
          accuracy_m: r.accuracy_m ?? null,
          provider: r.provider ?? null,
          app_version: r.app_version ?? null,
          install_id: r.install_id ?? null,
          employee: person ? { id: person.id, full_name: person.full_name, employee_code: person.employee_code ?? null } : null,
          branch: branch ? { id: branch.id, name: branch.name } : null,
        };
      }),
      truncated,
    });
  });
}

module.exports = { reportMockLocation, listMockLocationReports, dayRange, DEFAULT_DAYS, MAX_RANGE_DAYS, FIRST_LIST_DAY, LAST_LIST_DAY };
