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
 * holds a password hash, and hr_attendance_devices the hash of each phone's token, so neither is
 * ever read whole.
 *
 * Tables and columns checked against Scheduler_Backend supabase/migrations at c28b9ca:
 *   users                   id, role, faculty_id: 20251215134244_remote_schema.sql:854-863
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
 * and team_app's own hr_ess_* tables in db/migrations.
 */
const COLUMNS = Object.freeze({
  user: 'id, role, faculty_id',
  // The username is what the Scheduler records as the actor's name (attendanceAdminController.js:18).
  userLogin: 'id, username',
  employee: 'id, full_name, employee_code, designation, employment_status, date_of_exit, is_archived, branch_id, department_id, manager_id',
  report: 'id, employment_status, date_of_exit, is_archived',
  employeeName: 'id, full_name',
  // What HR's lists show about a person: never their phone, email or anything else on the record.
  employeeCard: 'id, full_name, employee_code, branch_id',
  branch: 'id, name',
  department: 'id, name',
  // password_set_at, and never password_hash: a 'pw' session already proves a hash existed, so
  // whether the person chose their own password is all the first-time check needs.
  attendanceAccount: 'id, employee_id, status, sessions_valid_from, password_set_at',
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

  async function run(table, build, verb = 'reading') {
    let result;
    try {
      result = await build(db.from(table));
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
  const read = (table, build) => run(table, build, 'reading');
  const write = (table, build) => run(table, build, 'writing');

  /** At most one row, or null. Every filter here is on a key that is unique in the schema. */
  const one = (table, columns, column, value) =>
    read(table, (q) => q.select(columns).eq(column, value).maybeSingle());

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
    listDirectReports: async (managerId) =>
      (await read('hr_employees', (q) => q.select(COLUMNS.report).eq('manager_id', managerId).eq('is_archived', false))) || [],

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
     * @returns the reset phones, { id, employee_id }
     */
    revokeActiveDevices: async (employeeIds, patch) => {
      const unique = [...new Set(employeeIds.filter(Boolean))];
      const out = [];
      for (const part of chunks(unique)) {
        out.push(...((await write('hr_attendance_devices', (q) => q
          .update({
            status: 'revoked',
            revoked_at: patch.revoked_at,
            revoked_by: patch.revoked_by,
            revoked_by_name: patch.revoked_by_name,
            revoke_reason: patch.revoke_reason,
          })
          .in('employee_id', part)
          .eq('status', 'active')
          .select(COLUMNS.revokedDevice))) || []));
      }
      return out;
    },

    /* ── A8: requests to correct or delete my data ── */

    createDataRequest: (row) =>
      write('hr_ess_data_requests', (q) => q.insert([row]).select(COLUMNS.dataRequest).single()),
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
    /** One row per employee (its primary key), written whole. */
    savePersonalDetails: (row) =>
      write('hr_ess_personal_details', (q) => q.upsert([row], { onConflict: 'employee_id' }).select(COLUMNS.personal).single()),

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
  DB_REQUEST_TIMEOUT_MS,
  IN_CHUNK,
  LIST_LIMITS,
};
