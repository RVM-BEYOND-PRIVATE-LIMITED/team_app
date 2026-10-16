/**
 * An in-memory stand-in for the supabase-js client, so the tests run the real store
 * (src/lib/store.js) against plain arrays and never reach a database.
 *
 * It answers the query shapes the store uses (from().select(columns) with .eq(), .limit() and
 * .abortSignal(), awaited as a list or through .maybeSingle()) the way PostgREST does where the
 * store depends on it:
 *   - an unknown table is PGRST205, an unknown column (selected or filtered on) is 42703;
 *   - two rows for maybeSingle() is PGRST116;
 *   - select('*') throws, because the store must always name its columns.
 *
 * `outage` simulates the database being away: 'error' (supabase-js returns an error, as it does
 * when fetch fails), 'throw' (the call itself rejects) or 'hang' (no answer until aborted).
 * Every query is recorded in `queries`.
 */

/**
 * The columns each table has in the Scheduler's migrations at c28b9ca. Not every column, but
 * enough that a whitelist naming a wrong one fails here as it would in production, and that the
 * password hashes are present to prove they are never read.
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
};

const clone = (value) => JSON.parse(JSON.stringify(value));

class Query {
  constructor(fake, table) {
    this.fake = fake;
    this.table = table;
    this.columns = null;
    this.filters = [];
    this.max = null;
    this.single = false;
    this.signal = null;
  }

  select(columns) {
    if (typeof columns !== 'string' || columns.includes('*')) {
      throw new Error(`select(${JSON.stringify(columns)}) on ${this.table}: the store must name its columns`);
    }
    this.columns = columns.split(',').map((c) => c.trim()).filter(Boolean);
    return this;
  }

  eq(column, value) {
    this.filters.push([column, value]);
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
    this.single = true;
    return this;
  }

  then(onFulfilled, onRejected) {
    return this.run().then(onFulfilled, onRejected);
  }

  async run() {
    const { fake } = this;
    const record = { table: this.table, columns: this.columns, filters: this.filters, single: this.single, limit: this.max, aborted: false };
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
    if (!known) {
      return { data: null, error: { code: 'PGRST205', message: `Could not find the table 'public.${this.table}' in the schema cache` } };
    }
    for (const column of [...(this.columns || []), ...this.filters.map(([c]) => c)]) {
      if (!known.has(column)) return { data: null, error: { code: '42703', message: `column ${this.table}.${column} does not exist` } };
    }

    let rows = (fake.tables[this.table] || []).filter((row) => this.filters.every(([c, v]) => (row[c] ?? null) === v));
    if (this.max !== null) rows = rows.slice(0, this.max);
    const out = rows.map((row) => Object.fromEntries(this.columns.map((c) => [c, row[c] === undefined ? null : clone(row[c])])));

    if (this.single) {
      if (out.length > 1) return { data: null, error: { code: 'PGRST116', message: 'JSON object requested, multiple (or no) rows returned' } };
      return { data: out[0] || null, error: null };
    }
    return { data: out, error: null };
  }
}

/**
 * @param {Record<string, object[]>} tables  rows by table name; copied, so the caller's fixture is not changed
 */
function createFakeSupabase(tables = {}) {
  const fake = {
    tables: clone(tables),
    schema: new Map(Object.entries(SCHEMA).map(([t, cols]) => [t, new Set(cols)])),
    queries: [],
    outage: null,
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
  };
  return fake;
}

module.exports = { createFakeSupabase, SCHEMA };
