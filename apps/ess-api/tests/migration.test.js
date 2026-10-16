const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

/**
 * db/migrations/20261101000000_hr_ess_sessions.sql and its rollback on a real Postgres 17, in a
 * throwaway container that is removed afterwards. Opt in with ESS_MIGRATION_TEST=docker (Docker
 * must be running); without it, as in CI today, this is skipped. Nothing here reaches a real
 * database: the container has no port open, and its two Scheduler tables are stand-ins holding
 * only the keys the migration's foreign keys point at.
 *
 * It applies the file twice, as KP may in the SQL editor, checks what the ESS relies on (the
 * one-live-row-per-family key, the one-trade-per-sign-in key, the checks, row-level security, who
 * may reach the table and the functions), runs the functions and the password trigger as the
 * service role, and then rolls back, twice, and applies again. tests/helpers/fakeSupabase.js answers the functions the way this shows the SQL does.
 */

const enabled = process.env.ESS_MIGRATION_TEST === 'docker';
const ROOT = path.join(__dirname, '..', '..', '..');
const MIGRATION = fs.readFileSync(path.join(ROOT, 'db', 'migrations', '20261101000000_hr_ess_sessions.sql'), 'utf8');
const ROLLBACK = fs.readFileSync(path.join(ROOT, 'db', 'rollbacks', '20261101000000_hr_ess_sessions.sql'), 'utf8');

const U1 = 'a0000000-0000-4000-8000-000000000001';
const E1 = 'e0000000-0000-4000-8000-000000000001';
const E2 = 'e0000000-0000-4000-8000-000000000002';
const ROTATE = 'public.hr_ess_session_rotate(uuid, uuid, text, timestamptz, timestamptz)';
const REVOKE = 'public.hr_ess_session_revoke(uuid, text, timestamptz, uuid)';
const CURRENT = 'public.hr_ess_session_password_current(uuid)';
const FINGERPRINT = 'public.hr_ess_password_fingerprint(text)';
const U1_HASH = '$2b$10$stand.in.hash.of.the.hr.login';

/** The Scheduler tables the foreign keys reach, and Supabase's three API roles with its default grants. */
const SCHEDULER_STAND_INS = `
  -- password_hash: read inside the database by the password fingerprint, never by the ESS.
  CREATE TABLE public.users (id uuid PRIMARY KEY, username text, password_hash text NOT NULL DEFAULT '!');
  CREATE TABLE public.hr_employees (id uuid PRIMARY KEY, full_name text);
  INSERT INTO public.users VALUES ('${U1}', 'hr.login', '${U1_HASH}');
  INSERT INTO public.hr_employees VALUES ('${E1}', 'Test HR'), ('${E2}', 'Test Other');
  CREATE ROLE anon NOLOGIN;
  CREATE ROLE authenticated NOLOGIN;
  CREATE ROLE service_role NOLOGIN BYPASSRLS;
  GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
  -- Supabase's service role reads every table; these two predate the default grants below.
  GRANT SELECT ON public.users, public.hr_employees TO service_role;
  -- What Supabase hands every new table and function in public; the migration takes it back.
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role;
`;

const literal = (v) => (v === null ? 'NULL' : `'${String(v).replace(/'/g, "''")}'`);

let rows = 0;
/**
 * An INSERT of one session row: a live portal sign-in of E1 unless told otherwise, each signed in
 * a second after the one before, since one Scheduler sign-in is kept once (hr_ess_sessions_sign_in_key).
 * `signedIn` is that time as psql prints it.
 */
function insert(change = {}) {
  rows += 1;
  const id = `5a000000-0000-4000-8000-${String(rows).padStart(12, '0')}`;
  const signedAt = new Date(Date.parse('2026-10-16T06:00:00Z') + rows * 1000).toISOString().replace('.000Z', 'Z');
  const row = {
    id, family_id: id, employee_id: E1, login_kind: 'portal', user_id: U1, location_name: 'Faridabad', method: null,
    signed_in_at: signedAt, install_id: 'install-0123456789abcdef', device_label: 'Test phone',
    refresh_hash: String(rows).padStart(64, 'a'), created_at: '2026-10-16T06:30:00Z', last_used_at: '2026-10-16T06:30:00Z',
    expires_at: '2027-01-14T06:30:00Z', ...change,
  };
  return {
    id: row.id,
    family: row.family_id,
    signedIn: `${row.signed_in_at.slice(0, 10)} ${row.signed_in_at.slice(11, 19)}+00`,
    sql: `INSERT INTO public.hr_ess_sessions (${Object.keys(row).join(', ')}) VALUES (${Object.values(row).map(literal).join(', ')});`,
  };
}

describe.skipIf(!enabled)('the hr_ess_sessions migration on a throwaway Postgres 17', { timeout: 60 * 1000 }, () => {
  let container = null;

  /** Runs SQL in the container, as the superuser KP applies migrations as, or as `role`. */
  const psql = (sql, { role } = {}) => execFileSync(
    'docker',
    ['exec', '-i', container, 'psql', '-X', '-q', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres', '-At', '-F', '|'],
    { input: role ? `SET ROLE ${role};\n${sql}` : sql, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] },
  ).trim();

  /** The error Postgres gives for this SQL, or null when it runs. */
  const failure = (sql, options) => {
    try {
      psql(sql, options);
      return null;
    } catch (e) {
      return String(e.stderr || e.message);
    }
  };

  beforeAll(async () => {
    container = execFileSync('docker', ['run', '-d', '--rm', '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', 'postgres:17-alpine'], { encoding: 'utf8' }).trim();
    // The image starts a server for its own set-up, stops it, and starts the real one: wait for that.
    const deadline = Date.now() + 90 * 1000;
    for (;;) {
      const logs = execFileSync('docker', ['logs', container], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
      if (/init process complete/.test(logs)) {
        try {
          if (psql('SELECT 1') === '1') break;
        } catch { /* still starting */ }
      }
      if (Date.now() > deadline) throw new Error('Postgres did not start in the container');
      await new Promise((resolve) => { setTimeout(resolve, 500); });
    }
    psql(SCHEDULER_STAND_INS);
  }, 120 * 1000);

  afterAll(() => {
    if (container) execFileSync('docker', ['rm', '-f', container], { stdio: 'ignore' });
  });

  it('applies, and applies again', () => {
    expect(failure(MIGRATION)).toBeNull();
    expect(failure(MIGRATION)).toBeNull();
    expect(psql("SELECT to_regclass('public.hr_ess_sessions') IS NOT NULL")).toBe('t');
  });

  it('turns row-level security on, with no policy, so only the service role reaches the rows', () => {
    expect(psql("SELECT relrowsecurity FROM pg_class WHERE oid = 'public.hr_ess_sessions'::regclass")).toBe('t');
    expect(psql("SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'hr_ess_sessions'")).toBe('0');
  });

  it('keeps the API roles away from the table and the functions, and lets the service role use them', () => {
    for (const role of ['anon', 'authenticated']) {
      for (const privilege of ['SELECT', 'INSERT', 'UPDATE', 'DELETE']) {
        expect(psql(`SELECT has_table_privilege('${role}', 'public.hr_ess_sessions', '${privilege}')`), `${role} ${privilege}`).toBe('f');
      }
      for (const fn of [ROTATE, REVOKE, CURRENT, FINGERPRINT, 'public.hr_ess_sessions_bind_password()']) {
        expect(psql(`SELECT has_function_privilege('${role}', '${fn}', 'EXECUTE')`), `${role} ${fn}`).toBe('f');
      }
      expect(failure('SELECT count(*) FROM public.hr_ess_sessions;', { role })).toMatch(/permission denied/);
    }
    for (const privilege of ['SELECT', 'INSERT', 'UPDATE']) {
      expect(psql(`SELECT has_table_privilege('service_role', 'public.hr_ess_sessions', '${privilege}')`)).toBe('t');
    }
    expect(psql(`SELECT has_function_privilege('service_role', '${ROTATE}', 'EXECUTE')`)).toBe('t');
    expect(psql(`SELECT has_function_privilege('service_role', '${REVOKE}', 'EXECUTE')`)).toBe('t');
    expect(psql(`SELECT has_function_privilege('service_role', '${CURRENT}', 'EXECUTE')`)).toBe('t');
    expect(psql(`SELECT has_function_privilege('public', '${ROTATE}', 'EXECUTE')`)).toBe('f');
    expect(psql(`SELECT has_function_privilege('public', '${CURRENT}', 'EXECUTE')`)).toBe('f');
  });

  it('has the indexes the ESS reads by', () => {
    const indexes = psql("SELECT indexname || ' ' || indexdef FROM pg_indexes WHERE tablename = 'hr_ess_sessions' ORDER BY indexname").split('\n');
    expect(indexes.map((i) => i.split(' ')[0])).toEqual([
      'hr_ess_sessions_family_idx', 'hr_ess_sessions_live_employee_idx', 'hr_ess_sessions_live_family_key', 'hr_ess_sessions_pkey',
      'hr_ess_sessions_refresh_hash_key', 'hr_ess_sessions_sign_in_key',
    ]);
    expect(indexes.find((i) => i.startsWith('hr_ess_sessions_sign_in_key')))
      .toMatch(/UNIQUE INDEX .*\(employee_id, login_kind, signed_in_at\) WHERE \(id = family_id\)/);
    expect(indexes.find((i) => i.startsWith('hr_ess_sessions_live_family_key'))).toMatch(/UNIQUE INDEX .*\(family_id\) WHERE \(revoked_at IS NULL\)/);
    expect(indexes.find((i) => i.startsWith('hr_ess_sessions_live_employee_idx'))).toMatch(/\(employee_id\) WHERE \(revoked_at IS NULL\)/);
  });

  describe('refuses a row the ESS must never write', () => {
    it('a second live row in one family, though a retired one may sit beside the live one', () => {
      const first = insert();
      expect(failure(first.sql, { role: 'service_role' })).toBeNull();
      expect(failure(insert({ family_id: first.family }).sql)).toMatch(/hr_ess_sessions_live_family_key/);
      expect(failure(insert({ family_id: first.family, revoked_at: '2026-10-16T06:31:00Z', revoked_reason: 'rotated' }).sql)).toBeNull();
    });

    it('a refresh hash twice', () => {
      expect(failure(insert({ refresh_hash: '1'.repeat(64) }).sql)).toBeNull();
      expect(failure(insert({ refresh_hash: '1'.repeat(64) }).sql)).toMatch(/hr_ess_sessions_refresh_hash_key/);
    });

    it.each([
      ['a portal sign-in with no account', { user_id: null }, /hr_ess_sessions_kind_fields/],
      ['a portal sign-in with a method', { method: 'otp' }, /hr_ess_sessions_kind_fields/],
      ['an attendance sign-in with an account', { login_kind: 'attendance', method: 'otp' }, /hr_ess_sessions_kind_fields/],
      ['an attendance sign-in with no method', { login_kind: 'attendance', user_id: null, location_name: null }, /hr_ess_sessions_kind_fields/],
      ['an attendance sign-in with a branch', { login_kind: 'attendance', user_id: null, method: 'pw' }, /hr_ess_sessions_kind_fields/],
      ['another kind of sign-in', { login_kind: 'student' }, /check constraint/],
      ['another method', { login_kind: 'attendance', user_id: null, location_name: null, method: 'sms' }, /check constraint/],
      ['an install id that is too short', { install_id: 'short' }, /hr_ess_sessions_install_id/],
      ['a phone name over 80 characters', { device_label: 'x'.repeat(81) }, /hr_ess_sessions_device_label/],
      ['a refresh hash that is not sha256 hex', { refresh_hash: 'not-a-hash' }, /hr_ess_sessions_refresh_hash/],
      ['an end with no reason', { revoked_at: '2026-10-16T07:00:00Z' }, /hr_ess_sessions_revoked_with_reason/],
      ['a reason with no end', { revoked_reason: 'signed_out' }, /hr_ess_sessions_revoked_with_reason/],
      ['a reason that is not one', { revoked_at: '2026-10-16T07:00:00Z', revoked_reason: 'forgot' }, /check constraint/],
      ['an expiry before it began', { expires_at: '2026-10-16T06:00:00Z' }, /hr_ess_sessions_lifetime/],
      ['an employee who does not exist', { employee_id: 'e0000000-0000-4000-8000-000000000999' }, /foreign key/],
      ['a password fingerprint on an attendance sign-in', { login_kind: 'attendance', user_id: null, location_name: null, method: 'otp', password_fingerprint: 'a'.repeat(64) }, /hr_ess_sessions_password_fingerprint/],
    ])('%s', (_label, change, error) => {
      expect(failure(insert(change).sql)).toMatch(error);
    });

    it('a second trade of one Scheduler sign-in, ended or not, though a later turn of it is no trade', () => {
      const first = insert();
      psql(first.sql, { role: 'service_role' });
      const signedAt = psql(`SELECT signed_in_at FROM public.hr_ess_sessions WHERE id = '${first.id}'`);
      const again = insert({ signed_in_at: signedAt });
      expect(failure(again.sql, { role: 'service_role' })).toMatch(/hr_ess_sessions_sign_in_key/);
      psql(`SELECT public.hr_ess_session_revoke('${first.family}', 'signed_out', '2026-10-16T07:00:00Z');`, { role: 'service_role' });
      expect(failure(insert({ signed_in_at: signedAt }).sql, { role: 'service_role' })).toMatch(/hr_ess_sessions_sign_in_key/);
      // The same person and time as an attendance sign-in, and a row that is not a family's first.
      expect(failure(insert({ signed_in_at: signedAt, login_kind: 'attendance', user_id: null, location_name: null, method: 'otp' }).sql)).toBeNull();
      expect(failure(insert({ signed_in_at: signedAt, family_id: first.family, revoked_at: '2026-10-16T06:40:00Z', revoked_reason: 'rotated' }).sql)).toBeNull();
    });

    it('but takes a live attendance sign-in', () => {
      expect(failure(insert({ login_kind: 'attendance', user_id: null, location_name: null, method: 'otp' }).sql, { role: 'service_role' })).toBeNull();
    });
  });

  describe('hr_ess_session_rotate, as the service role', () => {
    const rotate = (sessionId, newId, hash, now = '2026-10-16T07:30:00Z', expires = '2027-01-14T07:30:00Z') => psql(
      `SELECT new_session_id || '|' || session_family_id || '|' || new_expires_at FROM public.hr_ess_session_rotate('${sessionId}', '${newId}', '${hash}', '${now}', '${expires}');`,
      { role: 'service_role' },
    );

    it('retires a live row and adds the next one in its family, once', () => {
      const row = insert();
      psql(row.sql, { role: 'service_role' });
      const next = '5a000000-0000-4000-8000-0000000007a1';
      expect(rotate(row.id, next, 'b'.repeat(64))).toBe(`${next}|${row.family}|2027-01-14 07:30:00+00`);
      expect(psql(`SELECT revoked_reason || ' ' || replaced_by || ' ' || last_used_at FROM public.hr_ess_sessions WHERE id = '${row.id}'`))
        .toBe(`rotated ${next} 2026-10-16 07:30:00+00`);
      expect(psql(`SELECT family_id || ' ' || signed_in_at || ' ' || install_id || ' ' || coalesce(revoked_reason, 'live') FROM public.hr_ess_sessions WHERE id = '${next}'`))
        .toBe(`${row.family} ${row.signedIn} install-0123456789abcdef live`);
      // The same token again: no row, and nothing changes.
      expect(rotate(row.id, '5a000000-0000-4000-8000-0000000007a2', 'c'.repeat(64))).toBe('');
      expect(psql(`SELECT count(*) FROM public.hr_ess_sessions WHERE family_id = '${row.family}'`)).toBe('2');
    });

    it('does nothing for a row that has expired, ended, or never existed', () => {
      const expired = insert({ expires_at: '2026-10-16T07:00:00Z' });
      const ended = insert({ revoked_at: '2026-10-16T07:00:00Z', revoked_reason: 'signed_out' });
      psql(expired.sql + ended.sql);
      expect(rotate(expired.id, '5a000000-0000-4000-8000-0000000007b1', 'd'.repeat(64))).toBe('');
      expect(rotate(ended.id, '5a000000-0000-4000-8000-0000000007b2', 'e'.repeat(64))).toBe('');
      expect(rotate('5a000000-0000-4000-8000-0000000007bf', '5a000000-0000-4000-8000-0000000007b3', 'f'.repeat(64))).toBe('');
      expect(psql(`SELECT count(*) FROM public.hr_ess_sessions WHERE id IN ('5a000000-0000-4000-8000-0000000007b1', '5a000000-0000-4000-8000-0000000007b2', '5a000000-0000-4000-8000-0000000007b3')`)).toBe('0');
    });

    it('leaves the old row live when the next one cannot be added', () => {
      const row = insert();
      psql(row.sql);
      const taken = psql(`SELECT refresh_hash FROM public.hr_ess_sessions WHERE id <> '${row.id}' LIMIT 1`);
      expect(failure(`SELECT * FROM public.hr_ess_session_rotate('${row.id}', '5a000000-0000-4000-8000-0000000007c1', '${taken}', '2026-10-16T07:30:00Z', '2027-01-14T07:30:00Z');`, { role: 'service_role' }))
        .toMatch(/refresh_hash_key/);
      expect(psql(`SELECT revoked_at IS NULL FROM public.hr_ess_sessions WHERE id = '${row.id}'`)).toBe('t');
    });
  });

  describe('the portal password fingerprint', () => {
    const fingerprintOf = (id) => psql(`SELECT coalesce(password_fingerprint, 'none') FROM public.hr_ess_sessions WHERE id = '${id}'`);
    const current = (id) => psql(`SELECT coalesce(public.hr_ess_session_password_current('${id}')::text, 'null');`, { role: 'service_role' });
    const sha256 = (text) => crypto.createHash('sha256').update(text, 'utf8').digest('hex');

    it('is taken from users.password_hash as a portal sign-in goes in, whatever the insert says', () => {
      const sent = insert({ password_fingerprint: 'f'.repeat(64) });
      psql(sent.sql, { role: 'service_role' });
      expect(fingerprintOf(sent.id)).toBe(sha256(U1_HASH));
      const attendance = insert({ login_kind: 'attendance', user_id: null, location_name: null, method: 'pw' });
      psql(attendance.sql, { role: 'service_role' });
      expect(fingerprintOf(attendance.id)).toBe('none');
    });

    it('is copied to every turn of the sign-in, and says whether the password is still the same', () => {
      const row = insert();
      psql(row.sql, { role: 'service_role' });
      expect(current(row.id)).toBe('true');
      const next = '5a000000-0000-4000-8000-0000000007d1';
      psql(`SELECT * FROM public.hr_ess_session_rotate('${row.id}', '${next}', '${'d'.repeat(63)}1', '2026-10-16T07:30:00Z', '2027-01-14T07:30:00Z');`, { role: 'service_role' });
      expect(fingerprintOf(next)).toBe(sha256(U1_HASH));
      expect(current(next)).toBe('true');
      // An admin's reset in User Management writes password_hash and nothing else.
      psql(`UPDATE public.users SET password_hash = '$2b$10$a.new.hash' WHERE id = '${U1}';`);
      expect(current(next)).toBe('false');
      // A rotation after the change still carries the fingerprint of the password it was kept with.
      const after = '5a000000-0000-4000-8000-0000000007d2';
      psql(`SELECT * FROM public.hr_ess_session_rotate('${next}', '${after}', '${'d'.repeat(63)}2', '2026-10-16T08:30:00Z', '2027-01-14T08:30:00Z');`, { role: 'service_role' });
      expect(current(after)).toBe('false');
      psql(`UPDATE public.users SET password_hash = '${U1_HASH}' WHERE id = '${U1}';`);
    });

    it('answers null for an attendance sign-in and for a session that does not exist', () => {
      const attendance = insert({ login_kind: 'attendance', user_id: null, location_name: null, method: 'otp' });
      psql(attendance.sql);
      expect(current(attendance.id)).toBe('null');
      expect(current('5a000000-0000-4000-8000-0000000007df')).toBe('null');
    });
  });

  describe('hr_ess_session_revoke, as the service role', () => {
    const revoke = (family, reason, employee = null) => psql(
      `SELECT public.hr_ess_session_revoke('${family}', ${literal(reason)}, '2026-10-16T08:00:00Z', ${employee ? `'${employee}'` : 'NULL'});`,
      { role: 'service_role' },
    );

    it('ends a family\'s live row, and only an employee\'s own when one is named', () => {
      const row = insert();
      psql(row.sql);
      expect(revoke(row.family, 'signed_out', E2)).toBe('0');
      expect(psql(`SELECT revoked_at IS NULL FROM public.hr_ess_sessions WHERE id = '${row.id}'`)).toBe('t');
      expect(revoke(row.family, 'signed_out', E1)).toBe('1');
      expect(psql(`SELECT revoked_reason || ' ' || revoked_at FROM public.hr_ess_sessions WHERE id = '${row.id}'`)).toBe('signed_out 2026-10-16 08:00:00+00');
      expect(revoke(row.family, 'reuse')).toBe('0');
    });

    it.each([['rotated'], ['forgot'], [null]])('refuses %s as a reason', (reason) => {
      const row = insert();
      psql(row.sql);
      expect(failure(`SELECT public.hr_ess_session_revoke('${row.family}', ${literal(reason)}, '2026-10-16T08:00:00Z');`, { role: 'service_role' }))
        .toMatch(/is not a reason to end a sign-in/);
    });
  });

  it('goes with the employee record and the login it belongs to', () => {
    psql(`INSERT INTO public.users VALUES ('a0000000-0000-4000-8000-000000000002', 'gone.login', '!');
          INSERT INTO public.hr_employees VALUES ('e0000000-0000-4000-8000-000000000003', 'Gone');`);
    const portal = insert({ employee_id: E2, user_id: 'a0000000-0000-4000-8000-000000000002' });
    const attendance = insert({ employee_id: 'e0000000-0000-4000-8000-000000000003', login_kind: 'attendance', user_id: null, location_name: null, method: 'pw' });
    psql(portal.sql + attendance.sql);
    psql("DELETE FROM public.users WHERE id = 'a0000000-0000-4000-8000-000000000002'; DELETE FROM public.hr_employees WHERE id = 'e0000000-0000-4000-8000-000000000003';");
    expect(psql(`SELECT count(*) FROM public.hr_ess_sessions WHERE id IN ('${portal.id}', '${attendance.id}')`)).toBe('0');
  });

  it('rolls back, twice, leaving the Scheduler\'s tables alone, and applies again', () => {
    expect(failure(ROLLBACK)).toBeNull();
    expect(failure(ROLLBACK)).toBeNull();
    expect(psql("SELECT to_regclass('public.hr_ess_sessions') IS NULL")).toBe('t');
    expect(psql("SELECT count(*) FROM pg_proc WHERE proname IN ('hr_ess_session_rotate', 'hr_ess_session_revoke', 'hr_ess_session_password_current', 'hr_ess_sessions_bind_password', 'hr_ess_password_fingerprint')")).toBe('0');
    expect(psql('SELECT (SELECT count(*) FROM public.users) || \' \' || (SELECT count(*) FROM public.hr_employees)')).toBe('1 2');
    expect(failure(MIGRATION)).toBeNull();
    expect(psql("SELECT to_regclass('public.hr_ess_sessions') IS NOT NULL")).toBe('t');
  });
});
