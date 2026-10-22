const fs = require('fs');
const path = require('path');
const { createSupabaseStore, storeError, COLUMNS, NOT_INSTALLED_CODES, NIL_UUID } = require('../src/lib/store');
const { HttpError } = require('../src/lib/errors');
const { createFakeSupabase } = require('./helpers/fakeSupabase');
const { company, sessionRow } = require('./helpers/fixtures');
const { TEST_ENV } = require('./helpers/constants');
const { loadConfig } = require('../src/config');

/** lib/store.js over the in-memory client: what it asks the database for, and how a failure comes back. */

const setup = () => {
  const world = company();
  const db = createFakeSupabase(world.tables);
  const store = createSupabaseStore(loadConfig(TEST_ENV), { client: db });
  return { db, store, people: world.people };
};

describe('the reads', () => {
  it('each name their columns and none selects a password hash', async () => {
    const { db, store, people } = setup();
    await store.getUser(people.hr.user.id);
    await store.getEmployeeById(people.hr.employee.id);
    await store.getEmployeeByUserId(people.hr.user.id);
    await store.getEmployeeName(people.ceo.employee.id);
    await store.getBranch(people.hr.employee.branch_id);
    await store.getDepartment(people.hr.employee.department_id);
    await store.getAttendanceAccount(people.attendance.employee.id);
    await store.listDirectReports(people.ceo.employee.id);
    await store.ping();
    expect(db.queries).toHaveLength(9);
    for (const q of db.queries) {
      expect(q.columns.length).toBeGreaterThan(0);
      expect(q.columns).not.toContain('password_hash');
    }
  });

  it('return only the whitelisted columns', async () => {
    const { store, people } = setup();
    const user = await store.getUser(people.hr.user.id);
    expect(user).toEqual({ id: people.hr.user.id, role: 'hr', faculty_id: null });
    const account = await store.getAttendanceAccount(people.attendance.employee.id);
    expect(Object.keys(account).sort()).toEqual(['employee_id', 'id', 'password_set_at', 'sessions_valid_from', 'status']);
    const employee = await store.getEmployeeByUserId(people.faculty.user.id);
    expect(Object.keys(employee).sort()).toEqual(COLUMNS.employee.split(', ').sort());
    expect(employee).not.toHaveProperty('phone');
    expect(employee).not.toHaveProperty('photo_path');
  });

  it('find a portal login\'s employee through hr_employees.user_id', async () => {
    const { db, store, people } = setup();
    expect((await store.getEmployeeByUserId(people.hod.user.id)).id).toBe(people.hod.employee.id);
    expect(db.queries[0]).toMatchObject({ table: 'hr_employees', filters: [['user_id', people.hod.user.id]], single: true });
  });

  it('answer null for a row that is not there', async () => {
    const { store } = setup();
    const nobody = 'a0000000-0000-4000-8000-000000000999';
    expect(await store.getUser(nobody)).toBeNull();
    expect(await store.getEmployeeById(nobody)).toBeNull();
    expect(await store.getAttendanceAccount(nobody)).toBeNull();
  });

  it('list a manager\'s reports that are not archived, leaving the on-strength rule to the caller', async () => {
    const { db, store, people } = setup();
    db.tables.hr_employees.find((e) => e.id === people.admin.employee.id).is_archived = true;
    const reports = await store.listDirectReports(people.hoo.employee.id);
    expect(reports.map((r) => r.id).sort()).toEqual([people.admin_manager.employee.id, people.hod.employee.id].sort());
    expect(db.queries[0].filters).toEqual([['manager_id', people.hoo.employee.id], ['is_archived', false]]);
    expect(Object.keys(reports[0]).sort()).toEqual(['date_of_exit', 'employment_status', 'id', 'is_archived']);
  });

  it('hand the health check\'s cancel signal to the query', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    const { db, store } = setup();
    const controller = new AbortController();
    db.outage = 'hang';
    const pending = store.ping({ signal: controller.signal });
    controller.abort();
    await expect(pending).rejects.toMatchObject({ status: 503, code: 'UNAVAILABLE' });
    expect(db.queries[0].aborted).toBe(true);
  });
});

describe('the sign-in resolver\'s reads (task A5)', () => {
  it('name their columns and never select a password hash, an email or a phone of an account', async () => {
    const { db, store, people } = setup();
    await store.findUsersByUsername('hr.login');
    await store.findUsersByPhoneNumber('9810000009');
    await store.findUsersByEmail('hr@example.test');
    await store.listUsersByIds([people.hr.user.id]);
    await store.listLocations();
    await store.listAttendanceLogins();
    await store.listAttendanceLoginsWithPassword();
    for (const q of db.queries) {
      expect(q.columns.length).toBeGreaterThan(0);
      for (const secret of ['password_hash', 'username', 'phone_number', 'email']) expect(q.columns).not.toContain(secret);
    }
    expect(await store.findUsersByUsername('hr.login')).toEqual([{ id: people.hr.user.id, role: 'hr', location_id: 1 }]);
  });

  it('ask whether a login has a password with a filter, so not one hash leaves the database', async () => {
    const { db, store, people } = setup();
    db.tables.hr_attendance_accounts.push({ ...people.attendance.account, id: '90000000-0000-4000-8000-000000000077', employee_id: people.hr.employee.id, password_hash: null });
    expect(await store.listAttendanceLoginsWithPassword()).toEqual([{ employee_id: people.attendance.employee.id }]);
    expect(db.queries[0]).toMatchObject({ columns: ['employee_id'], filters: [['password_hash', null, 'not.is']] });
  });

  it('read the employees as the attendance sign-in does: every one not archived', async () => {
    const { db, store, people } = setup();
    db.tables.hr_employees.find((e) => e.id === people.admin.employee.id).is_archived = true;
    const employees = await store.listEmployeesForSignIn();
    expect(employees.map((e) => e.id)).not.toContain(people.admin.employee.id);
    expect(Object.keys(employees[0]).sort()).toEqual(COLUMNS.employeeForSignIn.split(', ').sort());
  });

  it('ask for an empty list of accounts as one id that matches nothing, so the request is the same', async () => {
    const { db, store } = setup();
    expect(await store.listUsersByIds([])).toEqual([]);
    expect(db.queries[0].filters).toEqual([['id', [NIL_UUID], 'in']]);
  });
});

describe('the kept sign-ins (task A3)', () => {
  it('find a session by its hash, and hand no hash back', async () => {
    const { db, store } = setup();
    const row = sessionRow({ refresh_hash: 'f'.repeat(64) });
    db.tables.hr_ess_sessions.push(row);
    const found = await store.getSessionByRefreshHash('f'.repeat(64));
    expect(found.id).toBe(row.id);
    expect(found).not.toHaveProperty('refresh_hash');
    expect(Object.keys(found).sort()).toEqual(COLUMNS.session.split(', ').sort());
    expect(await store.getSessionByRefreshHash('e'.repeat(64))).toBeNull();
  });

  it('answer timestamps as PostgREST spells them, which the routes read as instants', async () => {
    const { db, store } = setup();
    const row = sessionRow();
    db.tables.hr_ess_sessions.push(row);
    expect((await store.getLiveSession(row.family_id)).expires_at).toBe('2027-01-14T06:00:00+00:00');
  });

  it('find a family\'s live row only', async () => {
    const { db, store } = setup();
    const live = sessionRow();
    db.tables.hr_ess_sessions.push(live, sessionRow({ family_id: live.family_id, revoked_at: '2026-10-16T05:00:00.000Z', revoked_reason: 'rotated' }));
    expect((await store.getLiveSession(live.family_id)).id).toBe(live.id);
    expect(db.queries[0].filters).toEqual([['family_id', live.family_id], ['revoked_at', null, 'is']]);
  });

  it('rotate and end families through the migration\'s two functions', async () => {
    const { db, store } = setup();
    const row = sessionRow();
    db.tables.hr_ess_sessions.push(row);
    const next = await store.rotateSession({
      sessionId: row.id, newId: '5a000000-0000-4000-8000-0000000000b1', refreshHash: 'b'.repeat(64), at: '2026-10-16T07:00:00.000Z', expiresAt: '2027-01-14T07:00:00.000Z',
    });
    expect(next).toEqual({ id: '5a000000-0000-4000-8000-0000000000b1', family_id: row.family_id, expires_at: '2027-01-14T07:00:00+00:00' });
    expect(await store.rotateSession({
      sessionId: row.id, newId: '5a000000-0000-4000-8000-0000000000b2', refreshHash: 'c'.repeat(64), at: '2026-10-16T07:00:00.000Z', expiresAt: '2027-01-14T07:00:00.000Z',
    })).toBeNull();
    expect(await store.revokeFamily({ familyId: row.family_id, reason: 'signed_out', at: '2026-10-16T08:00:00.000Z', employeeId: '5a000000-0000-4000-8000-0000000000ff' })).toBe(0);
    expect(await store.revokeFamily({ familyId: row.family_id, reason: 'signed_out', at: '2026-10-16T08:00:00.000Z' })).toBe(1);
    expect(db.queries.filter((q) => q.op === 'rpc').map((q) => q.fn)).toEqual(['hr_ess_session_rotate', 'hr_ess_session_rotate', 'hr_ess_session_revoke', 'hr_ess_session_revoke']);
  });

  it('store a new sign-in as it is given', async () => {
    const { db, store } = setup();
    const row = sessionRow();
    await store.createSession(row);
    expect(db.tables.hr_ess_sessions).toEqual([row]);
  });

  it('answer 503 MODULE_NOT_INSTALLED before the migration, for the table and for its functions', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    const { db, store } = setup();
    db.dropTable('hr_ess_sessions');
    const missing = { status: 503, code: 'MODULE_NOT_INSTALLED' };
    await expect(store.getSessionByRefreshHash('f'.repeat(64))).rejects.toMatchObject(missing);
    await expect(store.createSession(sessionRow())).rejects.toMatchObject(missing);
    await expect(store.revokeFamily({ familyId: NIL_UUID, reason: 'signed_out', at: '2026-10-16T08:00:00.000Z' })).rejects.toMatchObject(missing);
    await expect(store.rotateSession({ sessionId: NIL_UUID, newId: NIL_UUID, refreshHash: 'b'.repeat(64), at: 'x', expiresAt: 'y' })).rejects.toMatchObject(missing);
  });

  it('treat a missing function as not installed, as PostgREST and Postgres name it', () => {
    expect(NOT_INSTALLED_CODES.has('PGRST202')).toBe(true);
    expect(NOT_INSTALLED_CODES.has('42883')).toBe(true);
  });

  it('answer 500 INTERNAL_ERROR when the database refuses a write, which is not an outage, and log no values', async () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    const { store } = setup();
    const row = sessionRow({ refresh_hash: '9'.repeat(64) });
    await store.createSession(row);
    await expect(store.createSession({ ...row, id: '5a000000-0000-4000-8000-0000000000c1', family_id: '5a000000-0000-4000-8000-0000000000c1' }))
      .rejects.toMatchObject({ status: 500, code: 'INTERNAL_ERROR' });
    expect(spy).toHaveBeenCalledWith(expect.stringMatching(/writing hr_ess_sessions failed: 23505/));
    expect(JSON.stringify(spy.mock.calls)).not.toContain('9'.repeat(64));
  });
});

describe('the Wave 2 reads and writes', () => {
  it('name their columns, and never read a password hash, a token hash or a users.id they would send', async () => {
    const { db, store, people } = setup();
    const e = people.attendance.employee.id;
    await store.getUserLogin(people.hr.user.id);
    await store.getEmployeeCard(e);
    await store.listEmployeeCards([e, people.hr.employee.id]);
    await store.listEmployeeIdsInBranch(people.hr.employee.branch_id);
    await store.listBranches([people.hr.employee.branch_id]);
    await store.getDayRow(e, '2026-10-15');
    await store.getHrRemark(e, '2026-10-15');
    await store.listMyRemarks(e, '2026-10-15');
    await store.listDevices();
    await store.listDevices({ status: 'active', employeeIds: [e] });
    await store.listMyDataRequests(e);
    await store.listDataRequests();
    await store.getDataRequest('50000000-0000-4000-8000-000000000001');
    await store.getPersonalDetails(e);
    await store.listMockReports({ fromIso: '2026-10-01T00:00:00.000Z', toIso: '2026-10-17T00:00:00.000Z' });
    for (const q of db.queries) {
      expect(q.columns.length, q.table).toBeGreaterThan(0);
      for (const secret of ['password_hash', 'token_hash', 'resolved_by_user_id', 'updated_by_user_id']) {
        expect(q.columns, q.table).not.toContain(secret);
      }
    }
  });

  it('return only the whitelisted columns', async () => {
    const { store, people } = setup();
    expect(await store.getUserLogin(people.hr.user.id)).toEqual({ id: people.hr.user.id, username: 'hr.login' });
    const [phone] = await store.listDevices({ employeeIds: [people.faculty.employee.id] });
    expect(Object.keys(phone).sort()).toEqual(COLUMNS.device.split(', ').sort());
    const card = await store.getEmployeeCard(people.attendance.employee.id);
    expect(Object.keys(card).sort()).toEqual(['branch_id', 'employee_code', 'full_name', 'id']);
  });

  it('reset only active phones, with the five columns the Scheduler\'s reset writes', async () => {
    const { db, store, people } = setup();
    const reset = await store.revokeActiveDevices([people.attendance.employee.id], {
      revoked_at: '2026-10-16T06:30:00.000Z', revoked_by: people.hr.user.id, revoked_by_name: 'hr.login', revoke_reason: 'Go-live',
    });
    expect(reset).toEqual([{ id: '70000000-0000-4000-8000-000000000002', employee_id: people.attendance.employee.id }]);
    const [write] = db.writes();
    expect(write).toMatchObject({ op: 'update', table: 'hr_attendance_devices', columns: ['id', 'employee_id'] });
    expect(write.values).toEqual([{ status: 'revoked', revoked_at: '2026-10-16T06:30:00.000Z', revoked_by: people.hr.user.id, revoked_by_name: 'hr.login', revoke_reason: 'Go-live' }]);
    expect(write.conditions).toEqual([['in', 'employee_id', [people.attendance.employee.id]], ['eq', 'status', 'active']]);
    // The one already reset keeps who reset it and why.
    expect(db.tables.hr_attendance_devices.find((d) => d.id === '70000000-0000-4000-8000-000000000003').revoke_reason).toBe('Phone lost');
  });

  it('write nothing to a Scheduler table except the five sanctioned methods', () => {
    const source = fs.readFileSync(path.join(__dirname, '..', 'src', 'lib', 'store.js'), 'utf8');
    const code = source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
    const written = [...code.matchAll(/write\('([a-z_]+)'/g)].map((m) => m[1]);
    // The five Scheduler writes, each one named method and nothing else: HR's phone reset
    // (revokeActiveDevices, the Scheduler's own update), the shift snapshot (setDaySnapshot,
    // the copy the Scheduler's ensureSnapshot makes), the employee's own photo pointer
    // (setEmployeePhoto, the same columns the Scheduler's setPhoto writes), and H1's class
    // marking (saveClassAttendance and updateClassRemark) with its alert resolution
    // (resolveAbsentRemarkAlerts). The day itself is never written from here: the SQL functions
    // go through hr_attendance_apply_override.
    const allowed = new Set(['hr_attendance_devices', 'hr_staff_attendance', 'hr_employees', 'student_attendance', 'pending_alerts']);
    expect(written.length).toBeGreaterThan(0);
    for (const table of written) {
      if (!allowed.has(table)) expect(table).toMatch(/^hr_ess_/);
    }
    expect(written.filter((t) => t === 'hr_attendance_devices')).toHaveLength(1);
    expect(written.filter((t) => t === 'hr_staff_attendance')).toHaveLength(1);
    expect(written.filter((t) => t === 'hr_employees')).toHaveLength(1);
    expect(written.filter((t) => t === 'student_attendance')).toHaveLength(2);
    expect(written.filter((t) => t === 'pending_alerts')).toHaveLength(1);
  });

  it('resolve a data request only while it is open', async () => {
    const { db, store, people } = setup();
    db.tables.hr_ess_data_requests = [{ id: '50000000-0000-4000-8000-000000000001', employee_id: people.faculty.employee.id, kind: 'correct', details: 'Fix it', status: 'done' }];
    expect(await store.resolveDataRequest('50000000-0000-4000-8000-000000000001', { status: 'rejected' })).toBeNull();
    expect(db.tables.hr_ess_data_requests[0].status).toBe('done');
  });

  it('write the audit trail without reading anything back', async () => {
    const { db, store } = setup();
    await store.writeAudit({ actor_name: 'x', action: 'devices.reset', details: {} });
    expect(db.writes()).toEqual([expect.objectContaining({ op: 'insert', table: 'hr_ess_audit', columns: [] })]);
  });

  it('answer a write to a missing column as 503 MODULE_NOT_INSTALLED', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    const { db, store, people } = setup();
    db.dropColumn('hr_ess_personal_details', 'emergency_relation');
    await expect(store.savePersonalDetails({ employee_id: people.hr.employee.id, emergency_relation: null }))
      .rejects.toMatchObject({ status: 503, code: 'MODULE_NOT_INSTALLED' });
  });
});

describe('a failed read', () => {
  beforeEach(() => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
  });

  it.each([['PGRST205'], ['PGRST204'], ['42P01'], ['42703']])('with %s is 503 MODULE_NOT_INSTALLED, naming the table', (code) => {
    const e = storeError('hr_attendance_accounts', { code, message: 'missing' });
    expect(e).toBeInstanceOf(HttpError);
    expect(e).toMatchObject({ status: 503, code: 'MODULE_NOT_INSTALLED' });
    expect(e.message).toMatch(/hr_attendance_accounts/);
  });

  it.each([['PGRST116'], ['PGRST301'], ['08006'], [''], [undefined]])('with %j is 503 UNAVAILABLE', (code) => {
    expect(storeError('users', { code, message: 'x' })).toMatchObject({ status: 503, code: 'UNAVAILABLE' });
  });

  it.each([['23514'], ['23505'], ['23503'], ['22P02']])('refused by the database with %s is 500 INTERNAL_ERROR, not an outage', (code) => {
    expect(storeError('hr_ess_personal_details', { code, message: 'x' })).toMatchObject({ status: 500, code: 'INTERNAL_ERROR' });
  });

  it('that throws is 503 UNAVAILABLE', () => {
    expect(storeError('users', new TypeError('fetch failed'))).toMatchObject({ status: 503, code: 'UNAVAILABLE' });
  });

  it('reaches the caller as those refusals, never as a raw database error', async () => {
    const { db, store, people } = setup();
    db.dropTable('hr_departments');
    await expect(store.getDepartment(people.hr.employee.department_id)).rejects.toMatchObject({ status: 503, code: 'MODULE_NOT_INSTALLED' });
    db.dropColumn('users', 'faculty_id');
    await expect(store.getUser(people.hr.user.id)).rejects.toMatchObject({ status: 503, code: 'MODULE_NOT_INSTALLED' });
    db.outage = 'error';
    await expect(store.getEmployeeById(people.hr.employee.id)).rejects.toMatchObject({ status: 503, code: 'UNAVAILABLE' });
    db.outage = 'throw';
    await expect(store.listDirectReports(people.ceo.employee.id)).rejects.toMatchObject({ status: 503, code: 'UNAVAILABLE' });
  });

  it('is logged with its code, for the tech team', async () => {
    const { db, store, people } = setup();
    db.dropTable('hr_branches');
    await expect(store.getBranch(people.hr.employee.branch_id)).rejects.toThrow();
    expect(console.error).toHaveBeenCalledWith(expect.stringMatching(/reading hr_branches failed: PGRST205/));
  });
});

describe('the real supabase-js client', () => {
  it('can be built on this Node version without a WebSocket library', () => {
    // On Node 20 supabase-js used to throw here, inside createClient, as the server started.
    // Building the client makes no request, so this reaches no database.
    expect(() => createSupabaseStore(loadConfig(TEST_ENV))).not.toThrow();
  });
});

describe('the store\'s source', () => {
  it('never selects every column', () => {
    const source = fs.readFileSync(path.join(__dirname, '..', 'src', 'lib', 'store.js'), 'utf8');
    // The comments explain why select('*') is banned; only the code is checked.
    const code = source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
    expect(code).toMatch(/\.select\(/);
    expect(code).not.toMatch(/select\(\s*['"`]\s*\*/);
    expect(code).not.toMatch(/select\(\s*\)/);
  });
});
