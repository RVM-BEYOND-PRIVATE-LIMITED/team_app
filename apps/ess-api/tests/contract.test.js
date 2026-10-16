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

describe('the scenario tables', () => {
  it('cover every route Wave 2 added', () => {
    const wave1 = ['GET /api/ess/health', 'GET /api/ess/me', 'GET /api/ess/me/capabilities'];
    const served = C.essRoutes(buildApp().app).filter((route) => !wave1.includes(route));
    expect(Object.keys(WAVE_2).sort()).toEqual(served);
  });

  it.each(Object.entries(WAVE_2))('provoke every status %s documents', (route, scenarios) => {
    const [method, path] = route.split(' ');
    const documented = Object.keys(C.operation(method, path).operation.responses).filter((s) => s !== 'default');
    const provoked = new Set(scenarios.map(([label]) => label.slice(0, 3)));
    for (const status of documented) expect(provoked, `${route} ${status}`).toContain(status);
  });
});

describe.each(Object.entries(WAVE_2))('%s', (route, scenarios) => {
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
