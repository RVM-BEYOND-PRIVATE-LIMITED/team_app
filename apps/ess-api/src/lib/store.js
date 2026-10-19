const { createClient } = require('@supabase/supabase-js');
const { HttpError, MESSAGES } = require('./errors');

/**
 * The ESS's reads and writes on the Scheduler's database, which stays the system of record
 * (ADR-0003).
 *
 * The ESS reads the Scheduler's tables. It writes its own hr_ess_* tables (ADR-0021), and one
 * Scheduler table, by one path only: HR's bulk phone reset makes exactly the update the
 * Scheduler's own reset makes on hr_attendance_devices (revokeActiveDevices below; KP, 16 Oct,
 * decision 11; ADR-0018).
 *
 * Every read names its columns, and nothing selects '*'. A select('*') is how the Scheduler's
 * marking roster came to hand out password hashes (J2), and a list also means that a column
 * added to one of these tables later cannot reach a reply by accident. hr_attendance_accounts
 * holds a password hash, so it is read for its status and cut-off only, and asked whether a
 * hash exists without the hash ever being sent; hr_attendance_devices holds the hash of each
 * phone's token, so it is never read whole either.
 *
 * Tables and columns checked against Scheduler_Backend supabase/migrations at c28b9ca:
 *   users                   id, username, phone_number, role, faculty_id:
 *                           20251215134244_remote_schema.sql:854-863; location_id:
 *                           20260514000000_schema_gaps.sql:13-14; email, password_changed_at:
 *                           20260909000000_user_profile_security.sql:40-49
 *   locations               id, name: 20260514000000_schema_gaps.sql:42-45
 *   hr_employees            20260826000001_hrms_tables.sql; user_id from
 *                           20260910000000_hr_employee_user_link.sql; the employment_status
 *                           values from 20260917000000_hr_employment_lifecycle.sql
 *   hr_branches, hr_departments  id, name: 20260826000001_hrms_tables.sql
 *   hr_attendance_accounts  20261021000000_hr_attendance_accounts.sql
 *   hr_attendance_devices   20261020000000_hr_attendance_punch.sql:77-93
 *   hr_staff_attendance     20261015000004_hr_staff_attendance.sql, with the punch columns of
 *                           20261020000000:62-66 and the rule columns of 20261022000000:106-123
 *   hr_attendance_remarks   HR's remark: 20261022000000_hr_attendance_shifts.sql:151-160
 *   hr_attendance_employee_remarks  the employee's own: 20261023000000
 * and team_app's own hr_ess_* tables in db/migrations (hr_ess_sessions:
 * 20261101000000_hr_ess_sessions.sql; the others: 20261105000000 to 20261105000003).
 */
const COLUMNS = Object.freeze({
  user: 'id, role, faculty_id',
  // The username is what the Scheduler records as the actor's name (attendanceAdminController.js:18).
  userLogin: 'id, username',
  // What a minted portal token is built from (lib/accessTokens.js), and when the password last
  // changed, which ends a kept sign-in made before it (policy/sessions.js passwordChangedSince).
  userForToken: 'id, username, role, location_id, faculty_id, password_changed_at',
  // What the sign-in resolver needs to know about an account, and no more: never its username,
  // phone or email, which it is found by and must not hand back.
  userForSignIn: 'id, role, location_id',
  employee: 'id, full_name, employee_code, designation, employment_status, date_of_exit, is_archived, branch_id, department_id, manager_id',
  // The attendance sign-in's own columns (attendanceOtpController.js:134) less the extra phones,
  // which only decide between two of its refusals. Matched in memory and never sent anywhere.
  employeeForSignIn: 'id, employee_code, email, phone, user_id, is_archived, employment_status, date_of_exit',
  report: 'id, employment_status, date_of_exit, is_archived',
  employeeName: 'id, full_name',
  // What HR's lists show about a person: never their phone, email or anything else on the record.
  employeeCard: 'id, full_name, employee_code, branch_id',
  branch: 'id, name',
  department: 'id, name',
  location: 'id, name',
  // password_set_at, and never password_hash: a 'pw' session already proves a hash existed, so
  // whether the person chose their own password is all the first-time check needs.
  attendanceAccount: 'id, employee_id, status, sessions_valid_from, password_set_at',
  attendanceLogin: 'employee_id, status',
  // Every column but refresh_hash and password_fingerprint: a session is found by its hash and
  // never hands it back, and the fingerprint is compared inside the database only.
  session: 'id, family_id, employee_id, login_kind, user_id, location_name, method, signed_in_at, install_id, device_label, created_at, last_used_at, expires_at, revoked_at, revoked_reason',
  sessionStart: 'id, created_at',
  // Never token_hash: it is what a phone's cookie is checked against. Neither user_agent nor
  // bound_ip either: HR's reset needs to know whose phone it is and when it was last used.
  device: 'id, employee_id, status, bound_at, last_seen_at, revoked_at, revoked_by_name, revoke_reason',
  revokedDevice: 'id, employee_id',
  // The day row as the punch screen reads it (attendancePunchController.js:178-179), plus note,
  // which the punch screen leaves out and B1 serves.
  day: 'day, status, leave_type, source, first_in, last_out, worked_minutes, note, '
    + 'late_minutes, early_exit_minutes, late_count, late_half_day, late_excused, shift_start, shift_end',
  hrRemark: 'remarks, updated_at',
  myRemark: 'day, remarks, updated_at',
  // resolved_by_user_id is kept for the record and never sent: the name is what people read.
  dataRequest: 'id, employee_id, kind, details, status, created_at, resolved_at, resolved_by_name, resolution_note',
  personal: 'employee_id, date_of_birth, blood_group, address_line1, address_line2, city, state, pincode, '
    + 'emergency_name, emergency_relation, emergency_phone, updated_at, updated_by_name',
  mockReport: 'id, employee_id, branch_id, reported_at, client_at, kind, latitude, longitude, accuracy_m, provider, app_version, install_id',
  mockReportCreated: 'id, reported_at',
  // C6: the numbers HR can change. updated_by_user_id is kept for the record and never sent.
  requestLimit: 'type, limit_count, limit_minutes, updated_at, updated_by_name',
  // C1-C12: a request as the app reads it. day_before and day_written_at stay server-side (HR's
  // cancel reads them inside SQL), and the decided_by and cancelled_by account ids are never sent.
  attendanceRequest: 'id, employee_id, type, status, day, reason, place, fix_in, fix_out, '
    + 'decided_by_name, decided_at, decision_note, cancelled_by_name, cancelled_at, cancel_reason, created_at, updated_at',
  leaveRequest: 'id, employee_id, type, status, day, reason, '
    + 'decided_by_name, decided_at, decision_note, cancelled_by_name, cancelled_at, cancel_reason, created_at, updated_at',
  // The counters and duplicate checks read these.
  requestFacts: 'id, employee_id, type, status, day',
  archive: 'id, family, request_id, employee_id',
  // What ensureSnapshot reads before it copies a shift onto a day (attendanceRules.js:214-236).
  daySnapshot: 'id, source, shift_start',
  employeeShifts: 'id, shift_id, saturday_shift_id, sunday_shift_id, week_off_days',
  shift: 'id, start_time, end_time, grace_minutes, is_active',
  holiday: 'id, day, name, branch_id',
  // The approvals Inbox's context: a day's late marks, and who else is off a day.
  dayLate: 'employee_id, day, late_minutes, late_count, late_half_day, late_excused',
  dayLeave: 'employee_id, day',
  leaveOnDay: 'employee_id, day, status',
});

/**
 * A missing table or column means the code is live before its migration: merges deploy at
 * once and KP applies migrations by hand afterwards (ADR-0011, ADR-0021). That answers 503
 * MODULE_NOT_INSTALLED, never a 500. PGRST205 and PGRST204 are PostgREST's "not in the schema
 * cache" for a table or a column, PGRST202 the same for a function; 42P01, 42703 and 42883 are
 * Postgres's own "undefined table", "undefined column" and "undefined function".
 */
const NOT_INSTALLED_CODES = new Set(['PGRST205', 'PGRST204', 'PGRST202', '42P01', '42703', '42883']);

/** The functions db/migrations/20261101000000_hr_ess_sessions.sql creates for the ESS to call. */
const SESSION_FUNCTIONS = Object.freeze({
  rotate: 'hr_ess_session_rotate',
  revoke: 'hr_ess_session_revoke',
  passwordCurrent: 'hr_ess_session_password_current',
});

/** The functions db/migrations/20261106000004_hr_ess_request_functions.sql creates. */
const REQUEST_FUNCTIONS = Object.freeze({
  decideAttendance: 'hr_ess_decide_attendance_request',
  decideLeave: 'hr_ess_decide_leave_request',
  withdrawAttendance: 'hr_ess_withdraw_attendance_request',
  withdrawLeave: 'hr_ess_withdraw_leave_request',
  cancelAttendance: 'hr_ess_cancel_attendance_request',
  cancelLeave: 'hr_ess_cancel_leave_request',
  onDutyApply: 'hr_ess_on_duty_apply',
});

/**
 * Refusals the database gives on purpose, which the routes answer as a 409 rather than as a
 * failure: the name of the key or rule is in Postgres's message, which PostgREST passes on.
 *   SIGN_IN_KEPT  a Scheduler sign-in already traded (hr_ess_sessions_sign_in_key, 23505)
 *   OPEN_LIMIT    a sixth open data request (the hr_ess_data_requests_open_limit trigger, 23514)
 *   EMERGENCY_HALF  personal details left with half an emergency contact by two saves made at
 *                   once (hr_ess_personal_details_emergency_chk, 23514)
 */
const REFUSALS = Object.freeze({
  SIGN_IN_KEPT: { code: '23505', name: 'hr_ess_sessions_sign_in_key' },
  OPEN_LIMIT: { code: '23514', name: 'hr_ess_data_requests_open_limit' },
  EMERGENCY_HALF: { code: '23514', name: 'hr_ess_personal_details_emergency_chk' },
  // The Scheduler's own one-CL-a-month index, hit when two CL approvals race (or a CL is
  // approved while somebody marks one): the decision answers 409 CL_LIMIT, as its own check does.
  CL_TAKEN: { code: '23505', name: 'uq_hr_staff_attendance_one_cl_a_month' },
  // Archiving a request twice for the same approver: the second is simply already archived.
  ARCHIVE_KEPT: { code: '23505', name: 'hr_ess_request_archives_family_request_id_employee_id_key' },
});

const isRefusal = (error, { code, name }) =>
  Boolean(error && error.code === code && String(error.message || '').includes(name));

/**
 * Matches nothing, so the sign-in resolver can make the same request whatever it found
 * (routes/signIn.js): a lookup it skipped would make "nobody" answer faster than "two people".
 */
const NIL_UUID = '00000000-0000-0000-0000-000000000000';

/**
 * How long one database request may take before it is abandoned. Without it, a database that
 * accepts the connection and then says nothing holds the request for fetch's five-minute
 * default. supabase-js still retries a failed connection a few times (1, 2 and 4 seconds
 * apart), which rides out a blip without letting an outage hang the app.
 */
const DB_REQUEST_TIMEOUT_MS = 5000;

/**
 * How many ids go into one IN filter. PostgREST takes the list in the URL, and a few hundred
 * UUIDs make a URL long enough to be refused; the Scheduler slices at the same size
 * (controllers/hr/staffAttendanceController.js:182-183).
 */
const IN_CHUNK = 150;

/** The most rows one HR list returns. One more is read, to tell the app the list was cut. */
const LIST_LIMITS = Object.freeze({
  // As many as the Scheduler's own phone list (attendanceAdminController.js:260).
  devices: 1000,
  mockReports: 500,
  dataRequests: 500,
  myDataRequests: 100,
  // My own requests, and one approver's Inbox.
  myRequests: 100,
  inbox: 100,
});

/**
 * supabase-js builds a Realtime client inside createClient, and on Node 20, which has no
 * built-in WebSocket, that throws as the server starts. The ESS never subscribes to anything,
 * so Realtime gets a transport that refuses to be used instead of a WebSocket library nothing
 * would call.
 */
class NoRealtime {
  constructor() {
    throw new Error('The ESS does not use Supabase Realtime.');
  }
}

/**
 * The refusal for a failed read or write. Never a 401: an outage must not sign anybody out.
 *
 * A data or integrity error (SQLSTATE class 22 or 23: a CHECK, a NOT NULL, a foreign key) means
 * the database refused what the ESS sent, which the ESS's own checks should have stopped. That
 * is the server's fault, not an outage, so it is a 500 rather than "cannot reach the database".
 */
function storeError(table, error) {
  if (error && NOT_INSTALLED_CODES.has(error.code)) {
    return new HttpError(
      503,
      'MODULE_NOT_INSTALLED',
      `Team RVM needs a database update that has not been applied yet (it cannot read ${table}). Ask the tech team.`,
    );
  }
  if (error && typeof error.code === 'string' && /^2[23][0-9A-Z]{3}$/.test(error.code)) {
    return new HttpError(500, 'INTERNAL_ERROR', MESSAGES.INTERNAL_ERROR);
  }
  return new HttpError(503, 'UNAVAILABLE', MESSAGES.UNAVAILABLE);
}

/** What run() answers in place of data for a refusal the caller asked to hear about. */
const REFUSED = Symbol('refused');

const chunks = (list, size = IN_CHUNK) => {
  const out = [];
  for (let i = 0; i < list.length; i += size) out.push(list.slice(i, i + size));
  return out;
};

/**
 * @param {{ supabaseUrl: string, supabaseServiceKey: string }} config
 * @param {{ client?: object }} [options]  tests pass an in-memory client in place of supabase-js
 */
function createSupabaseStore(config, { client } = {}) {
  // The service key, because every HR table is row-level-security deny-all (ADR-0005). No
  // session handling: this is a server, not a signed-in browser.
  const db = client || createClient(config.supabaseUrl, config.supabaseServiceKey, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    db: { timeout: DB_REQUEST_TIMEOUT_MS },
    realtime: { transport: NoRealtime },
  });

  /**
   * One database request. Only the table, the code and PostgREST's message are logged, never the
   * values asked with: those include refresh-token hashes and whatever was typed at sign-in.
   */
  async function run(verb, table, request, refusal = null) {
    let result;
    try {
      result = await request();
    } catch (e) {
      console.error(`[ess] ${verb} ${table} failed: ${e && e.message ? e.message : e}`);
      throw storeError(table, e);
    }
    // An answer the caller asked for (REFUSALS), not a failure: nothing to log.
    if (result.error && refusal && isRefusal(result.error, refusal)) return REFUSED;
    if (result.error) {
      console.error(`[ess] ${verb} ${table} failed: ${result.error.code || '-'} ${result.error.message || ''}`.trim());
      throw storeError(table, result.error);
    }
    return result.data;
  }

  const read = (table, build) => run('reading', table, () => build(db.from(table)));
  const write = (table, build, refusal) => run('writing', table, () => build(db.from(table)), refusal);
  /**
   * A database function. The table it carries is for the 503's words (and for tests that make one
   * table fail): the sessions functions read and write hr_ess_sessions, the request functions
   * their request table. `refusal` is a database refusal the caller answers as its own 409.
   */
  const call = (fn, args, { table = 'hr_ess_sessions', refusal = null } = {}) =>
    run('writing', table, () => db.rpc(fn, args), refusal);

  /** At most one row, or null. Every filter here is on a key that is unique in the schema. */
  const one = (table, columns, column, value) =>
    read(table, (q) => q.select(columns).eq(column, value).maybeSingle());

  const list = async (table, build) => (await read(table, build)) || [];

  /** Rows whose `column` is one of `ids`, in slices; `extend` adds the other filters. */
  async function readIn(table, columns, column, ids, extend = (q) => q) {
    const unique = [...new Set(ids.filter(Boolean))];
    const out = [];
    for (const part of chunks(unique)) {
      out.push(...((await read(table, (q) => extend(q.select(columns).in(column, part)))) || []));
    }
    return out;
  }

  return {
    getUser: (userId) => one('users', COLUMNS.user, 'id', userId),
    getUserLogin: (userId) => one('users', COLUMNS.userLogin, 'id', userId),
    getEmployeeById: (employeeId) => one('hr_employees', COLUMNS.employee, 'id', employeeId),
    // hr_employees.user_id is unique where set (hr_employees_user_id_key), so a login is at
    // most one employee.
    getEmployeeByUserId: (userId) => one('hr_employees', COLUMNS.employee, 'user_id', userId),
    getEmployeeName: (employeeId) => one('hr_employees', COLUMNS.employeeName, 'id', employeeId),
    getEmployeeCard: (employeeId) => one('hr_employees', COLUMNS.employeeCard, 'id', employeeId),
    listEmployeeCards: (employeeIds) => readIn('hr_employees', COLUMNS.employeeCard, 'id', employeeIds),
    /** Everybody whose HR record puts them at this branch, leavers included: their phones are still registered. */
    listEmployeeIdsInBranch: async (branchId) =>
      ((await read('hr_employees', (q) => q.select('id').eq('branch_id', branchId))) || []).map((e) => e.id),
    getBranch: (branchId) => one('hr_branches', COLUMNS.branch, 'id', branchId),
    listBranches: (branchIds) => readIn('hr_branches', COLUMNS.branch, 'id', branchIds),
    getDepartment: (departmentId) => one('hr_departments', COLUMNS.department, 'id', departmentId),
    getAttendanceAccount: (employeeId) => one('hr_attendance_accounts', COLUMNS.attendanceAccount, 'employee_id', employeeId),

    /**
     * The people who report to this employee and are not archived. The caller applies the full
     * on-strength rule (policy/employment.js) rather than this query repeating it as filters,
     * so the rule exists in one place.
     */
    listDirectReports: (managerId) =>
      list('hr_employees', (q) => q.select(COLUMNS.report).eq('manager_id', managerId).eq('is_archived', false)),

    /* ── the users row a minted portal token is built from (task A3) ── */

    getUserForToken: (userId) => one('users', COLUMNS.userForToken, 'id', userId),

    /* ── the sign-in resolver (task A5) ── */

    /**
     * The accounts the Scheduler's portal login would consider for a typed identifier: username
     * or login phone, compared exactly (controllers/userController.js:271-279). Two eq filters
     * rather than its or=(...), which needs the value quoted to stay a value; eq takes it as one.
     */
    findUsersByUsername: (value) => list('users', (q) => q.select(COLUMNS.userForSignIn).eq('username', value)),
    findUsersByPhoneNumber: (value) => list('users', (q) => q.select(COLUMNS.userForSignIn).eq('phone_number', value)),
    /** Stored lower-cased, so an exact match on the lower-cased value is the Scheduler's own (authSecurityController.js:139-141). */
    findUsersByEmail: (email) => list('users', (q) => q.select(COLUMNS.userForSignIn).eq('email', email)),
    /** Never empty: an empty list is asked as NIL_UUID, which matches nothing, at the same cost. */
    listUsersByIds: (ids) => list('users', (q) => q.select(COLUMNS.userForSignIn).in('id', ids.length ? ids : [NIL_UUID])),

    /**
     * Every employee not archived, matched in memory as the attendance sign-in matches them
     * (attendanceOtpController.js:132-142): a PostgREST ilike would read `_` and `*` in an address
     * as wildcards. About a hundred rows.
     */
    listEmployeesForSignIn: () => list('hr_employees', (q) => q.select(COLUMNS.employeeForSignIn).eq('is_archived', false)),
    listLocations: () => list('locations', (q) => q.select(COLUMNS.location)),
    listAttendanceLogins: () => list('hr_attendance_accounts', (q) => q.select(COLUMNS.attendanceLogin)),
    /** The logins that have a password, asked as a filter, so not one hash leaves the database. */
    listAttendanceLoginsWithPassword: () =>
      list('hr_attendance_accounts', (q) => q.select('employee_id').not('password_hash', 'is', null)),

    /* ── kept sign-ins, hr_ess_sessions (task A3) ── */

    getSessionByRefreshHash: (hash) => one('hr_ess_sessions', COLUMNS.session, 'refresh_hash', hash),
    /** A family's live row. hr_ess_sessions_live_family_key allows one, so this is at most one row. */
    getLiveSession: (familyId) =>
      read('hr_ess_sessions', (q) => q.select(COLUMNS.session).eq('family_id', familyId).is('revoked_at', null).maybeSingle()),
    listLiveSessions: (employeeId) =>
      list('hr_ess_sessions', (q) => q.select(COLUMNS.session).eq('employee_id', employeeId).is('revoked_at', null)),
    /** A family's id is its first row's, so this is when each sign-in began. */
    listSessionStarts: (familyIds) => list('hr_ess_sessions', (q) => q.select(COLUMNS.sessionStart).in('id', familyIds)),

    /**
     * false when this Scheduler sign-in has been kept before (hr_ess_sessions_sign_in_key): one
     * token is traded once. The database adds the portal password's fingerprint as the row goes in.
     */
    createSession: async (row) => (await write('hr_ess_sessions', (q) => q.insert(row), REFUSALS.SIGN_IN_KEPT)) !== REFUSED,

    /**
     * Is this portal session's password still the one it was kept with (hr_ess_session_password_current)?
     * true, false, or null for a row that is not a portal session or whose account is gone. The
     * hash and its fingerprint stay in the database.
     */
    isSessionPasswordCurrent: async (sessionId) => {
      const answer = await call(SESSION_FUNCTIONS.passwordCurrent, { p_session_id: sessionId });
      return typeof answer === 'boolean' ? answer : null;
    },

    /**
     * Retires a live row and adds the next one in its family, in one transaction
     * (hr_ess_session_rotate): null when the row was no longer live, because another refresh with
     * the same token got there first or the family has just ended.
     */
    rotateSession: async ({ sessionId, newId, refreshHash, at, expiresAt }) => {
      const rows = await call(SESSION_FUNCTIONS.rotate, {
        p_session_id: sessionId, p_new_id: newId, p_refresh_hash: refreshHash, p_now: at, p_expires_at: expiresAt,
      });
      const row = Array.isArray(rows) ? rows[0] : rows;
      return row && row.new_session_id
        ? { id: row.new_session_id, family_id: row.session_family_id, expires_at: row.new_expires_at }
        : null;
    },

    /**
     * Ends a family: its live row is revoked with the reason (hr_ess_session_revoke). With
     * `employeeId`, only a family of that employee. How many rows ended: 0 or 1.
     */
    revokeFamily: async ({ familyId, reason, at, employeeId = null }) => {
      const n = await call(SESSION_FUNCTIONS.revoke, { p_family_id: familyId, p_reason: reason, p_now: at, p_employee_id: employeeId });
      return Number(n) || 0;
    },

    /* ── B1: one of the caller's days ── */

    /** hr_staff_attendance is UNIQUE (employee_id, day) (20261015000004:27). */
    getDayRow: (employeeId, day) =>
      read('hr_staff_attendance', (q) => q.select(COLUMNS.day).eq('employee_id', employeeId).eq('day', day).maybeSingle()),
    /** HR's remark, UNIQUE (employee_id, day) (20261022000000:159). */
    getHrRemark: (employeeId, day) =>
      read('hr_attendance_remarks', (q) => q.select(COLUMNS.hrRemark).eq('employee_id', employeeId).eq('day', day).maybeSingle()),
    listMyRemarks: async (employeeId, day) =>
      (await read('hr_attendance_employee_remarks', (q) => q.select(COLUMNS.myRemark).eq('employee_id', employeeId).eq('day', day))) || [],

    /* ── B8: registered phones ── */

    /**
     * Registered phones, newest first, optionally only these employees' and only one status.
     * Reads one more than LIST_LIMITS.devices so the caller can say the list was cut.
     */
    listDevices: async ({ status = null, employeeIds = null } = {}) => {
      const limit = LIST_LIMITS.devices + 1;
      const withStatus = (q) => (status ? q.eq('status', status) : q);
      if (employeeIds) {
        const rows = await readIn('hr_attendance_devices', COLUMNS.device, 'employee_id', employeeIds,
          (q) => withStatus(q).order('bound_at', { ascending: false }).limit(limit));
        return rows.sort((a, b) => Date.parse(b.bound_at) - Date.parse(a.bound_at)).slice(0, limit);
      }
      return (await read('hr_attendance_devices', (q) => withStatus(q.select(COLUMNS.device))
        .order('bound_at', { ascending: false }).limit(limit))) || [];
    },

    /**
     * The one write to a Scheduler table (ADR-0018, decision 11): every ACTIVE phone of these
     * employees gets exactly the update the Scheduler's revokeDevice makes
     * (controllers/hr/attendanceAdminController.js:284-289): status 'revoked', revoked_at,
     * revoked_by, revoked_by_name and revoke_reason, only where the status is still 'active'.
     * A phone reset in the meantime is left alone, as there.
     *
     * One request per slice and no transaction around them, so a failure part-way leaves the
     * earlier slices reset. `onReset` hears of each slice's phones as soon as they are reset, so
     * the caller can record them whatever happens to the next slice.
     *
     * @returns the reset phones, { id, employee_id }
     */
    revokeActiveDevices: async (employeeIds, patch, onReset = () => {}) => {
      const unique = [...new Set(employeeIds.filter(Boolean))];
      const out = [];
      for (const part of chunks(unique)) {
        const reset = (await write('hr_attendance_devices', (q) => q
          .update({
            status: 'revoked',
            revoked_at: patch.revoked_at,
            revoked_by: patch.revoked_by,
            revoked_by_name: patch.revoked_by_name,
            revoke_reason: patch.revoke_reason,
          })
          .in('employee_id', part)
          .eq('status', 'active')
          .select(COLUMNS.revokedDevice))) || [];
        out.push(...reset);
        onReset(reset);
      }
      return out;
    },

    /* ── A8: requests to correct or delete my data ── */

    /** The new request, or null when the person already has five open (the database's own count). */
    createDataRequest: async (row) => {
      const created = await write('hr_ess_data_requests', (q) => q.insert([row]).select(COLUMNS.dataRequest).single(), REFUSALS.OPEN_LIMIT);
      return created === REFUSED ? null : created;
    },
    countOpenDataRequests: async (employeeId) =>
      ((await read('hr_ess_data_requests', (q) => q.select('id').eq('employee_id', employeeId).eq('status', 'open'))) || []).length,
    listMyDataRequests: async (employeeId) =>
      (await read('hr_ess_data_requests', (q) => q.select(COLUMNS.dataRequest).eq('employee_id', employeeId)
        .order('created_at', { ascending: false }).limit(LIST_LIMITS.myDataRequests))) || [],
    /** Newest first; one more than LIST_LIMITS.dataRequests, to tell a cut list. */
    listDataRequests: async ({ status = null } = {}) =>
      (await read('hr_ess_data_requests', (q) => {
        const base = q.select(COLUMNS.dataRequest);
        return (status ? base.eq('status', status) : base)
          .order('created_at', { ascending: false }).limit(LIST_LIMITS.dataRequests + 1);
      })) || [],
    getDataRequest: (id) => one('hr_ess_data_requests', COLUMNS.dataRequest, 'id', id),
    /**
     * Resolves a request only while it is still open, so two HR people answering at the same
     * moment cannot both resolve it: the second finds nothing to update and gets null.
     */
    resolveDataRequest: (id, patch) =>
      write('hr_ess_data_requests', (q) => q.update(patch).eq('id', id).eq('status', 'open')
        .select(COLUMNS.dataRequest).maybeSingle()),

    /* ── E9: personal details ── */

    getPersonalDetails: (employeeId) => one('hr_ess_personal_details', COLUMNS.personal, 'employee_id', employeeId),
    /**
     * One row per employee (its primary key). Only the columns in `row` are written: PostgREST's
     * upsert sets just those on a conflict, so a save cannot put back a field somebody else
     * changed since it read the row. Answers the whole row as it now stands, or null when the
     * row would be left with half an emergency contact by a save made in between.
     */
    savePersonalDetails: async (row) => {
      const saved = await write('hr_ess_personal_details', (q) => q.upsert([row], { onConflict: 'employee_id' }).select(COLUMNS.personal).single(),
        REFUSALS.EMERGENCY_HALF);
      return saved === REFUSED ? null : saved;
    },

    /* ── B14: mocked-location reports ── */

    createMockReport: (row) =>
      write('hr_ess_mock_location_reports', (q) => q.insert([row]).select(COLUMNS.mockReportCreated).single()),
    /**
     * Reports from `fromIso` (inclusive) to `toIso` (exclusive), newest first, optionally one
     * branch's; one more than LIST_LIMITS.mockReports, to tell a cut list.
     */
    listMockReports: async ({ fromIso, toIso, branchId = null }) =>
      (await read('hr_ess_mock_location_reports', (q) => {
        const base = q.select(COLUMNS.mockReport).gte('reported_at', fromIso).lt('reported_at', toIso);
        return (branchId ? base.eq('branch_id', branchId) : base)
          .order('reported_at', { ascending: false }).limit(LIST_LIMITS.mockReports + 1);
      })) || [],

    /* ── C6: the request limits HR can change ── */

    getRequestLimits: () => list('hr_ess_request_limits', (q) => q.select(COLUMNS.requestLimit).order('type')),
    /** One row per type (its primary key), so the update is at most one row; null for no such type. */
    setRequestLimit: (type, patch) =>
      write('hr_ess_request_limits', (q) => q.update(patch).eq('type', type).select(COLUMNS.requestLimit).maybeSingle()),

    /* ── C1, C3: my attendance requests ── */

    createAttendanceRequest: (row) =>
      write('hr_ess_attendance_requests', (q) => q.insert([row]).select(COLUMNS.attendanceRequest).single()),
    getAttendanceRequest: (id) => one('hr_ess_attendance_requests', COLUMNS.attendanceRequest, 'id', id),
    listMyAttendanceRequests: async (employeeId) =>
      (await read('hr_ess_attendance_requests', (q) => q.select(COLUMNS.attendanceRequest)
        .eq('employee_id', employeeId).order('created_at', { ascending: false }).limit(LIST_LIMITS.myRequests))) || [],
    /**
     * The counters a form and the balances need: the caller's attendance requests whose day is
     * in from..to, as the four columns that decide them -- never the reasons or the days' detail.
     */
    listMyRequestFacts: async (family, employeeId, from, to) => {
      const table = family === 'leave' ? 'hr_ess_leave_requests' : 'hr_ess_attendance_requests';
      return (await read(table, (q) => q.select(COLUMNS.requestFacts).eq('employee_id', employeeId)
        .gte('day', from).lte('day', to))) || [];
    },
    /** Whether the same type+day already waits: the duplicate check before a request goes in. */
    countPendingRequests: async ({ family, employeeId, type, day }) => {
      const table = family === 'leave' ? 'hr_ess_leave_requests' : 'hr_ess_attendance_requests';
      const rows = await read(table, (q) => q.select('id').eq('employee_id', employeeId)
        .eq('type', type).eq('day', day).eq('status', 'pending'));
      return (rows || []).length;
    },

    /* ── C2, C4, C5: my leave requests and the days the sheet records ── */

    createLeaveRequest: (row) =>
      write('hr_ess_leave_requests', (q) => q.insert([row]).select(COLUMNS.leaveRequest).single()),
    getLeaveRequest: (id) => one('hr_ess_leave_requests', COLUMNS.leaveRequest, 'id', id),
    listMyLeaveRequests: async (employeeId) =>
      (await read('hr_ess_leave_requests', (q) => q.select(COLUMNS.leaveRequest)
        .eq('employee_id', employeeId).order('created_at', { ascending: false }).limit(LIST_LIMITS.myRequests))) || [],
    /** The CL and LWP days the sheet records for the month: the leave ledger the balance shows. */
    listMyLeaveDays: async (employeeId, from, to) =>
      (await read('hr_staff_attendance', (q) => q.select('day, leave_type').eq('employee_id', employeeId)
        .eq('status', 'leave').in('leave_type', ['cl', 'lwp']).gte('day', from).lte('day', to))) || [],

    /* ── D1, H6: the approvals Inbox ── */

    /**
     * One family's requests, oldest first. `employeeIds` limits it to those people (a manager's
     * reports); without it, everybody (an HR decider's view). `status` null means any.
     */
    listRequestsForApprover: async ({ family, employeeIds = null, status = 'pending' }) => {
      const table = family === 'leave' ? 'hr_ess_leave_requests' : 'hr_ess_attendance_requests';
      const columns = family === 'leave' ? COLUMNS.leaveRequest : COLUMNS.attendanceRequest;
      const limit = LIST_LIMITS.inbox + 1;
      const withStatus = (q) => (status ? q.eq('status', status) : q);
      if (employeeIds) {
        const rows = await readIn(table, columns, 'employee_id', employeeIds,
          (q) => withStatus(q).order('created_at', { ascending: true }).limit(limit));
        return rows.sort((a, b) => Date.parse(a.created_at) - Date.parse(b.created_at)).slice(0, limit);
      }
      return (await read(table, (q) => withStatus(q.select(columns)).order('created_at', { ascending: true }).limit(limit))) || [];
    },
    /** One employee's requests of every status whose day is in from..to, for the context counts. */
    listRequestCountsFor: async ({ family, employeeIds, from, to }) => {
      const table = family === 'leave' ? 'hr_ess_leave_requests' : 'hr_ess_attendance_requests';
      return readIn(table, COLUMNS.requestFacts, 'employee_id', employeeIds, (q) => q.gte('day', from).lte('day', to));
    },
    /** The day rows' late marks for the Inbox's context, for these days. */
    listDayLateMarks: async (days) => {
      const unique = [...new Set((days || []).filter(Boolean))];
      if (!unique.length) return [];
      return readIn('hr_staff_attendance', COLUMNS.dayLate, 'day', unique);
    },
    /** Who the sheet records on leave on these days. */
    listDaysOnLeave: async (days) => {
      const unique = [...new Set((days || []).filter(Boolean))];
      if (!unique.length) return [];
      return readIn('hr_staff_attendance', COLUMNS.dayLeave, 'day', unique, (q) => q.eq('status', 'leave'));
    },
    /** Leave requests, pending or approved, whose day is one of these: "who else is off". */
    listLeaveRequestsOnDays: async (days, statuses) => {
      const unique = [...new Set((days || []).filter(Boolean))];
      if (!unique.length) return [];
      return readIn('hr_ess_leave_requests', COLUMNS.leaveOnDay, 'day', unique, (q) => q.in('status', statuses));
    },

    /* ── the decisions, withdrawals and cancels (the SQL functions) ── */

    /** A database refusal (a racing second CL) answers as the function's own cl_limit outcome. */
    decideAttendanceRequest: async (args) => {
      const out = await call(REQUEST_FUNCTIONS.decideAttendance, args,
        { table: 'hr_ess_attendance_requests', refusal: REFUSALS.CL_TAKEN });
      return out === REFUSED ? { outcome: 'cl_limit' } : out;
    },
    decideLeaveRequest: async (args) => {
      const out = await call(REQUEST_FUNCTIONS.decideLeave, args,
        { table: 'hr_ess_leave_requests', refusal: REFUSALS.CL_TAKEN });
      return out === REFUSED ? { outcome: 'cl_limit' } : out;
    },
    withdrawAttendanceRequest: (args) =>
      call(REQUEST_FUNCTIONS.withdrawAttendance, args, { table: 'hr_ess_attendance_requests' }),
    withdrawLeaveRequest: (args) =>
      call(REQUEST_FUNCTIONS.withdrawLeave, args, { table: 'hr_ess_leave_requests' }),
    cancelAttendanceRequest: (args) =>
      call(REQUEST_FUNCTIONS.cancelAttendance, args, { table: 'hr_ess_attendance_requests' }),
    cancelLeaveRequest: (args) =>
      call(REQUEST_FUNCTIONS.cancelLeave, args, { table: 'hr_ess_leave_requests' }),
    /**
     * The on-duty morning job (one call a day, idempotent): every approved on_duty request for
     * `day` with no day row yet is written as present. Answers { applied, failed, employees }.
     */
    applyOnDutyDays: (day, at) =>
      call(REQUEST_FUNCTIONS.onDutyApply, { p_day: day, p_now: at }, { table: 'hr_ess_attendance_requests' }),
    /** Archiving twice is the same as once: the unique key answers the second one. */
    createArchive: async (row) => {
      const created = await write('hr_ess_request_archives', (q) => q.insert([row]), REFUSALS.ARCHIVE_KEPT);
      return created !== REFUSED;
    },
    listMyArchives: async (employeeId) =>
      (await read('hr_ess_request_archives', (q) => q.select(COLUMNS.archive).eq('employee_id', employeeId))) || [],

    /* ── the day's shift snapshot, and the month's recompute (policy/attendance.js) ── */

    getEmployeeShifts: (employeeId) => one('hr_employees', COLUMNS.employeeShifts, 'id', employeeId),
    getShift: (shiftId) => one('hr_shifts', COLUMNS.shift, 'id', shiftId),
    listHolidays: (from, to) => list('hr_holidays', (q) => q.select(COLUMNS.holiday).gte('day', from).lte('day', to)),
    getDaySnapshotState: (employeeId, day) =>
      read('hr_staff_attendance', (q) => q.select(COLUMNS.daySnapshot).eq('employee_id', employeeId).eq('day', day).maybeSingle()),
    /** The shift a day is judged by, copied on while it has none (attendanceRules.js ensureSnapshot). */
    setDaySnapshot: (id, snapshot) =>
      write('hr_staff_attendance', (q) => q.update(snapshot).eq('id', id).select('id').maybeSingle()),
    /**
     * Re-work late, early and the third-late half day for the month of `day`. Before the
     * Scheduler's shifts migration the function is missing and the rules are simply off
     * (attendanceRules.js:20-22): that is not a failure of the decision that called this.
     */
    recomputeAttendance: async ({ employeeIds, day, today, halfDayMinutes }) => {
      try {
        await run('writing', 'hr_attendance_recompute', () => db.rpc('hr_attendance_recompute', {
          p_employee_ids: employeeIds,
          p_day: day,
          p_today: today,
          p_half_day_minutes: halfDayMinutes,
        }));
      } catch (e) {
        if (!(e instanceof HttpError && e.code === 'MODULE_NOT_INSTALLED')) throw e;
      }
    },

    /* ── the audit trail ── */

    /** Append-only: nothing in the ESS updates or deletes a row of hr_ess_audit. */
    writeAudit: async (row) => {
      await write('hr_ess_audit', (q) => q.insert([row]));
    },

    /** The health check's read: one row of a small table. `signal` lets the caller give up on it. */
    ping: async ({ signal } = {}) => {
      await read('hr_branches', (q) => {
        const query = q.select('id').limit(1);
        return signal ? query.abortSignal(signal) : query;
      });
    },
  };
}

module.exports = {
  createSupabaseStore,
  storeError,
  COLUMNS,
  NOT_INSTALLED_CODES,
  SESSION_FUNCTIONS,
  REFUSALS,
  NIL_UUID,
  DB_REQUEST_TIMEOUT_MS,
  IN_CHUNK,
  LIST_LIMITS,
};
