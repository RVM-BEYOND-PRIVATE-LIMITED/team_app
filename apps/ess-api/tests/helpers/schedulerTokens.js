const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { SEES_ALL_LOCATIONS, TEACHING_ROLES } = require('../../src/policy/roles');

/**
 * The Scheduler's own token code, copied verbatim from Scheduler_Backend at c28b9ca, so the
 * tests sign tokens exactly as production does and can read them back the way the Scheduler
 * does. If the ESS's reading (src/lib/tokens.js) drifts from the Scheduler's signing, the tests
 * fail.
 *
 * Each copied block sits between a `// <scheduler file=... lines=...>` line and a
 * `// </scheduler>` line. tests/schedulerCopies.test.js checks every block against a Scheduler
 * checkout whenever SCHEDULER_BACKEND_DIR is set, so a copy cannot go stale unnoticed. Do not
 * edit inside a block; copy the Scheduler's new lines over it instead.
 *
 * The copied lines read process.env.JWT_SECRET; tests/setup.js sets it to the test secret.
 */

/* ── the attendance session ── */

// <scheduler file="services/attendancePunch.js" lines="205-239">
const PUNCH_SESSION_DAYS = 30;
const PUNCH_AUDIENCE = 'rvm-punch';
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const punchSessionKey = () => {
  const secret = process.env.JWT_SECRET;
  if (!secret) throw new Error('JWT_SECRET is not set');
  return crypto.createHash('sha256').update(`rvm-punch-session:${secret}`).digest('hex');
};

/**
 * `method` says how the session was earned: 'otp' (a code to the main phone or email) or 'pw'
 * (the password). Only a FRESH 'otp' session may set a password -- see PASSWORD_SET_WINDOW_MS --
 * so a stolen password session can never quietly change the password it was stolen with.
 */
function issuePunchSession(employeeId, method = 'otp') {
  return jwt.sign({ k: 'punch', e: employeeId, m: method === 'pw' ? 'pw' : 'otp' }, punchSessionKey(), {
    algorithm: 'HS256', audience: PUNCH_AUDIENCE, expiresIn: `${PUNCH_SESSION_DAYS}d`,
  });
}

/**
 * What a punch-only token carries -- { employeeId, method, issuedAt (ms) } -- or null for
 * anything else, a portal token included.
 */
function readPunchSession(token) {
  if (!token) return null;
  try {
    const p = jwt.verify(token, punchSessionKey(), { algorithms: ['HS256'], audience: PUNCH_AUDIENCE });
    if (!(p && p.k === 'punch' && typeof p.e === 'string' && UUID_RE.test(p.e))) return null;
    return { employeeId: p.e, method: p.m === 'pw' ? 'pw' : 'otp', issuedAt: (Number(p.iat) || 0) * 1000 };
  } catch {
    return null;
  }
}
// </scheduler>

/* ── the portal token ── */

/** POST /api/users/login's token. `user` is a users row; `locationName` is the branch typed at sign-in. */
function portalLoginToken(user, locationName) {
  // <scheduler file="controllers/userController.js" lines="498-512">
  let tokenPayload = {
    userId: user.id,
    role: user.role,
    locationId: user.location_id,
    username: user.username,
    locationName: locationName,
    isSuperAdmin: SEES_ALL_LOCATIONS.has(user.role)
  };

  // Teaching roles carry faculty_id as `id`; auth resolves them by it. A HOD is
  // promoted from faculty and keeps teaching, so it must be set for them too —
  // without this the promoted user drops off their batches, schedule and attendance.
  if (TEACHING_ROLES.has(user.role)) tokenPayload.id = user.faculty_id;

  const token = jwt.sign(tokenPayload, process.env.JWT_SECRET, { expiresIn: "64h" });
  // </scheduler>
  return token;
}

/** The token POST /api/users/login/verify issues after a two-factor code. */
// <scheduler file="controllers/authSecurityController.js" lines="19-31">
/** The same payload login() signs, built the same way. Kept here so the two cannot drift. */
const tokenFor = (user, locationName) => {
  const payload = {
    userId: user.id,
    role: user.role,
    locationId: user.location_id,
    username: user.username,
    locationName,
    isSuperAdmin: SEES_ALL_LOCATIONS.has(user.role),
  };
  if (TEACHING_ROLES.has(user.role)) payload.id = user.faculty_id;
  return jwt.sign(payload, process.env.JWT_SECRET, { expiresIn: '64h' });
};
// </scheduler>

/* ── tokens the ESS must refuse ── */

/** POST /api/users/student-login's token. `student` is a students row. */
function studentToken(student) {
  // <scheduler file="controllers/userController.js" lines="797-801">
  const token = jwt.sign(
    { id: student.id, role: 'student', name: student.name, location_id: student.location_id },
    process.env.JWT_SECRET,
    { expiresIn: '7d' }
  );
  // </scheduler>
  return token;
}

// <scheduler file="utils/admissionUndertakingToken.js" lines="3-13">
const ISSUER = 'rvmcad-admission-undertaking';
const TTL_SECONDS = 30 * 60;

const issueAdmissionUndertakingToken = ({ admissionId, phoneNumber }) => {
  if (!process.env.JWT_SECRET) throw new Error('JWT_SECRET is not set; undertaking tokens cannot be issued');
  return jwt.sign(
    { scope: 'admission_undertaking', admission_id: String(admissionId), phone_number: phoneNumber },
    process.env.JWT_SECRET,
    { issuer: ISSUER, expiresIn: TTL_SECONDS },
  );
};
// </scheduler>

/* ── the clock ── */

/**
 * Runs a signer with the system clock set to `when`, so a token's iat and exp are known.
 * jsonwebtoken reads Date.now() for both, and the copied code above cannot take a clock.
 */
function signedAt(when, sign) {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(when);
  try {
    return sign();
  } finally {
    vi.useRealTimers();
  }
}

module.exports = {
  PUNCH_SESSION_DAYS,
  punchSessionKey,
  issuePunchSession,
  readPunchSession,
  portalLoginToken,
  tokenFor,
  studentToken,
  issueAdmissionUndertakingToken,
  signedAt,
};
