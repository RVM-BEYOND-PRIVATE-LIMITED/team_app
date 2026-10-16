const request = require('supertest');
const { createApp } = require('../src/app');
const { loadConfig } = require('../src/config');
const { MESSAGES } = require('../src/lib/errors');
const { ROLES } = require('../src/policy/roles');
const { TABS, capabilitiesFor } = require('../src/policy/capabilities');
const { REQUEST_TYPES } = require('../src/policy/requestLimits');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { NOW, SIGNED_AT, TEST_ENV } = require('./helpers/constants');
const { PORTAL_PEOPLE, INSTALL_ID, OTHER_INSTALL_ID } = require('./helpers/fixtures');
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
 * Routes the ESS serves whose contract is still to be written: Wave 2's kept sign-ins (task A3)
 * and one-field sign-in (task A5). The contract is written in packages/contracts by whoever
 * integrates the wave; each route leaves this list in the change that documents it. The test
 * below fails while a documented route is still listed, and while a served route is in neither.
 * Their replies are held against the contract further down, as soon as it documents them.
 */
const AWAITING_CONTRACT = [
  'DELETE /api/ess/sessions/{id}',
  'GET /api/ess/sessions',
  'POST /api/ess/session',
  'POST /api/ess/session/refresh',
  'POST /api/ess/session/sign-out',
  'POST /api/ess/sign-in/resolve',
];

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
    ['401 signed_out', refreshAfter({}, (k) => H.signOut(k.app, { token: k.session.access_token }))],
    ['401 password_changed', refreshAfter({}, (k) => { accountOf(k).sessions_valid_from = NOW.toISOString(); })],
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
    ['503 MODULE_NOT_INSTALLED', async () => { const { app, db, people } = buildApp(); db.dropTable('hr_ess_sessions'); return H.listSessions(app, tokens.portal(people.hr)); }],
  ],
  'DELETE /api/ess/sessions/{id}': [
    ['204', async () => { const k = await kept(); return H.endSession(k.app, k.session.access_token, k.session.session.id); }],
    ['404 NOT_FOUND', async () => { const k = await kept(); return H.endSession(k.app, tokens.portal(k.people.hr), k.session.session.id); }],
    ['401', async () => { const { app } = buildApp(); return request(app).delete('/api/ess/sessions/5a000000-0000-4000-8000-000000000001'); }],
    ['403 NOT_AN_EMPLOYEE', async () => { const { app } = buildApp(); return H.endSession(app, tokens.student(), '5a000000-0000-4000-8000-000000000001'); }],
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

describe.each(Object.entries(WAVE_2))('%s', (route, scenarios) => {
  const [method, path] = route.split(' ');
  // Skipped until the contract documents the route (AWAITING_CONTRACT above), then held to it.
  describe.skipIf(!C.documents(method, path))('answers as documented', () => {
    it.each(scenarios)('%s', async (_label, provoke) => {
      quietErrors();
      expectContract(C.operation(method, path), await provoke());
    });
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
