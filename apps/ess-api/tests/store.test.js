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
    expect(Object.keys(account).sort()).toEqual(['employee_id', 'id', 'sessions_valid_from', 'status']);
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
