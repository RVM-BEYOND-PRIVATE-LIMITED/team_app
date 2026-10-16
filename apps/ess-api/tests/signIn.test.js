const request = require('supertest');
const { buildApp } = require('./helpers/app');
const { company, LOCATIONS } = require('./helpers/fixtures');
const { createFakeSupabase } = require('./helpers/fakeSupabase');
const { createSupabaseStore } = require('../src/lib/store');
const { loadConfig } = require('../src/config');
const { TEST_ENV, TODAY } = require('./helpers/constants');
const P = require('../src/policy/signIn');
const Scheduler = require('./helpers/schedulerSignIn');

/**
 * POST /api/ess/sign-in/resolve (task A5): the one sign-in field. Who is found, and how, held
 * against the Scheduler's own lookups (tests/helpers/schedulerSignIn.js) where they exist.
 *
 * The fixture's people (tests/helpers/fixtures.js): portal logins `<role>.login` with login phone
 * 98100000NN, email <role>@example.test and employee code RVM-0NN, whose HR record's main phone is
 * 97100000NN; and the attendance-only Office Assistant, RVM-050, main phone 9710000050, no email.
 */

const ALL_BRANCHES = ['Faridabad', 'Pune', 'Ahmedabad', 'Lucknow'];
const UNKNOWN = { kind: 'unknown' };

const resolve = (app, identifier, from) => {
  const req = request(app).post('/api/ess/sign-in/resolve');
  if (from) req.set('X-Forwarded-For', from);
  return req.send(identifier === undefined ? {} : { identifier });
};

/** One answer, after checking it is a 200 with nothing identifying in it. */
async function answer(app, identifier, world) {
  const res = await resolve(app, identifier);
  expect(res.status, JSON.stringify(res.body)).toBe(200);
  if (world) expectNothingIdentifying(res.body, world);
  return res.body;
}

/** No user id, username, phone or email of anybody in the fixture, in any answer. */
function expectNothingIdentifying(body, { db }) {
  const text = JSON.stringify(body);
  for (const u of db.tables.users) for (const v of [u.id, u.username, u.phone_number, u.email]) if (v) expect(text).not.toContain(v);
  for (const e of db.tables.hr_employees) for (const v of [e.id, e.phone, e.email, e.user_id]) if (v) expect(text).not.toContain(v);
}

const giveAttendanceLogin = (w, key, extra = {}) => w.tables.hr_attendance_accounts.push({
  ...w.people.attendance.account, id: `90000000-0000-4000-8000-0000000001${String(w.tables.hr_attendance_accounts.length).padStart(2, '0')}`,
  employee_id: w.people[key].employee.id, ...extra,
});

describe('a portal login, found as the Scheduler\'s portal login finds it', () => {
  it('by its username: sign in with what was typed, at its own branch', async () => {
    const world = buildApp();
    expect(await answer(world.app, 'faculty.login', world)).toEqual({ kind: 'portal', login_with: 'as_typed', location_name: 'Faridabad' });
  });

  it('by its login phone, exactly as stored', async () => {
    const world = buildApp();
    expect(await answer(world.app, '9810000011', world)).toEqual({ kind: 'portal', login_with: 'as_typed', location_name: 'Faridabad' });
  });

  it('at whichever branch the account is', async () => {
    const world = buildApp({ setup: (w) => { w.people.admin.user.location_id = 2; } });
    expect(await answer(world.app, 'admin.login', world)).toEqual({ kind: 'portal', login_with: 'as_typed', location_name: 'Pune' });
  });

  it.each(['ceo', 'super_admin', 'accounts_admin', 'hr', 'hr_executive'])(
    'for %s, a role that may have no branch: every branch, in the web\'s order, branch or not',
    async (key) => {
      for (const locationId of [1, null]) {
        const world = buildApp({ setup: (w) => { w.people[key].user.location_id = locationId; } });
        expect(await answer(world.app, `${key}.login`, world)).toEqual({ kind: 'portal', login_with: 'as_typed', location_names: ALL_BRANCHES });
      }
    },
  );

  it('with every branch, too, for an account whose branch is missing or unknown', async () => {
    for (const locationId of [null, 99]) {
      const world = buildApp({ setup: (w) => { w.people.faculty.user.location_id = locationId; } });
      expect(await answer(world.app, 'faculty.login', world)).toEqual({ kind: 'portal', login_with: 'as_typed', location_names: ALL_BRANCHES });
    }
  });

  it('only exactly: another case, a space or a prefix finds nothing, as at the Scheduler', async () => {
    const world = buildApp();
    for (const typed of ['Faculty.login', ' faculty.login', 'faculty.login ', '+91 9810000011', '09810000011']) {
      expect(await answer(world.app, typed, world), typed).toEqual(UNKNOWN);
    }
  });

  it('by the account\'s email, in any case: asked for its username or login phone, which portal login takes', async () => {
    const world = buildApp({ setup: (w) => { w.people.faculty.user.email = 'f.login@example.test'; } });
    for (const typed of ['f.login@example.test', '  F.Login@Example.TEST ']) {
      expect(await answer(world.app, typed, world)).toEqual({ kind: 'portal', login_with: 'username_or_phone' });
    }
  });

  it('by its employee code on the HR record, in any case', async () => {
    const world = buildApp();
    for (const typed of ['RVM-011', 'rvm-011', ' RVM-011 ']) {
      expect(await answer(world.app, typed, world)).toEqual({ kind: 'portal', login_with: 'username_or_phone' });
    }
  });

  it('by the main phone or the email on the HR record, in any spelling', async () => {
    const world = buildApp({ setup: (w) => { w.people.faculty.user.email = null; } });
    for (const typed of ['9710000011', '+91 97100 00011', '09710000011', 'faculty@example.test']) {
      expect(await answer(world.app, typed, world), typed).toEqual({ kind: 'portal', login_with: 'username_or_phone' });
    }
  });

  it('when the person has an attendance login as well: the portal login, which carries their role', async () => {
    const world = buildApp({ setup: (w) => giveAttendanceLogin(w, 'faculty') });
    expect(await answer(world.app, 'RVM-011', world)).toEqual({ kind: 'portal', login_with: 'username_or_phone' });
    expect(await answer(world.app, 'faculty.login', world)).toEqual({ kind: 'portal', login_with: 'as_typed', location_name: 'Faridabad' });
  });
});

describe('an attendance login, found as the Scheduler\'s attendance sign-in finds it', () => {
  it.each([['RVM-050'], ['rvm-050'], ['9710000050'], ['+91 97100 00050'], ['097100 00050'], ['  9710000050  ']])(
    'by %s: a code and the password',
    async (typed) => {
      const world = buildApp();
      expect(await answer(world.app, typed, world)).toEqual({ kind: 'attendance', methods: ['code', 'password'] });
    },
  );

  it('by the email on the HR record, in any case', async () => {
    const world = buildApp({ setup: (w) => { w.people.attendance.employee.email = 'office.assistant@example.test'; } });
    expect(await answer(world.app, 'Office.Assistant@Example.test', world)).toEqual({ kind: 'attendance', methods: ['code', 'password'] });
  });

  it('with no password yet: a code only', async () => {
    const world = buildApp({ setup: (w) => { Object.assign(w.people.attendance.account, { password_hash: null, password_set_at: null }); } });
    expect(await answer(world.app, 'RVM-050', world)).toEqual({ kind: 'attendance', methods: ['code'] });
  });

  it('with the password HR gave and not yet replaced: a code and the password', async () => {
    const world = buildApp({ setup: (w) => { w.people.attendance.account.password_set_at = null; } });
    expect(await answer(world.app, 'RVM-050', world)).toEqual({ kind: 'attendance', methods: ['code', 'password'] });
  });

  it('with no main mobile and no email, so no code can reach them: the password only, or nothing', async () => {
    const noContact = (w) => Object.assign(w.people.attendance.employee, { phone: '01294000000', email: null });
    const world = buildApp({ setup: noContact });
    expect(await answer(world.app, 'RVM-050', world)).toEqual({ kind: 'attendance', methods: ['password'] });
    const neither = buildApp({ setup: (w) => { noContact(w); w.people.attendance.account.password_hash = null; } });
    expect(await answer(neither.app, 'RVM-050', neither)).toEqual({ kind: 'attendance', methods: [] });
  });

  it.each([
    ['switched off by HR', (w) => { w.people.attendance.account.status = 'disabled'; }],
    ['not created yet', (w) => { w.tables.hr_attendance_accounts = []; }],
  ])('whose login is %s: no methods, and the app sends them to HR', async (_label, setup) => {
    const world = buildApp({ setup });
    expect(await answer(world.app, 'RVM-050', world)).toEqual({ kind: 'attendance', methods: [] });
  });
});

describe('nobody, or more than one person: { kind: "unknown" }', () => {
  it('for something nobody has', async () => {
    const world = buildApp();
    for (const typed of ['nobody.here', '9999999999', 'RVM-999', 'nobody@example.test', 'x']) {
      expect(await answer(world.app, typed, world), typed).toEqual(UNKNOWN);
    }
  });

  it('for a main phone two people share', async () => {
    const world = buildApp({ setup: (w) => { w.people.hr_executive.employee.phone = '9710000050'; } });
    expect(await answer(world.app, '9710000050', world)).toEqual(UNKNOWN);
  });

  it('for one person\'s username that is another person\'s employee code', async () => {
    const world = buildApp({ setup: (w) => { w.people.hr.user.username = 'RVM-050'; } });
    expect(await answer(world.app, 'RVM-050', world)).toEqual(UNKNOWN);
  });

  it('for one person\'s login phone that is another person\'s main phone', async () => {
    const world = buildApp({ setup: (w) => { w.people.attendance.employee.phone = '9810000011'; } });
    expect(await answer(world.app, '9810000011', world)).toEqual(UNKNOWN);
  });

  it.each([
    ['exited', { employment_status: 'exited' }],
    ['archived', { is_archived: true }],
    ['past the last working day', { employment_status: 'notice_period', date_of_exit: '2026-10-15' }],
  ])('for somebody who has left (%s), by any identifier', async (_label, change) => {
    const world = buildApp({ setup: (w) => { Object.assign(w.people.attendance.employee, change); Object.assign(w.people.faculty.employee, change); } });
    for (const typed of ['RVM-050', '9710000050', 'faculty.login', '9810000011', 'RVM-011', 'faculty@example.test']) {
      expect(await answer(world.app, typed, world), typed).toEqual(UNKNOWN);
    }
  });

  it('but not for somebody on their last working day, who is on strength until it ends', async () => {
    const world = buildApp({ setup: (w) => Object.assign(w.people.attendance.employee, { employment_status: 'notice_period', date_of_exit: TODAY }) });
    expect(await answer(world.app, 'RVM-050', world)).toEqual({ kind: 'attendance', methods: ['code', 'password'] });
  });

  it('for the connector identity, linked to a record or not', async () => {
    for (const linked of [false, true]) {
      const world = buildApp({ setup: (w) => { if (linked) w.people.hr_executive.employee.user_id = w.people.bot.user.id; } });
      expect(await answer(world.app, 'control-room-bot', world)).toEqual(UNKNOWN);
    }
  });

  it('for a desk login with no HR record, by its name or its phone', async () => {
    const world = buildApp();
    expect(await answer(world.app, 'fbd.admin', world)).toEqual(UNKNOWN);
    expect(await answer(world.app, '9810000090', world)).toEqual(UNKNOWN);
  });

  it('for a student account', async () => {
    const world = buildApp({ setup: (w) => { w.people.faculty.user.role = 'student'; } });
    expect(await answer(world.app, 'faculty.login', world)).toEqual(UNKNOWN);
  });

  it('but not when a desk login only shares a number with one real person: that person is answered', async () => {
    const world = buildApp({ setup: (w) => { w.people.attendance.employee.phone = '9810000090'; } });
    expect(await answer(world.app, '9810000090', world)).toEqual({ kind: 'attendance', methods: ['code', 'password'] });
  });

  it('nor when a second, unlinked account shares the username: the linked person is answered', async () => {
    const world = buildApp({
      setup: (w) => w.tables.users.push({ ...w.people.desk.user, id: 'a0000000-0000-4000-8000-000000000092', username: 'faculty.login', location_id: 2 }),
    });
    expect(await answer(world.app, 'faculty.login', world)).toEqual({ kind: 'portal', login_with: 'as_typed', location_name: 'Faridabad' });
  });

  it('in the same shape and after the same database requests, whatever the reason', async () => {
    const shapeOf = (q) => `${q.op} ${q.table} ${q.columns.join(',')} ${q.filters.map(([c, , op]) => `${c}${op ? `:${op}` : ''}`).join(',')}`;
    const run = async (setup, typed) => {
      const world = buildApp({ setup });
      const res = await resolve(world.app, typed);
      return { body: res.body, requests: world.db.queries.map(shapeOf) };
    };
    const nobody = await run(undefined, 'nobody.here');
    const two = await run((w) => { w.people.hr.user.username = 'RVM-050'; }, 'RVM-050');
    const leaver = await run((w) => { w.people.attendance.employee.employment_status = 'exited'; }, 'RVM-050');
    expect(nobody.body).toEqual(UNKNOWN);
    expect(two).toEqual(nobody);
    expect(leaver).toEqual(nobody);
  });
});

describe('what it takes', () => {
  it.each([
    ['nothing', undefined],
    ['an empty string', ''],
    ['spaces', '   '],
    ['a number', 9810000011],
    ['a list', ['faculty.login']],
    ['255 characters', 'x'.repeat(255)],
  ])('refuses %s with 400 BAD_IDENTIFIER', async (_label, identifier) => {
    const { app } = buildApp();
    const res = await resolve(app, identifier);
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: 'Enter your phone number, email, employee code or username.', code: 'BAD_IDENTIFIER' });
  });

  it('takes 254 characters', async () => {
    const world = buildApp();
    expect(await answer(world.app, 'x'.repeat(254), world)).toEqual(UNKNOWN);
  });

  it('needs no token', async () => {
    const world = buildApp();
    const res = await request(world.app).post('/api/ess/sign-in/resolve').set('Authorization', 'Bearer forged').send({ identifier: 'RVM-050' });
    expect(res.status).toBe(200);
  });
});

describe('the limits', () => {
  it('per address: 429 RATE_LIMITED, and only for that address', async () => {
    const { app } = buildApp({ limits: { signInPerIp: { windowMs: 60 * 1000, limit: 2 } } });
    await resolve(app, 'a.one', '203.0.113.10');
    await resolve(app, 'a.two', '203.0.113.10');
    const res = await resolve(app, 'a.three', '203.0.113.10');
    expect(res.status).toBe(429);
    expect(res.body).toEqual({ error: expect.any(String), code: 'RATE_LIMITED' });
    expect((await resolve(app, 'a.three', '203.0.113.11')).status).toBe(200);
  });

  it('per identifier, from any address, any spelling of one number counting as one', async () => {
    const { app } = buildApp({ limits: { signInPerIdentifier: { windowMs: 60 * 1000, limit: 2 } } });
    expect((await resolve(app, '9710000050', '203.0.113.20')).status).toBe(200);
    expect((await resolve(app, '+91 97100 00050', '198.51.100.21')).status).toBe(200);
    const res = await resolve(app, '097100 00050', '192.0.2.22');
    expect(res.status).toBe(429);
    expect(res.body.code).toBe('RATE_LIMITED');
    expect((await resolve(app, 'RVM-050', '192.0.2.22')).status).toBe(200);
  });

  it('are counted before anything is read', async () => {
    const { app, db } = buildApp({ limits: { signInPerIp: { windowMs: 60 * 1000, limit: 1 } } });
    await resolve(app, 'RVM-050');
    const before = db.queries.length;
    expect((await resolve(app, 'RVM-050')).status).toBe(429);
    expect(db.queries.length).toBe(before);
  });
});

describe('when the database is not ready', () => {
  beforeEach(() => vi.spyOn(console, 'error').mockImplementation(() => {}));

  it.each([['error'], ['throw']])('is 503 UNAVAILABLE when the database answers with %s', async (outage) => {
    const { app, db } = buildApp();
    db.outage = outage;
    const res = await resolve(app, 'RVM-050');
    expect(res.status).toBe(503);
    expect(res.body.code).toBe('UNAVAILABLE');
  });

  it.each([
    ['the attendance logins', (db) => db.dropTable('hr_attendance_accounts')],
    ['the branches', (db) => db.dropTable('locations')],
    ['users.email', (db) => db.dropColumn('users', 'email')],
  ])('is 503 MODULE_NOT_INSTALLED without %s', async (_label, drop) => {
    const { app, db } = buildApp();
    drop(db);
    const res = await resolve(app, 'faculty.login');
    expect(res.status).toBe(503);
    expect(res.body.code).toBe('MODULE_NOT_INSTALLED');
  });
});

describe('the reads', () => {
  it('never ask for a password hash, and ask whether one exists without sending it', async () => {
    const { app, db } = buildApp();
    await resolve(app, 'RVM-050');
    for (const q of db.queries) expect(q.columns).not.toContain('password_hash');
    expect(db.queries.find((q) => q.table === 'hr_attendance_accounts' && q.filters.some(([c]) => c === 'password_hash')))
      .toMatchObject({ columns: ['employee_id'], filters: [['password_hash', null, 'not.is']] });
  });

  it('do not log what was typed', async () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    const { app, db } = buildApp();
    db.outage = 'error';
    await resolve(app, 'Secret.Person@example.test');
    expect(JSON.stringify(spy.mock.calls)).not.toMatch(/secret\.person/i);
  });
});

/* ── against the Scheduler's own lookups ── */

describe('the Scheduler\'s comparisons, mirrored', () => {
  const samples = [
    '', ' ', '9810012345', '+91 98100 12345', '919810012345', '09810012345', '98100 12345', '5810012345', '981001234',
    '98100123456', '0091 98100 12345', 'RVM-050', 'rvm-050', 'R', 'RV', 'R/V_M-1', '-RVM', 'RVM 050', 'a'.repeat(40), 'a'.repeat(41),
    'name@example.test', ' Name@Example.TEST ', 'not@an', '@example.test', 'two@@example.test', `${'a'.repeat(250)}@x.co`,
    'faculty.login', 'ab@c.de', '١٢٣٤٥٦٧٨٩٠', 'RVM-050\n',
  ];

  it.each(samples.map((s) => [s]))('read %j as the attendance sign-in reads it', (typed) => {
    const theirs = Scheduler.readLoginIdentifier(typed);
    expect(P.readAttendanceIdentifier(typed)).toEqual(theirs.error ? null : theirs);
    expect(P.normaliseIndianMobile(typed)).toBe(Scheduler.normaliseIndianMobile(typed));
    expect(P.phoneDigits(typed)).toBe(Scheduler.phoneDigits(typed));
  });

  it('read a main phone and reachability as the Scheduler does', () => {
    const phones = [null, '', '9710000050', '+91 97100 00050', '097100 00050', '01294000000', '5710000050', '97100000501', 'n/a'];
    const emails = [null, '', 'a@b.c', 'no-at-sign'];
    for (const phone of phones) {
      for (const email of emails) {
        expect(P.mainNumber({ phone })).toBe(Scheduler.mainNumber({ phone }));
        expect(P.reachable({ phone, email })).toBe(Scheduler.reachable({ phone, email }));
      }
    }
  });
});

describe('finding a portal account, against findAccountsByIdentifier', () => {
  const tricky = ['plain', 'with,comma', 'with"quote', 'with\\backslash', 'with(paren)', 'a.b,c.eq.d', 'space here', 'ümlaut', '9810000001', 'or=(x)'];

  it.each(tricky.map((u) => [u]))('finds exactly the accounts the Scheduler finds for %j', async (typed) => {
    const world = company();
    const users = [
      ...world.tables.users,
      ...tricky.map((name, i) => ({ id: `a0000000-0000-4000-8000-0000000002${String(i).padStart(2, '0')}`, username: name, phone_number: null, role: 'admin', location_id: 1 })),
      { id: 'a0000000-0000-4000-8000-000000000299', username: 'someone.else', phone_number: typed, role: 'faculty', location_id: 2 },
    ];
    Scheduler.useRows({ users });
    const theirs = (await Scheduler.findAccountsByIdentifier(typed)).map((u) => u.id).sort();
    const store = createSupabaseStore(loadConfig(TEST_ENV), { client: createFakeSupabase({ ...world.tables, users }) });
    const ours = [...await store.findUsersByUsername(typed), ...await store.findUsersByPhoneNumber(typed)].map((u) => u.id).sort();
    expect(ours).toEqual(theirs);
    expect(theirs.length).toBeGreaterThan(0);
  });
});

describe('the branch it answers, against resolveLoginCandidate', () => {
  /** Which account the Scheduler's portal login settles on for this identifier and branch. */
  const signsIn = async (users, typed, locationName) => {
    Scheduler.useRows({ users });
    const locationId = LOCATIONS.find((l) => l.name === locationName).id;
    return Scheduler.resolveLoginCandidate(await Scheduler.findAccountsByIdentifier(typed), locationId);
  };

  it.each(['faculty', 'hod', 'admin', 'hoo', 'admin_manager', 'hod_placement', 'ceo', 'hr', 'hr_executive', 'super_admin', 'accounts_admin'])(
    'signs %s in to their own account at the branch, or at every branch offered',
    async (key) => {
      const world = buildApp();
      const body = await answer(world.app, `${key}.login`, world);
      for (const name of body.location_names || [body.location_name]) {
        expect((await signsIn(world.db.tables.users, `${key}.login`, name)).id).toBe(world.people[key].user.id);
      }
    },
  );

  it('signs the linked person in when an unlinked account at another branch shares the username', async () => {
    const world = buildApp({
      setup: (w) => w.tables.users.push({ ...w.people.desk.user, id: 'a0000000-0000-4000-8000-000000000093', username: 'faculty.login', location_id: 2 }),
    });
    const body = await answer(world.app, 'faculty.login', world);
    expect(body.location_name).toBe('Faridabad');
    expect((await signsIn(world.db.tables.users, 'faculty.login', body.location_name)).id).toBe(world.people.faculty.user.id);
  });
});

describe('finding an attendance login, against findEmployee and requireAttendanceLogin', () => {
  /**
   * A small company whose standing does not depend on the day, since the Scheduler's copy reads
   * the real clock: no portal account shares an identifier with anybody's HR record here.
   */
  const world = () => {
    const w = company();
    const e = w.people.attendance.employee;
    const extra = (n, change) => ({ ...e, id: `e0000000-0000-4000-8000-0000000003${n}`, employee_code: `RVM-3${n}`, phone: `97100003${n}`, email: null, ...change });
    w.tables.hr_employees.push(
      extra('01', { email: 'one@example.test' }),
      extra('02', { employment_status: 'exited' }),
      extra('03', { phone: '9710000301' }),
      extra('04', { additional_phones: ['9710000399'] }),
      extra('05', {}),
    );
    w.tables.hr_attendance_accounts.push(
      { ...w.people.attendance.account, id: '90000000-0000-4000-8000-000000000301', employee_id: 'e0000000-0000-4000-8000-000000000301', password_hash: null },
      { ...w.people.attendance.account, id: '90000000-0000-4000-8000-000000000305', employee_id: 'e0000000-0000-4000-8000-000000000305', status: 'disabled' },
    );
    w.tables.hr_attendance_accounts.push({ ...w.people.attendance.account, id: '90000000-0000-4000-8000-000000000311', employee_id: w.people.faculty.employee.id });
    return w;
  };

  const identifiers = [
    'RVM-050', '9710000050', '+91 97100 00050', 'RVM-301', 'one@example.test', 'ONE@example.test', '9710000301', 'RVM-302',
    '9710000302', 'RVM-303', '9710000303', 'RVM-304', '9710000399', 'RVM-305', 'RVM-011', '9710000011', 'faculty@example.test',
    'RVM-009', '9710000009', 'RVM-999', '9999999999', 'nobody@example.test', 'bad identifier', '',
  ];

  it.each(identifiers.map((s) => [s]))('%j', async (typed) => {
    const w = world();
    Scheduler.useRows({ users: w.tables.users, employees: w.tables.hr_employees, accounts: w.tables.hr_attendance_accounts });
    const theirs = await Scheduler.attendanceSignIn(typed);

    const store = createSupabaseStore(loadConfig(TEST_ENV), { client: createFakeSupabase(w.tables) });
    const app = require('../src/app').createApp({ config: loadConfig(TEST_ENV), store, now: () => new Date(`${TODAY}T06:30:00.000Z`) });
    const res = await resolve(app, typed);
    if (typed === '') {
      expect(res.status).toBe(400);
      return;
    }
    const ours = res.body;

    if (theirs.employee && theirs.employee.user_id) {
      // The Scheduler would let this person's attendance login in too; the resolver points them
      // at their portal login, which carries their role.
      expect(ours).toEqual({ kind: 'portal', login_with: 'username_or_phone' });
    } else if (theirs.employee) {
      // The Scheduler would go on to the password or the code.
      expect(ours.kind).toBe('attendance');
      expect(ours.methods.length).toBeGreaterThan(0);
      expect(ours.methods.includes('password')).toBe(Boolean(theirs.account.password_hash));
    } else if (theirs.refused === 'HAS_PORTAL_LOGIN') {
      expect(ours).toEqual({ kind: 'portal', login_with: 'username_or_phone' });
    } else if (theirs.refused === 'NO_ATTENDANCE_LOGIN') {
      expect(ours).toEqual({ kind: 'attendance', methods: [] });
    } else {
      // NOT_FOUND, AMBIGUOUS, NOT_ACTIVE, NOT_MAIN_PHONE, BAD_IDENTIFIER: nobody the app could sign in.
      expect(['NOT_FOUND', 'AMBIGUOUS', 'NOT_ACTIVE', 'NOT_MAIN_PHONE', 'BAD_IDENTIFIER']).toContain(theirs.refused);
      expect(ours).toEqual(UNKNOWN);
    }
  });

  it('covers every answer the attendance sign-in can give before the password', async () => {
    const w = world();
    Scheduler.useRows({ users: w.tables.users, employees: w.tables.hr_employees, accounts: w.tables.hr_attendance_accounts });
    const seen = new Set();
    for (const typed of identifiers) {
      const theirs = await Scheduler.attendanceSignIn(typed);
      seen.add(theirs.refused || (theirs.employee.user_id ? 'BOTH_LOGINS' : 'GOES_ON'));
    }
    expect([...seen].sort()).toEqual([
      'AMBIGUOUS', 'BAD_IDENTIFIER', 'BOTH_LOGINS', 'GOES_ON', 'HAS_PORTAL_LOGIN', 'NOT_ACTIVE', 'NOT_FOUND', 'NOT_MAIN_PHONE', 'NO_ATTENDANCE_LOGIN',
    ]);
  });
});
