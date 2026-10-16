const crypto = require('crypto');

/**
 * An in-memory stand-in for the supabase-js client, so the tests run the real store
 * (src/lib/store.js) against plain arrays and never reach a database.
 *
 * It answers the query shapes the store uses the way PostgREST does where the store depends on
 * it:
 *   - reads: from().select(columns) with .eq(), .neq(), .in(), .is(), .gte(), .gt(), .lte(),
 *     .lt(), .order(), .limit() and .abortSignal(), awaited as a list or through .maybeSingle()
 *     or .single();
 *   - writes: .insert(rows), .upsert(rows, { onConflict }) and .update(patch) with the same
 *     filters, returning rows only when .select(columns) follows, as PostgREST does;
 *   - an unknown table is PGRST205; an unknown column selected, filtered or ordered on is 42703,
 *     and an unknown column written is PGRST204;
 *   - a second row on a primary or unique key is 23505;
 *   - two rows for maybeSingle(), or anything but one for single(), is PGRST116;
 *   - select('*') throws, because the store must always name its columns.
 *
 * Inserted rows get the defaults db/migrations gives the hr_ess_* tables, timed by `now`.
 *
 * `outage` simulates the database being away: 'error' (supabase-js returns an error, as it does
 * when fetch fails), 'throw' (the call itself rejects) or 'hang' (no answer until aborted).
 * Every query is recorded in `queries`.
 */

/**
 * The columns each table has. Scheduler tables: its migrations at c28b9ca, not every column,
 * but enough that a whitelist naming a wrong one fails here as it would in production, and that
 * the password and token hashes are present to prove they are never read. hr_ess_* tables:
 * db/migrations, all of them. Keep this in step with both (docs/04-build-plan.md, Risks).
 */
const SCHEMA = {
  users: ['id', 'username', 'phone_number', 'password_hash', 'role', 'faculty_id', 'created_at', 'location_id',
    'email', 'email_verified_at', 'photo_path', 'two_factor_enabled', 'password_changed_at'],
  hr_employees: ['id', 'employee_code', 'full_name', 'designation', 'department_id', 'branch_id', 'manager_id',
    'email', 'phone', 'date_of_joining', 'date_of_exit', 'employment_status', 'performance_tag', 'seniority',
    'is_archived', 'archived_at', 'archive_reason', 'user_id', 'photo_path', 'geofence_exempt', 'created_at', 'updated_at'],
  hr_branches: ['id', 'name', 'is_active', 'latitude', 'longitude', 'geofence_radius_m', 'office_ips', 'created_at', 'updated_at'],
  hr_departments: ['id', 'name', 'is_active', 'source', 'created_at', 'updated_at'],
  hr_attendance_accounts: ['id', 'employee_id', 'status', 'password_hash', 'password_set_at', 'sessions_valid_from',
    'failed_attempts', 'locked_until', 'last_login_at', 'created_at', 'updated_at'],
  // 20261020000000_hr_attendance_punch.sql:77-90
  hr_attendance_devices: ['id', 'employee_id', 'token_hash', 'user_agent', 'bound_ip', 'status', 'bound_at', 'last_seen_at',
    'revoked_at', 'revoked_by', 'revoked_by_name', 'revoke_reason'],
  // 20261015000004:13-28, 20261020000000:62-66, 20261022000000:106-123
  hr_staff_attendance: ['id', 'employee_id', 'branch_id', 'day', 'status', 'leave_type', 'note', 'marked_by', 'marked_by_name',
    'marked_at', 'updated_at', 'source', 'first_in', 'last_out', 'worked_minutes', 'shift_id', 'shift_start', 'shift_end',
    'grace_minutes', 'late_minutes', 'early_exit_minutes', 'late_count', 'late_half_day', 'late_excused',
    'late_excused_by_name', 'late_excused_reason', 'late_excused_at'],
  // 20261022000000:151-160
  hr_attendance_remarks: ['id', 'employee_id', 'day', 'remarks', 'updated_by', 'updated_by_name', 'updated_at'],
  // 20261023000000:12-19
  hr_attendance_employee_remarks: ['id', 'employee_id', 'day', 'remarks', 'updated_at'],
  // db/migrations
  hr_ess_audit: ['id', 'at', 'actor_user_id', 'actor_employee_id', 'actor_name', 'action', 'target_employee_id', 'details'],
  hr_ess_data_requests: ['id', 'employee_id', 'kind', 'details', 'status', 'created_at', 'resolved_at', 'resolved_by_user_id',
    'resolved_by_name', 'resolution_note'],
  hr_ess_personal_details: ['employee_id', 'date_of_birth', 'blood_group', 'address_line1', 'address_line2', 'city', 'state',
    'pincode', 'emergency_name', 'emergency_relation', 'emergency_phone', 'updated_at', 'updated_by_user_id', 'updated_by_name'],
  hr_ess_mock_location_reports: ['id', 'employee_id', 'branch_id', 'reported_at', 'client_at', 'kind', 'latitude', 'longitude',
    'accuracy_m', 'provider', 'app_version', 'install_id'],
};

/** The primary key of each table, where it is not `id`. */
const KEYS = {
  hr_ess_personal_details: ['employee_id'],
};

/** What the database fills in on insert: the hr_ess_* DEFAULTs in db/migrations. */
const DEFAULTS = {
  hr_ess_audit: (at) => ({ at, details: {} }),
  hr_ess_data_requests: (at) => ({ status: 'open', created_at: at }),
  hr_ess_personal_details: (at) => ({ updated_at: at }),
  hr_ess_mock_location_reports: (at) => ({ reported_at: at }),
};

const clone = (value) => (value === undefined ? undefined : JSON.parse(JSON.stringify(value)));

/** Timestamps compare as instants whatever their offset, as Postgres compares timestamptz. */
const TIMESTAMP_RE = /^\d{4}-\d{2}-\d{2}T/;
function compare(a, b) {
  if (typeof a === 'string' && typeof b === 'string' && TIMESTAMP_RE.test(a) && TIMESTAMP_RE.test(b)) {
    return Date.parse(a) - Date.parse(b);
  }
  if (typeof a === 'number' && typeof b === 'number') return a - b;
  const [x, y] = [String(a), String(b)];
  return x < y ? -1 : x > y ? 1 : 0;
}

const TESTS = {
  eq: (v, x) => v === x,
  neq: (v, x) => v !== x,
  is: (v, x) => v === x,
  in: (v, xs) => xs.includes(v),
  gte: (v, x) => v !== null && compare(v, x) >= 0,
  gt: (v, x) => v !== null && compare(v, x) > 0,
  lte: (v, x) => v !== null && compare(v, x) <= 0,
  lt: (v, x) => v !== null && compare(v, x) < 0,
};

const missingTable = (table) => ({ data: null, error: { code: 'PGRST205', message: `Could not find the table 'public.${table}' in the schema cache` } });

class Query {
  constructor(fake, table) {
    this.fake = fake;
    this.table = table;
    this.op = 'select';
    this.columns = null;
    this.returning = null;
    this.values = null;
    this.onConflict = null;
    this.conditions = [];
    this.orders = [];
    this.max = null;
    this.expect = null;
    this.signal = null;
  }

  select(columns) {
    if (typeof columns !== 'string' || columns.includes('*')) {
      throw new Error(`select(${JSON.stringify(columns)}) on ${this.table}: the store must name its columns`);
    }
    const list = columns.split(',').map((c) => c.trim()).filter(Boolean);
    if (this.op === 'select') this.columns = list;
    else this.returning = list;
    return this;
  }

  insert(rows) {
    this.op = 'insert';
    this.values = Array.isArray(rows) ? rows : [rows];
    return this;
  }

  upsert(rows, { onConflict } = {}) {
    this.op = 'upsert';
    this.values = Array.isArray(rows) ? rows : [rows];
    this.onConflict = onConflict ? onConflict.split(',').map((c) => c.trim()) : null;
    return this;
  }

  update(patch) {
    this.op = 'update';
    this.values = [patch];
    return this;
  }

  where(test, column, value) {
    this.conditions.push([test, column, value]);
    return this;
  }

  eq(column, value) { return this.where('eq', column, value); }
  neq(column, value) { return this.where('neq', column, value); }
  is(column, value) { return this.where('is', column, value); }
  in(column, values) { return this.where('in', column, values); }
  gte(column, value) { return this.where('gte', column, value); }
  gt(column, value) { return this.where('gt', column, value); }
  lte(column, value) { return this.where('lte', column, value); }
  lt(column, value) { return this.where('lt', column, value); }

  order(column, { ascending = true } = {}) {
    this.orders.push([column, ascending]);
    return this;
  }

  limit(n) {
    this.max = n;
    return this;
  }

  abortSignal(signal) {
    this.signal = signal;
    return this;
  }

  maybeSingle() {
    this.expect = 'maybe';
    return this;
  }

  single() {
    this.expect = 'one';
    return this;
  }

  then(onFulfilled, onRejected) {
    return this.run().then(onFulfilled, onRejected);
  }

  matches(row) {
    return this.conditions.every(([test, column, value]) => TESTS[test](row[column] ?? null, value));
  }

  project(rows, columns) {
    return rows.map((row) => Object.fromEntries(columns.map((c) => [c, row[c] === undefined ? null : clone(row[c])])));
  }

  async run() {
    const { fake } = this;
    const record = {
      op: this.op,
      table: this.table,
      columns: this.op === 'select' ? this.columns : (this.returning || []),
      // The equality filters as [column, value], the shape the older tests read; every
      // condition, with its test, in `conditions`.
      filters: this.conditions.filter(([t]) => t === 'eq').map(([, c, v]) => [c, v]),
      conditions: this.conditions,
      values: clone(this.values),
      single: this.expect !== null,
      limit: this.max,
      aborted: false,
    };
    fake.queries.push(record);

    if (fake.outage === 'throw') throw new TypeError('fetch failed');
    if (fake.outage === 'error') return { data: null, error: { code: '', message: 'TypeError: fetch failed', details: '', hint: '' } };
    if (fake.outage === 'hang') {
      return new Promise((resolve) => {
        if (!this.signal) return;
        const abort = () => {
          record.aborted = true;
          resolve({ data: null, error: { code: '20', message: 'AbortError: This operation was aborted' } });
        };
        // Like fetch: a signal that is already aborted ends the request at once.
        if (this.signal.aborted) abort();
        else this.signal.addEventListener('abort', abort, { once: true });
      });
    }

    const known = fake.schema.get(this.table);
    if (!known) return missingTable(this.table);
    const read = [...(this.columns || []), ...(this.returning || []), ...this.conditions.map(([, c]) => c), ...this.orders.map(([c]) => c)];
    for (const column of read) {
      if (!known.has(column)) return { data: null, error: { code: '42703', message: `column ${this.table}.${column} does not exist` } };
    }
    for (const value of this.values || []) {
      for (const column of Object.keys(value)) {
        if (!known.has(column)) return { data: null, error: { code: 'PGRST204', message: `Could not find the '${column}' column of '${this.table}' in the schema cache` } };
      }
    }

    const rows = fake.rows(this.table);
    let out;
    if (this.op === 'select') {
      out = rows.filter((row) => this.matches(row));
      for (const [column, ascending] of [...this.orders].reverse()) {
        out = [...out].sort((a, b) => {
          const [x, y] = [a[column] ?? null, b[column] ?? null];
          // PostgREST's defaults: nulls last going up, first going down.
          if (x === null || y === null) return x === y ? 0 : (x === null ? 1 : -1) * (ascending ? 1 : -1);
          return ascending ? compare(x, y) : compare(y, x);
        });
      }
      if (this.max !== null) out = out.slice(0, this.max);
      out = this.project(out, this.columns);
    } else {
      const result = this.write(rows);
      if (result.error) return result;
      out = this.returning ? this.project(result.rows, this.returning) : null;
    }

    if (this.expect && out) {
      if (out.length > 1 || (this.expect === 'one' && out.length === 0)) {
        return { data: null, error: { code: 'PGRST116', message: 'JSON object requested, multiple (or no) rows returned' } };
      }
      return { data: out[0] || null, error: null };
    }
    return { data: out, error: null };
  }

  write(rows) {
    const { fake, table } = this;
    const key = KEYS[table] || ['id'];
    const at = fake.now().toISOString();
    const sameKey = (a, b, columns) => columns.every((c) => (a[c] ?? null) === (b[c] ?? null));
    const duplicate = () => ({ error: { code: '23505', message: `duplicate key value violates unique constraint "${table}_pkey"` } });

    if (this.op === 'update') {
      const changed = rows.filter((row) => this.matches(row));
      for (const row of changed) Object.assign(row, clone(this.values[0]));
      return { rows: changed };
    }

    const written = [];
    for (const value of this.values) {
      const conflictOn = this.op === 'upsert' ? (this.onConflict || key) : null;
      const existing = conflictOn ? rows.find((row) => sameKey(row, value, conflictOn)) : null;
      if (existing) {
        // PostgREST's merge-duplicates: only the columns sent are written.
        Object.assign(existing, clone(value));
        written.push(existing);
        continue;
      }
      const row = {
        ...(key.includes('id') ? { id: crypto.randomUUID() } : {}),
        ...(DEFAULTS[table] ? DEFAULTS[table](at) : {}),
        ...clone(value),
      };
      if (rows.some((other) => sameKey(other, row, key))) return duplicate();
      rows.push(row);
      written.push(row);
    }
    return { rows: written };
  }
}

/**
 * @param {Record<string, object[]>} tables  rows by table name; copied, so the caller's fixture is not changed
 * @param {{ now?: () => Date }} [options]   the database's clock, for its DEFAULT now() columns
 */
function createFakeSupabase(tables = {}, { now = () => new Date() } = {}) {
  const fake = {
    tables: clone(tables),
    schema: new Map(Object.entries(SCHEMA).map(([t, cols]) => [t, new Set(cols)])),
    queries: [],
    outage: null,
    now,
    from(table) {
      return new Query(fake, table);
    },
    /** As if the migration that creates this table has not been applied. */
    dropTable(table) {
      fake.schema.delete(table);
    },
    /** As if the migration that adds this column has not been applied. */
    dropColumn(table, column) {
      const known = fake.schema.get(table);
      if (known) known.delete(column);
    },
    rows(table) {
      if (!fake.tables[table]) fake.tables[table] = [];
      return fake.tables[table];
    },
    /** The writes made, oldest first: { op, table, values, conditions }. */
    writes() {
      return fake.queries.filter((q) => q.op !== 'select');
    },
  };
  return fake;
}

module.exports = { createFakeSupabase, SCHEMA };
