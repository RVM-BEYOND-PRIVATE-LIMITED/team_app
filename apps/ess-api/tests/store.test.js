const fs = require('fs');
const path = require('path');
const { createSupabaseStore, storeError, COLUMNS } = require('../src/lib/store');
const { HttpError } = require('../src/lib/errors');
const { createFakeSupabase } = require('./helpers/fakeSupabase');
const { company } = require('./helpers/fixtures');
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

  it('write nothing to a Scheduler table except that reset', () => {
    const source = fs.readFileSync(path.join(__dirname, '..', 'src', 'lib', 'store.js'), 'utf8');
    const code = source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
    const written = [...code.matchAll(/write\('([a-z_]+)'/g)].map((m) => m[1]);
    expect(written.length).toBeGreaterThan(0);
    for (const table of written) {
      if (table !== 'hr_attendance_devices') expect(table).toMatch(/^hr_ess_/);
    }
    expect(written.filter((t) => t === 'hr_attendance_devices')).toHaveLength(1);
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
