const { createClient } = require('@supabase/supabase-js');
const { HttpError, MESSAGES } = require('./errors');

/**
 * The ESS's reads from the Scheduler's database, which stays the system of record (ADR-0003):
 * the ESS reads the Scheduler's tables and never writes them directly. It writes only its own
 * hr_ess_* tables (ADR-0021).
 *
 * Every read names its columns, and nothing selects '*'. A select('*') is how the Scheduler's
 * marking roster came to hand out password hashes (J2), and a list also means that a column
 * added to one of these tables later cannot reach a reply by accident. hr_attendance_accounts
 * holds a password hash, so it is read for its status and cut-off only, and asked whether a
 * hash exists without the hash ever being sent.
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
 * and team_app's own:
 *   hr_ess_sessions         db/migrations/20261101000000_hr_ess_sessions.sql
 */
const COLUMNS = Object.freeze({
  user: 'id, role, faculty_id',
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
  branch: 'id, name',
  department: 'id, name',
  location: 'id, name',
  // password_set_at, and never password_hash: a 'pw' session already proves a hash existed, so
  // whether the person chose their own password is all the first-time check needs.
  attendanceAccount: 'id, employee_id, status, sessions_valid_from, password_set_at',
  attendanceLogin: 'employee_id, status',
  // Every column but refresh_hash: a session is found by its hash and never hands it back.
  session: 'id, family_id, employee_id, login_kind, user_id, location_name, method, signed_in_at, install_id, device_label, created_at, last_used_at, expires_at, revoked_at, revoked_reason',
  sessionStart: 'id, created_at',
});

/**
 * A missing table or column means the code is live before its migration: merges deploy at
 * once and KP applies migrations by hand afterwards (ADR-0011, ADR-0021). That answers 503
 * MODULE_NOT_INSTALLED, never a 500. PGRST205 and PGRST204 are PostgREST's "not in the schema
 * cache" for a table or a column, PGRST202 the same for a function; 42P01, 42703 and 42883 are
 * Postgres's own "undefined table", "undefined column" and "undefined function".
 */
const NOT_INSTALLED_CODES = new Set(['PGRST205', 'PGRST204', 'PGRST202', '42P01', '42703', '42883']);

/** The functions db/migrations/20261101000000_hr_ess_sessions.sql creates. */
const SESSION_FUNCTIONS = Object.freeze({ rotate: 'hr_ess_session_rotate', revoke: 'hr_ess_session_revoke' });

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

/** The refusal for a failed read. Never a 401: an outage must not sign anybody out. */
function storeError(table, error) {
  if (error && NOT_INSTALLED_CODES.has(error.code)) {
    return new HttpError(
      503,
      'MODULE_NOT_INSTALLED',
      `Team RVM needs a database update that has not been applied yet (it cannot read ${table}). Ask the tech team.`,
    );
  }
  return new HttpError(503, 'UNAVAILABLE', MESSAGES.UNAVAILABLE);
}

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
  async function run(verb, table, request) {
    let result;
    try {
      result = await request();
    } catch (e) {
      console.error(`[ess] ${verb} ${table} failed: ${e && e.message ? e.message : e}`);
      throw storeError(table, e);
    }
    if (result.error) {
      console.error(`[ess] ${verb} ${table} failed: ${result.error.code || '-'} ${result.error.message || ''}`.trim());
      throw storeError(table, result.error);
    }
    return result.data;
  }

  const read = (table, build) => run('reading', table, () => build(db.from(table)));
  const write = (table, build) => run('writing', table, () => build(db.from(table)));
  // The session functions read and write hr_ess_sessions, and arrive with it in one migration.
  const call = (fn, args) => run('writing', 'hr_ess_sessions', () => db.rpc(fn, args));

  /** At most one row, or null. Every filter here is on a key that is unique in the schema. */
  const one = (table, columns, column, value) =>
    read(table, (q) => q.select(columns).eq(column, value).maybeSingle());

  const list = async (table, build) => (await read(table, build)) || [];

  return {
    getUser: (userId) => one('users', COLUMNS.user, 'id', userId),
    getEmployeeById: (employeeId) => one('hr_employees', COLUMNS.employee, 'id', employeeId),
    // hr_employees.user_id is unique where set (hr_employees_user_id_key), so a login is at
    // most one employee.
    getEmployeeByUserId: (userId) => one('hr_employees', COLUMNS.employee, 'user_id', userId),
    getEmployeeName: (employeeId) => one('hr_employees', COLUMNS.employeeName, 'id', employeeId),
    getBranch: (branchId) => one('hr_branches', COLUMNS.branch, 'id', branchId),
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

    createSession: async (row) => {
      await write('hr_ess_sessions', (q) => q.insert(row));
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

    /** The health check's read: one row of a small table. `signal` lets the caller give up on it. */
    ping: async ({ signal } = {}) => {
      await read('hr_branches', (q) => {
        const query = q.select('id').limit(1);
        return signal ? query.abortSignal(signal) : query;
      });
    },
  };
}

module.exports = { createSupabaseStore, storeError, COLUMNS, NOT_INSTALLED_CODES, SESSION_FUNCTIONS, NIL_UUID, DB_REQUEST_TIMEOUT_MS };
