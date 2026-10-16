const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { NOW, SIGNED_AT, TEST_JWT_SECRET, TEST_ENV } = require('./helpers/constants');
const { INSTALL_ID, OTHER_INSTALL_ID } = require('./helpers/fixtures');
const H = require('./helpers/sessions');
const G = require('./helpers/schedulerGuards');
const { refreshTokenHash } = require('../src/lib/accessTokens');
const { createApp } = require('../src/app');
const { loadConfig } = require('../src/config');
const { createSupabaseStore } = require('../src/lib/store');

/**
 * POST /api/ess/session/refresh (task A3): rotation, reuse, the 90 days, and every way a kept
 * sign-in ends, each checked the way employeeAuth checks a request.
 */

const { MINUTE, HOUR, DAY } = H;

const expectRefused = (res, reason) => {
  expect(res.status).toBe(401);
  expect(res.body).toEqual({ error: expect.any(String), code: 'NOT_AUTHENTICATED', reason });
  expect(res.headers['www-authenticate']).toBe('Bearer');
};

const expectRefusal = (res, status, code) => {
  expect(res.status).toBe(status);
  expect(res.body).toEqual({ error: expect.any(String), code });
};

const quiet = () => vi.spyOn(console, 'error').mockImplementation(() => {});

/** A kept sign-in, made at NOW with a token signed a minute before, on a clock the test moves. */
async function keptSignIn({ who = 'attendance', method = 'otp', setup, limits } = {}) {
  const clock = H.clockAt(NOW);
  const world = buildApp({ now: clock.now, setup, limits });
  const person = world.people[who];
  const token = who === 'attendance' ? tokens.attendance(person, method) : tokens.portal(person);
  const kept = await H.keep(world.app, token);
  expect(kept.status).toBe(201);
  return { ...world, clock, person, kept: kept.body };
}

describe('a refresh', () => {
  it('trades the refresh token for a new access and refresh token in the same sign-in, for 90 more days', async () => {
    const { app, clock, kept, db } = await keptSignIn();
    clock.advance(50 * MINUTE);
    const res = await H.refresh(app, kept.refresh_token);
    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      session: { id: kept.session.id, expires_at: new Date(clock.ms + 90 * DAY).toISOString() },
      access_token: expect.any(String),
      access_expires_at: new Date(clock.ms + HOUR).toISOString(),
      refresh_token: expect.stringMatching(/^[A-Za-z0-9_-]{43}$/),
      login: { kind: 'attendance', role: null, user_id: null },
    });
    expect(res.body.refresh_token).not.toBe(kept.refresh_token);
    expect(res.body.access_token).not.toBe(kept.access_token);
    expect(H.liveRows(db, kept.session.id)).toHaveLength(1);
  });

  it('retires the old row as rotated, pointing at the new one, which is the only live row', async () => {
    const { app, clock, kept, db } = await keptSignIn();
    clock.advance(HOUR);
    const res = await H.refresh(app, kept.refresh_token);
    const rows = H.familyRows(db, kept.session.id);
    expect(rows).toHaveLength(2);
    const [old, next] = rows;
    expect(old).toMatchObject({ revoked_reason: 'rotated', revoked_at: new Date(clock.ms).toISOString(), replaced_by: next.id, last_used_at: new Date(clock.ms).toISOString() });
    expect(next).toMatchObject({
      family_id: kept.session.id, refresh_hash: refreshTokenHash(res.body.refresh_token, TEST_JWT_SECRET), revoked_at: null,
      created_at: new Date(clock.ms).toISOString(), last_used_at: new Date(clock.ms).toISOString(),
      signed_in_at: old.signed_in_at, install_id: old.install_id, device_label: old.device_label, method: old.method,
    });
  });

  it('keeps the original sign-in as the iat of every access token, however many refreshes later', async () => {
    const { app, clock, kept } = await keptSignIn();
    let refreshToken = kept.refresh_token;
    for (let i = 0; i < 3; i++) {
      clock.advance(5 * DAY);
      const res = await H.refresh(app, refreshToken);
      expect(res.status).toBe(200);
      expect(H.claims(res.body.access_token)).toMatchObject({ iat: SIGNED_AT.getTime() / 1000, exp: Math.floor(clock.ms / 1000) + 3600, sid: kept.session.id, m: 'otp' });
      // The new access token works on the ESS, and the one before it still does too, until its hour.
      expect((await H.me(app, res.body.access_token)).status).toBe(200);
      refreshToken = res.body.refresh_token;
    }
  });

  it('builds a portal access token from the account as it is now: a new role or branch is in the next token', async () => {
    const { app, clock, kept, db, person } = await keptSignIn({ who: 'admin' });
    const account = db.tables.users.find((u) => u.id === person.user.id);
    Object.assign(account, { role: 'admin_manager', location_id: 2, username: 'renamed.login' });
    clock.advance(HOUR);
    const res = await H.refresh(app, kept.refresh_token);
    expect(res.status).toBe(200);
    expect(res.body.login).toEqual({ kind: 'portal', role: 'admin_manager', user_id: person.user.id });
    expect(H.claims(res.body.access_token)).toMatchObject({
      userId: person.user.id, role: 'admin_manager', locationId: 2, username: 'renamed.login',
      // The branch the person signed in at, as the Scheduler's own token would carry it.
      locationName: 'Faridabad', isSuperAdmin: false, iat: SIGNED_AT.getTime() / 1000,
    });
  });

  it('gives a teacher the faculty id the account has now', async () => {
    const { app, clock, kept, db, person } = await keptSignIn({ who: 'faculty' });
    db.tables.users.find((u) => u.id === person.user.id).faculty_id = 'f0000000-0000-4000-8000-000000000777';
    clock.advance(HOUR);
    const res = await H.refresh(app, kept.refresh_token);
    expect(H.claims(res.body.access_token).id).toBe('f0000000-0000-4000-8000-000000000777');
  });

  it('needs no bearer, and an expired one does not stand in its way', async () => {
    const { app, clock, kept } = await keptSignIn();
    clock.advance(3 * HOUR);
    const res = await request(app).post('/api/ess/session/refresh').set(bearer(kept.access_token))
      .send({ refresh_token: kept.refresh_token, install_id: INSTALL_ID });
    expect(res.status).toBe(200);
  });
});

describe('the 90 days', () => {
  it('start again at every refresh, so a sign-in used every 89 days goes on', async () => {
    const { app, clock, kept } = await keptSignIn();
    clock.advance(89 * DAY);
    const first = await H.refresh(app, kept.refresh_token);
    expect(first.status).toBe(200);
    clock.advance(89 * DAY);
    const second = await H.refresh(app, first.body.refresh_token);
    expect(second.status).toBe(200);
    expect(second.body.session.expires_at).toBe(new Date(clock.ms + 90 * DAY).toISOString());
  });

  it('run out for a sign-in left unused: 401 expired, and the sign-in is closed', async () => {
    const { app, clock, kept, db } = await keptSignIn();
    clock.advance(90 * DAY);
    expectRefused(await H.refresh(app, kept.refresh_token), 'expired');
    expect(H.familyRows(db, kept.session.id)[0]).toMatchObject({ revoked_reason: 'expired' });
    expectRefused(await H.refresh(app, kept.refresh_token), 'expired');
  });
});

describe('a refresh token the ESS does not know', () => {
  it.each([
    ['one it never issued', 'A'.repeat(43)],
    ['one too short', 'A'.repeat(42)],
    ['one with a character base64url has not', `${'A'.repeat(42)}=`],
    ['a number', 42],
    ['nothing', undefined],
  ])('is 401 unknown: %s', async (_label, refreshToken) => {
    const { app, db, kept } = await keptSignIn();
    expectRefused(await H.refresh(app, refreshToken), 'unknown');
    expect(H.liveRows(db, kept.session.id)).toHaveLength(1);
  });

  it('is 401 unknown for an access token in its place', async () => {
    const { app, kept } = await keptSignIn();
    expectRefused(await H.refresh(app, kept.access_token), 'unknown');
  });
});

it('a missing or malformed install id is 400 BAD_INSTALL_ID, and ends nothing', async () => {
  const { app, kept } = await keptSignIn();
  const bodies = [
    { refresh_token: kept.refresh_token },
    { refresh_token: kept.refresh_token, install_id: 'short' },
    { refresh_token: kept.refresh_token, install_id: 42 },
    { refresh_token: kept.refresh_token, install_id: 'has spaces in it 0123' },
  ];
  for (const body of bodies) {
    expectRefusal(await request(app).post('/api/ess/session/refresh').send(body), 400, 'BAD_INSTALL_ID');
  }
  expect((await H.refresh(app, kept.refresh_token)).status).toBe(200);
});

describe('a refresh token presented twice', () => {
  it('within a minute, from the same install, is a retry: 409 REFRESH_IN_PROGRESS, and nothing ends', async () => {
    const { app, clock, kept, db } = await keptSignIn();
    clock.advance(HOUR);
    const first = await H.refresh(app, kept.refresh_token);
    clock.advance(59 * 1000);
    const again = await H.refresh(app, kept.refresh_token);
    expectRefusal(again, 409, 'REFRESH_IN_PROGRESS');
    expect(H.liveRows(db, kept.session.id)).toHaveLength(1);
    expect((await H.refresh(app, first.body.refresh_token)).status).toBe(200);
  });

  it('after a minute is reuse: the whole sign-in ends, its newest tokens with it', async () => {
    const { app, clock, kept, db } = await keptSignIn();
    clock.advance(HOUR);
    const first = await H.refresh(app, kept.refresh_token);
    clock.advance(61 * 1000);
    expectRefused(await H.refresh(app, kept.refresh_token), 'reuse');
    expect(H.liveRows(db, kept.session.id)).toHaveLength(0);
    expect(H.familyRows(db, kept.session.id).find((r) => r.revoked_reason === 'reuse')).toBeTruthy();
    expectRefused(await H.refresh(app, first.body.refresh_token), 'reuse');
    expectRefusal(await H.me(app, first.body.access_token), 401, 'NOT_AUTHENTICATED');
  });

  it('from another install, even at once, is reuse', async () => {
    const { app, clock, kept, db } = await keptSignIn();
    clock.advance(HOUR);
    const first = await H.refresh(app, kept.refresh_token);
    expectRefused(await H.refresh(app, kept.refresh_token, OTHER_INSTALL_ID), 'reuse');
    expect(H.liveRows(db, kept.session.id)).toHaveLength(0);
    expectRefused(await H.refresh(app, first.body.refresh_token), 'reuse');
  });

  it('after its sign-in has ended is refused as reuse, with nothing left to end', async () => {
    const { app, clock, kept } = await keptSignIn();
    clock.advance(HOUR);
    const first = await H.refresh(app, kept.refresh_token);
    await H.signOut(app, { token: first.body.access_token });
    clock.advance(HOUR);
    expectRefused(await H.refresh(app, kept.refresh_token), 'reuse');
    expectRefused(await H.refresh(app, first.body.refresh_token), 'signed_out');
  });

  it('at the same moment as the first: one refresh wins, the other is told to retry', async () => {
    const { app, clock, kept, db } = await keptSignIn();
    clock.advance(HOUR);
    const answers = await Promise.all([H.refresh(app, kept.refresh_token), H.refresh(app, kept.refresh_token)]);
    expect(answers.map((r) => r.status).sort()).toEqual([200, 409]);
    expect(H.liveRows(db, kept.session.id)).toHaveLength(1);
  });
});

it('ends every kept sign-in once JWT_SECRET is rotated, as the docs promise of a rotation', async () => {
  const { db, kept: before } = await keptSignIn();
  // The same database, read by an ESS started with a new secret.
  const config = loadConfig({ ...TEST_ENV, JWT_SECRET: `${TEST_JWT_SECRET}-rotated` });
  const rotated = createApp({ config, store: createSupabaseStore(config, { client: db }), now: () => new Date(NOW.getTime() + HOUR) });
  expectRefused(await H.refresh(rotated, before.refresh_token), 'unknown');
  expectRefusal(await H.me(rotated, before.access_token), 401, 'NOT_AUTHENTICATED');
});

it('a refresh token presented by another install is reuse, and ends its sign-in', async () => {
  const { app, kept, db } = await keptSignIn();
  expectRefused(await H.refresh(app, kept.refresh_token, OTHER_INSTALL_ID), 'reuse');
  expect(H.familyRows(db, kept.session.id)[0]).toMatchObject({ revoked_reason: 'reuse' });
  expectRefused(await H.refresh(app, kept.refresh_token), 'reuse');
});

describe('ends the sign-in when employeeAuth would no longer let the person in', () => {
  const cases = [
    ['attendance', 'otp', 'the attendance password was set or reset since', 'password_changed',
      (db, p) => { db.tables.hr_attendance_accounts.find((a) => a.employee_id === p.employee.id).sessions_valid_from = new Date(SIGNED_AT.getTime() + 1000).toISOString(); }],
    ['attendance', 'otp', 'HR switched the attendance login off', 'login_off',
      (db, p) => { db.tables.hr_attendance_accounts.find((a) => a.employee_id === p.employee.id).status = 'disabled'; }],
    ['attendance', 'otp', 'the attendance login was removed', 'login_off',
      (db) => { db.tables.hr_attendance_accounts = []; }],
    ['attendance', 'pw', 'the login is back on a password HR gave', 'password_changed',
      (db, p) => { db.tables.hr_attendance_accounts.find((a) => a.employee_id === p.employee.id).password_set_at = null; }],
    ['attendance', 'otp', 'the employee exited', 'left',
      (db, p) => { db.tables.hr_employees.find((e) => e.id === p.employee.id).employment_status = 'exited'; }],
    ['attendance', 'otp', 'the employee was archived', 'left',
      (db, p) => { db.tables.hr_employees.find((e) => e.id === p.employee.id).is_archived = true; }],
    ['attendance', 'otp', 'the employee is past their last working day', 'left',
      (db, p) => { Object.assign(db.tables.hr_employees.find((e) => e.id === p.employee.id), { employment_status: 'notice_period', date_of_exit: '2026-10-15' }); }],
    ['attendance', 'otp', 'the employee record was deleted', 'left',
      (db, p) => { db.tables.hr_employees = db.tables.hr_employees.filter((e) => e.id !== p.employee.id); }],
    ['hr', null, 'the portal login was unlinked from the HR record', 'unlinked',
      (db, p) => { db.tables.hr_employees.find((e) => e.id === p.employee.id).user_id = null; }],
    ['hr', null, 'the portal login was linked to somebody else', 'unlinked',
      (db, p) => {
        db.tables.hr_employees.find((e) => e.id === p.employee.id).user_id = null;
        db.tables.hr_employees.find((e) => e.employee_code === 'RVM-050').user_id = p.user.id;
      }],
    ['hr', null, 'the account became the connector identity', 'unlinked',
      (db, p) => { db.tables.users.find((u) => u.id === p.user.id).role = 'bot_readonly'; }],
    ['hr', null, 'the account was deleted', 'unlinked',
      (db, p) => { db.tables.users = db.tables.users.filter((u) => u.id !== p.user.id); }],
    ['hr', null, 'the person left', 'left',
      (db, p) => { db.tables.hr_employees.find((e) => e.id === p.employee.id).employment_status = 'exited'; }],
    ['hr', null, 'the portal password changed since the sign-in', 'password_changed',
      (db, p) => { db.tables.users.find((u) => u.id === p.user.id).password_changed_at = new Date(SIGNED_AT.getTime() + 30 * MINUTE).toISOString(); }],
  ];

  it.each(cases)('%s (%s): %s -> 401 %s, and the sign-in is closed', async (who, method, _label, reason, change) => {
    const { app, clock, kept, db, person } = await keptSignIn({ who, method: method || 'otp' });
    clock.advance(HOUR);
    change(db, person);
    const res = await H.refresh(app, kept.refresh_token);
    expectRefused(res, reason);
    expect(H.familyRows(db, kept.session.id)[0]).toMatchObject({ revoked_reason: reason, revoked_at: new Date(clock.ms).toISOString() });
    // Every token of that sign-in is over on the ESS at once, and the refresh token stays refused.
    expectRefusal(await H.me(app, kept.access_token), 401, 'NOT_AUTHENTICATED');
    expectRefused(await H.refresh(app, kept.refresh_token), reason);
  });

  it('lets a sign-in on when the attendance password changed in the same second, which is the new one', async () => {
    const { app, clock, kept, db, person } = await keptSignIn();
    db.tables.hr_attendance_accounts.find((a) => a.employee_id === person.employee.id).sessions_valid_from = new Date(SIGNED_AT.getTime() + 999).toISOString();
    clock.advance(HOUR);
    expect((await H.refresh(app, kept.refresh_token)).status).toBe(200);
  });

  describe('a portal password changed by a Scheduler path that does not stamp password_changed_at', () => {
    // Scheduler_Backend c28b9ca: updateUser (userController.js:1022-1031), resetPassword
    // (:1231-1236) and changeOwnPassword (:1313-1318) write password_hash only.
    it.each([
      ['an admin resets it in User Management (PATCH /api/users/update/:id)'],
      ['the public legacy reset (POST /api/users/reset-password)'],
      ['the person changes it (POST /api/users/change-password)'],
    ])('%s: the next refresh ends the sign-in', async () => {
      const { app, clock, kept, db, person } = await keptSignIn({ who: 'hr' });
      clock.advance(30 * MINUTE);
      db.tables.users.find((u) => u.id === person.user.id).password_hash = '$2b$10$new.password.hash.set.by.scheduler';
      clock.advance(HOUR);
      const res = await H.refresh(app, kept.refresh_token);
      if (res.status === 200) {
        // What would happen otherwise: the Scheduler takes what this refresh minted as the same user.
        process.env.JWT_SECRET = TEST_JWT_SECRET;
        G.useRows({ users: db.tables.users });
        vi.useFakeTimers({ toFake: ['Date'], now: clock.ms });
        try {
          const scheduler = await G.runAuth(res.body.access_token);
          expect(scheduler.passed).toBe(true);
          expect(scheduler.req.user.id).toBe(person.user.id);
        } finally { vi.useRealTimers(); }
      }
      expectRefused(res, 'password_changed');
      expect(H.familyRows(db, kept.session.id).find((r) => r.revoked_reason !== 'rotated')).toMatchObject({ revoked_reason: 'password_changed' });
      expectRefused(await H.refresh(app, kept.refresh_token), 'password_changed');
    });

    it('also after the sign-in has been renewed: every turn keeps the password it was kept with', async () => {
      const { app, clock, kept, db, person } = await keptSignIn({ who: 'hr' });
      clock.advance(HOUR);
      const first = await H.refresh(app, kept.refresh_token);
      expect(first.status).toBe(200);
      db.tables.users.find((u) => u.id === person.user.id).password_hash = '$2b$10$another.hash.set.by.the.scheduler';
      clock.advance(HOUR);
      expectRefused(await H.refresh(app, first.body.refresh_token), 'password_changed');
    });

    it('lets the sign-in on while the password is the one it was kept with', async () => {
      const { app, clock, kept } = await keptSignIn({ who: 'hr' });
      let latest = kept.refresh_token;
      for (let i = 0; i < 3; i += 1) {
        clock.advance(HOUR);
        const res = await H.refresh(app, latest);
        expect(res.status).toBe(200);
        latest = res.body.refresh_token;
      }
    });

    it('never sends the password hash, or anything made from it, to the ESS', async () => {
      const { app, clock, kept, db } = await keptSignIn({ who: 'hr' });
      clock.advance(HOUR);
      expect((await H.refresh(app, kept.refresh_token)).status).toBe(200);
      for (const q of db.queries) {
        expect(q.columns || [], `${q.op} ${q.table}`).not.toContain('password_hash');
        expect(q.columns || [], `${q.op} ${q.table}`).not.toContain('password_fingerprint');
      }
    });
  });

  it('lets a portal sign-in on when the password changed before it', async () => {
    const { app, clock, kept, db, person } = await keptSignIn({ who: 'hr' });
    db.tables.users.find((u) => u.id === person.user.id).password_changed_at = new Date(SIGNED_AT.getTime() - DAY).toISOString();
    clock.advance(HOUR);
    expect((await H.refresh(app, kept.refresh_token)).status).toBe(200);
  });

  it('answers 503 for a cut-off it cannot read, and ends nothing', async () => {
    const { app, clock, kept, db, person } = await keptSignIn();
    db.tables.hr_attendance_accounts.find((a) => a.employee_id === person.employee.id).sessions_valid_from = 'not a time';
    clock.advance(HOUR);
    expectRefusal(await H.refresh(app, kept.refresh_token), 503, 'UNAVAILABLE');
    expect(H.liveRows(db, kept.session.id)).toHaveLength(1);
  });
});

describe('a database failure is 503 and ends nothing', () => {
  beforeEach(quiet);

  it.each([['error'], ['throw']])('when the database answers with %s', async (outage) => {
    const { app, clock, kept, db } = await keptSignIn();
    clock.advance(HOUR);
    db.outage = outage;
    expectRefusal(await H.refresh(app, kept.refresh_token), 503, 'UNAVAILABLE');
    db.outage = null;
    expect((await H.refresh(app, kept.refresh_token)).status).toBe(200);
  });

  it('when the person cannot be checked', async () => {
    const { app, clock, kept, db } = await keptSignIn({ who: 'hr' });
    clock.advance(HOUR);
    db.failWhen = (q) => (q.table === 'users' ? 'error' : null);
    expectRefusal(await H.refresh(app, kept.refresh_token), 503, 'UNAVAILABLE');
    db.failWhen = null;
    expect((await H.refresh(app, kept.refresh_token)).status).toBe(200);
  });

  it('when the rotation fails', async () => {
    const { app, clock, kept, db } = await keptSignIn();
    clock.advance(HOUR);
    db.failWhen = (q) => (q.fn === 'hr_ess_session_rotate' ? 'error' : null);
    expectRefusal(await H.refresh(app, kept.refresh_token), 503, 'UNAVAILABLE');
    expect(H.familyRows(db, kept.session.id)).toHaveLength(1);
    db.failWhen = null;
    expect((await H.refresh(app, kept.refresh_token)).status).toBe(200);
  });

  it('when ending a reused sign-in fails: the reuse is not reported as dealt with', async () => {
    const { app, clock, kept, db } = await keptSignIn();
    clock.advance(HOUR);
    db.failWhen = (q) => (q.fn === 'hr_ess_session_revoke' ? 'error' : null);
    expectRefusal(await H.refresh(app, kept.refresh_token, OTHER_INSTALL_ID), 503, 'UNAVAILABLE');
    db.failWhen = null;
    expectRefused(await H.refresh(app, kept.refresh_token, OTHER_INSTALL_ID), 'reuse');
  });

  it('before the migration: 503 MODULE_NOT_INSTALLED', async () => {
    const { app, kept, db } = await keptSignIn();
    db.dropTable('hr_ess_sessions');
    const res = await H.refresh(app, kept.refresh_token);
    expectRefusal(res, 503, 'MODULE_NOT_INSTALLED');
    expect(res.body.error).toMatch(/hr_ess_sessions/);
  });
});

it('is limited per address: 429 RATE_LIMITED, counted before the token is looked at', async () => {
  const { app, db } = await keptSignIn({ limits: { sessionPerIp: { windowMs: 60 * 1000, limit: 2 } } });
  const before = db.queries.length;
  await H.refresh(app, 'A'.repeat(43));
  await H.refresh(app, 'A'.repeat(43));
  const res = await H.refresh(app, 'A'.repeat(43));
  expectRefusal(res, 429, 'RATE_LIMITED');
  expect(Number(res.headers['retry-after'])).toBeGreaterThan(0);
  expect(db.queries.length - before).toBe(2);
});
