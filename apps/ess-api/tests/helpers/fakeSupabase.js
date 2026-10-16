/**
 * An in-memory stand-in for the supabase-js client, so the tests run the real store
 * (src/lib/store.js) against plain arrays and never reach a database.
 *
 * It answers the query shapes the store uses the way PostgREST does where the store depends on
 * it: from().select(columns) with .eq(), .is(), .not(column, 'is', null), .in(), .limit() and
 * .abortSignal(), awaited as a list or through .maybeSingle(); .insert() and .update(), each
 * optionally followed by .select(columns); and .rpc() for the functions team_app's migrations
 * create.
 *   - an unknown table is PGRST205, an unknown function PGRST202, an unknown column selected or
 *     filtered on is 42703, and one written PGRST204;
 *   - two rows for maybeSingle() is PGRST116;
 *   - a duplicate key is 23505, checked against the unique keys below;
 *   - select('*') throws, because the store must always name its columns.
 * Timestamps of team_app's own tables come back in PostgREST's spelling (+00:00, not Z), so code
 * that compares them as strings fails here as it would in production.
 *
 * `outage` simulates the database being away: 'error' (supabase-js returns an error, as it does
 * when fetch fails), 'throw' (the call itself rejects) or 'hang' (no answer until aborted).
 * `failWhen(record)` does the same for chosen requests only, returning 'error' or 'throw'.
 * Every request is recorded in `queries`.
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
    'email', 'phone', 'additional_phones', 'date_of_joining', 'date_of_exit', 'employment_status', 'performance_tag', 'seniority',
    'is_archived', 'archived_at', 'archive_reason', 'user_id', 'photo_path', 'geofence_exempt', 'created_at', 'updated_at'],
  hr_branches: ['id', 'name', 'is_active', 'latitude', 'longitude', 'geofence_radius_m', 'office_ips', 'created_at', 'updated_at'],
  hr_departments: ['id', 'name', 'is_active', 'source', 'created_at', 'updated_at'],
  hr_attendance_accounts: ['id', 'employee_id', 'status', 'password_hash', 'password_set_at', 'sessions_valid_from',
    'failed_attempts', 'locked_until', 'last_login_at', 'created_at', 'updated_at'],
  locations: ['id', 'name'],
  // team_app's own: db/migrations/20261101000000_hr_ess_sessions.sql.
  hr_ess_sessions: ['id', 'family_id', 'employee_id', 'login_kind', 'user_id', 'location_name', 'method', 'signed_in_at',
    'install_id', 'device_label', 'refresh_hash', 'created_at', 'last_used_at', 'expires_at', 'replaced_by', 'revoked_at',
    'revoked_reason'],
};

/** The unique keys the stand-in enforces, as the migrations declare them. */
const UNIQUE = {
  hr_ess_sessions: [
    { name: 'hr_ess_sessions_pkey', columns: ['id'] },
    { name: 'hr_ess_sessions_refresh_hash_key', columns: ['refresh_hash'] },
    // One live row per family (the partial unique index).
    { name: 'hr_ess_sessions_live_family_key', columns: ['family_id'], where: (row) => row.revoked_at == null },
  ],
};

/** timestamptz columns of team_app's own tables, answered in PostgREST's spelling. */
const TIMESTAMPS = {
  hr_ess_sessions: new Set(['signed_in_at', 'created_at', 'last_used_at', 'expires_at', 'revoked_at']),
};

const clone = (value) => JSON.parse(JSON.stringify(value));

/** 2026-10-16T06:30:00.000Z -> 2026-10-16T06:30:00+00:00, as PostgREST writes a timestamptz. */
function postgrestTime(value) {
  if (typeof value !== 'string' || Number.isNaN(Date.parse(value))) return value;
  const iso = new Date(value).toISOString();
  return `${iso.slice(0, 19)}${iso.slice(19, 23) === '.000' ? '' : iso.slice(19, 23)}+00:00`;
}

const missingTable = (table) => ({ data: null, error: { code: 'PGRST205', message: `Could not find the table 'public.${table}' in the schema cache` } });
const missingColumn = (table, column) => ({ data: null, error: { code: '42703', message: `column ${table}.${column} does not exist` } });
const duplicate = (key) => ({ data: null, error: { code: '23505', message: `duplicate key value violates unique constraint "${key}"` } });

/** The first unique key `candidate` would break among `rows` (itself excepted), or null. */
function brokenKey(table, rows, candidate) {
  for (const key of UNIQUE[table] || []) {
    if (key.where && !key.where(candidate)) continue;
    const value = key.columns.map((c) => candidate[c] ?? null);
    if (value.some((v) => v === null)) continue;
    const clash = rows.some((row) => row !== candidate
      && (!key.where || key.where(row))
      && key.columns.every((c, i) => (row[c] ?? null) === value[i]));
    if (clash) return key.name;
  }
  return null;
}

class Query {
  constructor(fake, table) {
    this.fake = fake;
    this.table = table;
    this.op = 'select';
    this.columns = null;
    this.values = null;
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

  insert(rows) {
    this.op = 'insert';
    this.values = clone(Array.isArray(rows) ? rows : [rows]);
    return this;
  }

  update(values) {
    this.op = 'update';
    this.values = clone(values);
    return this;
  }

  /** Filters are [column, value] for eq, and [column, value, operator] for the others. */
  eq(column, value) {
    this.filters.push([column, value]);
    return this;
  }

  is(column, value) {
    this.filters.push([column, value, 'is']);
    return this;
  }

  not(column, operator, value) {
    if (operator !== 'is') throw new Error(`not(${column}, ${operator}): only "is" is supported here`);
    this.filters.push([column, value, 'not.is']);
    return this;
  }

  in(column, values) {
    this.filters.push([column, [...values], 'in']);
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

  matches(row) {
    return this.filters.every(([c, v, op]) => {
      const actual = row[c] ?? null;
      if (op === 'is') return actual === v;
      if (op === 'not.is') return actual !== v;
      if (op === 'in') return v.includes(actual);
      return actual === v;
    });
  }

  shape(rows) {
    const times = TIMESTAMPS[this.table];
    return rows.map((row) => Object.fromEntries(this.columns.map((c) => {
      const value = row[c] === undefined ? null : clone(row[c]);
      return [c, times && times.has(c) ? postgrestTime(value) : value];
    })));
  }

  async run() {
    const { fake } = this;
    const record = {
      table: this.table, op: this.op, columns: this.columns || [], filters: this.filters, values: this.values,
      single: this.single, limit: this.max, aborted: false,
    };
    fake.queries.push(record);

    const failure = fake.outage || (fake.failWhen && fake.failWhen(record));
    if (failure === 'throw') throw new TypeError('fetch failed');
    if (failure === 'error') return { data: null, error: { code: '', message: 'TypeError: fetch failed', details: '', hint: '' } };
    if (failure === 'hang') {
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
    for (const column of [...(this.columns || []), ...this.filters.map(([c]) => c)]) {
      if (!known.has(column)) return missingColumn(this.table, column);
    }
    const table = fake.rows(this.table);

    if (this.op === 'insert') {
      for (const row of this.values) {
        const unknown = Object.keys(row).find((c) => !known.has(c));
        if (unknown) return { data: null, error: { code: 'PGRST204', message: `Could not find the '${unknown}' column of '${this.table}' in the schema cache` } };
      }
      const after = [...table];
      for (const row of this.values) {
        after.push(row);
        const key = brokenKey(this.table, after, row);
        if (key) return duplicate(key);
      }
      table.push(...this.values);
      return { data: this.columns ? this.shape(this.values) : null, error: null };
    }

    if (this.op === 'update') {
      const unknown = Object.keys(this.values).find((c) => !known.has(c));
      if (unknown) return { data: null, error: { code: 'PGRST204', message: `Could not find the '${unknown}' column of '${this.table}' in the schema cache` } };
      const hit = table.filter((row) => this.matches(row));
      const before = hit.map((row) => ({ ...row }));
      hit.forEach((row) => Object.assign(row, clone(this.values)));
      const key = hit.map((row) => brokenKey(this.table, table, row)).find(Boolean);
      if (key) {
        hit.forEach((row, i) => { Object.keys(row).forEach((k) => delete row[k]); Object.assign(row, before[i]); });
        return duplicate(key);
      }
      return { data: this.columns ? this.shape(hit) : null, error: null };
    }

    let rows = table.filter((row) => this.matches(row));
    if (this.max !== null) rows = rows.slice(0, this.max);
    const out = this.shape(rows);
    if (this.single) {
      if (out.length > 1) return { data: null, error: { code: 'PGRST116', message: 'JSON object requested, multiple (or no) rows returned' } };
      return { data: out[0] || null, error: null };
    }
    return { data: out, error: null };
  }
}

/**
 * The functions db/migrations/20261101000000_hr_ess_sessions.sql creates, doing what their SQL
 * does (tests/migration.test.js runs the SQL itself on a real Postgres). Each answers as PostgREST
 * would: a RETURNS TABLE function a list of rows, a RETURNS integer one a number.
 */
const FUNCTIONS = {
  hr_ess_session_rotate: {
    table: 'hr_ess_sessions',
    run(fake, { p_session_id, p_new_id, p_refresh_hash, p_now, p_expires_at }) {
      const rows = fake.rows('hr_ess_sessions');
      const old = rows.find((r) => r.id === p_session_id);
      if (!old || old.revoked_at != null || !(Date.parse(old.expires_at) > Date.parse(p_now))) return { data: [], error: null };
      const next = {
        id: p_new_id, family_id: old.family_id, employee_id: old.employee_id, login_kind: old.login_kind, user_id: old.user_id,
        location_name: old.location_name, method: old.method, signed_in_at: old.signed_in_at, install_id: old.install_id,
        device_label: old.device_label, refresh_hash: p_refresh_hash, created_at: p_now, last_used_at: p_now,
        expires_at: p_expires_at, replaced_by: null, revoked_at: null, revoked_reason: null,
      };
      // One transaction: a clash leaves the old row as it was.
      const retired = { ...old, revoked_at: p_now, revoked_reason: 'rotated', replaced_by: p_new_id, last_used_at: p_now };
      const key = brokenKey('hr_ess_sessions', [...rows.filter((r) => r !== old), retired, next], next);
      if (key) return duplicate(key);
      Object.assign(old, retired);
      rows.push(next);
      return {
        data: [{ new_session_id: next.id, session_family_id: next.family_id, new_expires_at: postgrestTime(next.expires_at) }],
        error: null,
      };
    },
  },
  hr_ess_session_revoke: {
    table: 'hr_ess_sessions',
    run(fake, { p_family_id, p_reason, p_now, p_employee_id }) {
      if (!['signed_out', 'reuse', 'password_changed', 'login_off', 'left', 'unlinked', 'expired'].includes(p_reason)) {
        return { data: null, error: { code: 'P0001', message: `hr_ess_session_revoke: ${p_reason} is not a reason to end a sign-in` } };
      }
      let n = 0;
      for (const row of fake.rows('hr_ess_sessions')) {
        if (row.family_id !== p_family_id || row.revoked_at != null) continue;
        if (p_employee_id != null && row.employee_id !== p_employee_id) continue;
        Object.assign(row, { revoked_at: p_now, revoked_reason: p_reason });
        n += 1;
      }
      return { data: n, error: null };
    },
  },
};

class RpcCall {
  constructor(fake, fn, args) {
    this.fake = fake;
    this.fn = fn;
    this.args = args;
  }

  then(onFulfilled, onRejected) {
    return this.run().then(onFulfilled, onRejected);
  }

  async run() {
    const { fake, fn, args } = this;
    const definition = FUNCTIONS[fn];
    const record = { table: definition ? definition.table : null, op: 'rpc', fn, args: clone(args || {}), columns: [], filters: [] };
    fake.queries.push(record);
    const failure = fake.outage || (fake.failWhen && fake.failWhen(record));
    if (failure === 'throw') throw new TypeError('fetch failed');
    if (failure === 'error' || failure === 'hang') return { data: null, error: { code: '', message: 'TypeError: fetch failed', details: '', hint: '' } };
    // A function arrives with its table in one migration, so a missing table means no function.
    if (!definition || !fake.schema.has(definition.table)) {
      return { data: null, error: { code: 'PGRST202', message: `Could not find the function public.${fn} in the schema cache` } };
    }
    return definition.run(fake, clone(args || {}));
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
    failWhen: null,
    from(table) {
      return new Query(fake, table);
    },
    rpc(fn, args) {
      return new RpcCall(fake, fn, args);
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

module.exports = { createFakeSupabase, SCHEMA, UNIQUE, postgrestTime };
