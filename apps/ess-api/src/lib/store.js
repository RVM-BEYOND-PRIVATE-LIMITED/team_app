const { createClient } = require('@supabase/supabase-js');
const { HttpError, MESSAGES } = require('./errors');

/**
 * The ESS's reads from the Scheduler's database, which stays the system of record (ADR-0003):
 * the ESS reads the Scheduler's tables and never writes them directly.
 *
 * Every read names its columns, and nothing selects '*'. A select('*') is how the Scheduler's
 * marking roster came to hand out password hashes (J2), and a list also means that a column
 * added to one of these tables later cannot reach a reply by accident. hr_attendance_accounts
 * holds a password hash, so it is read for its status and cut-off only.
 *
 * Tables and columns checked against Scheduler_Backend supabase/migrations at c28b9ca:
 *   users                   id, role, faculty_id: 20251215134244_remote_schema.sql
 *   hr_employees            20260826000001_hrms_tables.sql; user_id from
 *                           20260910000000_hr_employee_user_link.sql; the employment_status
 *                           values from 20260917000000_hr_employment_lifecycle.sql
 *   hr_branches, hr_departments  id, name: 20260826000001_hrms_tables.sql
 *   hr_attendance_accounts  20261021000000_hr_attendance_accounts.sql
 */
const COLUMNS = Object.freeze({
  user: 'id, role, faculty_id',
  employee: 'id, full_name, employee_code, designation, employment_status, date_of_exit, is_archived, branch_id, department_id, manager_id',
  report: 'id, employment_status, date_of_exit, is_archived',
  employeeName: 'id, full_name',
  branch: 'id, name',
  department: 'id, name',
  attendanceAccount: 'id, employee_id, status, sessions_valid_from',
});

/**
 * A missing table or column means the code is live before its migration: merges deploy at
 * once and KP applies migrations by hand afterwards (ADR-0011, ADR-0021). That answers 503
 * MODULE_NOT_INSTALLED, never a 500. PGRST205 and PGRST204 are PostgREST's "not in the schema
 * cache"; 42P01 and 42703 are Postgres's own "undefined table" and "undefined column".
 */
const NOT_INSTALLED_CODES = new Set(['PGRST205', 'PGRST204', '42P01', '42703']);

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

  async function read(table, build) {
    let result;
    try {
      result = await build(db.from(table));
    } catch (e) {
      console.error(`[ess] reading ${table} failed: ${e && e.message ? e.message : e}`);
      throw storeError(table, e);
    }
    if (result.error) {
      console.error(`[ess] reading ${table} failed: ${result.error.code || '-'} ${result.error.message || ''}`.trim());
      throw storeError(table, result.error);
    }
    return result.data;
  }

  /** At most one row, or null. Every filter here is on a key that is unique in the schema. */
  const one = (table, columns, column, value) =>
    read(table, (q) => q.select(columns).eq(column, value).maybeSingle());

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
    listDirectReports: async (managerId) =>
      (await read('hr_employees', (q) => q.select(COLUMNS.report).eq('manager_id', managerId).eq('is_archived', false))) || [],

    /** The health check's read: one row of a small table. `signal` lets the caller give up on it. */
    ping: async ({ signal } = {}) => {
      await read('hr_branches', (q) => {
        const query = q.select('id').limit(1);
        return signal ? query.abortSignal(signal) : query;
      });
    },
  };
}

module.exports = { createSupabaseStore, storeError, COLUMNS, NOT_INSTALLED_CODES, DB_REQUEST_TIMEOUT_MS };
