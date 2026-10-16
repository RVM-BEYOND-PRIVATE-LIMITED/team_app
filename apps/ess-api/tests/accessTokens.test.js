const jwt = require('jsonwebtoken');
const T = require('../src/lib/accessTokens');
const { readToken } = require('../src/lib/tokens');
const { ACCESS_TOKEN_SECONDS } = require('../src/policy/sessions');
const S = require('./helpers/schedulerTokens');
const G = require('./helpers/schedulerGuards');
const Rules = require('./helpers/schedulerRules');
const { company, PORTAL_PEOPLE } = require('./helpers/fixtures');
const { TEST_JWT_SECRET } = require('./helpers/constants');

/**
 * lib/accessTokens.js against the Scheduler's own code (tests/helpers/schedulerGuards.js and
 * schedulerTokens.js): what the Scheduler does with a token the ESS minted for a kept sign-in.
 *
 * The copied Scheduler code reads the real clock, so these tokens are minted against it too.
 */

const MINUTE = 60 * 1000;
const HOUR = 60 * MINUTE;
const SID = '5a000000-0000-4000-8000-0000000000aa';
const jwtSecret = TEST_JWT_SECRET;

const { people } = company();
const users = Object.values(people).map((p) => p.user).filter(Boolean);
const EMPLOYEE = people.attendance.employee.id;

/** A token's claims less the three that differ by design between a sign-in and a mint. */
function signedClaims(token) {
  const claims = { ...jwt.decode(token) };
  delete claims.iat;
  delete claims.exp;
  delete claims.sid;
  return claims;
}

const mintPortal = (user, { signedInAgo = 20 * MINUTE, mintedAgo = 0, locationName = 'Faridabad' } = {}) => {
  const nowMs = Date.now() - mintedAgo;
  return T.mintPortalToken({ user, locationName, sessionId: SID, signedInAtMs: Date.now() - signedInAgo, nowMs, jwtSecret });
};

const mintAttendance = (method, { signedInAgo = 20 * MINUTE, mintedAgo = 0, employeeId = EMPLOYEE } = {}) =>
  T.mintAttendanceToken({ employeeId, method, sessionId: SID, signedInAtMs: Date.now() - signedInAgo, nowMs: Date.now() - mintedAgo, jwtSecret });

beforeEach(() => {
  G.useRows({ users });
  // The Scheduler logs every refused token; the refusals here are on purpose.
  vi.spyOn(console, 'error').mockImplementation(() => {});
});

describe('a minted portal token', () => {
  it.each(PORTAL_PEOPLE.map(([key]) => [key]))('for %s carries exactly the claims the Scheduler signs at sign-in, plus sid', (key) => {
    const { user } = people[key];
    expect(signedClaims(mintPortal(user))).toEqual(signedClaims(S.portalLoginToken(user, 'Faridabad')));
    expect(signedClaims(mintPortal(user, { locationName: null }))).toEqual(signedClaims(S.tokenFor(user, null)));
  });

  it('keeps the original sign-in as its iat and lasts an hour from the mint', () => {
    const signedInAtMs = Date.parse('2026-09-01T10:00:00.400Z');
    const nowMs = Date.parse('2026-10-16T06:30:00.700Z');
    const token = T.mintPortalToken({ user: people.hr.user, locationName: 'Pune', sessionId: SID, signedInAtMs, nowMs, jwtSecret });
    expect(jwt.decode(token)).toMatchObject({ sid: SID, iat: Math.floor(signedInAtMs / 1000), exp: Math.floor(nowMs / 1000) + 3600 });
    expect(ACCESS_TOKEN_SECONDS).toBe(3600);
  });

  it('is HS256 with no audience or issuer, as the Scheduler signs it', () => {
    const token = mintPortal(people.hr.user);
    expect(jwt.decode(token, { complete: true }).header).toEqual({ alg: 'HS256', typ: 'JWT' });
    expect(jwt.decode(token)).not.toHaveProperty('aud');
    expect(jwt.decode(token)).not.toHaveProperty('iss');
  });

  it.each(PORTAL_PEOPLE.map(([key]) => [key]))('for %s is let in by auth.js as the same account a real sign-in gives', async (key) => {
    const { user } = people[key];
    const view = (r) => ({
      passed: r.passed,
      user: r.req.user,
      userType: r.req.userType,
      roles: r.req.roleSet ? [...r.req.roleSet].sort() : null,
      isSuperAdmin: r.req.isSuperAdmin,
      isCEO: r.req.isCEO,
      isAccountsAdmin: r.req.isAccountsAdmin,
      locationId: r.req.locationId,
    });
    const real = view(await G.runAuth(S.portalLoginToken(user, 'Faridabad')));
    expect(real.passed).toBe(true);
    expect(view(await G.runAuth(mintPortal(user)))).toEqual(real);
  });

  it('for a teaching role is found by its faculty id, as auth.js finds a teacher', async () => {
    const r = await G.runAuth(mintPortal(people.hod.user));
    expect(r.passed).toBe(true);
    expect(r.req.user.id).toBe(people.hod.user.id);
    expect(jwt.decode(mintPortal(people.hod.user)).id).toBe(people.hod.user.faculty_id);
  });

  it('is refused by auth.js once its hour is over, whenever the sign-in was', async () => {
    const r = await G.runAuth(mintPortal(people.hr.user, { mintedAgo: HOUR + MINUTE }));
    expect(r).toMatchObject({ passed: false, status: 401, body: { error: 'Please authenticate' } });
  });

  it('is not an attendance session to the Scheduler', () => {
    expect(S.readPunchSession(mintPortal(people.hr.user))).toBeNull();
  });

  it('is read by the ESS as the portal login and the session it was minted for', () => {
    const signedInAtMs = Date.now() - 20 * MINUTE;
    const token = T.mintPortalToken({ user: people.hr.user, locationName: 'Faridabad', sessionId: SID, signedInAtMs, nowMs: Date.now(), jwtSecret });
    expect(readToken(token, { jwtSecret, nowMs: Date.now() })).toEqual({
      kind: 'portal', userId: people.hr.user.id, role: 'hr', facultyId: null, locationName: 'Faridabad',
      issuedAt: Math.floor(signedInAtMs / 1000) * 1000, sessionId: SID,
    });
  });
});

describe('a minted attendance session', () => {
  it.each(['otp', 'pw'])('earned by %s is read by readPunchSession as the original sign-in, at its original time', (method) => {
    const signedInAtMs = Date.now() - 20 * MINUTE;
    const token = T.mintAttendanceToken({ employeeId: EMPLOYEE, method, sessionId: SID, signedInAtMs, nowMs: Date.now(), jwtSecret });
    expect(S.readPunchSession(token)).toEqual({ employeeId: EMPLOYEE, method, issuedAt: Math.floor(signedInAtMs / 1000) * 1000 });
  });

  it('carries the claims issuePunchSession signs, plus sid, under the same key and audience', () => {
    const minted = mintAttendance('otp');
    const real = S.issuePunchSession(EMPLOYEE, 'otp');
    expect(signedClaims(minted)).toEqual(signedClaims(real));
    expect(() => jwt.verify(minted, S.punchSessionKey(), { algorithms: ['HS256'], audience: 'rvm-punch' })).not.toThrow();
    expect(jwt.decode(minted, { complete: true }).header).toEqual({ alg: 'HS256', typ: 'JWT' });
  });

  it('is taken by punchAuth as an attendance session, with no portal account', async () => {
    const signedInAtMs = Date.now() - 20 * MINUTE;
    const token = T.mintAttendanceToken({ employeeId: EMPLOYEE, method: 'otp', sessionId: SID, signedInAtMs, nowMs: Date.now(), jwtSecret });
    const r = await G.runPunchAuth(token);
    expect(r.passed).toBe(true);
    expect(r.req.user).toBeNull();
    expect(r.req.punchEmployeeId).toBe(EMPLOYEE);
    expect(r.req.punchSession).toEqual({ employeeId: EMPLOYEE, method: 'otp', issuedAt: Math.floor(signedInAtMs / 1000) * 1000 });
  });

  it('is refused everywhere else on the Scheduler, as its own attendance sessions are', async () => {
    const r = await G.runAuth(mintAttendance('otp'));
    expect(r).toMatchObject({ passed: false, status: 401, body: { error: 'Please authenticate' } });
  });

  it('is over once its hour is', () => {
    expect(S.readPunchSession(mintAttendance('otp', { mintedAgo: HOUR + MINUTE }))).toBeNull();
    expect(S.readPunchSession(mintAttendance('otp', { mintedAgo: HOUR - MINUTE }))).not.toBeNull();
  });
});

describe('the Scheduler\'s 15-minute window to set the attendance password', () => {
  // POST /hr/my-attendance/password, guarded by punchAuth and then this gate
  // (attendanceOtpController.js:341-354): a code sign-in may set the password for 15 minutes
  // after its iat.
  const gate = async (token) => {
    const { req } = await G.runPunchAuth(token);
    return G.setPasswordGate(req).then(() => 'allowed', (e) => e.code);
  };

  beforeEach(() => {
    G.useAttendanceAccount({
      employee_id: EMPLOYEE, status: 'active', password_hash: '$2b$10$fixture.attendance.hash.never.returned', password_set_at: '2026-10-02T04:00:00+00:00',
    });
  });

  it('is 15 minutes, as the copy says', () => {
    expect(G.PASSWORD_SET_WINDOW_MS).toBe(15 * MINUTE);
  });

  it('stays open to a minted code token inside the 15 minutes, as to the sign-in it came from', async () => {
    const original = S.signedAt(new Date(Date.now() - 5 * MINUTE), () => S.issuePunchSession(EMPLOYEE, 'otp'));
    expect(await gate(original)).toBe('allowed');
    expect(await gate(mintAttendance('otp', { signedInAgo: 5 * MINUTE }))).toBe('allowed');
  });

  it('is closed to a minted code token 15 minutes after the original sign-in, however new the token', async () => {
    const original = S.signedAt(new Date(Date.now() - 16 * MINUTE), () => S.issuePunchSession(EMPLOYEE, 'otp'));
    expect(await gate(original)).toBe('CODE_REQUIRED');
    // Minted this very moment, at a refresh, from a sign-in made 16 minutes ago.
    expect(await gate(mintAttendance('otp', { signedInAgo: 16 * MINUTE, mintedAgo: 0 }))).toBe('CODE_REQUIRED');
    // And days later.
    expect(await gate(mintAttendance('otp', { signedInAgo: 30 * 24 * HOUR }))).toBe('CODE_REQUIRED');
  });

  it('would be open if a minted token carried the moment it was minted, which is why none does', async () => {
    // What a naive refresh would sign: the same claims with a fresh iat. Every refresh would open
    // a new 15-minute window to change the password with no code typed.
    const naive = jwt.sign({ k: 'punch', e: EMPLOYEE, m: 'otp' }, S.punchSessionKey(), { algorithm: 'HS256', audience: 'rvm-punch', expiresIn: '1h' });
    expect(await gate(naive)).toBe('allowed');
    expect(await gate(mintAttendance('otp', { signedInAgo: 16 * MINUTE }))).toBe('CODE_REQUIRED');
  });

  it('is closed to a minted password token, as to the password sign-in it came from', async () => {
    expect(await gate(mintAttendance('pw', { signedInAgo: MINUTE }))).toBe('CODE_REQUIRED');
  });
});

describe('a password change after the sign-in', () => {
  const signedInAgo = 3 * HOUR;

  it('ends every attendance token minted from that sign-in on the Scheduler (sessions_valid_from)', () => {
    const changedAt = new Date(Date.now() - signedInAgo + HOUR).toISOString();
    // One token from each refresh of the last hour.
    for (const mintedAgo of [50 * MINUTE, 30 * MINUTE, 10 * MINUTE, 0]) {
      const session = S.readPunchSession(mintAttendance('otp', { signedInAgo, mintedAgo }));
      expect(session).not.toBeNull();
      expect(Rules.sessionProblem(session, { status: 'active', sessions_valid_from: changedAt }))
        .toEqual({ status: 401, code: 'NOT_AUTHENTICATED', message: 'Your password was changed. Please sign in again.' });
    }
  });

  it('made before the sign-in leaves them working', () => {
    const changedAt = new Date(Date.now() - signedInAgo - HOUR).toISOString();
    const session = S.readPunchSession(mintAttendance('pw', { signedInAgo }));
    expect(Rules.sessionProblem(session, { status: 'active', sessions_valid_from: changedAt })).toBeNull();
  });

  it('in the same second as the sign-in leaves them working, as the Scheduler counts whole seconds', () => {
    const signedInAtMs = Math.floor((Date.now() - signedInAgo) / 1000) * 1000;
    const token = T.mintAttendanceToken({ employeeId: EMPLOYEE, method: 'pw', sessionId: SID, signedInAtMs, nowMs: Date.now(), jwtSecret });
    const sameSecond = new Date(signedInAtMs + 999).toISOString();
    expect(Rules.sessionProblem(S.readPunchSession(token), { status: 'active', sessions_valid_from: sameSecond })).toBeNull();
  });
});

describe('the refresh token', () => {
  it('is 32 random bytes in base64url, and never twice the same', () => {
    const seen = new Set();
    for (let i = 0; i < 200; i++) {
      const token = T.newRefreshToken();
      expect(token).toMatch(/^[A-Za-z0-9_-]{43}$/);
      expect(Buffer.from(token, 'base64url')).toHaveLength(32);
      seen.add(token);
    }
    expect(seen.size).toBe(200);
  });

  it('is kept only as a sha256 HMAC, keyed from JWT_SECRET but never with it', () => {
    const crypto = require('crypto');
    const token = T.newRefreshToken();
    const hash = T.refreshTokenHash(token, jwtSecret);
    expect(hash).toMatch(/^[0-9a-f]{64}$/);
    expect(T.refreshTokenHash(token, jwtSecret)).toBe(hash);
    expect(hash).not.toContain(token);
    expect(T.refreshTokenHash(T.newRefreshToken(), jwtSecret)).not.toBe(hash);
    // Neither a bare sha256 nor an HMAC under the secret itself.
    expect(hash).not.toBe(crypto.createHash('sha256').update(token).digest('hex'));
    expect(hash).not.toBe(crypto.createHmac('sha256', jwtSecret).update(token).digest('hex'));
  });

  it('hashes differently under another JWT_SECRET, so rotating the secret ends every kept sign-in', () => {
    const token = T.newRefreshToken();
    expect(T.refreshTokenHash(token, `${jwtSecret}-rotated`)).not.toBe(T.refreshTokenHash(token, jwtSecret));
  });
});
