const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { NOW, SIGNED_AT, TEST_JWT_SECRET } = require('./helpers/constants');
const { INSTALL_ID, OTHER_INSTALL_ID, sessionRow } = require('./helpers/fixtures');
const H = require('./helpers/sessions');
const S = require('./helpers/schedulerTokens');
const { refreshTokenHash, mintAttendanceToken, mintPortalToken } = require('../src/lib/accessTokens');
const { passwordFingerprint } = require('./helpers/fakeSupabase');

/**
 * Keeping a sign-in (task A3): POST /api/ess/session, GET /api/ess/sessions,
 * DELETE /api/ess/sessions/:id, POST /api/ess/session/sign-out, and what employeeAuth does with
 * the tokens the ESS mints. Refreshing is in tests/refresh.test.js.
 */

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const { MINUTE, HOUR, DAY } = H;

const expectRefusal = (res, status, code) => {
  expect(res.status).toBe(status);
  expect(res.body).toMatchObject({ error: expect.any(String), code });
  expect(res.body.error.length).toBeGreaterThan(10);
};

const quiet = () => vi.spyOn(console, 'error').mockImplementation(() => {});

/**
 * The person's nth separate portal sign-in, n seconds before the usual one: still fresh, and a
 * sign-in of its own, since one Scheduler sign-in is kept only once.
 */
const nthSignIn = (person, n) => tokens.portal(person, new Date(SIGNED_AT.getTime() - n * 1000));

describe('POST /api/ess/session', () => {
  describe('trades a fresh sign-in for a kept one', () => {
    it('for a portal login', async () => {
      const { app, db, people } = buildApp();
      const res = await H.keep(app, tokens.portal(people.faculty));
      expect(res.status).toBe(201);
      expect(res.body).toEqual({
        session: { id: expect.stringMatching(UUID), expires_at: new Date(NOW.getTime() + 90 * DAY).toISOString() },
        access_token: expect.any(String),
        access_expires_at: new Date(NOW.getTime() + HOUR).toISOString(),
        refresh_token: expect.stringMatching(/^[A-Za-z0-9_-]{43}$/),
        login: { kind: 'portal', role: 'faculty', user_id: people.faculty.user.id },
      });
      expect(db.tables.hr_ess_sessions).toEqual([{
        id: res.body.session.id,
        family_id: res.body.session.id,
        employee_id: people.faculty.employee.id,
        login_kind: 'portal',
        user_id: people.faculty.user.id,
        location_name: 'Faridabad',
        method: null,
        signed_in_at: SIGNED_AT.toISOString(),
        install_id: INSTALL_ID,
        device_label: 'Test phone',
        refresh_hash: refreshTokenHash(res.body.refresh_token, TEST_JWT_SECRET),
        // Put there by the database, never sent by the ESS (hr_ess_sessions_bind_password).
        password_fingerprint: passwordFingerprint(people.faculty.user.password_hash),
        created_at: NOW.toISOString(),
        last_used_at: NOW.toISOString(),
        expires_at: res.body.session.expires_at,
      }]);
    });

    it.each(['otp', 'pw'])('for an attendance session earned by %s', async (method) => {
      const { app, db, people } = buildApp();
      const res = await H.keep(app, tokens.attendance(people.attendance, method));
      expect(res.status).toBe(201);
      expect(res.body.login).toEqual({ kind: 'attendance', role: null, user_id: null });
      expect(db.tables.hr_ess_sessions[0]).toMatchObject({
        employee_id: people.attendance.employee.id, login_kind: 'attendance', user_id: null, location_name: null, method,
      });
    });

    it('never stores the refresh token itself', async () => {
      const { app, db, people } = buildApp();
      const res = await H.keep(app, tokens.portal(people.hr));
      expect(JSON.stringify(db.tables.hr_ess_sessions)).not.toContain(res.body.refresh_token);
      expect(JSON.stringify(db.queries)).not.toContain(res.body.refresh_token);
    });

    it('with a portal access token in the Scheduler\'s format, carrying the original sign-in time', async () => {
      const { app, people } = buildApp();
      const res = await H.keep(app, tokens.portal(people.faculty));
      expect(H.claims(res.body.access_token)).toEqual({
        userId: people.faculty.user.id,
        role: 'faculty',
        locationId: 1,
        username: 'faculty.login',
        locationName: 'Faridabad',
        isSuperAdmin: false,
        id: people.faculty.user.faculty_id,
        sid: res.body.session.id,
        iat: SIGNED_AT.getTime() / 1000,
        exp: NOW.getTime() / 1000 + 3600,
      });
    });

    it('with an attendance access token in the Scheduler\'s format, carrying the original sign-in time', async () => {
      const { app, people } = buildApp();
      const res = await H.keep(app, tokens.attendance(people.attendance, 'otp'));
      expect(H.claims(res.body.access_token)).toEqual({
        k: 'punch', e: people.attendance.employee.id, m: 'otp', sid: res.body.session.id,
        iat: SIGNED_AT.getTime() / 1000, exp: NOW.getTime() / 1000 + 3600, aud: 'rvm-punch',
      });
    });

    it('whose access token the ESS takes, as the same person', async () => {
      const { app, people } = buildApp();
      const kept = await H.keep(app, tokens.portal(people.hr));
      const res = await H.me(app, kept.body.access_token);
      expect(res.status).toBe(200);
      expect(res.body.login).toEqual({ kind: 'portal', role: 'hr', user_id: people.hr.user.id });
      expect((await request(app).get('/api/ess/me/capabilities').set(bearer(kept.body.access_token))).status).toBe(200);
    });

    it('carrying the branch the two-factor sign-in signed, null included', async () => {
      const { app, db, people } = buildApp();
      const res = await H.keep(app, tokens.twoFactor(people.ceo));
      expect(H.claims(res.body.access_token).locationName).toBe('Faridabad');
      const noBranch = S.signedAt(SIGNED_AT, () => S.tokenFor(people.hr.user, null));
      const kept = await H.keep(app, noBranch);
      expect(kept.status).toBe(201);
      expect(H.claims(kept.body.access_token).locationName).toBeNull();
      expect(db.tables.hr_ess_sessions[1].location_name).toBeNull();
    });

    it('starting a new kept sign-in for every Scheduler sign-in, with its own refresh token', async () => {
      const { app, db, people } = buildApp();
      const a = await H.keep(app, nthSignIn(people.hr, 0));
      const b = await H.keep(app, nthSignIn(people.hr, 1));
      expect(a.body.session.id).not.toBe(b.body.session.id);
      expect(a.body.refresh_token).not.toBe(b.body.refresh_token);
      expect(db.tables.hr_ess_sessions).toHaveLength(2);
    });

    it('for the caller only, whatever the body names', async () => {
      const { app, db, people } = buildApp();
      const res = await H.keep(app, tokens.portal(people.faculty), {
        install_id: INSTALL_ID, employee_id: people.ceo.employee.id, user_id: people.ceo.user.id, login_kind: 'attendance', method: 'otp',
      });
      expect(res.status).toBe(201);
      expect(db.tables.hr_ess_sessions[0]).toMatchObject({
        employee_id: people.faculty.employee.id, user_id: people.faculty.user.id, login_kind: 'portal', method: null,
      });
    });
  });

  describe('takes only a fresh sign-in', () => {
    it('up to ten minutes after it was made', async () => {
      const { app, people } = buildApp();
      expect((await H.keep(app, tokens.portal(people.hr, new Date(NOW.getTime() - 10 * MINUTE)))).status).toBe(201);
      expect((await H.keep(app, tokens.attendance(people.attendance, 'otp', new Date(NOW.getTime() - 10 * MINUTE)))).status).toBe(201);
    });

    it('and refuses one a second older with 403 SIGN_IN_NOT_FRESH, though it is still good for everything else', async () => {
      const { app, db, people } = buildApp();
      const old = tokens.portal(people.hr, new Date(NOW.getTime() - 10 * MINUTE - 1000));
      expectRefusal(await H.keep(app, old), 403, 'SIGN_IN_NOT_FRESH');
      expect((await H.me(app, old)).status).toBe(200);
      expect(db.tables.hr_ess_sessions).toHaveLength(0);
    });

    it('so a token from days ago cannot become a 90-day sign-in', async () => {
      const { app, people } = buildApp();
      expectRefusal(await H.keep(app, tokens.portal(people.hr, new Date(NOW.getTime() - 2 * DAY))), 403, 'SIGN_IN_NOT_FRESH');
      // Ten days old, and after the login's last password change, so employeeAuth itself lets it in.
      expectRefusal(await H.keep(app, tokens.attendance(people.attendance, 'pw', new Date(NOW.getTime() - 10 * DAY))), 403, 'SIGN_IN_NOT_FRESH');
    });

    it('and refuses one from more than a minute in the future', async () => {
      const { app, people } = buildApp();
      expect((await H.keep(app, tokens.portal(people.hr, new Date(NOW.getTime() + 59 * 1000)))).status).toBe(201);
      expectRefusal(await H.keep(app, tokens.portal(people.hr, new Date(NOW.getTime() + 61 * 1000))), 403, 'SIGN_IN_NOT_FRESH');
    });
  });

  describe('trades one Scheduler sign-in once', () => {
    it.each([
      ['portal', (people) => tokens.portal(people.hr)],
      ['attendance', (people) => tokens.attendance(people.attendance)],
    ])('refuses a second trade of the same %s token with 409 ALREADY_EXCHANGED, and starts no second sign-in', async (_kind, tokenOf) => {
      const { app, db, people } = buildApp();
      const token = tokenOf(people);
      expect((await H.keep(app, token)).status).toBe(201);
      const second = await H.keep(app, token, { install_id: OTHER_INSTALL_ID, device_label: 'Pixel 7' });
      expectRefusal(second, 409, 'ALREADY_EXCHANGED');
      expect(second.body.error).toMatch(/sign in again/i);
      const families = new Set(db.tables.hr_ess_sessions.filter((r) => r.revoked_at == null).map((r) => r.family_id));
      expect(families.size).toBe(1);
    });

    it('still refuses it once the first sign-in has ended', async () => {
      const { app, db, people } = buildApp();
      const token = tokens.portal(people.hr);
      const kept = await H.keep(app, token);
      expect((await H.signOut(app, { refreshToken: kept.body.refresh_token })).status).toBe(204);
      expectRefusal(await H.keep(app, token), 409, 'ALREADY_EXCHANGED');
      expect(db.tables.hr_ess_sessions).toHaveLength(1);
    });

    it('takes a new sign-in of the same person a second later, on another phone', async () => {
      const { app, people } = buildApp();
      expect((await H.keep(app, tokens.portal(people.hr))).status).toBe(201);
      const again = await H.keep(app, tokens.portal(people.hr, new Date(SIGNED_AT.getTime() + 1000)), { install_id: OTHER_INSTALL_ID });
      expect(again.status).toBe(201);
    });
  });

  it('refuses a token it minted itself with 409 ALREADY_EXCHANGED', async () => {
    const { app, db, people } = buildApp();
    const kept = await H.keep(app, tokens.attendance(people.attendance));
    expectRefusal(await H.keep(app, kept.body.access_token), 409, 'ALREADY_EXCHANGED');
    expect(db.tables.hr_ess_sessions).toHaveLength(1);
  });

  describe('reads the install id and the phone\'s name', () => {
    it.each([
      ['no install id', {}],
      ['one of 15 characters', { install_id: 'a'.repeat(15) }],
      ['one of 129 characters', { install_id: 'a'.repeat(129) }],
      ['one with a space', { install_id: 'install id 0123456789' }],
      ['one with a slash', { install_id: 'install/0123456789ab' }],
      ['a number', { install_id: 1234567890123456 }],
    ])('400 BAD_INSTALL_ID for %s', async (_label, body) => {
      const { app, db, people } = buildApp();
      expectRefusal(await H.keep(app, tokens.portal(people.hr), body), 400, 'BAD_INSTALL_ID');
      expect(db.tables.hr_ess_sessions).toHaveLength(0);
    });

    it('takes install ids of 16 and of 128 letters, digits, dots, dashes and underscores', async () => {
      const { app, db, people } = buildApp();
      for (const [n, install] of ['A.b-c_0123456789', `${'x'.repeat(127)}.`].entries()) {
        expect((await H.keep(app, nthSignIn(people.hr, n), { install_id: install })).status).toBe(201);
      }
      expect(db.tables.hr_ess_sessions.map((r) => r.install_id)).toEqual(['A.b-c_0123456789', `${'x'.repeat(127)}.`]);
    });

    it.each([
      ['81 characters', 'x'.repeat(81)],
      ['a line break', 'Pixel\n7'],
      ['a number', 7],
      ['an object', { name: 'Pixel' }],
    ])('400 BAD_DEVICE_LABEL for one of %s', async (_label, deviceLabel) => {
      const { app, people } = buildApp();
      expectRefusal(await H.keep(app, tokens.portal(people.hr), { install_id: INSTALL_ID, device_label: deviceLabel }), 400, 'BAD_DEVICE_LABEL');
    });

    it('takes no name, a blank one, and one of 80 characters, trimmed', async () => {
      const { app, db, people } = buildApp();
      const eighty = `${'é'.repeat(79)}7`;
      for (const [n, deviceLabel] of [undefined, null, '   ', `  ${eighty}  `].entries()) {
        expect((await H.keep(app, nthSignIn(people.hr, n), { install_id: INSTALL_ID, device_label: deviceLabel })).status).toBe(201);
      }
      expect(db.tables.hr_ess_sessions.map((r) => r.device_label)).toEqual([null, null, null, eighty]);
    });
  });

  describe('a portal password changed after the sign-in', () => {
    const changed = (when) => (w) => { w.people.hr.user.password_changed_at = when; };

    it('ends that sign-in: 401, and nothing is kept', async () => {
      const { app, db, people } = buildApp({ setup: changed(new Date(SIGNED_AT.getTime() + 30 * 1000).toISOString()) });
      const res = await H.keep(app, tokens.portal(people.hr));
      expectRefusal(res, 401, 'NOT_AUTHENTICATED');
      expect(res.body.error).toBe('Your password was changed. Please sign in again.');
      expect(res.headers['www-authenticate']).toBe('Bearer');
      expect(db.tables.hr_ess_sessions).toHaveLength(0);
    });

    it('does not end a sign-in made after the change, or in the same second', async () => {
      for (const when of [new Date(SIGNED_AT.getTime() - MINUTE).toISOString(), new Date(SIGNED_AT.getTime() + 999).toISOString()]) {
        const { app, people } = buildApp({ setup: changed(when) });
        expect((await H.keep(app, tokens.portal(people.hr))).status).toBe(201);
      }
    });
  });

  describe('lets in only what employeeAuth lets in', () => {
    const cases = [
      ['no token', 401, 'NOT_AUTHENTICATED', () => ({ world: buildApp(), token: null })],
      ['a forged token', 401, 'NOT_AUTHENTICATED', () => ({ world: buildApp(), token: () => 'not.a.token' })],
      ['a student token', 403, 'NOT_AN_EMPLOYEE', () => ({ world: buildApp(), token: () => tokens.student() })],
      ['an admission-undertaking token', 403, 'NOT_AN_EMPLOYEE', () => ({ world: buildApp(), token: () => tokens.undertaking() })],
      ['the connector identity', 403, 'NOT_AN_EMPLOYEE', () => ({ world: buildApp(), token: (p) => tokens.portal(p.bot) })],
      ['a desk login with no HR record', 403, 'NOT_LINKED', () => ({ world: buildApp(), token: (p) => tokens.portal(p.desk) })],
      ['a leaver', 403, 'NOT_ACTIVE', () => ({
        world: buildApp({ setup: (w) => { w.people.faculty.employee.employment_status = 'exited'; } }),
        token: (p) => tokens.portal(p.faculty),
      })],
      ['an attendance login switched off', 403, 'NO_ATTENDANCE_LOGIN', () => ({
        world: buildApp({ setup: (w) => { w.people.attendance.account.status = 'disabled'; } }),
        token: (p) => tokens.attendance(p.attendance),
      })],
      ['a session still on HR\'s first-time password', 403, 'PASSWORD_CHANGE_REQUIRED', () => ({
        world: buildApp({ setup: (w) => { w.people.attendance.account.password_set_at = null; } }),
        token: (p) => tokens.attendance(p.attendance, 'pw'),
      })],
    ];

    it.each(cases)('%s: %i %s, and nothing is kept', async (_label, status, code, scenario) => {
      const { world, token } = scenario();
      const req = request(world.app).post('/api/ess/session');
      const res = await (token ? req.set(bearer(token(world.people))) : req).send({ install_id: INSTALL_ID });
      expectRefusal(res, status, code);
      expect(world.db.tables.hr_ess_sessions).toHaveLength(0);
    });
  });

  describe('when the database is not ready', () => {
    beforeEach(quiet);

    it.each([['a portal login', (p) => tokens.portal(p.hr)], ['an attendance session', (p) => tokens.attendance(p.attendance)]])(
      'answers 503 MODULE_NOT_INSTALLED for %s before the migration',
      async (_label, token) => {
        const { app, db, people } = buildApp();
        db.dropTable('hr_ess_sessions');
        const res = await H.keep(app, token(people));
        expectRefusal(res, 503, 'MODULE_NOT_INSTALLED');
        expect(res.body.error).toMatch(/hr_ess_sessions/);
      },
    );

    it('answers 503 UNAVAILABLE when the sign-in cannot be stored, and keeps nothing', async () => {
      const { app, db, people } = buildApp();
      db.failWhen = (q) => (q.table === 'hr_ess_sessions' && q.op === 'insert' ? 'error' : null);
      expectRefusal(await H.keep(app, tokens.portal(people.hr)), 503, 'UNAVAILABLE');
      expect(db.tables.hr_ess_sessions).toHaveLength(0);
    });
  });

  it('allows one employee only so many in a window: 429 RATE_LIMITED', async () => {
    const { app, people } = buildApp({ limits: { exchangePerEmployee: { windowMs: 60 * 1000, limit: 2 } } });
    expect((await H.keep(app, nthSignIn(people.hr, 0))).status).toBe(201);
    expect((await H.keep(app, nthSignIn(people.hr, 1))).status).toBe(201);
    expectRefusal(await H.keep(app, nthSignIn(people.hr, 2)), 429, 'RATE_LIMITED');
    // Somebody else at the same address is not held back.
    expect((await H.keep(app, tokens.portal(people.ceo))).status).toBe(201);
  });
});

describe('a token the ESS minted, at employeeAuth', () => {
  it('is let in while its sign-in is live', async () => {
    const { app, people } = buildApp();
    const kept = await H.keep(app, tokens.attendance(people.attendance));
    expect((await H.me(app, kept.body.access_token)).status).toBe(200);
  });

  it.each([
    ['signed out', { revoked_at: '2026-10-16T06:30:00.000Z', revoked_reason: 'signed_out' }],
    ['ended for reuse', { revoked_at: '2026-10-16T06:30:00.000Z', revoked_reason: 'reuse' }],
    ['past its 90 days', { expires_at: '2026-10-16T06:29:59.000Z' }],
  ])('is refused with 401 once its sign-in is %s', async (_label, change) => {
    const { app, db, people } = buildApp();
    const kept = await H.keep(app, tokens.attendance(people.attendance));
    Object.assign(db.tables.hr_ess_sessions[0], change);
    for (const path of ['/api/ess/me', '/api/ess/me/capabilities', '/api/ess/sessions']) {
      const res = await request(app).get(path).set(bearer(kept.body.access_token));
      expectRefusal(res, 401, 'NOT_AUTHENTICATED');
      expect(res.headers['www-authenticate']).toBe('Bearer');
    }
  });

  it('is refused with 401 when its sign-in is not in the table at all', async () => {
    const { app, people } = buildApp();
    const token = mintAttendanceToken({
      employeeId: people.attendance.employee.id, method: 'otp', sessionId: '5a000000-0000-4000-8000-000000000404',
      signedInAtMs: SIGNED_AT.getTime(), nowMs: NOW.getTime(), jwtSecret: TEST_JWT_SECRET,
    });
    expectRefusal(await H.me(app, token), 401, 'NOT_AUTHENTICATED');
  });

  it('is refused with 401 when its sid names somebody else\'s sign-in', async () => {
    const { app, people } = buildApp();
    const theirs = await H.keep(app, tokens.portal(people.ceo));
    const sessionId = theirs.body.session.id;
    const attendance = mintAttendanceToken({
      employeeId: people.attendance.employee.id, method: 'otp', sessionId, signedInAtMs: SIGNED_AT.getTime(), nowMs: NOW.getTime(), jwtSecret: TEST_JWT_SECRET,
    });
    const portal = mintPortalToken({
      user: people.hr.user, locationName: 'Faridabad', sessionId, signedInAtMs: SIGNED_AT.getTime(), nowMs: NOW.getTime(), jwtSecret: TEST_JWT_SECRET,
    });
    expectRefusal(await H.me(app, attendance), 401, 'NOT_AUTHENTICATED');
    expectRefusal(await H.me(app, portal), 401, 'NOT_AUTHENTICATED');
    expect((await H.me(app, theirs.body.access_token)).status).toBe(200);
  });

  it('is refused with 401 when its sid names a sign-in of the other kind', async () => {
    const { app, people } = buildApp({
      setup: (w) => w.tables.hr_attendance_accounts.push({ ...w.people.attendance.account, id: '90000000-0000-4000-8000-000000000098', employee_id: w.people.hr.employee.id }),
    });
    const portal = await H.keep(app, tokens.portal(people.hr));
    const token = mintAttendanceToken({
      employeeId: people.hr.employee.id, method: 'otp', sessionId: portal.body.session.id, signedInAtMs: SIGNED_AT.getTime(), nowMs: NOW.getTime(), jwtSecret: TEST_JWT_SECRET,
    });
    expectRefusal(await H.me(app, token), 401, 'NOT_AUTHENTICATED');
  });

  it('still meets every other check: a leaver is 403 NOT_ACTIVE though the sign-in is live', async () => {
    const { app, db, people } = buildApp();
    const kept = await H.keep(app, tokens.portal(people.faculty));
    db.tables.hr_employees.find((e) => e.id === people.faculty.employee.id).employment_status = 'exited';
    expectRefusal(await H.me(app, kept.body.access_token), 403, 'NOT_ACTIVE');
  });

  it('is a 503, not a 401, when the database is away or the table is missing', async () => {
    quiet();
    const { app, db, people } = buildApp();
    const kept = await H.keep(app, tokens.attendance(people.attendance));
    db.outage = 'error';
    expectRefusal(await H.me(app, kept.body.access_token), 503, 'UNAVAILABLE');
    db.outage = null;
    db.dropTable('hr_ess_sessions');
    expectRefusal(await H.me(app, kept.body.access_token), 503, 'MODULE_NOT_INSTALLED');
  });

  it('leaves a token the Scheduler issued as it was: no session is looked up for it', async () => {
    const { app, db, people } = buildApp();
    db.dropTable('hr_ess_sessions');
    expect((await H.me(app, tokens.portal(people.hr))).status).toBe(200);
    expect((await H.me(app, tokens.attendance(people.attendance))).status).toBe(200);
    expect(db.queries.filter((q) => q.table === 'hr_ess_sessions')).toHaveLength(0);
  });
});

describe('GET /api/ess/sessions', () => {
  it('lists my live sign-ins, newest use first, with the one I am using marked', async () => {
    const clock = H.clockAt(NOW);
    const { app, people } = buildApp({ now: clock.now });
    const phone = await H.keep(app, nthSignIn(people.hr, 0), { install_id: INSTALL_ID, device_label: 'Pixel 7' });
    clock.advance(MINUTE);
    const tablet = await H.keep(app, nthSignIn(people.hr, 1), { install_id: OTHER_INSTALL_ID });
    const res = await H.listSessions(app, phone.body.access_token);
    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      sessions: [
        {
          id: tablet.body.session.id, device_label: null, created_at: new Date(NOW.getTime() + MINUTE).toISOString(),
          last_used_at: new Date(NOW.getTime() + MINUTE).toISOString(), expires_at: tablet.body.session.expires_at, current: false,
        },
        {
          id: phone.body.session.id, device_label: 'Pixel 7', created_at: NOW.toISOString(),
          last_used_at: NOW.toISOString(), expires_at: phone.body.session.expires_at, current: true,
        },
      ],
    });
  });

  it('marks none as current for a token the Scheduler issued', async () => {
    const { app, people } = buildApp();
    await H.keep(app, tokens.portal(people.hr));
    const res = await H.listSessions(app, tokens.portal(people.hr));
    expect(res.body.sessions).toHaveLength(1);
    expect(res.body.sessions[0].current).toBe(false);
  });

  it('never lists somebody else\'s, or one that has ended or expired', async () => {
    const { app, db, people } = buildApp();
    const mine = await H.keep(app, tokens.portal(people.hr));
    await H.keep(app, tokens.portal(people.ceo));
    await H.keep(app, tokens.attendance(people.attendance));
    db.tables.hr_ess_sessions.push(
      sessionRow({ employee_id: people.hr.employee.id, login_kind: 'portal', user_id: people.hr.user.id, method: null, revoked_at: '2026-10-15T00:00:00.000Z', revoked_reason: 'signed_out' }),
      sessionRow({ employee_id: people.hr.employee.id, login_kind: 'portal', user_id: people.hr.user.id, method: null, expires_at: '2026-10-16T06:00:00.000Z' }),
    );
    const res = await H.listSessions(app, mine.body.access_token);
    expect(res.body.sessions.map((s) => s.id)).toEqual([mine.body.session.id]);
  });

  it('lists a person\'s sign-ins of both kinds, since both are theirs', async () => {
    const { app, people } = buildApp({
      setup: (w) => w.tables.hr_attendance_accounts.push({ ...w.people.attendance.account, id: '90000000-0000-4000-8000-000000000096', employee_id: w.people.hr.employee.id }),
    });
    const portal = await H.keep(app, tokens.portal(people.hr));
    const attendance = await H.keep(app, tokens.attendance(people.hr));
    const res = await H.listSessions(app, portal.body.access_token);
    expect(res.body.sessions.map((s) => s.id).sort()).toEqual([portal.body.session.id, attendance.body.session.id].sort());
  });

  it('dates a sign-in from its first row, and from its sign-in once that row is gone', async () => {
    const clock = H.clockAt(NOW);
    const { app, db, people } = buildApp({ now: clock.now });
    const kept = await H.keep(app, tokens.portal(people.hr));
    clock.advance(2 * HOUR);
    const refreshed = await H.refresh(app, kept.body.refresh_token);
    const list = async () => (await H.listSessions(app, refreshed.body.access_token)).body.sessions[0];
    expect(await list()).toMatchObject({ created_at: NOW.toISOString(), last_used_at: new Date(NOW.getTime() + 2 * HOUR).toISOString() });
    db.tables.hr_ess_sessions = db.tables.hr_ess_sessions.filter((r) => r.id !== kept.body.session.id);
    expect((await list()).created_at).toBe(SIGNED_AT.toISOString());
  });

  it('answers only staff, and 503 before the migration', async () => {
    quiet();
    const { app, db, people } = buildApp();
    expectRefusal(await H.listSessions(app, tokens.student()), 403, 'NOT_AN_EMPLOYEE');
    expectRefusal(await request(app).get('/api/ess/sessions'), 401, 'NOT_AUTHENTICATED');
    db.dropTable('hr_ess_sessions');
    expectRefusal(await H.listSessions(app, tokens.portal(people.hr)), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('DELETE /api/ess/sessions/:id', () => {
  it('ends one of my sign-ins: 204, and its tokens stop working', async () => {
    const { app, db, people } = buildApp();
    const phone = await H.keep(app, nthSignIn(people.hr, 0));
    const tablet = await H.keep(app, nthSignIn(people.hr, 1), { install_id: OTHER_INSTALL_ID });
    const res = await H.endSession(app, phone.body.access_token, tablet.body.session.id);
    expect(res.status).toBe(204);
    expect(res.text).toBe('');
    expect(H.familyRows(db, tablet.body.session.id)[0]).toMatchObject({ revoked_reason: 'signed_out', revoked_at: NOW.toISOString() });
    expectRefusal(await H.me(app, tablet.body.access_token), 401, 'NOT_AUTHENTICATED');
    expect((await H.refresh(app, tablet.body.refresh_token, OTHER_INSTALL_ID)).body.reason).toBe('signed_out');
    // The one I am using carries on.
    expect((await H.me(app, phone.body.access_token)).status).toBe(200);
  });

  it('ends the one I am using, too', async () => {
    const { app, people } = buildApp();
    const kept = await H.keep(app, tokens.attendance(people.attendance));
    expect((await H.endSession(app, kept.body.access_token, kept.body.session.id)).status).toBe(204);
    expectRefusal(await H.me(app, kept.body.access_token), 401, 'NOT_AUTHENTICATED');
  });

  it('answers 404, never 403, for somebody else\'s, and leaves it alone', async () => {
    const { app, db, people } = buildApp();
    const mine = await H.keep(app, tokens.portal(people.hr));
    const theirs = await H.keep(app, tokens.portal(people.ceo));
    const res = await H.endSession(app, mine.body.access_token, theirs.body.session.id);
    expectRefusal(res, 404, 'NOT_FOUND');
    expect(H.liveRows(db, theirs.body.session.id)).toHaveLength(1);
    expect((await H.me(app, theirs.body.access_token)).status).toBe(200);
  });

  it('answers the same 404 for an id that does not exist, one that is not an id, and one already ended', async () => {
    const { app, people } = buildApp();
    const mine = await H.keep(app, nthSignIn(people.hr, 0));
    const other = await H.keep(app, nthSignIn(people.hr, 1), { install_id: OTHER_INSTALL_ID });
    await H.endSession(app, mine.body.access_token, other.body.session.id);
    const answers = [];
    for (const id of ['5a000000-0000-4000-8000-000000000999', 'not-an-id', '1', other.body.session.id]) {
      const res = await H.endSession(app, mine.body.access_token, id);
      expectRefusal(res, 404, 'NOT_FOUND');
      answers.push(res.body);
    }
    expect(new Set(answers.map((a) => JSON.stringify(a))).size).toBe(1);
  });

  it('takes an id in capitals as the same id', async () => {
    const { app, people } = buildApp();
    const kept = await H.keep(app, tokens.portal(people.hr));
    expect((await H.endSession(app, tokens.portal(people.hr), kept.body.session.id.toUpperCase())).status).toBe(204);
  });

  it('answers only staff, and 503 when the database is away', async () => {
    quiet();
    const { app, db, people } = buildApp();
    const kept = await H.keep(app, tokens.portal(people.hr));
    expectRefusal(await H.endSession(app, tokens.student(), kept.body.session.id), 403, 'NOT_AN_EMPLOYEE');
    db.failWhen = (q) => (q.op === 'rpc' ? 'error' : null);
    expectRefusal(await H.endSession(app, tokens.portal(people.hr), kept.body.session.id), 503, 'UNAVAILABLE');
    expect(H.liveRows(db, kept.body.session.id)).toHaveLength(1);
  });
});

describe('POST /api/ess/session/sign-out', () => {
  it('with the access token ends its sign-in: 204, and none of its tokens works again', async () => {
    const { app, db, people } = buildApp();
    const kept = await H.keep(app, tokens.portal(people.hr));
    const res = await H.signOut(app, { token: kept.body.access_token });
    expect(res.status).toBe(204);
    expect(res.text).toBe('');
    expect(H.familyRows(db, kept.body.session.id)[0]).toMatchObject({ revoked_reason: 'signed_out' });
    expectRefusal(await H.me(app, kept.body.access_token), 401, 'NOT_AUTHENTICATED');
    const again = await H.refresh(app, kept.body.refresh_token);
    expectRefusal(again, 401, 'NOT_AUTHENTICATED');
    expect(again.body.reason).toBe('signed_out');
  });

  it('with the refresh token ends its sign-in with no bearer at all, as after the access token has run out', async () => {
    const clock = H.clockAt(NOW);
    const { app, db, people } = buildApp({ now: clock.now });
    const kept = await H.keep(app, tokens.attendance(people.attendance));
    clock.advance(2 * HOUR);
    expectRefusal(await H.me(app, kept.body.access_token), 401, 'NOT_AUTHENTICATED');
    const res = await request(app).post('/api/ess/session/sign-out').set(bearer(kept.body.access_token)).send({ refresh_token: kept.body.refresh_token });
    expect(res.status).toBe(204);
    expect(H.liveRows(db, kept.body.session.id)).toHaveLength(0);
  });

  it('with a refresh token already traded in still ends the sign-in it belongs to', async () => {
    const clock = H.clockAt(NOW);
    const { app, db, people } = buildApp({ now: clock.now });
    const kept = await H.keep(app, tokens.portal(people.hr));
    clock.advance(HOUR);
    const refreshed = await H.refresh(app, kept.body.refresh_token);
    expect((await H.signOut(app, { refreshToken: kept.body.refresh_token })).status).toBe(204);
    expect(H.liveRows(db, kept.body.session.id)).toHaveLength(0);
    expect((await H.refresh(app, refreshed.body.refresh_token)).body.reason).toBe('signed_out');
  });

  it('answers 204 for a refresh token it does not know, and ends nothing', async () => {
    const { app, db, people } = buildApp();
    const kept = await H.keep(app, tokens.portal(people.hr));
    for (const refreshToken of ['A'.repeat(43), 'short', 42, '']) {
      expect((await H.signOut(app, { refreshToken })).status).toBe(204);
    }
    expect(H.liveRows(db, kept.body.session.id)).toHaveLength(1);
  });

  it('with a token the Scheduler issued answers 204 and ends nothing: the ESS cannot end those', async () => {
    const { app, db, people } = buildApp();
    const kept = await H.keep(app, tokens.portal(people.hr));
    expect((await H.signOut(app, { token: tokens.portal(people.hr) })).status).toBe(204);
    expect(H.liveRows(db, kept.body.session.id)).toHaveLength(1);
  });

  it('ends only the caller\'s own sign-in', async () => {
    const { app, db, people } = buildApp();
    const mine = await H.keep(app, tokens.portal(people.hr));
    const theirs = await H.keep(app, tokens.portal(people.ceo));
    await H.signOut(app, { token: mine.body.access_token });
    expect(H.liveRows(db, theirs.body.session.id)).toHaveLength(1);
  });

  it('with neither token is 401', async () => {
    const { app } = buildApp();
    expectRefusal(await H.signOut(app), 401, 'NOT_AUTHENTICATED');
    expectRefusal(await H.signOut(app, { token: 'forged.token.here' }), 401, 'NOT_AUTHENTICATED');
  });

  it('answers 503 and claims nothing when the sign-in cannot be ended', async () => {
    quiet();
    const { app, db, people } = buildApp();
    const kept = await H.keep(app, tokens.portal(people.hr));
    db.failWhen = (q) => (q.op === 'rpc' ? 'error' : null);
    expectRefusal(await H.signOut(app, { token: kept.body.access_token }), 503, 'UNAVAILABLE');
    expectRefusal(await H.signOut(app, { refreshToken: kept.body.refresh_token }), 503, 'UNAVAILABLE');
    expect(H.liveRows(db, kept.body.session.id)).toHaveLength(1);
  });

  it('shares the strict per-address limit with refresh: 429 RATE_LIMITED', async () => {
    const { app } = buildApp({ limits: { sessionPerIp: { windowMs: 60 * 1000, limit: 2 } } });
    await H.signOut(app, { refreshToken: 'A'.repeat(43) });
    await H.refresh(app, 'A'.repeat(43));
    expectRefusal(await H.signOut(app, { refreshToken: 'A'.repeat(43) }), 429, 'RATE_LIMITED');
  });
});
