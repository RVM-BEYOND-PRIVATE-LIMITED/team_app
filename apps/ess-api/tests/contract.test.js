const request = require('supertest');
const { createApp } = require('../src/app');
const { loadConfig } = require('../src/config');
const { MESSAGES } = require('../src/lib/errors');
const { ROLES } = require('../src/policy/roles');
const { TABS, capabilitiesFor } = require('../src/policy/capabilities');
const { REQUEST_TYPES } = require('../src/policy/requestLimits');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { NOW, SIGNED_AT, TEST_ENV } = require('./helpers/constants');
const { PORTAL_PEOPLE, INSTALL_ID, OTHER_INSTALL_ID, BRANCH_ID, BRANCH_PUNE_ID, uuid } = require('./helpers/fixtures');
const C = require('./helpers/contract');
const H = require('./helpers/sessions');
const { WAVE_6 } = require('./helpers/wave6');
const { WAVE_7 } = require('./helpers/wave7');
const { WAVE_8 } = require('./helpers/wave8');
const { WAVE_9 } = require('./helpers/wave9');
const { WAVE_10 } = require('./helpers/wave10');
const { WAVE_11 } = require('./helpers/wave11');

/**
 * The ESS against packages/contracts/openapi.yaml (ADR-0010): the routes it serves are the ESS
 * operations the contract lists, and every reply the tests can provoke from them, success and
 * refusal alike, has a status, a body, an error code and headers the contract documents. A
 * change to either side that the other does not share fails here.
 */

const health = C.operation('GET', '/api/ess/health');
const me = C.operation('GET', '/api/ess/me');
const caps = C.operation('GET', '/api/ess/me/capabilities');

const expectContract = (op, res) => expect(C.contractProblems(op, res), `${op.method} ${op.path} answered ${res.status} ${JSON.stringify(res.body)}`).toEqual([]);

const quietErrors = () => vi.spyOn(console, 'error').mockImplementation(() => {});

/**
 * Routes the ESS serves whose contract is still to be written. Empty: every route of Waves 1 and 2
 * is documented. A route built before its contract entry goes here, and leaves in the change
 * that documents it; the test below fails while a documented route is still listed, and while a
 * served route is in neither.
 */
const AWAITING_CONTRACT = [];

describe('the routes', () => {
  it('are exactly the ESS operations in the contract, and those awaiting it', () => {
    const { app } = buildApp();
    const served = C.essRoutes(app);
    expect(served.length).toBeGreaterThan(0);
    const documented = C.operations().filter((op) => op.owner === 'ess').map((op) => `${op.method} ${op.path}`).sort();
    expect(served.filter((route) => !AWAITING_CONTRACT.includes(route))).toEqual(documented.filter((route) => !AWAITING_CONTRACT.includes(route)));
    for (const route of AWAITING_CONTRACT) {
      expect(served, `${route} is listed as awaiting the contract but is not served`).toContain(route);
      expect(documented, `${route} is in the contract now: take it off AWAITING_CONTRACT`).not.toContain(route);
    }
  });

  it('are all documented as ESS operations on the ESS host', () => {
    for (const op of C.operations().filter((o) => o.path.startsWith('/api/ess'))) {
      expect(op.owner, `${op.method} ${op.path}`).toBe('ess');
      expect(op.operation.tags).toEqual(['ESS']);
      // Its own host name (ADR-0019), never the Scheduler's, which answers /api/ess with HTML.
      expect(op.server, `${op.method} ${op.path}`).toBe('https://{essHost}/api');
    }
  });
});

describe('GET /api/ess/health', () => {
  it('answers as documented with the database up', async () => {
    const { app } = buildApp();
    expectContract(health, await request(app).get('/api/ess/health'));
  });

  it('answers as documented with the database down', async () => {
    quietErrors();
    const { app, db } = buildApp();
    db.outage = 'error';
    const res = await request(app).get('/api/ess/health');
    expect(res.body.db).toBe('unavailable');
    expectContract(health, res);
  });

  it('answers as documented with the app versions set', async () => {
    const { app } = buildApp({ env: { MIN_APP_VERSION: '1.0.0', LATEST_APP_VERSION: '1.2.0+14', GIT_SHA: 'ea05808bf223f7b647be373ef550cad6b781b0c0' } });
    expectContract(health, await request(app).get('/api/ess/health'));
  });

  it('refuses as documented past the per-address limit', async () => {
    const { app } = buildApp({ limits: { perIp: { windowMs: 60 * 1000, limit: 1 } } });
    await request(app).get('/api/ess/health');
    const res = await request(app).get('/api/ess/health');
    expect(res.status).toBe(429);
    expectContract(health, res);
  });
});

/** Replies that GET /api/ess/me and GET /api/ess/me/capabilities share, each built from scratch. */
const SHARED = [
  ['200, a portal login', () => ({ world: buildApp(), token: (p) => tokens.portal(p.faculty) })],
  ['200, an attendance session', () => ({ world: buildApp(), token: (p) => tokens.attendance(p.attendance) })],
  ['200, no branch, department, manager, code or designation', () => ({
    world: buildApp({ setup: (w) => Object.assign(w.people.ceo.employee, { branch_id: null, department_id: null, manager_id: null, employee_code: null, designation: null }) }),
    token: (p) => tokens.portal(p.ceo),
  })],
  ['200, serving notice', () => ({
    world: buildApp({ setup: (w) => Object.assign(w.people.hr.employee, { employment_status: 'notice_period', date_of_exit: '2026-11-30' }) }),
    token: (p) => tokens.portal(p.hr),
  })],
  ['401, no token', () => ({ world: buildApp(), token: null })],
  ['401, not a token', () => ({ world: buildApp(), token: () => 'not-a-token' })],
  ['401, an expired portal token', () => ({
    world: buildApp({ now: new Date(SIGNED_AT.getTime() + 65 * 3600 * 1000) }),
    token: (p) => tokens.portal(p.hr),
  })],
  ['401, a deleted account', () => {
    const world = buildApp();
    world.db.tables.users = world.db.tables.users.filter((u) => u.id !== world.people.admin.user.id);
    return { world, token: (p) => tokens.portal(p.admin) };
  }],
  ['401, a session older than the password', () => ({
    world: buildApp({ setup: (w) => { w.people.attendance.account.sessions_valid_from = NOW.toISOString(); } }),
    token: (p) => tokens.attendance(p.attendance),
  })],
  ['403 NOT_AN_EMPLOYEE, a student token', () => ({ world: buildApp(), token: () => tokens.student() })],
  ['403 NOT_AN_EMPLOYEE, the connector account', () => ({ world: buildApp(), token: (p) => tokens.portal(p.bot) })],
  ['403 NOT_LINKED, a desk login', () => ({ world: buildApp(), token: (p) => tokens.portal(p.desk) })],
  ['403 NOT_ACTIVE, a leaver', () => ({
    world: buildApp({ setup: (w) => { w.people.faculty.employee.employment_status = 'exited'; } }),
    token: (p) => tokens.portal(p.faculty),
  })],
  ['403 NO_ATTENDANCE_LOGIN, no login', () => ({
    world: buildApp({ setup: (w) => { w.tables.hr_attendance_accounts = []; } }),
    token: (p) => tokens.attendance(p.attendance),
  })],
  ['403 NO_ATTENDANCE_LOGIN, a login switched off', () => ({
    world: buildApp({ setup: (w) => { w.people.attendance.account.status = 'disabled'; } }),
    token: (p) => tokens.attendance(p.attendance),
  })],
  ['403 PASSWORD_CHANGE_REQUIRED, still on HR\'s first-time password', () => ({
    world: buildApp({ setup: (w) => { w.people.attendance.account.password_set_at = null; } }),
    token: (p) => tokens.attendance(p.attendance, 'pw'),
  })],
  ['503 UNAVAILABLE', () => {
    const world = buildApp();
    world.db.outage = 'error';
    return { world, token: (p) => tokens.portal(p.hr) };
  }],
  ['503 MODULE_NOT_INSTALLED', () => {
    const world = buildApp();
    world.db.dropTable('hr_attendance_accounts');
    return { world, token: (p) => tokens.attendance(p.attendance) };
  }],
  ['503 MODULE_DISABLED', () => ({ world: buildApp({ env: { ESS_ENABLED: 'false' } }), token: (p) => tokens.portal(p.hr) })],
];

/** Bodies the app never sends to these GETs, but which reach the body parser all the same. */
const BAD_BODIES = [
  ['400 INVALID_JSON', (req) => req.set('Content-Type', 'application/json').send('{"oops": ')],
  ['413 PAYLOAD_TOO_LARGE', (req) => req.set('Content-Type', 'application/json').send(JSON.stringify({ x: 'x'.repeat(20 * 1024) }))],
  ['415 UNSUPPORTED_MEDIA_TYPE', (req) => req.set('Content-Type', 'application/json').set('Content-Encoding', 'compress-of-some-kind').send('{}')],
];

describe.each([['GET /api/ess/me', me], ['GET /api/ess/me/capabilities', caps]])('%s', (_name, op) => {
  it.each(SHARED)('%s', async (_label, scenario) => {
    quietErrors();
    const { world, token } = scenario();
    const req = request(world.app).get(op.path);
    const res = await (token ? req.set(bearer(token(world.people))) : req);
    expectContract(op, res);
  });

  it('429, past the per-employee limit', async () => {
    const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
    const token = tokens.portal(people.hr);
    await request(app).get(op.path).set(bearer(token));
    const res = await request(app).get(op.path).set(bearer(token));
    expect(res.status).toBe(429);
    expectContract(op, res);
  });

  it('429, past the per-address limit', async () => {
    const { app } = buildApp({ limits: { perIp: { windowMs: 60 * 1000, limit: 1 } } });
    await request(app).get(op.path);
    const res = await request(app).get(op.path);
    expect(res.status).toBe(429);
    expectContract(op, res);
  });

  it.each(BAD_BODIES)('%s', async (_label, send) => {
    const { app, people } = buildApp();
    const res = await send(request(app).get(op.path).set(bearer(tokens.portal(people.hr))));
    expectContract(op, res);
  });

  it('500 INTERNAL_ERROR', async () => {
    quietErrors();
    const { store, people } = buildApp();
    const broken = { ...store, getEmployeeByUserId: async () => { throw new TypeError('unexpected'); } };
    const app = createApp({ config: loadConfig(TEST_ENV), store: broken, now: () => new Date(NOW.getTime()) });
    const res = await request(app).get(op.path).set(bearer(tokens.portal(people.hr)));
    expect(res.status).toBe(500);
    expectContract(op, res);
  });
});

describe('GET /api/ess/me/capabilities, role by role', () => {
  const WHO = [...PORTAL_PEOPLE.map(([key]) => key), 'attendance'];

  it.each(WHO)('%s', async (who) => {
    const { app, people } = buildApp();
    const token = who === 'attendance' ? tokens.attendance(people.attendance) : tokens.portal(people[who]);
    expectContract(caps, await request(app).get(caps.path).set(bearer(token)));
  });

  it('with push configured and direct reports', async () => {
    const { app, people } = buildApp({
      env: { FIREBASE_PROJECT_ID: 'p', FIREBASE_CLIENT_EMAIL: 'e@example.test', FIREBASE_PRIVATE_KEY_B64: Buffer.from('dummy').toString('base64') },
    });
    const res = await request(app).get(caps.path).set(bearer(tokens.portal(people.ceo)));
    expect(res.body.push.enabled).toBe(true);
    expect(res.body.team.direct_reports).toBeGreaterThan(0);
    expectContract(caps, res);
  });
});

/* ── Wave 2: kept sign-ins (A3) and the one-field sign-in (A5) ── */

/** A sign-in kept at NOW on a clock the scenario can move, and the world it lives in. */
async function kept({ who = 'attendance', setup, env, limits } = {}) {
  const clock = H.clockAt(NOW);
  const world = buildApp({ now: clock.now, setup, env, limits });
  const person = world.people[who];
  const res = await H.keep(world.app, who === 'attendance' ? tokens.attendance(person) : tokens.portal(person));
  return { ...world, clock, person, session: res.body };
}

/** A refresh an hour after the sign-in, after `change` has been made to the world. */
const refreshAfter = (options, change) => async () => {
  const k = await kept(options);
  k.clock.advance(H.HOUR);
  if (change) await change(k);
  return H.refresh(k.app, k.session.refresh_token);
};

const resolveIn = (setup, identifier, options = {}) => async () => {
  const { app, db } = buildApp({ setup, ...options });
  if (options.outage) db.outage = options.outage;
  if (options.drop) db.dropTable(options.drop);
  return request(app).post('/api/ess/sign-in/resolve').send(identifier === undefined ? {} : { identifier });
};

const accountOf = (k) => k.db.tables.hr_attendance_accounts.find((a) => a.employee_id === k.person.employee.id);

/** Every kind of reply the Wave 2 tests provoke, operation by operation. */
const WAVE_2 = {
  'POST /api/ess/session': [
    ['201, a portal login', async () => { const { app, people } = buildApp(); return H.keep(app, tokens.portal(people.hr)); }],
    ['201, an attendance session', async () => { const { app, people } = buildApp(); return H.keep(app, tokens.attendance(people.attendance)); }],
    ['400 BAD_INSTALL_ID', async () => { const { app, people } = buildApp(); return H.keep(app, tokens.portal(people.hr), {}); }],
    ['400 BAD_DEVICE_LABEL', async () => { const { app, people } = buildApp(); return H.keep(app, tokens.portal(people.hr), { install_id: INSTALL_ID, device_label: 'x'.repeat(81) }); }],
    ['400 INVALID_JSON', async () => { const { app, people } = buildApp(); return request(app).post('/api/ess/session').set(bearer(tokens.portal(people.hr))).set('Content-Type', 'application/json').send('{"install_id": '); }],
    ['401, no token', async () => { const { app } = buildApp(); return request(app).post('/api/ess/session').send({ install_id: INSTALL_ID }); }],
    ['401, a password changed since the sign-in', async () => {
      const { app, people } = buildApp({ setup: (w) => { w.people.hr.user.password_changed_at = NOW.toISOString(); } });
      return H.keep(app, tokens.portal(people.hr));
    }],
    ['403 SIGN_IN_NOT_FRESH', async () => { const { app, people } = buildApp(); return H.keep(app, tokens.portal(people.hr, new Date(NOW.getTime() - H.DAY))); }],
    ['403 NOT_AN_EMPLOYEE', async () => { const { app } = buildApp(); return H.keep(app, tokens.student()); }],
    ['403 NOT_LINKED', async () => { const { app, people } = buildApp(); return H.keep(app, tokens.portal(people.desk)); }],
    ['403 NOT_ACTIVE', async () => {
      const { app, people } = buildApp({ setup: (w) => { w.people.hr.employee.employment_status = 'exited'; } });
      return H.keep(app, tokens.portal(people.hr));
    }],
    ['403 NO_ATTENDANCE_LOGIN', async () => {
      const { app, people } = buildApp({ setup: (w) => { w.people.attendance.account.status = 'disabled'; } });
      return H.keep(app, tokens.attendance(people.attendance));
    }],
    ['403 PASSWORD_CHANGE_REQUIRED', async () => {
      const { app, people } = buildApp({ setup: (w) => { w.people.attendance.account.password_set_at = null; } });
      return H.keep(app, tokens.attendance(people.attendance, 'pw'));
    }],
    ['409 ALREADY_EXCHANGED', async () => { const k = await kept(); return H.keep(k.app, k.session.access_token); }],
    ['409 ALREADY_EXCHANGED, a Scheduler sign-in traded twice', async () => {
      const { app, people } = buildApp();
      const token = tokens.portal(people.hr);
      await H.keep(app, token);
      return H.keep(app, token, { install_id: OTHER_INSTALL_ID });
    }],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { exchangePerEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await H.keep(app, tokens.portal(people.hr));
      return H.keep(app, tokens.portal(people.hr));
    }],
    ['503 MODULE_NOT_INSTALLED', async () => { const { app, db, people } = buildApp(); db.dropTable('hr_ess_sessions'); return H.keep(app, tokens.portal(people.hr)); }],
    ['503 UNAVAILABLE', async () => { const { app, db, people } = buildApp(); db.failWhen = (q) => (q.op === 'insert' ? 'error' : null); return H.keep(app, tokens.portal(people.hr)); }],
    ['503 MODULE_DISABLED', async () => { const { app, people } = buildApp({ env: { ESS_ENABLED: 'false' } }); return H.keep(app, tokens.portal(people.hr)); }],
  ],
  'POST /api/ess/session/refresh': [
    ['200, an attendance session', refreshAfter()],
    ['200, a portal login', refreshAfter({ who: 'faculty' })],
    ['400 BAD_INSTALL_ID', async () => { const k = await kept(); return request(k.app).post('/api/ess/session/refresh').send({ refresh_token: k.session.refresh_token }); }],
    ['401 unknown', async () => { const { app } = buildApp(); return H.refresh(app, 'A'.repeat(43)); }],
    ['401 expired', async () => { const k = await kept(); k.clock.advance(91 * H.DAY); return H.refresh(k.app, k.session.refresh_token); }],
    ['401 reuse', async () => { const k = await kept(); return H.refresh(k.app, k.session.refresh_token, OTHER_INSTALL_ID); }],
    // By refresh token: an hour on, the access token has run out, and signing out with it is a 401.
    ['401 signed_out', refreshAfter({}, (k) => H.signOut(k.app, { refreshToken: k.session.refresh_token }))],
    ['401 password_changed', refreshAfter({}, (k) => { accountOf(k).sessions_valid_from = NOW.toISOString(); })],
    ['401 password_changed, a portal password reset in User Management', refreshAfter({ who: 'hr' }, (k) => {
      k.db.tables.users.find((u) => u.id === k.person.user.id).password_hash = '$2b$10$a.hash.an.admin.set';
    })],
    ['401 login_off', refreshAfter({}, (k) => { accountOf(k).status = 'disabled'; })],
    ['401 left', refreshAfter({}, (k) => { k.db.tables.hr_employees.find((e) => e.id === k.person.employee.id).is_archived = true; })],
    ['401 unlinked', refreshAfter({ who: 'hr' }, (k) => { k.db.tables.hr_employees.find((e) => e.id === k.person.employee.id).user_id = null; })],
    ['409 REFRESH_IN_PROGRESS', async () => {
      const k = await kept();
      k.clock.advance(H.HOUR);
      await H.refresh(k.app, k.session.refresh_token);
      return H.refresh(k.app, k.session.refresh_token);
    }],
    ['429 RATE_LIMITED', async () => {
      const { app } = buildApp({ limits: { sessionPerIp: { windowMs: 60 * 1000, limit: 1 } } });
      await H.refresh(app, 'A'.repeat(43));
      return H.refresh(app, 'A'.repeat(43));
    }],
    ['503 UNAVAILABLE', refreshAfter({}, (k) => { k.db.outage = 'error'; })],
    ['503 MODULE_NOT_INSTALLED', refreshAfter({}, (k) => { k.db.dropTable('hr_ess_sessions'); })],
    ['503 MODULE_DISABLED', async () => { const { app } = buildApp({ env: { ESS_ENABLED: 'false' } }); return H.refresh(app, 'A'.repeat(43)); }],
  ],
  'POST /api/ess/session/sign-out': [
    ['204, with the access token', async () => { const k = await kept(); return H.signOut(k.app, { token: k.session.access_token }); }],
    ['204, with the refresh token', async () => { const k = await kept(); return H.signOut(k.app, { refreshToken: k.session.refresh_token }); }],
    ['401, neither', async () => { const { app } = buildApp(); return H.signOut(app); }],
    ['403 NOT_AN_EMPLOYEE', async () => { const { app } = buildApp(); return H.signOut(app, { token: tokens.student() }); }],
    ['429 RATE_LIMITED', async () => {
      const { app } = buildApp({ limits: { sessionPerIp: { windowMs: 60 * 1000, limit: 1 } } });
      await H.signOut(app);
      return H.signOut(app);
    }],
    ['503 UNAVAILABLE', async () => { const k = await kept(); k.db.failWhen = (q) => (q.op === 'rpc' ? 'error' : null); return H.signOut(k.app, { token: k.session.access_token }); }],
  ],
  'GET /api/ess/sessions': [
    ['200', async () => { const k = await kept({ who: 'hr' }); await H.keep(k.app, tokens.portal(k.person), { install_id: OTHER_INSTALL_ID }); return H.listSessions(k.app, k.session.access_token); }],
    ['200, none', async () => { const { app, people } = buildApp(); return H.listSessions(app, tokens.portal(people.hr)); }],
    ['401', async () => { const { app } = buildApp(); return request(app).get('/api/ess/sessions'); }],
    ['403 NOT_AN_EMPLOYEE', async () => { const { app } = buildApp(); return H.listSessions(app, tokens.student()); }],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await H.listSessions(app, tokens.portal(people.hr));
      return H.listSessions(app, tokens.portal(people.hr));
    }],
    ['503 MODULE_NOT_INSTALLED', async () => { const { app, db, people } = buildApp(); db.dropTable('hr_ess_sessions'); return H.listSessions(app, tokens.portal(people.hr)); }],
  ],
  'DELETE /api/ess/sessions/{id}': [
    ['204', async () => { const k = await kept(); return H.endSession(k.app, k.session.access_token, k.session.session.id); }],
    ['404 NOT_FOUND', async () => { const k = await kept(); return H.endSession(k.app, tokens.portal(k.people.hr), k.session.session.id); }],
    ['401', async () => { const { app } = buildApp(); return request(app).delete('/api/ess/sessions/5a000000-0000-4000-8000-000000000001'); }],
    ['403 NOT_AN_EMPLOYEE', async () => { const { app } = buildApp(); return H.endSession(app, tokens.student(), '5a000000-0000-4000-8000-000000000001'); }],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await H.endSession(app, tokens.portal(people.hr), '5a000000-0000-4000-8000-000000000001');
      return H.endSession(app, tokens.portal(people.hr), '5a000000-0000-4000-8000-000000000001');
    }],
    ['503 UNAVAILABLE', async () => { const k = await kept(); k.db.failWhen = (q) => (q.op === 'rpc' ? 'error' : null); return H.endSession(k.app, k.session.access_token, k.session.session.id); }],
  ],
  'POST /api/ess/sign-in/resolve': [
    ['200, portal as typed', resolveIn(undefined, 'faculty.login')],
    ['200, portal at any branch', resolveIn(undefined, 'hr.login')],
    ['200, portal by username or phone', resolveIn(undefined, 'RVM-011')],
    ['200, attendance', resolveIn(undefined, 'RVM-050')],
    ['200, attendance with no methods', resolveIn((w) => { w.people.attendance.account.status = 'disabled'; }, 'RVM-050')],
    ['200, unknown', resolveIn(undefined, 'nobody.here')],
    ['400 BAD_IDENTIFIER', resolveIn(undefined, '')],
    ['429 RATE_LIMITED', async () => {
      const { app } = buildApp({ limits: { signInPerIdentifier: { windowMs: 60 * 1000, limit: 1 } } });
      await request(app).post('/api/ess/sign-in/resolve').send({ identifier: 'RVM-050' });
      return request(app).post('/api/ess/sign-in/resolve').send({ identifier: 'RVM-050' });
    }],
    ['503 UNAVAILABLE', resolveIn(undefined, 'RVM-050', { outage: 'error' })],
    ['503 MODULE_NOT_INSTALLED', resolveIn(undefined, 'RVM-050', { drop: 'hr_attendance_accounts' })],
    ['503 MODULE_DISABLED', resolveIn(undefined, 'RVM-050', { env: { ESS_ENABLED: 'false' } })],
  ],
};

/* ── Wave 2: my data (A8, E9), my day (B1), mocked locations (B14) and the phone reset (B8) ── */

/** A token for `who`: a fixture person's key, or 'attendance' for the attendance-only employee's session. */
const as = (people, who) => (who === 'attendance' ? tokens.attendance(people.attendance) : tokens.portal(people[who]));

/**
 * One request in a world built with `options` (buildApp's), after `prepare` has changed it:
 * `send(app, token, world)` makes the request with `who`'s token.
 */
const call = (who, send, { prepare, ...options } = {}) => async () => {
  const world = buildApp(options);
  if (prepare) prepare(world);
  return send(world.app, as(world.people, who), world);
};

const get = (path) => (app, token) => request(app).get(path).set(bearer(token));
const post = (path, body) => (app, token) => request(app).post(path).set(bearer(token)).send(body);
const put = (path, body) => (app, token) => request(app).put(path).set(bearer(token)).send(body);
const patch = (path, body) => (app, token) => request(app).patch(path).set(bearer(token)).send(body);

const REQUEST_ID = (n) => `51000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

/** A data request as HR's queue holds it. */
const dataRequestRow = (employeeId, n, change = {}) => ({
  id: REQUEST_ID(n),
  employee_id: employeeId,
  kind: 'correct',
  details: 'My employee code is wrong.',
  status: 'open',
  created_at: `2026-10-1${n % 6}T05:00:00+00:00`,
  resolved_at: null,
  resolved_by_user_id: null,
  resolved_by_name: null,
  resolution_note: null,
  ...change,
});

/** One open request from the attendance employee (1), one from HR (2), and one HR has answered (3). */
const withDataRequests = (w) => {
  w.tables.hr_ess_data_requests = [
    dataRequestRow(w.people.attendance.employee.id, 1),
    dataRequestRow(w.people.hr.employee.id, 2, { kind: 'delete', details: 'Delete my old address.' }),
    dataRequestRow(w.people.faculty.employee.id, 3, {
      status: 'rejected', resolved_at: '2026-10-15T06:00:00+00:00', resolved_by_user_id: w.people.hr.user.id,
      resolved_by_name: 'Test HR Manager', resolution_note: 'That is how it is spelt on your offer letter.',
    }),
  ];
};
const fiveOpen = (w) => {
  w.tables.hr_ess_data_requests = [1, 2, 3, 4, 5].map((n) => dataRequestRow(w.people.faculty.employee.id, n));
};

/** The attendance employee's personal details, as HR recorded them. */
const withPersonal = (w) => {
  w.tables.hr_ess_personal_details = [{
    employee_id: w.people.attendance.employee.id,
    date_of_birth: '1994-05-21', blood_group: 'B+', address_line1: 'House 12, Sector 15', address_line2: null,
    city: 'Faridabad', state: 'Haryana', pincode: '121007',
    emergency_name: 'Sunita Yadav', emergency_relation: 'Mother', emergency_phone: '9876543210',
    updated_at: '2026-10-10T05:00:00+00:00', updated_by_user_id: w.people.hr.user.id, updated_by_name: 'Test HR Manager',
  }];
};

const NOBODY = uuid('e', 999);

/** Mocked-location reports at both branches, and one whose employee record has gone. */
const withMockReports = (w) => {
  const row = (employeeId, branchId, reportedAt, n, change = {}) => ({
    id: `60000000-0000-4000-8000-${String(n).padStart(12, '0')}`, employee_id: employeeId, branch_id: branchId,
    reported_at: reportedAt, client_at: null, kind: 'punch', latitude: 28.4, longitude: 77.3, accuracy_m: 0,
    provider: 'gps', app_version: '1.0.0', install_id: `install-${n}`, ...change,
  });
  w.tables.hr_ess_mock_location_reports = [
    row(w.people.attendance.employee.id, BRANCH_ID, '2026-10-16T05:00:00+00:00', 1, { client_at: '2026-10-16T04:59:58+00:00' }),
    row(w.people.pune.employee.id, BRANCH_PUNE_ID, '2026-10-10T05:00:00+00:00', 2, { latitude: null, longitude: null, accuracy_m: null, provider: null }),
    row(NOBODY, null, '2026-10-09T05:00:00+00:00', 3),
  ];
};

const MY_DATA = '/api/ess/me/data-requests';
const HR_DATA = '/api/ess/hr/data-requests';
const MY_PERSONAL = '/api/ess/me/personal';
const theirPersonal = (id) => `/api/ess/hr/employees/${id}/personal`;
const DAY = '/api/ess/attendance/day';
const MOCK = '/api/ess/attendance/mock-location';
const MOCK_LIST = '/api/ess/hr/mock-location-reports';
const DEVICES = '/api/ess/hr/devices';
const RESET = '/api/ess/hr/devices/reset';
const ATTENDANCE_EMPLOYEE = uuid('e', 50);
const HR_EMPLOYEE = uuid('e', 9);
const A_REQUEST = { kind: 'correct', details: 'My employee code is wrong.' };
const FIX = {
  kind: 'punch', latitude: 28.40912, longitude: 77.31801, accuracy_m: 0,
  client_at: '2026-10-16T11:59:00.000+05:30', provider: 'gps', app_version: '1.0.0+3', install_id: 'install-3f9a',
};
const fails = (table, how = 'error') => (w) => { w.db.failWhen = (q) => (q.table === table ? how : null); };
const drop = (table) => (w) => w.db.dropTable(table);

/** Reads of `table` answer what `rows()` gives, as if made before a change the table now holds. */
const staleReads = (table, rows) => (w) => {
  const realFrom = w.db.from;
  w.db.from = (t) => {
    const q = realFrom(t);
    if (t !== table) return q;
    const run = q.run.bind(q);
    q.run = async () => {
      if (q.op !== 'select') return run();
      const out = await run();
      return { ...out, data: q.expect ? (rows()[0] || null) : rows() };
    };
    return q;
  };
};

/** The save reads the emergency contact withPersonal records, which somebody has removed since. */
const contactRemovedMeanwhile = (w) => {
  const row = w.db.tables.hr_ess_personal_details[0];
  const asRead = { ...row };
  Object.assign(row, { emergency_name: null, emergency_relation: null, emergency_phone: null });
  staleReads('hr_ess_personal_details', () => [asRead])(w);
};

Object.assign(WAVE_2, {
  'POST /api/ess/me/data-requests': [
    ['201, a portal login', call('faculty', post(MY_DATA, A_REQUEST))],
    ['201, an attendance session', call('attendance', post(MY_DATA, { kind: 'delete', details: 'Please delete my second phone number.' }))],
    ['400 VALIDATION_FAILED, a kind not offered', call('faculty', post(MY_DATA, { kind: 'export', details: 'Everything about me.' }))],
    ['400 VALIDATION_FAILED, details too short', call('faculty', post(MY_DATA, { kind: 'correct', details: 'fix' }))],
    ['400 VALIDATION_FAILED, somebody else\'s employee id', call('faculty', post(MY_DATA, { ...A_REQUEST, employee_id: HR_EMPLOYEE }))],
    ['400 VALIDATION_FAILED, not an object', call('faculty', post(MY_DATA, ['correct']))],
    ['400 INVALID_JSON', call('faculty', (app, token) => request(app).post(MY_DATA).set(bearer(token)).set('Content-Type', 'application/json').send('{"kind": '))],
    ['401, no token', call('faculty', (app) => request(app).post(MY_DATA).send(A_REQUEST))],
    ['403 NOT_LINKED', call('desk', post(MY_DATA, A_REQUEST))],
    ['403 PASSWORD_CHANGE_REQUIRED', call('attendance', (app, _token, w) => post(MY_DATA, A_REQUEST)(app, tokens.attendance(w.people.attendance, 'pw')), {
      setup: (w) => { w.people.attendance.account.password_set_at = null; },
    })],
    ['409 TOO_MANY_OPEN_REQUESTS', call('faculty', post(MY_DATA, A_REQUEST), { setup: fiveOpen })],
    // The count read before the insert saw fewer (requests sent at once); the database's own count refuses.
    ['409 TOO_MANY_OPEN_REQUESTS, counted by the database', call('faculty', post(MY_DATA, A_REQUEST), { setup: fiveOpen, prepare: staleReads('hr_ess_data_requests', () => []) })],
    ['413 PAYLOAD_TOO_LARGE', call('faculty', post(MY_DATA, { kind: 'correct', details: 'x'.repeat(20 * 1024) }))],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await post(MY_DATA, A_REQUEST)(app, tokens.portal(people.faculty));
      return post(MY_DATA, A_REQUEST)(app, tokens.portal(people.faculty));
    }],
    ['503 MODULE_NOT_INSTALLED', call('faculty', post(MY_DATA, A_REQUEST), { prepare: drop('hr_ess_data_requests') })],
    ['503 UNAVAILABLE', call('faculty', post(MY_DATA, A_REQUEST), { prepare: fails('hr_ess_data_requests') })],
    ['503 MODULE_DISABLED', call('faculty', post(MY_DATA, A_REQUEST), { env: { ESS_ENABLED: 'false' } })],
  ],
  'GET /api/ess/me/data-requests': [
    ['200, one answered', call('faculty', get(MY_DATA), { setup: withDataRequests })],
    ['200, none', call('ceo', get(MY_DATA), { setup: withDataRequests })],
    ['401, no token', call('faculty', (app) => request(app).get(MY_DATA))],
    ['403 NOT_ACTIVE', call('faculty', get(MY_DATA), { setup: (w) => { w.people.faculty.employee.employment_status = 'exited'; } })],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await get(MY_DATA)(app, tokens.portal(people.faculty));
      return get(MY_DATA)(app, tokens.portal(people.faculty));
    }],
    ['503 MODULE_NOT_INSTALLED', call('faculty', get(MY_DATA), { prepare: drop('hr_ess_data_requests') })],
  ],
  'GET /api/ess/hr/data-requests': [
    ['200, the open queue for HR', call('hr', get(HR_DATA), { setup: withDataRequests })],
    ['200, every request for an HR Executive', call('hr_executive', get(`${HR_DATA}?status=all`), { setup: withDataRequests })],
    ['200, the rejected ones for a super admin', call('super_admin', get(`${HR_DATA}?status=rejected`), { setup: withDataRequests })],
    ['400 VALIDATION_FAILED', call('hr', get(`${HR_DATA}?status=closed`))],
    ['401, no token', call('hr', (app) => request(app).get(HR_DATA))],
    ['403 HR_ACCESS_DENIED, an admin', call('admin', get(HR_DATA))],
    ['403 HR_ACCESS_DENIED, a manager', call('hod', get(HR_DATA))],
    ['403 PORTAL_LOGIN_REQUIRED', call('attendance', get(HR_DATA))],
    ['403 NOT_LINKED', call('desk', get(HR_DATA))],
    ['429 RATE_LIMITED', async () => {
      const { app } = buildApp({ limits: { perIp: { windowMs: 60 * 1000, limit: 1 } } });
      await request(app).get(HR_DATA);
      return request(app).get(HR_DATA);
    }],
    ['503 MODULE_NOT_INSTALLED', call('hr', get(HR_DATA), { prepare: drop('hr_ess_data_requests') })],
  ],
  'PATCH /api/ess/hr/data-requests/{id}': [
    ['200, done', call('hr', patch(`${HR_DATA}/${REQUEST_ID(1)}`, { status: 'done', note: 'Corrected in the HR record.' }), { setup: withDataRequests })],
    ['200, rejected', call('hr_executive', patch(`${HR_DATA}/${REQUEST_ID(1)}`, { status: 'rejected', note: 'The code is right.' }), { setup: withDataRequests })],
    ['400 VALIDATION_FAILED, not an id', call('hr', patch(`${HR_DATA}/42`, { status: 'done' }))],
    ['400 VALIDATION_FAILED, a rejection with no reason', call('hr', patch(`${HR_DATA}/${REQUEST_ID(1)}`, { status: 'rejected' }), { setup: withDataRequests })],
    ['401, no token', call('hr', (app) => request(app).patch(`${HR_DATA}/${REQUEST_ID(1)}`).send({ status: 'done' }))],
    ['403 HR_ACCESS_DENIED', call('faculty', patch(`${HR_DATA}/${REQUEST_ID(1)}`, { status: 'done' }), { setup: withDataRequests })],
    ['403 PORTAL_LOGIN_REQUIRED', call('attendance', patch(`${HR_DATA}/${REQUEST_ID(1)}`, { status: 'done' }), { setup: withDataRequests })],
    ['404 NOT_FOUND', call('hr', patch(`${HR_DATA}/${REQUEST_ID(9)}`, { status: 'done' }), { setup: withDataRequests })],
    ['409 OWN_REQUEST', call('hr', patch(`${HR_DATA}/${REQUEST_ID(2)}`, { status: 'done' }), { setup: withDataRequests })],
    ['409 ALREADY_RESOLVED', call('hr', patch(`${HR_DATA}/${REQUEST_ID(3)}`, { status: 'done' }), { setup: withDataRequests })],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ setup: withDataRequests, limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await patch(`${HR_DATA}/${REQUEST_ID(1)}`, { status: 'done' })(app, tokens.portal(people.hr));
      return patch(`${HR_DATA}/${REQUEST_ID(1)}`, { status: 'done' })(app, tokens.portal(people.hr));
    }],
    ['503 MODULE_NOT_INSTALLED', call('hr', patch(`${HR_DATA}/${REQUEST_ID(1)}`, { status: 'done' }), { prepare: drop('hr_ess_data_requests') })],
  ],
  'GET /api/ess/me/personal': [
    ['200, recorded', call('attendance', get(MY_PERSONAL), { setup: withPersonal })],
    ['200, nothing recorded', call('faculty', get(MY_PERSONAL), { setup: withPersonal })],
    ['401, no token', call('faculty', (app) => request(app).get(MY_PERSONAL))],
    ['403 NOT_LINKED', call('desk', get(MY_PERSONAL))],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await get(MY_PERSONAL)(app, tokens.portal(people.faculty));
      return get(MY_PERSONAL)(app, tokens.portal(people.faculty));
    }],
    ['503 MODULE_NOT_INSTALLED', call('faculty', get(MY_PERSONAL), { prepare: drop('hr_ess_personal_details') })],
  ],
  'PUT /api/ess/me/personal': [
    ['200', call('faculty', put(MY_PERSONAL, { blood_group: 'o +', emergency_name: 'Sunita Yadav', emergency_relation: 'Mother', emergency_phone: '+91 98765 43210' }))],
    ['200, the contact cleared', call('attendance', put(MY_PERSONAL, { emergency_name: null, emergency_relation: '', emergency_phone: null }), { setup: withPersonal })],
    ['400 VALIDATION_FAILED, a blood group', call('faculty', put(MY_PERSONAL, { blood_group: 'Z' }))],
    ['400 VALIDATION_FAILED, nothing to change', call('faculty', put(MY_PERSONAL, {}))],
    ['400 VALIDATION_FAILED, half a contact', call('faculty', put(MY_PERSONAL, { emergency_name: 'Sunita Yadav' }))],
    ['401, no token', call('faculty', (app) => request(app).put(MY_PERSONAL).send({ blood_group: 'B+' }))],
    ['403 SENSITIVE_FIELD', call('faculty', put(MY_PERSONAL, { date_of_birth: '1994-05-21' }))],
    ['403 NOT_ACTIVE', call('faculty', put(MY_PERSONAL, { blood_group: 'B+' }), { setup: (w) => { w.people.faculty.employee.is_archived = true; } })],
    ['409 RECORD_CHANGED', call('attendance', put(MY_PERSONAL, { emergency_relation: 'Sister' }), { setup: withPersonal, prepare: contactRemovedMeanwhile })],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await put(MY_PERSONAL, { blood_group: 'B+' })(app, tokens.portal(people.faculty));
      return put(MY_PERSONAL, { blood_group: 'B+' })(app, tokens.portal(people.faculty));
    }],
    ['503 MODULE_NOT_INSTALLED', call('faculty', put(MY_PERSONAL, { blood_group: 'B+' }), { prepare: drop('hr_ess_personal_details') })],
  ],
  'GET /api/ess/hr/employees/{id}/personal': [
    ['200, recorded', call('hr', get(theirPersonal(ATTENDANCE_EMPLOYEE)), { setup: withPersonal })],
    ['200, nothing recorded', call('super_admin', get(theirPersonal(uuid('e', 11))))],
    ['400 VALIDATION_FAILED', call('hr', get(theirPersonal('not-an-id')))],
    ['401, no token', call('hr', (app) => request(app).get(theirPersonal(ATTENDANCE_EMPLOYEE)))],
    ['403 HR_ACCESS_DENIED, the employee\'s own manager', call('admin_manager', get(theirPersonal(ATTENDANCE_EMPLOYEE)), { setup: withPersonal })],
    ['403 PORTAL_LOGIN_REQUIRED', call('attendance', get(theirPersonal(ATTENDANCE_EMPLOYEE)))],
    ['404 NOT_FOUND', call('hr', get(theirPersonal(NOBODY)))],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await get(theirPersonal(ATTENDANCE_EMPLOYEE))(app, tokens.portal(people.hr));
      return get(theirPersonal(ATTENDANCE_EMPLOYEE))(app, tokens.portal(people.hr));
    }],
    ['503 UNAVAILABLE, the audit row cannot be written', call('hr', get(theirPersonal(ATTENDANCE_EMPLOYEE)), { setup: withPersonal, prepare: fails('hr_ess_audit') })],
    ['503 MODULE_NOT_INSTALLED', call('hr', get(theirPersonal(ATTENDANCE_EMPLOYEE)), { prepare: drop('hr_ess_personal_details') })],
  ],
  'PUT /api/ess/hr/employees/{id}/personal': [
    ['200', call('hr', put(theirPersonal(ATTENDANCE_EMPLOYEE), { date_of_birth: '1994-05-21', address_line1: 'House 12, Sector 15', city: 'Faridabad', state: 'Haryana', pincode: '121007' }))],
    ['200, a change over what is recorded', call('hr_executive', put(theirPersonal(ATTENDANCE_EMPLOYEE), { address_line2: 'Near the market' }), { setup: withPersonal })],
    ['400 VALIDATION_FAILED, too young', call('hr', put(theirPersonal(ATTENDANCE_EMPLOYEE), { date_of_birth: '2015-01-01' }))],
    ['400 VALIDATION_FAILED, a PIN code', call('hr', put(theirPersonal(ATTENDANCE_EMPLOYEE), { pincode: '012345' }))],
    ['401, no token', call('hr', (app) => request(app).put(theirPersonal(ATTENDANCE_EMPLOYEE)).send({ city: 'Pune' }))],
    ['403 HR_ACCESS_DENIED', call('admin', put(theirPersonal(ATTENDANCE_EMPLOYEE), { city: 'Pune' }))],
    ['403 PORTAL_LOGIN_REQUIRED', call('attendance', put(theirPersonal(ATTENDANCE_EMPLOYEE), { city: 'Pune' }))],
    ['404 NOT_FOUND', call('hr', put(theirPersonal(NOBODY), { city: 'Pune' }))],
    ['409 OWN_RECORD', call('hr', put(theirPersonal(HR_EMPLOYEE), { city: 'Pune' }))],
    ['409 RECORD_CHANGED', call('hr', put(theirPersonal(ATTENDANCE_EMPLOYEE), { emergency_relation: 'Sister' }), { setup: withPersonal, prepare: contactRemovedMeanwhile })],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await put(theirPersonal(ATTENDANCE_EMPLOYEE), { city: 'Pune' })(app, tokens.portal(people.hr));
      return put(theirPersonal(ATTENDANCE_EMPLOYEE), { city: 'Pune' })(app, tokens.portal(people.hr));
    }],
    ['503 MODULE_NOT_INSTALLED', call('hr', put(theirPersonal(ATTENDANCE_EMPLOYEE), { city: 'Pune' }), { prepare: drop('hr_ess_personal_details') })],
  ],
  'GET /api/ess/attendance/day': [
    ['200, a late day with its note and both remarks', call('attendance', get(`${DAY}?date=2026-10-15`))],
    ['200, an override from last month', call('attendance', get(`${DAY}?date=2026-09-20`))],
    ['200, today with nothing recorded', call('faculty', get(DAY))],
    ['400 DAY_OUT_OF_RANGE', call('attendance', get(`${DAY}?date=2026-08-31`))],
    ['400 VALIDATION_FAILED', call('attendance', get(`${DAY}?date=2026-02-30`))],
    ['401, no token', call('attendance', (app) => request(app).get(DAY))],
    ['403 NO_ATTENDANCE_LOGIN', call('attendance', get(DAY), { setup: (w) => { w.people.attendance.account.status = 'disabled'; } })],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await get(DAY)(app, tokens.attendance(people.attendance));
      return get(DAY)(app, tokens.attendance(people.attendance));
    }],
    ['503 MODULE_NOT_INSTALLED', call('attendance', get(DAY), { prepare: (w) => w.db.dropColumn('hr_staff_attendance', 'late_minutes') })],
    ['503 UNAVAILABLE', call('attendance', get(DAY), { prepare: fails('hr_attendance_remarks', 'throw') })],
  ],
  'POST /api/ess/attendance/mock-location': [
    ['201', call('attendance', post(MOCK, FIX))],
    ['201, no location and an unreadable phone clock', call('faculty', post(MOCK, { kind: 'punch', client_at: 'yesterday' }))],
    ['201, a phone clock in year 0', call('faculty', post(MOCK, { kind: 'punch', client_at: '0000-06-01T00:00:00Z' }))],
    ['400 VALIDATION_FAILED, a ping', call('attendance', post(MOCK, { ...FIX, kind: 'ping' }))],
    ['400 VALIDATION_FAILED, half a location', call('attendance', post(MOCK, { kind: 'punch', latitude: 28.4 }))],
    ['400 VALIDATION_FAILED, somebody else\'s employee id', call('attendance', post(MOCK, { ...FIX, employee_id: HR_EMPLOYEE }))],
    ['401, no token', call('attendance', (app) => request(app).post(MOCK).send(FIX))],
    ['403 NOT_LINKED', call('desk', post(MOCK, FIX))],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { mockReports: { windowMs: 60 * 1000, limit: 1 } } });
      await post(MOCK, FIX)(app, tokens.attendance(people.attendance));
      return post(MOCK, FIX)(app, tokens.attendance(people.attendance));
    }],
    ['503 MODULE_NOT_INSTALLED', call('attendance', post(MOCK, FIX), { prepare: drop('hr_ess_mock_location_reports') })],
  ],
  'GET /api/ess/hr/mock-location-reports': [
    ['200, HR', call('hr', get(MOCK_LIST), { setup: withMockReports })],
    ['200, the CEO, one branch', call('ceo', get(`${MOCK_LIST}?branch_id=${BRANCH_PUNE_ID}`), { setup: withMockReports })],
    ['200, a super admin, a range with nothing', call('super_admin', get(`${MOCK_LIST}?from=2026-01-01&to=2026-01-31`), { setup: withMockReports })],
    ['400 VALIDATION_FAILED, a range the wrong way round', call('hr', get(`${MOCK_LIST}?from=2026-10-16&to=2026-10-01`))],
    ['400 VALIDATION_FAILED, a branch that is not an id', call('hr', get(`${MOCK_LIST}?branch_id=1`))],
    ['400 VALIDATION_FAILED, a year Postgres cannot take', call('hr', get(`${MOCK_LIST}?from=0000-01-01&to=0000-01-31`))],
    ['401, no token', call('hr', (app) => request(app).get(MOCK_LIST))],
    ['403 ATTENDANCE_OVERRIDE_DENIED, an HR Executive', call('hr_executive', get(MOCK_LIST))],
    ['403 PORTAL_LOGIN_REQUIRED', call('attendance', get(MOCK_LIST))],
    ['404 NOT_FOUND', call('hr', get(`${MOCK_LIST}?branch_id=${uuid('b', 9)}`))],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await get(MOCK_LIST)(app, tokens.portal(people.hr));
      return get(MOCK_LIST)(app, tokens.portal(people.hr));
    }],
    ['503 MODULE_NOT_INSTALLED', call('hr', get(MOCK_LIST), { prepare: drop('hr_ess_mock_location_reports') })],
  ],
  'GET /api/ess/hr/devices': [
    ['200, the active phones', call('hr', get(DEVICES))],
    ['200, every phone at one branch', call('ceo', get(`${DEVICES}?status=all&branch_id=${BRANCH_ID}`))],
    ['200, a phone whose employee record has gone', call('super_admin', get(`${DEVICES}?status=revoked`), {
      setup: (w) => { w.tables.hr_attendance_devices[2].employee_id = NOBODY; },
    })],
    ['400 VALIDATION_FAILED', call('hr', get(`${DEVICES}?status=lost`))],
    ['401, no token', call('hr', (app) => request(app).get(DEVICES))],
    ['403 ATTENDANCE_OVERRIDE_DENIED', call('admin_manager', get(DEVICES))],
    ['403 PORTAL_LOGIN_REQUIRED', call('attendance', get(DEVICES))],
    ['404 NOT_FOUND', call('hr', get(`${DEVICES}?branch_id=${uuid('b', 9)}`))],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await get(DEVICES)(app, tokens.portal(people.hr));
      return get(DEVICES)(app, tokens.portal(people.hr));
    }],
    ['503 MODULE_NOT_INSTALLED', call('hr', get(DEVICES), { prepare: drop('hr_attendance_devices') })],
  ],
  'POST /api/ess/hr/devices/reset': [
    ['200, a branch', call('hr', post(RESET, { branch_id: BRANCH_ID, reason: 'Moving Faridabad to the app' }))],
    ['200, a list of people', call('super_admin', post(RESET, { employee_ids: [ATTENDANCE_EMPLOYEE, NOBODY], reason: 'New phone' }))],
    ['200, nothing left to reset', call('ceo', post(RESET, { employee_ids: [NOBODY], reason: 'New phone' }))],
    ['400 VALIDATION_FAILED, both targets', call('hr', post(RESET, { branch_id: BRANCH_ID, employee_ids: [ATTENDANCE_EMPLOYEE], reason: 'New phone' }))],
    ['400 VALIDATION_FAILED, no reason', call('hr', post(RESET, { employee_ids: [ATTENDANCE_EMPLOYEE] }))],
    ['401, no token', call('hr', (app) => request(app).post(RESET).send({ branch_id: BRANCH_ID, reason: 'Go-live' }))],
    ['403 ATTENDANCE_OVERRIDE_DENIED, an HR Executive', call('hr_executive', post(RESET, { branch_id: BRANCH_ID, reason: 'Go-live' }))],
    ['403 PORTAL_LOGIN_REQUIRED', call('attendance', post(RESET, { branch_id: BRANCH_ID, reason: 'Go-live' }))],
    ['404 NOT_FOUND', call('hr', post(RESET, { branch_id: uuid('b', 9), reason: 'Go-live' }))],
    ['413 PAYLOAD_TOO_LARGE', call('hr', post(RESET, { employee_ids: [ATTENDANCE_EMPLOYEE], reason: 'Go-live', padding: 'x'.repeat(40 * 1024) }))],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await post(RESET, { branch_id: BRANCH_ID, reason: 'Go-live' })(app, tokens.portal(people.hr));
      return post(RESET, { branch_id: BRANCH_ID, reason: 'Go-live' })(app, tokens.portal(people.hr));
    }],
    ['503 UNAVAILABLE', call('hr', post(RESET, { branch_id: BRANCH_ID, reason: 'Go-live' }), { prepare: fails('hr_attendance_devices') })],
    ['503 UNAVAILABLE, part-way through', call('hr', post(RESET, { employee_ids: Array.from({ length: 151 }, (_, i) => uuid('e', i + 1)), reason: 'Go-live' }), {
      prepare: (w) => { let n = 0; w.db.failWhen = (q) => (q.table === 'hr_attendance_devices' && q.op === 'update' && ++n === 2 ? 'error' : null); },
    })],
    ['503 MODULE_NOT_INSTALLED', call('hr', post(RESET, { branch_id: BRANCH_ID, reason: 'Go-live' }), { prepare: drop('hr_attendance_devices') })],
  ],
});

/* ── Wave 3 (Phase 1C): requests, leave, approvals, cancels and the limits ── */

const AR_REQ = '/api/ess/attendance-requests';
const LR_REQ = '/api/ess/leave-requests';
const BALANCES = '/api/ess/leave/balances';
const INBOX = '/api/ess/approvals';
const LIMITS = '/api/ess/hr/request-limits';
const AID = (n) => `7c000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const LID = (n) => `7c000000-0001-4000-8000-${String(n).padStart(12, '0')}`;
const ON_DUTY = { type: 'on_duty', day: '2026-10-15', reason: 'Client visit at the Pune centre.', place: 'Pune centre' };
const A_FIX = { type: 'fix_a_day', day: '2026-10-15', reason: 'I forgot to punch out.', fix_out: '18:00' };

/** A request row of either family, as the tables hold it. */
const requestRow = (family, employeeId, id, change = {}) => {
  const common = {
    id,
    employee_id: employeeId,
    type: family === 'leave' ? 'cl' : 'on_duty',
    status: 'pending',
    day: '2026-10-15',
    reason: 'Client visit at the Pune centre.',
    day_before: null,
    day_written_at: null,
    decided_by_employee_id: null,
    decided_by_user_id: null,
    decided_by_name: null,
    decided_at: null,
    decision_note: null,
    cancelled_by_user_id: null,
    cancelled_by_name: null,
    cancelled_at: null,
    cancel_reason: null,
    created_at: '2026-10-14T05:00:00+00:00',
    updated_at: '2026-10-14T05:00:00+00:00',
    ...change,
  };
  return family === 'attendance' ? { place: null, fix_in: null, fix_out: null, ...common } : common;
};

/** A day row, for the late marks and the days a fix or an excuse lands on. */
const contractDayRow = (employeeId, day, change = {}) => ({
  id: `7e000000-0000-4000-8000-${String(day.charCodeAt(9) * 37).padStart(12, '0')}`, employee_id: employeeId, branch_id: null,
  day, status: 'present', leave_type: null, note: null, marked_by: null, marked_by_name: 'Test (self punch)',
  marked_at: `${day}T04:00:00+00:00`, updated_at: `${day}T12:00:00+00:00`, source: 'self_punch',
  first_in: `${day}T04:20:00+00:00`, last_out: `${day}T12:40:00+00:00`, worked_minutes: 500, shift_id: null,
  shift_start: null, shift_end: null, grace_minutes: null, late_minutes: null, early_exit_minutes: null, late_count: null,
  late_half_day: false, late_excused: false, late_excused_by_name: null, late_excused_reason: null, late_excused_at: null,
  ...change,
});

/** One pending on-duty request from the attendance employee, one pending CL from the faculty member. */
const withRequests = (w) => {
  w.tables.hr_ess_attendance_requests = [requestRow('attendance', w.people.attendance.employee.id, AID(1), { place: 'Pune centre' })];
  w.tables.hr_ess_leave_requests = [requestRow('leave', w.people.faculty.employee.id, LID(2))];
};

/** A decided attendance request, for the cancel and archive scenarios. */
const withApproved = (w) => {
  w.tables.hr_ess_attendance_requests = [requestRow('attendance', w.people.attendance.employee.id, AID(3), {
    status: 'approved', place: 'Pune centre', decided_by_name: 'Test Admin Manager', decided_at: '2026-10-16T06:00:00+00:00',
  })];
};

const AT_SIX = () => new Date('2026-10-06T06:30:00.000Z');

const WAVE_3 = {
  'POST /api/ess/attendance-requests': [
    ['201, on duty as an attendance session', call('attendance', post(AR_REQ, ON_DUTY))],
    ['201, a fix as a portal login', call('faculty', post(AR_REQ, A_FIX))],
    ['400 VALIDATION_FAILED, a type not offered', call('faculty', post(AR_REQ, { type: 'wfh', day: '2026-10-15', reason: 'Working from home today.' }))],
    ['400 VALIDATION_FAILED, a day before last month', call('faculty', post(AR_REQ, { ...ON_DUTY, day: '2026-08-31' }))],
    ['400 VALIDATION_FAILED, a fix for a day that has not happened', call('faculty', post(AR_REQ, { ...A_FIX, day: '2026-10-17' }))],
    ['400 INVALID_JSON', call('faculty', (app, token) => request(app).post(AR_REQ).set(bearer(token)).set('Content-Type', 'application/json').send('{"type": '))],
    ['401, no token', call('faculty', (app) => request(app).post(AR_REQ).send(ON_DUTY))],
    ['403 NOT_LINKED', call('desk', post(AR_REQ, ON_DUTY))],
    ['403 PASSWORD_CHANGE_REQUIRED', call('attendance', (app, _token, w) => post(AR_REQ, ON_DUTY)(app, tokens.attendance(w.people.attendance, 'pw')), {
      setup: (w) => { w.people.attendance.account.password_set_at = null; },
    })],
    ['409 REQUEST_CLOSED', async () => {
      const w = buildApp({ now: AT_SIX() });
      return post(AR_REQ, { ...ON_DUTY, day: '2026-09-30' })(w.app, tokens.portal(w.people.faculty));
    }],
    ['409 DUPLICATE_REQUEST', call('attendance', post(AR_REQ, ON_DUTY), { setup: withRequests })],
    ['409 LIMIT_REACHED', call('faculty', post(AR_REQ, A_FIX), {
      prepare: (w) => { w.db.tables.hr_ess_request_limits.find((l) => l.type === 'fix_a_day').limit_count = 0; },
    })],
    ['413 PAYLOAD_TOO_LARGE', call('faculty', post(AR_REQ, { ...ON_DUTY, reason: 'x'.repeat(20 * 1024) }))],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await post(AR_REQ, ON_DUTY)(app, tokens.portal(people.faculty));
      return post(AR_REQ, { ...ON_DUTY, day: '2026-10-16' })(app, tokens.portal(people.faculty));
    }],
    ['503 MODULE_NOT_INSTALLED', call('faculty', post(AR_REQ, ON_DUTY), { prepare: drop('hr_ess_attendance_requests') })],
    ['503 UNAVAILABLE', call('faculty', post(AR_REQ, ON_DUTY), { prepare: fails('hr_ess_request_limits') })],
    ['503 MODULE_DISABLED', call('faculty', post(AR_REQ, ON_DUTY), { env: { ESS_ENABLED: 'false' } })],
  ],
  'GET /api/ess/attendance-requests': [
    ['200, mine', call('attendance', get(AR_REQ), { setup: withRequests })],
    ['401, no token', call('attendance', (app) => request(app).get(AR_REQ))],
    ['403 NOT_LINKED', call('desk', get(AR_REQ))],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await get(AR_REQ)(app, tokens.portal(people.faculty));
      return get(AR_REQ)(app, tokens.portal(people.faculty));
    }],
    ['503 MODULE_NOT_INSTALLED', call('attendance', get(AR_REQ), { prepare: drop('hr_ess_attendance_requests') })],
  ],
  'POST /api/ess/attendance-requests/{id}/withdraw': [
    ['200, mine and pending', call('attendance', post(`${AR_REQ}/${AID(1)}/withdraw`, undefined), { setup: withRequests })],
    ['400 VALIDATION_FAILED', call('attendance', post(`${AR_REQ}/42/withdraw`, undefined), { setup: withRequests })],
    ['401, no token', call('attendance', (app) => request(app).post(`${AR_REQ}/${AID(1)}/withdraw`))],
    ['403 NOT_LINKED', call('desk', post(`${AR_REQ}/${AID(1)}/withdraw`, undefined))],
    ['404 NOT_FOUND, somebody else\'s', call('attendance', post(`${AR_REQ}/${LID(2)}/withdraw`, undefined), { setup: withRequests })],
    ['409 REQUEST_NOT_PENDING', call('attendance', post(`${AR_REQ}/${AID(1)}/withdraw`, undefined), {
      setup: (w) => { w.tables.hr_ess_attendance_requests = [requestRow('attendance', w.people.attendance.employee.id, AID(1), { status: 'withdrawn' })]; },
    })],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await post(`${AR_REQ}/${AID(1)}/withdraw`, undefined)(app, tokens.portal(people.faculty));
      return post(`${AR_REQ}/${AID(1)}/withdraw`, undefined)(app, tokens.portal(people.faculty));
    }],
    ['503 MODULE_NOT_INSTALLED', call('attendance', post(`${AR_REQ}/${AID(1)}/withdraw`, undefined), { prepare: drop('hr_ess_attendance_requests') })],
  ],
  'POST /api/ess/leave-requests': [
    ['201, a CL as a portal login', call('faculty', post(LR_REQ, { type: 'cl', day: '2026-10-20', reason: 'Family function at home.' }))],
    ['400 VALIDATION_FAILED, a type it does not take', call('faculty', post(LR_REQ, { type: 'sick', day: '2026-10-20', reason: 'Down with a fever.' }))],
    ['400 VALIDATION_FAILED, a short reason', call('faculty', post(LR_REQ, { type: 'cl', day: '2026-10-20', reason: 'home' }))],
    ['401, no token', call('faculty', (app) => request(app).post(LR_REQ).send({ type: 'cl', day: '2026-10-20', reason: 'Family function at home.' }))],
    ['403 PASSWORD_CHANGE_REQUIRED', call('attendance', (app, _token, w) => post(LR_REQ, { type: 'cl', day: '2026-10-20', reason: 'Family function at home.' })(app, tokens.attendance(w.people.attendance, 'pw')), {
      setup: (w) => { w.people.attendance.account.password_set_at = null; },
    })],
    ['409 DUPLICATE_REQUEST', call('faculty', post(LR_REQ, { type: 'cl', day: '2026-10-15', reason: 'Family function at home.' }), { setup: withRequests })],
    ['409 LIMIT_REACHED', call('faculty', post(LR_REQ, { type: 'cl', day: '2026-10-20', reason: 'Family function at home.' }), {
      prepare: (w) => { w.db.tables.hr_staff_attendance.push(contractDayRow(w.people.faculty.employee.id, '2026-10-10', { status: 'leave', leave_type: 'cl', source: 'override' })); },
    })],
    ['409 REQUEST_CLOSED', async () => {
      const w = buildApp({ now: AT_SIX() });
      return post(LR_REQ, { type: 'cl', day: '2026-09-30', reason: 'Family function at home.' })(w.app, tokens.portal(w.people.faculty));
    }],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await post(LR_REQ, { type: 'lwp', day: '2026-10-20', reason: 'Unpaid days at home.' })(app, tokens.portal(people.faculty));
      return post(LR_REQ, { type: 'lwp', day: '2026-10-21', reason: 'Unpaid days at home.' })(app, tokens.portal(people.faculty));
    }],
    ['503 MODULE_NOT_INSTALLED', call('faculty', post(LR_REQ, { type: 'cl', day: '2026-10-20', reason: 'Family function at home.' }), { prepare: drop('hr_ess_leave_requests') })],
    ['503 UNAVAILABLE', call('faculty', post(LR_REQ, { type: 'cl', day: '2026-10-20', reason: 'Family function at home.' }), { prepare: fails('hr_ess_request_limits') })],
    ['503 MODULE_DISABLED', call('faculty', post(LR_REQ, { type: 'cl', day: '2026-10-20', reason: 'Family function at home.' }), { env: { ESS_ENABLED: 'false' } })],
  ],
  'GET /api/ess/leave-requests': [
    ['200, mine', call('faculty', get(LR_REQ), { setup: withRequests })],
    ['401, no token', call('faculty', (app) => request(app).get(LR_REQ))],
    ['403 NOT_LINKED', call('desk', get(LR_REQ))],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await get(LR_REQ)(app, tokens.portal(people.faculty));
      return get(LR_REQ)(app, tokens.portal(people.faculty));
    }],
    ['503 MODULE_NOT_INSTALLED', call('faculty', get(LR_REQ), { prepare: drop('hr_ess_leave_requests') })],
  ],
  'POST /api/ess/leave-requests/{id}/withdraw': [
    ['200, mine and pending', call('faculty', post(`${LR_REQ}/${LID(2)}/withdraw`, undefined), { setup: withRequests })],
    ['400 VALIDATION_FAILED', call('faculty', post(`${LR_REQ}/42/withdraw`, undefined), { setup: withRequests })],
    ['401, no token', call('faculty', (app) => request(app).post(`${LR_REQ}/${LID(2)}/withdraw`))],
    ['403 NOT_LINKED', call('desk', post(`${LR_REQ}/${LID(2)}/withdraw`, undefined))],
    ['404 NOT_FOUND, somebody else\'s', call('faculty', post(`${LR_REQ}/${AID(1)}/withdraw`, undefined), { setup: withRequests })],
    ['409 REQUEST_NOT_PENDING', call('faculty', post(`${LR_REQ}/${LID(2)}/withdraw`, undefined), {
      setup: (w) => { w.tables.hr_ess_leave_requests = [requestRow('leave', w.people.faculty.employee.id, LID(2), { status: 'approved', decided_by_name: 'Test HR Manager', decided_at: '2026-10-15T05:00:00+00:00' })]; },
    })],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await post(`${LR_REQ}/${LID(2)}/withdraw`, undefined)(app, tokens.portal(people.faculty));
      return post(`${LR_REQ}/${LID(2)}/withdraw`, undefined)(app, tokens.portal(people.faculty));
    }],
    ['503 MODULE_NOT_INSTALLED', call('faculty', post(`${LR_REQ}/${LID(2)}/withdraw`, undefined), { prepare: drop('hr_ess_leave_requests') })],
  ],
  'GET /api/ess/leave/balances': [
    ['200, this month', call('attendance', get(BALANCES), { setup: withRequests })],
    ['400 DAY_OUT_OF_RANGE', call('attendance', get(`${BALANCES}?month=2026-08`))],
    ['400 VALIDATION_FAILED', call('attendance', get(`${BALANCES}?month=26-10`))],
    ['401, no token', call('attendance', (app) => request(app).get(BALANCES))],
    ['403 NOT_LINKED', call('desk', get(BALANCES))],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await get(BALANCES)(app, tokens.portal(people.faculty));
      return get(BALANCES)(app, tokens.portal(people.faculty));
    }],
    ['503 MODULE_NOT_INSTALLED', call('attendance', get(BALANCES), { prepare: drop('hr_ess_request_limits') })],
  ],
  'GET /api/ess/approvals': [
    ['200, a manager', call('admin_manager', get(INBOX), { setup: withRequests })],
    ['400 VALIDATION_FAILED', call('hr', get(`${INBOX}?status=lost`))],
    ['401, no token', call('hr', (app) => request(app).get(INBOX))],
    ['403 NOT_AN_APPROVER', call('hr_executive', get(`${INBOX}?status=all`))],
    ['403 NOT_LINKED', call('desk', get(INBOX))],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await get(INBOX)(app, tokens.portal(people.hr));
      return get(INBOX)(app, tokens.portal(people.hr));
    }],
    ['503 MODULE_NOT_INSTALLED', call('admin_manager', get(INBOX), { prepare: drop('hr_ess_attendance_requests') })],
  ],
  'POST /api/ess/approvals/{family}/{id}/decide': [
    ['200, a manager approves an on-duty day', call('admin_manager', post(`${INBOX}/attendance/${AID(1)}/decide`, { decision: 'approve' }), { setup: withRequests })],
    ['400 VALIDATION_FAILED, no decision', call('admin_manager', post(`${INBOX}/attendance/${AID(1)}/decide`, {}), { setup: withRequests })],
    ['400 VALIDATION_FAILED, a bad id', call('admin_manager', post(`${INBOX}/attendance/nope/decide`, { decision: 'approve' }), { setup: withRequests })],
    ['401, no token', call('admin_manager', (app) => request(app).post(`${INBOX}/attendance/${AID(1)}/decide`).send({ decision: 'approve' }))],
    ['403 NOT_AN_APPROVER', call('attendance', post(`${INBOX}/leave/${LID(2)}/decide`, { decision: 'approve' }), { setup: withRequests })],
    ['404 NOT_FOUND, no such request', call('hr', post(`${INBOX}/attendance/${AID(9)}/decide`, { decision: 'approve' }), { setup: withRequests })],
    ['404 NOT_FOUND, no such family', call('hr', post(`${INBOX}/wall/${AID(1)}/decide`, { decision: 'approve' }))],
    ['409 ALREADY_DECIDED', async () => {
      const w = buildApp({ setup: withRequests });
      await post(`${INBOX}/attendance/${AID(1)}/decide`, { decision: 'approve' })(w.app, tokens.portal(w.people.admin_manager));
      return post(`${INBOX}/attendance/${AID(1)}/decide`, { decision: 'reject', note: 'Changed my mind.' })(w.app, tokens.portal(w.people.admin_manager));
    }],
    ['409 CL_LIMIT', call('hr', post(`${INBOX}/leave/${LID(2)}/decide`, { decision: 'approve' }), {
      setup: withRequests,
      prepare: (w) => { w.db.tables.hr_staff_attendance.push(contractDayRow(w.people.faculty.employee.id, '2026-10-10', { status: 'leave', leave_type: 'cl', source: 'override' })); },
    })],
    ['409 NOT_LATE', call('admin_manager', post(`${INBOX}/attendance/${AID(4)}/decide`, { decision: 'approve' }), {
      setup: (w) => { w.tables.hr_ess_attendance_requests = [requestRow('attendance', w.people.attendance.employee.id, AID(4), { type: 'excuse_late', place: null, day: '2026-10-13' })]; },
    })],
    ['409 TIMES_INCOMPLETE', call('admin_manager', post(`${INBOX}/attendance/${AID(5)}/decide`, { decision: 'approve' }), {
      setup: (w) => { w.tables.hr_ess_attendance_requests = [requestRow('attendance', w.people.attendance.employee.id, AID(5), { type: 'fix_a_day', place: null, day: '2026-10-13', fix_in: '09:00' })]; },
    })],
    ['409 DAY_LOCKED', call('admin_manager', post(`${INBOX}/attendance/${AID(6)}/decide`, { decision: 'approve' }), {
      setup: (w) => {
        w.tables.hr_staff_attendance.push(contractDayRow(w.people.attendance.employee.id, '2026-10-13', { status: 'week_off' }));
        w.tables.hr_ess_attendance_requests = [requestRow('attendance', w.people.attendance.employee.id, AID(6), { type: 'fix_a_day', place: null, day: '2026-10-13', fix_out: '18:00' })];
      },
    })],
    ['409 REQUEST_CLOSED', async () => {
      const w = buildApp({ now: AT_SIX(), setup: (x) => { x.tables.hr_ess_leave_requests = [requestRow('leave', x.people.faculty.employee.id, LID(7), { type: 'lwp', day: '2026-09-30' })]; } });
      return post(`${INBOX}/leave/${LID(7)}/decide`, { decision: 'approve' })(w.app, tokens.portal(w.people.hr));
    }],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ setup: withRequests, limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await post(`${INBOX}/attendance/${AID(1)}/decide`, { decision: 'approve' })(app, tokens.portal(people.admin_manager));
      return post(`${INBOX}/attendance/${AID(1)}/decide`, { decision: 'approve' })(app, tokens.portal(people.admin_manager));
    }],
    ['503 MODULE_NOT_INSTALLED', call('hr', post(`${INBOX}/attendance/${AID(1)}/decide`, { decision: 'approve' }), { setup: withRequests, prepare: drop('hr_ess_attendance_requests') })],
  ],
  'POST /api/ess/approvals/{family}/{id}/archive': [
    ['204, mine to clear', call('admin_manager', post(`${INBOX}/attendance/${AID(1)}/archive`, undefined), { setup: withRequests })],
    ['400 VALIDATION_FAILED', call('admin_manager', post(`${INBOX}/attendance/42/archive`, undefined), { setup: withRequests })],
    ['401, no token', call('admin_manager', (app) => request(app).post(`${INBOX}/attendance/${AID(1)}/archive`))],
    ['403 NOT_AN_APPROVER', call('faculty', post(`${INBOX}/attendance/${AID(1)}/archive`, undefined), { setup: withRequests })],
    ['404 NOT_FOUND', call('hr', post(`${INBOX}/attendance/${AID(9)}/archive`, undefined), { setup: withRequests })],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ setup: withRequests, limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await post(`${INBOX}/attendance/${AID(1)}/archive`, undefined)(app, tokens.portal(people.admin_manager));
      return post(`${INBOX}/attendance/${AID(1)}/archive`, undefined)(app, tokens.portal(people.admin_manager));
    }],
    ['503 MODULE_NOT_INSTALLED', call('admin_manager', post(`${INBOX}/attendance/${AID(1)}/archive`, undefined), { setup: withRequests, prepare: drop('hr_ess_attendance_requests') })],
  ],
  'POST /api/ess/hr/attendance-requests/{id}/cancel': [
    ['200, an approved one comes back', call('hr', post(`/api/ess/hr/attendance-requests/${AID(3)}/cancel`, { reason: 'Recorded by mistake.' }), { setup: withApproved })],
    ['400 VALIDATION_FAILED, a short reason', call('hr', post(`/api/ess/hr/attendance-requests/${AID(3)}/cancel`, { reason: 'x' }), { setup: withApproved })],
    ['401, no token', call('hr', (app) => request(app).post(`/api/ess/hr/attendance-requests/${AID(3)}/cancel`).send({ reason: 'Recorded by mistake.' }))],
    ['403 ATTENDANCE_OVERRIDE_DENIED, an HR Executive', call('hr_executive', post(`/api/ess/hr/attendance-requests/${AID(3)}/cancel`, { reason: 'Let me, too.' }), { setup: withApproved })],
    ['404 NOT_FOUND', call('hr', post(`/api/ess/hr/attendance-requests/${AID(9)}/cancel`, { reason: 'Nothing there.' }), { setup: withApproved })],
    ['409 CANNOT_CANCEL, still pending', call('hr', post(`/api/ess/hr/attendance-requests/${AID(1)}/cancel`, { reason: 'Not yet decided.' }), { setup: withRequests })],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ setup: withApproved, limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await post(`/api/ess/hr/attendance-requests/${AID(3)}/cancel`, { reason: 'Recorded by mistake.' })(app, tokens.portal(people.hr));
      return post(`/api/ess/hr/attendance-requests/${AID(3)}/cancel`, { reason: 'Recorded by mistake.' })(app, tokens.portal(people.hr));
    }],
    ['503 MODULE_NOT_INSTALLED', call('hr', post(`/api/ess/hr/attendance-requests/${AID(3)}/cancel`, { reason: 'Recorded by mistake.' }), { setup: withApproved, prepare: drop('hr_ess_attendance_requests') })],
  ],
  'POST /api/ess/hr/leave-requests/{id}/cancel': [
    ['200, an approved one comes back', call('hr', post(`/api/ess/hr/leave-requests/${LID(4)}/cancel`, { reason: 'The dates changed.' }), {
      setup: (w) => { w.tables.hr_ess_leave_requests = [requestRow('leave', w.people.faculty.employee.id, LID(4), { status: 'approved', decided_by_name: 'Test HR Manager', decided_at: '2026-10-16T06:00:00+00:00' })]; },
    })],
    ['400 VALIDATION_FAILED, a short reason', call('hr', post(`/api/ess/hr/leave-requests/${LID(4)}/cancel`, { reason: 'x' }), {
      setup: (w) => { w.tables.hr_ess_leave_requests = [requestRow('leave', w.people.faculty.employee.id, LID(4), { status: 'approved', decided_by_name: 'Test HR Manager', decided_at: '2026-10-16T06:00:00+00:00' })]; },
    })],
    ['401, no token', call('hr', (app) => request(app).post(`/api/ess/hr/leave-requests/${LID(4)}/cancel`).send({ reason: 'The dates changed.' }))],
    ['403 ATTENDANCE_OVERRIDE_DENIED', call('hod', post(`/api/ess/hr/leave-requests/${LID(2)}/cancel`, { reason: 'The dates changed.' }), { setup: withRequests })],
    ['404 NOT_FOUND', call('hr', post(`/api/ess/hr/leave-requests/${LID(9)}/cancel`, { reason: 'Nothing there.' }), { setup: withRequests })],
    ['409 CANNOT_CANCEL, still pending', call('hr', post(`/api/ess/hr/leave-requests/${LID(2)}/cancel`, { reason: 'Not yet decided.' }), { setup: withRequests })],
    ['429 RATE_LIMITED', async () => {
      const setup = (w) => { w.tables.hr_ess_leave_requests = [requestRow('leave', w.people.faculty.employee.id, LID(4), { status: 'approved', decided_by_name: 'Test HR Manager', decided_at: '2026-10-16T06:00:00+00:00' })]; };
      const { app, people } = buildApp({ setup, limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await post(`/api/ess/hr/leave-requests/${LID(4)}/cancel`, { reason: 'The dates changed.' })(app, tokens.portal(people.hr));
      return post(`/api/ess/hr/leave-requests/${LID(4)}/cancel`, { reason: 'The dates changed.' })(app, tokens.portal(people.hr));
    }],
    ['503 MODULE_NOT_INSTALLED', call('hr', post(`/api/ess/hr/leave-requests/${LID(4)}/cancel`, { reason: 'The dates changed.' }), { setup: withRequests, prepare: drop('hr_ess_leave_requests') })],
  ],
  'GET /api/ess/hr/request-limits': [
    ['200, the seeded limits', call('hr', get(LIMITS))],
    ['401, no token', call('hr', (app) => request(app).get(LIMITS))],
    ['403 ATTENDANCE_OVERRIDE_DENIED', call('hr_executive', get(LIMITS))],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await get(LIMITS)(app, tokens.portal(people.hr));
      return get(LIMITS)(app, tokens.portal(people.hr));
    }],
    ['503 MODULE_NOT_INSTALLED', call('hr', get(LIMITS), { prepare: drop('hr_ess_request_limits') })],
  ],
  'PUT /api/ess/hr/request-limits/{type}': [
    ['200, a count type', call('hr', put(`${LIMITS}/fix_a_day`, { limit_count: 5 }))],
    ['200, cleared to no limit', call('super_admin', put(`${LIMITS}/leave_lwp`, { limit_count: null }))],
    ['400 VALIDATION_FAILED, not a type', call('hr', put(`${LIMITS}/tea_break`, { limit_count: 2 }))],
    ['400 VALIDATION_FAILED, a negative number', call('hr', put(`${LIMITS}/fix_a_day`, { limit_count: -1 }))],
    ['401, no token', call('hr', (app) => request(app).put(`${LIMITS}/fix_a_day`).send({ limit_count: 5 }))],
    ['403 ATTENDANCE_OVERRIDE_DENIED', call('admin_manager', put(`${LIMITS}/fix_a_day`, { limit_count: 5 }))],
    ['404 NOT_FOUND, a row somebody deleted', call('hr', put(`${LIMITS}/fix_a_day`, { limit_count: 5 }), {
      prepare: (w) => { w.db.tables.hr_ess_request_limits = w.db.tables.hr_ess_request_limits.filter((l) => l.type !== 'fix_a_day'); },
    })],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await put(`${LIMITS}/fix_a_day`, { limit_count: 5 })(app, tokens.portal(people.hr));
      return put(`${LIMITS}/fix_a_day`, { limit_count: 5 })(app, tokens.portal(people.hr));
    }],
    ['503 MODULE_NOT_INSTALLED', call('hr', put(`${LIMITS}/fix_a_day`, { limit_count: 5 }), { prepare: drop('hr_ess_request_limits') })],
  ],
};

/* ── Wave 4 (Phase 1D): push devices, notifications and their settings ── */

const PUSH = '/api/ess/push-devices';
const NOTIF = '/api/ess/notifications';
const NOTIF_SETTINGS = '/api/ess/notifications/settings';
const PUSH_TOKEN = `test-token-${'a'.repeat(40)}`;
const NID4 = (n) => `81000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

const notificationSeed = (employeeId, n, change = {}) => ({
  id: NID4(n), employee_id: employeeId, category: 'decisions', title: 'Request approved',
  body: 'Your request for on duty on 15 Oct was approved.', data: { request_id: '7a000000-0000-4000-8000-000000000001' },
  read_at: null, pushed_at: null, push_mode: null, push_attempts: 0, push_error: null,
  created_at: '2026-10-16T05:00:00+00:00', ...change,
});

const withNotification = (w) => {
  w.tables.hr_ess_notifications = [notificationSeed(w.people.attendance.employee.id, 1)];
};

const WAVE_4 = {
  'POST /api/ess/push-devices': [
    ['201, an attendance session', call('attendance', post(PUSH, { token: PUSH_TOKEN, device_label: 'Pixel 8' }))],
    ['400 VALIDATION_FAILED, a token too short', call('attendance', post(PUSH, { token: 'short' }))],
    ['401, no token', call('attendance', (app) => request(app).post(PUSH).send({ token: PUSH_TOKEN }))],
    ['403 PASSWORD_CHANGE_REQUIRED', call('attendance', (app, _token, w) => post(PUSH, { token: PUSH_TOKEN })(app, tokens.attendance(w.people.attendance, 'pw')), {
      setup: (w) => { w.people.attendance.account.password_set_at = null; },
    })],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await post(PUSH, { token: PUSH_TOKEN })(app, tokens.attendance(people.attendance));
      return post(PUSH, { token: `${PUSH_TOKEN}b` })(app, tokens.attendance(people.attendance));
    }],
    ['503 MODULE_NOT_INSTALLED', call('attendance', post(PUSH, { token: PUSH_TOKEN }), { prepare: drop('hr_ess_push_devices') })],
  ],
  'DELETE /api/ess/push-devices/{id}': [
    ['204, mine', async () => {
      const w = buildApp();
      const token = tokens.attendance(w.people.attendance);
      const registered = await post(PUSH, { token: PUSH_TOKEN })(w.app, token);
      return request(w.app).delete(`${PUSH}/${registered.body.device.id}`).set(bearer(token));
    }],
    ['400 VALIDATION_FAILED', call('attendance', (app, token) => request(app).delete(`${PUSH}/42`).set(bearer(token)))],
    ['401, no token', call('attendance', (app) => request(app).delete(`${PUSH}/83000000-0000-4000-8000-000000000001`))],
    ['403 NOT_LINKED', call('desk', (app, token) => request(app).delete(`${PUSH}/83000000-0000-4000-8000-000000000001`).set(bearer(token)))],
    ['404 NOT_FOUND', call('attendance', (app, token) => request(app).delete(`${PUSH}/83000000-0000-4000-8000-000000000001`).set(bearer(token)))],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await request(app).delete(`${PUSH}/83000000-0000-4000-8000-000000000001`).set(bearer(tokens.attendance(people.attendance)));
      return request(app).delete(`${PUSH}/83000000-0000-4000-8000-000000000001`).set(bearer(tokens.attendance(people.attendance)));
    }],
    ['503 MODULE_NOT_INSTALLED', call('attendance', (app, token) => request(app).delete(`${PUSH}/83000000-0000-4000-8000-000000000001`).set(bearer(token)), { prepare: drop('hr_ess_push_devices') })],
  ],
  'GET /api/ess/notifications': [
    ['200, mine', call('attendance', get(NOTIF), { setup: withNotification })],
    ['401, no token', call('attendance', (app) => request(app).get(NOTIF))],
    ['403 NOT_LINKED', call('desk', get(NOTIF))],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await get(NOTIF)(app, tokens.attendance(people.attendance));
      return get(NOTIF)(app, tokens.attendance(people.attendance));
    }],
    ['503 MODULE_NOT_INSTALLED', call('attendance', get(NOTIF), { prepare: drop('hr_ess_notifications') })],
  ],
  'POST /api/ess/notifications/{id}/read': [
    ['204, mine', call('attendance', (app, token) => request(app).post(`${NOTIF}/${NID4(1)}/read`).set(bearer(token)), { setup: withNotification })],
    ['204, already read', call('attendance', (app, token) => request(app).post(`${NOTIF}/${NID4(1)}/read`).set(bearer(token)), {
      setup: (w) => { w.tables.hr_ess_notifications = [notificationSeed(w.people.attendance.employee.id, 1, { read_at: '2026-10-16T06:00:00+00:00' })]; },
    })],
    ['400 VALIDATION_FAILED', call('attendance', (app, token) => request(app).post(`${NOTIF}/nope/read`).set(bearer(token)))],
    ['401, no token', call('attendance', (app) => request(app).post(`${NOTIF}/${NID4(1)}/read`))],
    ['403 NOT_LINKED', call('desk', (app, token) => request(app).post(`${NOTIF}/${NID4(1)}/read`).set(bearer(token)))],
    ['404 NOT_FOUND, somebody else\'s', call('attendance', (app, token) => request(app).post(`${NOTIF}/${NID4(2)}/read`).set(bearer(token)), {
      setup: (w) => { w.tables.hr_ess_notifications = [notificationSeed(w.people.faculty.employee.id, 2)]; },
    })],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ setup: withNotification, limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await request(app).post(`${NOTIF}/${NID4(1)}/read`).set(bearer(tokens.attendance(people.attendance)));
      return request(app).post(`${NOTIF}/${NID4(1)}/read`).set(bearer(tokens.attendance(people.attendance)));
    }],
    ['503 MODULE_NOT_INSTALLED', call('attendance', (app, token) => request(app).post(`${NOTIF}/${NID4(1)}/read`).set(bearer(token)), { setup: withNotification, prepare: drop('hr_ess_notifications') })],
  ],
  'POST /api/ess/notifications/read-all': [
    ['200, two unread', call('attendance', (app, token) => request(app).post(`${NOTIF}/read-all`).set(bearer(token)), { setup: withNotification })],
    ['401, no token', call('attendance', (app) => request(app).post(`${NOTIF}/read-all`))],
    ['403 NOT_LINKED', call('desk', post(`${NOTIF}/read-all`, undefined))],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await request(app).post(`${NOTIF}/read-all`).set(bearer(tokens.attendance(people.attendance)));
      return request(app).post(`${NOTIF}/read-all`).set(bearer(tokens.attendance(people.attendance)));
    }],
    ['503 MODULE_NOT_INSTALLED', call('attendance', post(`${NOTIF}/read-all`, undefined), { prepare: drop('hr_ess_notifications') })],
  ],
  'GET /api/ess/notifications/settings': [
    ['200, the defaults', call('attendance', get(NOTIF_SETTINGS))],
    ['401, no token', call('attendance', (app) => request(app).get(NOTIF_SETTINGS))],
    ['403 NOT_LINKED', call('desk', get(NOTIF_SETTINGS))],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await get(NOTIF_SETTINGS)(app, tokens.attendance(people.attendance));
      return get(NOTIF_SETTINGS)(app, tokens.attendance(people.attendance));
    }],
    ['503 MODULE_NOT_INSTALLED', call('attendance', get(NOTIF_SETTINGS), { prepare: drop('hr_ess_notification_settings') })],
  ],
  'PUT /api/ess/notifications/settings': [
    ['200, one turned off', call('attendance', put(NOTIF_SETTINGS, { disabled_categories: ['approvals'] }))],
    ['400 VALIDATION_FAILED, a category it does not know', call('attendance', put(NOTIF_SETTINGS, { disabled_categories: ['wall'] }))],
    ['401, no token', call('attendance', (app) => request(app).put(NOTIF_SETTINGS).send({ disabled_categories: [] }))],
    ['403 NOT_LINKED', call('desk', put(NOTIF_SETTINGS, { disabled_categories: [] }))],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await put(NOTIF_SETTINGS, { disabled_categories: [] })(app, tokens.attendance(people.attendance));
      return put(NOTIF_SETTINGS, { disabled_categories: [] })(app, tokens.attendance(people.attendance));
    }],
    ['503 MODULE_NOT_INSTALLED', call('attendance', put(NOTIF_SETTINGS, { disabled_categories: [] }), { prepare: drop('hr_ess_notification_settings') })],
  ],
};

/* ── Wave 5 (Phase 1E): profile, org, directory and team ── */

const OFF = '/api/ess/team/off-this-week';
const TODAY_TEAM = '/api/ess/team/today';
const PNG_B64 = Buffer.from('89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d4944415478da63fcffff3f030005fe02fea72d1e4b0000000049454e44ae426082', 'hex').toString('base64');

const teamDaySeed = (w, employeeId, day, change = {}) => {
  w.tables.hr_staff_attendance.push({
    id: `86000000-0000-4000-8000-${String(day.charCodeAt(9) * 7).padStart(12, '0')}`, employee_id: employeeId,
    branch_id: null, day, status: 'present', leave_type: null, note: null, marked_by: null, marked_by_name: 'Test (self punch)',
    marked_at: `${day}T04:00:00+00:00`, updated_at: `${day}T12:00:00+00:00`, source: 'self_punch',
    first_in: `${day}T04:20:00+00:00`, last_out: `${day}T12:40:00+00:00`, worked_minutes: 500, shift_id: null,
    shift_start: null, shift_end: null, grace_minutes: null, late_minutes: null, early_exit_minutes: null,
    late_count: null, late_half_day: false, late_excused: false, late_excused_by_name: null, late_excused_reason: null,
    late_excused_at: null, ...change,
  });
};

const WAVE_5 = {
  'GET /api/ess/me/profile': [
    ['200, an attendance session', call('attendance', get('/api/ess/me/profile'))],
    ['401, no token', call('attendance', (app) => request(app).get('/api/ess/me/profile'))],
    ['403 NOT_ACTIVE', call('faculty', get('/api/ess/me/profile'), { setup: (w) => { w.people.faculty.employee.employment_status = 'exited'; } })],
    ['403 NOT_LINKED', call('desk', get('/api/ess/me/profile'))],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await get('/api/ess/me/profile')(app, tokens.attendance(people.attendance));
      return get('/api/ess/me/profile')(app, tokens.attendance(people.attendance));
    }],
    ['503 MODULE_NOT_INSTALLED', call('faculty', get('/api/ess/me/profile'), { prepare: drop('hr_activity_events') })],
  ],
  'PUT /api/ess/me/photo': [
    ['200, mine', call('attendance', put('/api/ess/me/photo', { photo_base64: PNG_B64, content_type: 'image/png' }))],
    ['400 VALIDATION_FAILED, not an image type', call('attendance', put('/api/ess/me/photo', { photo_base64: PNG_B64, content_type: 'application/pdf' }))],
    ['400 INVALID_JSON', call('attendance', (app, token) => request(app).put('/api/ess/me/photo').set(bearer(token)).set('Content-Type', 'application/json').send('{"photo_base64": '))],
    ['401, no token', call('attendance', (app) => request(app).put('/api/ess/me/photo').send({ photo_base64: PNG_B64, content_type: 'image/png' }))],
    ['403 NOT_LINKED', call('desk', put('/api/ess/me/photo', { photo_base64: PNG_B64, content_type: 'image/png' }))],
    ['403 PASSWORD_CHANGE_REQUIRED', call('attendance', (app, _token, w) => put('/api/ess/me/photo', { photo_base64: PNG_B64, content_type: 'image/png' })(app, tokens.attendance(w.people.attendance, 'pw')), {
      setup: (w) => { w.people.attendance.account.password_set_at = null; },
    })],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      const body = { photo_base64: PNG_B64, content_type: 'image/png' };
      await put('/api/ess/me/photo', body)(app, tokens.attendance(people.attendance));
      return put('/api/ess/me/photo', body)(app, tokens.attendance(people.attendance));
    }],
    ['503 MODULE_NOT_INSTALLED', call('faculty', put('/api/ess/me/photo', { photo_base64: PNG_B64, content_type: 'image/png' }), {
      prepare: (w) => w.db.dropColumn('hr_employees', 'photo_updated_at'),
    })],
  ],
  'GET /api/ess/me/org': [
    ['200, a manager', call('admin_manager', get('/api/ess/me/org'))],
    ['200, a chain that reports to the CEO (not recorded)', call('faculty', get('/api/ess/me/org'), { setup: (w) => { w.people.hod.employee.manager_id = null; } })],
    ['401, no token', call('faculty', (app) => request(app).get('/api/ess/me/org'))],
    ['403 NOT_LINKED', call('desk', get('/api/ess/me/org'))],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await get('/api/ess/me/org')(app, tokens.portal(people.hr));
      return get('/api/ess/me/org')(app, tokens.portal(people.hr));
    }],
    ['503 MODULE_NOT_INSTALLED', call('faculty', get('/api/ess/me/org'), { prepare: drop('hr_employees') })],
  ],
  'GET /api/ess/directory': [
    ['200, a code search', call('attendance', get('/api/ess/directory?q=RVM-011'))],
    ['200, a branch filter', call('attendance', get(`/api/ess/directory?branch_id=${BRANCH_PUNE_ID}`))],
    ['400 VALIDATION_FAILED', call('attendance', get('/api/ess/directory?branch_id=1'))],
    ['401, no token', call('attendance', (app) => request(app).get('/api/ess/directory'))],
    ['403 NOT_LINKED', call('desk', get('/api/ess/directory'))],
    ['404 NOT_FOUND, a branch that does not exist', call('attendance', get(`/api/ess/directory?branch_id=${uuid('b', 9)}`))],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await get('/api/ess/directory')(app, tokens.attendance(people.attendance));
      return get('/api/ess/directory')(app, tokens.attendance(people.attendance));
    }],
    ['503 MODULE_NOT_INSTALLED', call('attendance', get('/api/ess/directory'), { prepare: drop('hr_departments') })],
  ],
  'GET /api/ess/team/today': [
    ['200, a manager', call('admin_manager', get(TODAY_TEAM), { setup: (w) => {
      teamDaySeed(w, w.people.attendance.employee.id, '2026-10-16', { last_out: null, late_minutes: 25 });
    } })],
    ['200, the HoO\'s branch', call('hoo', get(TODAY_TEAM))],
    ['200, nobody to show', call('faculty', get(TODAY_TEAM))],
    ['400 VALIDATION_FAILED', call('admin_manager', get(`${TODAY_TEAM}?filter=wfh`))],
    ['401, no token', call('admin_manager', (app) => request(app).get(TODAY_TEAM))],
    ['403 NOT_LINKED', call('desk', get(TODAY_TEAM))],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await get(TODAY_TEAM)(app, tokens.portal(people.hr));
      return get(TODAY_TEAM)(app, tokens.portal(people.hr));
    }],
    ['503 MODULE_NOT_INSTALLED', call('admin_manager', get(TODAY_TEAM), { prepare: drop('hr_staff_attendance') })],
  ],
  'GET /api/ess/team/off-this-week': [
    ['200, a manager', call('admin_manager', get(OFF), { setup: (w) => {
      teamDaySeed(w, w.people.attendance.employee.id, '2026-10-15', { status: 'leave', source: 'override', first_in: null, last_out: null });
    } })],
    ['200, the peers under the same manager', call('hr', get(OFF), { setup: (w) => {
      teamDaySeed(w, w.people.hoo.employee.id, '2026-10-15', { status: 'leave', source: 'override', first_in: null, last_out: null });
    } })],
    ['200, nobody', call('faculty', get(OFF))],
    ['401, no token', call('faculty', (app) => request(app).get(OFF))],
    ['403 NOT_LINKED', call('desk', get(OFF))],
    ['429 RATE_LIMITED', async () => {
      const { app, people } = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      await get(OFF)(app, tokens.portal(people.hr));
      return get(OFF)(app, tokens.portal(people.hr));
    }],
    ['503 MODULE_NOT_INSTALLED', call('admin_manager', get(OFF), { prepare: drop('hr_staff_attendance') })],
  ],
};

describe('the scenario tables', () => {
  it('cover every route Wave 2 to Wave 11 added', () => {
    const wave1 = ['GET /api/ess/health', 'GET /api/ess/me', 'GET /api/ess/me/capabilities'];
    const served = C.essRoutes(buildApp().app).filter((route) => !wave1.includes(route));
    expect([...Object.keys(WAVE_2), ...Object.keys(WAVE_3), ...Object.keys(WAVE_4), ...Object.keys(WAVE_5), ...Object.keys(WAVE_6), ...Object.keys(WAVE_7), ...Object.keys(WAVE_8), ...Object.keys(WAVE_9), ...Object.keys(WAVE_10), ...Object.keys(WAVE_11)].sort()).toEqual(served);
  });

  it.each([...Object.entries(WAVE_2), ...Object.entries(WAVE_3), ...Object.entries(WAVE_4), ...Object.entries(WAVE_5), ...Object.entries(WAVE_6), ...Object.entries(WAVE_7), ...Object.entries(WAVE_8), ...Object.entries(WAVE_9), ...Object.entries(WAVE_10), ...Object.entries(WAVE_11)])('provoke every status %s documents', (route, scenarios) => {
    const [method, path] = route.split(' ');
    const documented = Object.keys(C.operation(method, path).operation.responses).filter((s) => s !== 'default');
    const provoked = new Set(scenarios.map(([label]) => label.slice(0, 3)));
    for (const status of documented) expect(provoked, `${route} ${status}`).toContain(status);
  });
});

describe.each([...Object.entries(WAVE_2), ...Object.entries(WAVE_3), ...Object.entries(WAVE_4), ...Object.entries(WAVE_5), ...Object.entries(WAVE_6), ...Object.entries(WAVE_7), ...Object.entries(WAVE_8), ...Object.entries(WAVE_9), ...Object.entries(WAVE_10), ...Object.entries(WAVE_11)])('%s', (route, scenarios) => {
  const [method, path] = route.split(' ');
  it.each(scenarios)('%s', async (label, provoke) => {
    quietErrors();
    const res = await provoke();
    // Each label starts with the status it provokes, so a scenario that drifts to another
    // documented status fails here rather than passing as a different reply.
    expect(res.status, JSON.stringify(res.body)).toBe(Number(label.slice(0, 3)));
    expectContract(C.operation(method, path), res);
  });
});

describe('what the contract promises the app', () => {
  it('uses the ESS\'s own words in every error example', () => {
    const sent = new Set(Object.values(MESSAGES));
    const notInstalled = /^Team RVM needs a database update that has not been applied yet \(it cannot read [a-z_]+\)\. Ask the tech team\.$/;
    for (const op of C.operations().filter((o) => o.owner === 'ess')) {
      for (const [status, ref] of Object.entries(op.operation.responses)) {
        if (status.startsWith('2')) continue;
        const media = C.deref(ref).content['application/json'];
        for (const [name, example] of Object.entries(media.examples || {})) {
          const { error, code } = C.deref(example).value;
          const known = code === 'MODULE_NOT_INSTALLED' ? notInstalled.test(error) : sent.has(error);
          expect(known, `${op.method} ${op.path} ${status} example ${name}: "${error}"`).toBe(true);
        }
      }
    }
  });

  it('lists the request types the policy table holds, and no others', () => {
    expect(C.contract.components.schemas.RequestType.enum).toEqual(REQUEST_TYPES.map((t) => t.type));
  });

  it('lists every staff role the account can hold, and no others', () => {
    const staff = Object.values(ROLES).filter((r) => r !== ROLES.STUDENT && r !== ROLES.BOT_READONLY);
    const documented = C.contract.components.schemas.Login.properties.role.enum;
    expect(documented.filter((r) => r !== null).sort()).toEqual(staff.sort());
    expect(documented).toContain(null);
  });

  it('lists the tabs and HR queues the capability rules hand out', () => {
    const schema = C.contract.components.schemas.Capabilities.properties;
    expect(schema.tabs.items.enum).toEqual(TABS);
    const hr = capabilitiesFor({ kind: 'portal', role: ROLES.HR, directReports: 0, pushEnabled: false });
    expect(schema.approvals.properties.hr_scope.items.enum).toEqual(hr.approvals.hr_scope);
  });
});

describe('any other address', () => {
  it('answers in the contract\'s Error shape', async () => {
    const { app } = buildApp();
    const validate = (res) => {
      // The contract's own catch-all for an ESS reply that is not an operation's: the Error schema.
      const problems = C.contractProblems({ method: 'GET', path: '(any)', operation: { responses: { default: { $ref: '#/components/responses/EssUnexpected' } } } }, res);
      expect(problems, `${res.status} ${JSON.stringify(res.body)}`).toEqual([]);
    };
    validate(await request(app).get('/api/ess/nothing-here'));
    validate(await request(app).options('/api/ess/me'));
    validate(await request(app).delete('/api/ess/me'));
  });
});
