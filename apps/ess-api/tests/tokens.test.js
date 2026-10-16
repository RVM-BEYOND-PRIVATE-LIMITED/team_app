const jwt = require('jsonwebtoken');
const { readToken, readAttendanceSession, attendanceSessionKey, bearerToken, ATTENDANCE_AUDIENCE } = require('../src/lib/tokens');
const S = require('./helpers/schedulerTokens');
const { company, STUDENT_ID } = require('./helpers/fixtures');
const { TEST_JWT_SECRET } = require('./helpers/constants');

/**
 * lib/tokens.js against tokens made by the Scheduler's own code (tests/helpers/schedulerTokens.js),
 * and against the Scheduler's own reader of the attendance session.
 */

const { people } = company();
const at = new Date('2026-10-16T05:00:00.000Z');
const nowMs = at.getTime() + 60 * 1000;
const read = (token, ms = nowMs) => readToken(token, { jwtSecret: TEST_JWT_SECRET, nowMs: ms });
const signed = (fn) => S.signedAt(at, fn);

describe('the attendance session', () => {
  it('is signed with the same derived key as the Scheduler\'s', () => {
    expect(attendanceSessionKey(TEST_JWT_SECRET)).toBe(S.punchSessionKey());
    expect(attendanceSessionKey(TEST_JWT_SECRET)).not.toBe(TEST_JWT_SECRET);
    expect(ATTENDANCE_AUDIENCE).toBe('rvm-punch');
  });

  it.each(['otp', 'pw'])('earned by %s reads back as the employee it names', (method) => {
    const token = signed(() => S.issuePunchSession(people.attendance.employee.id, method));
    expect(read(token)).toEqual({ kind: 'attendance', employeeId: people.attendance.employee.id, method, issuedAt: at.getTime() });
  });

  it('is read exactly as the Scheduler\'s readPunchSession reads it', () => {
    const emp = people.attendance.employee.id;
    const now = Date.now();
    const samples = [
      S.issuePunchSession(emp),
      S.issuePunchSession(emp, 'pw'),
      S.portalLoginToken(people.hr.user, 'Faridabad'),
      jwt.sign({ k: 'punch', e: emp }, TEST_JWT_SECRET, { audience: 'rvm-punch' }),
      jwt.sign({ k: 'punch', e: emp, m: 'otp' }, S.punchSessionKey(), { audience: 'someone-else' }),
      jwt.sign({ k: 'punch', e: 'not-a-uuid' }, S.punchSessionKey(), { audience: 'rvm-punch' }),
      jwt.sign({ k: 'other', e: emp }, S.punchSessionKey(), { audience: 'rvm-punch' }),
      jwt.sign({ k: 'punch', e: emp }, S.punchSessionKey(), { audience: 'rvm-punch', algorithm: 'HS512' }),
      S.signedAt(new Date(now - 31 * 86400 * 1000), () => S.issuePunchSession(emp)),
      'garbage',
      '',
    ];
    for (const token of samples) {
      expect(readAttendanceSession(token, { jwtSecret: TEST_JWT_SECRET, nowMs: now })).toEqual(S.readPunchSession(token));
    }
  });

  it('expires after 30 days', () => {
    const token = signed(() => S.issuePunchSession(people.attendance.employee.id));
    const thirtyDays = 30 * 86400 * 1000;
    expect(read(token, at.getTime() + thirtyDays - 1000).kind).toBe('attendance');
    expect(read(token, at.getTime() + thirtyDays + 1000)).toEqual({ kind: 'rejected', reason: 'invalid' });
  });
});

describe('the portal token', () => {
  it('from sign-in reads back with its account, role and no faculty id for a non-teaching role', () => {
    const token = signed(() => S.portalLoginToken(people.hr.user, 'Faridabad'));
    expect(read(token)).toEqual({ kind: 'portal', userId: people.hr.user.id, role: 'hr', facultyId: null, issuedAt: at.getTime() });
  });

  it.each(['faculty', 'hod'])('for a %s carries the faculty id auth.js resolves it by', (who) => {
    const token = signed(() => S.portalLoginToken(people[who].user, 'Faridabad'));
    expect(read(token)).toMatchObject({ kind: 'portal', role: who, facultyId: people[who].user.faculty_id });
  });

  it('from a two-factor sign-in reads back the same', () => {
    const viaLogin = read(signed(() => S.portalLoginToken(people.ceo.user, 'Pune')));
    const viaCode = read(signed(() => S.tokenFor(people.ceo.user, 'Pune')));
    expect(viaCode).toEqual(viaLogin);
  });

  it('expires after 64 hours', () => {
    const token = signed(() => S.portalLoginToken(people.hr.user, 'Faridabad'));
    const sixtyFour = 64 * 3600 * 1000;
    expect(read(token, at.getTime() + sixtyFour - 1000).kind).toBe('portal');
    expect(read(token, at.getTime() + sixtyFour + 1000)).toEqual({ kind: 'rejected', reason: 'expired' });
  });

  it('is pinned to HS256', () => {
    const payload = { userId: people.hr.user.id, role: 'hr' };
    for (const algorithm of ['HS384', 'HS512']) {
      expect(read(jwt.sign(payload, TEST_JWT_SECRET, { algorithm }))).toEqual({ kind: 'rejected', reason: 'invalid' });
    }
    expect(read(jwt.sign(payload, null, { algorithm: 'none' }))).toEqual({ kind: 'rejected', reason: 'invalid' });
    expect(read(jwt.sign(payload, TEST_JWT_SECRET, { algorithm: 'HS256' })).kind).toBe('portal');
  });

  it('signed with another secret is rejected', () => {
    expect(read(jwt.sign({ userId: people.hr.user.id, role: 'hr' }, `${TEST_JWT_SECRET}x`))).toEqual({ kind: 'rejected', reason: 'invalid' });
  });

  it('that is no token at all is rejected', () => {
    for (const token of ['', 'abc', 'a.b.c', `${'x'.repeat(30)}.${'y'.repeat(30)}.${'z'.repeat(30)}`]) {
      expect(read(token)).toEqual({ kind: 'rejected', reason: 'invalid' });
    }
  });
});

describe('other tokens signed with JWT_SECRET', () => {
  it('a student token is not a staff login', () => {
    expect(read(signed(() => S.studentToken({ id: STUDENT_ID, name: 'Test Student', location_id: 1 })))).toEqual({ kind: 'not_staff' });
  });

  it('an admission-undertaking token is not a staff login', () => {
    expect(read(signed(() => S.issueAdmissionUndertakingToken({ admissionId: 7, phoneNumber: '9876500000' })))).toEqual({ kind: 'not_staff' });
  });

  it('a look-alike attendance session signed with JWT_SECRET is neither an attendance session nor a portal token', () => {
    const token = jwt.sign({ k: 'punch', e: people.attendance.employee.id, m: 'otp' }, TEST_JWT_SECRET, { audience: 'rvm-punch' });
    expect(read(token)).toEqual({ kind: 'not_staff' });
  });

  it.each([
    ['a scope', { scope: 'anything' }],
    ['an issuer', { iss: 'someone' }],
    ['an audience', { aud: 'someone' }],
    ['a punch kind', { k: 'punch' }],
    ['the student role', { role: 'student' }],
    ['no userId', { userId: undefined }],
    ['a userId that is not a UUID', { userId: '42' }],
    ['a userId that is a number', { userId: 42 }],
  ])('a payload with %s is not a staff login', (_label, change) => {
    const payload = { userId: people.hr.user.id, role: 'hr', ...change };
    expect(read(jwt.sign(payload, TEST_JWT_SECRET))).toEqual({ kind: 'not_staff' });
  });

  it('a string payload is not a staff login', () => {
    expect(read(jwt.sign('just a string', TEST_JWT_SECRET))).toEqual({ kind: 'not_staff' });
  });
});

describe('bearerToken', () => {
  it('takes the token after "Bearer ", exactly as the Scheduler strips it', () => {
    expect(bearerToken('Bearer abc.def.ghi')).toBe('abc.def.ghi');
  });

  it.each([
    [undefined], [null], [''], ['Bearer'], ['Bearer '], ['bearer abc'], ['BEARER abc'], ['Basic abc'],
    ['Bearer abc def'], ['Bearer  abc'], ['Token Bearer abc'], [['Bearer abc']],
  ])('finds no token in %j', (header) => {
    expect(bearerToken(header)).toBeNull();
  });
});
