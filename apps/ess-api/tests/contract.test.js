const request = require('supertest');
const { createApp } = require('../src/app');
const { loadConfig } = require('../src/config');
const { MESSAGES } = require('../src/lib/errors');
const { ROLES } = require('../src/policy/roles');
const { TABS, capabilitiesFor } = require('../src/policy/capabilities');
const { REQUEST_TYPES } = require('../src/policy/requestLimits');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { NOW, SIGNED_AT, TEST_ENV } = require('./helpers/constants');
const { PORTAL_PEOPLE } = require('./helpers/fixtures');
const C = require('./helpers/contract');

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
 * Wave 2 routes served before their contract entries exist (branch wave2/data, 16 Oct): this
 * slice was built with packages/contracts left alone, and the contract entries are written next.
 * Each one must be served and must not be documented yet, so the list can only shrink: once an
 * entry is in openapi.yaml, the second test below fails until the route is taken off this list,
 * and from then on every reply it gives is held against the contract like any other.
 */
const AWAITING_CONTRACT = [
  'GET /api/ess/attendance/day',
  'GET /api/ess/hr/data-requests',
  'GET /api/ess/hr/devices',
  'GET /api/ess/hr/employees/:id/personal',
  'GET /api/ess/hr/mock-location-reports',
  'GET /api/ess/me/data-requests',
  'GET /api/ess/me/personal',
  'PATCH /api/ess/hr/data-requests/:id',
  'POST /api/ess/attendance/mock-location',
  'POST /api/ess/hr/devices/reset',
  'POST /api/ess/me/data-requests',
  'PUT /api/ess/hr/employees/:id/personal',
  'PUT /api/ess/me/personal',
];

describe('the routes', () => {
  const documented = () => C.operations().filter((op) => op.owner === 'ess').map((op) => `${op.method} ${op.path}`).sort();

  it('are exactly the ESS operations in the contract, apart from the routes awaiting it', () => {
    const { app } = buildApp();
    const served = C.essRoutes(app);
    expect(served.length).toBeGreaterThan(0);
    expect(served.filter((r) => !AWAITING_CONTRACT.includes(r))).toEqual(documented());
  });

  it('await the contract only while they are served and not yet documented', () => {
    const served = C.essRoutes(buildApp().app);
    for (const route of AWAITING_CONTRACT) {
      expect(served, route).toContain(route);
      expect(documented(), `${route} is in the contract now: take it off AWAITING_CONTRACT`).not.toContain(route);
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
