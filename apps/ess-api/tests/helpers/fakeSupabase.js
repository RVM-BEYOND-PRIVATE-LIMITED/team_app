const crypto = require('crypto');

/**
 * An in-memory stand-in for the supabase-js client, so the tests run the real store
 * (src/lib/store.js) against plain arrays and never reach a database.
 *
 * It answers the query shapes the store uses the way PostgREST does where the store depends on
 * it:
 *   - reads: from().select(columns) with .eq(), .neq(), .in(), .is(), .not(column, 'is', null),
 *     .gte(), .gt(), .lte(), .lt(), .order(), .limit() and .abortSignal(), awaited as a list or
 *     through .maybeSingle() or .single();
 *   - writes: .insert(rows), .upsert(rows, { onConflict }) and .update(patch) with the same
 *     filters, returning rows only when .select(columns) follows, as PostgREST does;
 *   - .rpc() for the functions team_app's migrations create, and the BEFORE INSERT triggers they
 *     put on hr_ess_sessions and hr_ess_data_requests (TRIGGERS);
 *   - an unknown table is PGRST205, an unknown function PGRST202; an unknown column selected,
 *     filtered or ordered on is 42703, and an unknown column written is PGRST204;
 *   - a second row on a primary or unique key is 23505, checked against KEYS and UNIQUE below, and
 *     a row breaking one of CHECKS is 23514;
 *   - two rows for maybeSingle(), or anything but one for single(), is PGRST116;
 *   - select('*') throws, because the store must always name its columns.
 * Timestamps of team_app's own tables come back in PostgREST's spelling (+00:00, not Z), so code
 * that compares them as strings fails here as it would in production.
 *
 * Inserted rows get the defaults db/migrations gives the hr_ess_* tables, timed by `now`.
 *
 * `outage` simulates the database being away: 'error' (supabase-js returns an error, as it does
 * when fetch fails), 'throw' (the call itself rejects) or 'hang' (no answer until aborted).
 * `failWhen(record)` does the same for chosen requests only, returning 'error' or 'throw'.
 * Every request is recorded in `queries`.
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
    'email', 'phone', 'additional_phones', 'date_of_joining', 'date_of_exit', 'employment_status', 'performance_tag', 'seniority',
    'is_archived', 'archived_at', 'archive_reason', 'user_id', 'photo_path', 'geofence_exempt', 'created_at', 'updated_at'],
  hr_branches: ['id', 'name', 'is_active', 'latitude', 'longitude', 'geofence_radius_m', 'office_ips', 'created_at', 'updated_at'],
  hr_departments: ['id', 'name', 'is_active', 'source', 'created_at', 'updated_at'],
  hr_attendance_accounts: ['id', 'employee_id', 'status', 'password_hash', 'password_set_at', 'sessions_valid_from',
    'failed_attempts', 'locked_until', 'last_login_at', 'created_at', 'updated_at'],
  locations: ['id', 'name'],
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
  // team_app's own, db/migrations: 20261101000000_hr_ess_sessions.sql
  hr_ess_sessions: ['id', 'family_id', 'employee_id', 'login_kind', 'user_id', 'location_name', 'method', 'signed_in_at',
    'install_id', 'device_label', 'refresh_hash', 'password_fingerprint', 'created_at', 'last_used_at', 'expires_at',
    'replaced_by', 'revoked_at', 'revoked_reason'],
  // and 20261105000000 to 20261105000003
  hr_ess_audit: ['id', 'at', 'actor_user_id', 'actor_employee_id', 'actor_name', 'action', 'target_employee_id', 'details'],
  hr_ess_data_requests: ['id', 'employee_id', 'kind', 'details', 'status', 'created_at', 'resolved_at', 'resolved_by_user_id',
    'resolved_by_name', 'resolution_note'],
  hr_ess_personal_details: ['employee_id', 'date_of_birth', 'blood_group', 'address_line1', 'address_line2', 'city', 'state',
    'pincode', 'emergency_name', 'emergency_relation', 'emergency_phone', 'updated_at', 'updated_by_user_id', 'updated_by_name'],
  hr_ess_mock_location_reports: ['id', 'employee_id', 'branch_id', 'reported_at', 'client_at', 'kind', 'latitude', 'longitude',
    'accuracy_m', 'provider', 'app_version', 'install_id'],
};

/** The unique keys the stand-in enforces besides the primary key (KEYS), as the migrations declare them. */
const UNIQUE = {
  hr_ess_sessions: [
    { name: 'hr_ess_sessions_refresh_hash_key', columns: ['refresh_hash'] },
    // One live row per family (the partial unique index).
    { name: 'hr_ess_sessions_live_family_key', columns: ['family_id'], where: (row) => row.revoked_at == null },
    // One trade per Scheduler sign-in: a family's first row, by person, kind and sign-in time.
    { name: 'hr_ess_sessions_sign_in_key', columns: ['employee_id', 'login_kind', 'signed_in_at'], where: (row) => row.id === row.family_id },
  ],
};

/**
 * The table CHECKs a route relies on the database for, by name, as the migrations declare them:
 * each answers whether a row as written keeps the rule.
 */
const CHECKS = {
  hr_ess_personal_details: {
    hr_ess_personal_details_emergency_chk: (r) => ((r.emergency_name ?? null) === null) === ((r.emergency_phone ?? null) === null)
      && ((r.emergency_relation ?? null) === null || (r.emergency_name ?? null) !== null),
  },
};

/** The first CHECK of CHECKS this row breaks, as Postgres words it, or null. */
function brokenCheck(table, row) {
  const name = Object.entries(CHECKS[table] || {}).find(([, keeps]) => !keeps(row))?.[0];
  return name ? { code: '23514', message: `new row for relation "${table}" violates check constraint "${name}"` } : null;
}

/** hr_ess_password_fingerprint: SHA-256, in hex, of the stored password hash. */
const passwordFingerprint = (hash) => (hash == null ? null : crypto.createHash('sha256').update(String(hash), 'utf8').digest('hex'));

/**
 * The BEFORE INSERT triggers of team_app's migrations, doing what their SQL does
 * (tests/migration.test.js runs the SQL itself). Each may change the row, or answer the error
 * Postgres would.
 */
const TRIGGERS = {
  // hr_ess_sessions_bind_password: a family's first portal row takes the password's fingerprint.
  hr_ess_sessions(fake, row) {
    if (row.login_kind === 'portal' && row.id === row.family_id) {
      const user = fake.rows('users').find((u) => u.id === row.user_id);
      row.password_fingerprint = user ? passwordFingerprint(user.password_hash) : null;
    }
    return null;
  },
  // hr_ess_data_requests_open_limit: at most five open requests each. The stand-in runs one
  // statement at a time, as the advisory lock makes Postgres do for one employee.
  hr_ess_data_requests(fake, row) {
    if (row.status !== 'open') return null;
    const open = fake.rows('hr_ess_data_requests').filter((r) => r.employee_id === row.employee_id && r.status === 'open').length;
    return open >= 5
      ? { code: '23514', message: `hr_ess_data_requests_open_limit: ${row.employee_id} already has 5 open requests` }
      : null;
  },
};

/** timestamptz columns of team_app's own tables, answered in PostgREST's spelling. */
const TIMESTAMPS = {
  hr_ess_sessions: new Set(['signed_in_at', 'created_at', 'last_used_at', 'expires_at', 'revoked_at']),
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
  'not.is': (v, x) => v !== x,
  in: (v, xs) => xs.includes(v),
  gte: (v, x) => v !== null && compare(v, x) >= 0,
  gt: (v, x) => v !== null && compare(v, x) > 0,
  lte: (v, x) => v !== null && compare(v, x) <= 0,
  lt: (v, x) => v !== null && compare(v, x) < 0,
};

const missingTable = (table) => ({ data: null, error: { code: 'PGRST205', message: `Could not find the table 'public.${table}' in the schema cache` } });

/** 2026-10-16T06:30:00.000Z -> 2026-10-16T06:30:00+00:00, as PostgREST writes a timestamptz. */
function postgrestTime(value) {
  if (typeof value !== 'string' || Number.isNaN(Date.parse(value))) return value;
  const iso = new Date(value).toISOString();
  return `${iso.slice(0, 19)}${iso.slice(19, 23) === '.000' ? '' : iso.slice(19, 23)}+00:00`;
}

const missingColumn = (table, column) => ({ data: null, error: { code: '42703', message: `column ${table}.${column} does not exist` } });
const duplicate = (key) => ({ data: null, error: { code: '23505', message: `duplicate key value violates unique constraint "${key}"` } });

const primaryKey = (table) => KEYS[table] || ['id'];

/**
 * The first key `candidate` would break among `rows` (itself excepted), or null: the primary key
 * (KEYS, `id` by default), then the table's UNIQUE keys.
 */
function brokenKey(table, rows, candidate) {
  const keys = [{ name: `${table}_pkey`, columns: primaryKey(table) }, ...(UNIQUE[table] || [])];
  for (const key of keys) {
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
    this.values = clone(Array.isArray(rows) ? rows : [rows]);
    return this;
  }

  upsert(rows, { onConflict } = {}) {
    this.op = 'upsert';
    this.values = clone(Array.isArray(rows) ? rows : [rows]);
    this.onConflict = onConflict ? onConflict.split(',').map((c) => c.trim()) : null;
    return this;
  }

  update(patch) {
    this.op = 'update';
    this.values = [clone(patch)];
    return this;
  }

  where(test, column, value) {
    this.conditions.push([test, column, value]);
    return this;
  }

  eq(column, value) { return this.where('eq', column, value); }
  neq(column, value) { return this.where('neq', column, value); }
  is(column, value) { return this.where('is', column, value); }
  in(column, values) { return this.where('in', column, [...values]); }
  gte(column, value) { return this.where('gte', column, value); }
  gt(column, value) { return this.where('gt', column, value); }
  lte(column, value) { return this.where('lte', column, value); }
  lt(column, value) { return this.where('lt', column, value); }

  not(column, operator, value) {
    if (operator !== 'is') throw new Error(`not(${column}, ${operator}): only "is" is supported here`);
    return this.where('not.is', column, value);
  }

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
    const times = TIMESTAMPS[this.table];
    return rows.map((row) => Object.fromEntries(columns.map((c) => {
      const value = row[c] === undefined ? null : clone(row[c]);
      return [c, times && times.has(c) ? postgrestTime(value) : value];
    })));
  }

  async run() {
    const { fake } = this;
    const record = {
      op: this.op,
      table: this.table,
      columns: this.op === 'select' ? this.columns : (this.returning || []),
      // [column, value] for an equality filter and [column, value, operator] for the others, the
      // shape the older tests read; every condition, with its test first, in `conditions`.
      filters: this.conditions.map(([t, c, v]) => (t === 'eq' ? [c, v] : [c, v, t])),
      conditions: this.conditions,
      values: clone(this.values),
      single: this.expect !== null,
      limit: this.max,
      aborted: false,
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
    const read = [...(this.columns || []), ...(this.returning || []), ...this.conditions.map(([, c]) => c), ...this.orders.map(([c]) => c)];
    for (const column of read) {
      if (!known.has(column)) return missingColumn(this.table, column);
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

  /** One statement, all or nothing, as Postgres runs it: a broken key leaves the table as it was. */
  write(rows) {
    const { fake, table } = this;
    const key = primaryKey(table);
    const at = fake.now().toISOString();
    const sameKey = (a, b, columns) => columns.every((c) => (a[c] ?? null) === (b[c] ?? null));

    if (this.op === 'update') {
      const changed = rows.filter((row) => this.matches(row));
      const before = changed.map((row) => clone(row));
      for (const row of changed) Object.assign(row, clone(this.values[0]));
      const broken = changed.map((row) => brokenKey(table, rows, row)).find(Boolean);
      if (broken) {
        changed.forEach((row, i) => { Object.keys(row).forEach((k) => delete row[k]); Object.assign(row, before[i]); });
        return duplicate(broken);
      }
      return { rows: changed };
    }

    const written = [];
    const added = [];
    const undo = [];
    /** Undoes the statement's earlier rows and answers `result`, an error as PostgREST gives it. */
    const fail = (result) => {
      for (const row of added) rows.splice(rows.indexOf(row), 1);
      for (const [row, was] of undo) { Object.keys(row).forEach((k) => delete row[k]); Object.assign(row, was); }
      return result;
    };
    for (const value of this.values) {
      const conflictOn = this.op === 'upsert' ? (this.onConflict || key) : null;
      const existing = conflictOn ? rows.find((row) => sameKey(row, value, conflictOn)) : null;
      if (existing) {
        // PostgREST's merge-duplicates: only the columns sent are written.
        undo.push([existing, clone(existing)]);
        Object.assign(existing, clone(value));
        const checked = brokenCheck(table, existing);
        if (checked) return fail({ data: null, error: checked });
        const broken = brokenKey(table, rows, existing);
        if (broken) return fail(duplicate(broken));
        written.push(existing);
        continue;
      }
      const row = {
        ...(key.includes('id') ? { id: crypto.randomUUID() } : {}),
        ...(DEFAULTS[table] ? DEFAULTS[table](at) : {}),
        ...clone(value),
      };
      const refused = TRIGGERS[table] ? TRIGGERS[table](fake, row) : null;
      if (refused) return fail({ data: null, error: refused });
      const checked = brokenCheck(table, row);
      if (checked) return fail({ data: null, error: checked });
      const broken = brokenKey(table, [...rows, row], row);
      if (broken) return fail(duplicate(broken));
      rows.push(row);
      added.push(row);
      written.push(row);
    }
    return { rows: written };
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
        device_label: old.device_label, refresh_hash: p_refresh_hash, password_fingerprint: old.password_fingerprint ?? null,
        created_at: p_now, last_used_at: p_now, expires_at: p_expires_at, replaced_by: null, revoked_at: null, revoked_reason: null,
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
  hr_ess_session_password_current: {
    table: 'hr_ess_sessions',
    run(fake, { p_session_id }) {
      const session = fake.rows('hr_ess_sessions').find((r) => r.id === p_session_id && r.login_kind === 'portal');
      const user = session ? fake.rows('users').find((u) => u.id === session.user_id) : null;
      if (!session || !user) return { data: null, error: null };
      return { data: (session.password_fingerprint ?? null) === passwordFingerprint(user.password_hash), error: null };
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
 * @param {{ now?: () => Date }} [options]   the database's clock, for its DEFAULT now() columns
 */
function createFakeSupabase(tables = {}, { now = () => new Date() } = {}) {
  const fake = {
    tables: clone(tables),
    schema: new Map(Object.entries(SCHEMA).map(([t, cols]) => [t, new Set(cols)])),
    queries: [],
    outage: null,
    failWhen: null,
    now,
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
    /** The writes made, oldest first: { op, table, values, conditions }. */
    writes() {
      return fake.queries.filter((q) => q.op !== 'select');
    },
  };
  return fake;
}

module.exports = { createFakeSupabase, SCHEMA, UNIQUE, postgrestTime, passwordFingerprint };
