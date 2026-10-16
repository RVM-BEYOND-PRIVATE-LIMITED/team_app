const jwt = require('jsonwebtoken');
const { ROLES, expandRoles, SEES_ALL_LOCATIONS, TEACHING_ROLES } = require('../../src/policy/roles');
const { readPunchSession } = require('./schedulerTokens');

/**
 * The Scheduler's own guards, copied verbatim from Scheduler_Backend at c28b9ca, so the tests can
 * hand them a token the ESS minted (src/lib/accessTokens.js) and see what the Scheduler does with
 * it: middleware/auth.js on every portal route, middleware/punchAuth.js on /hr/my-attendance, and
 * the gate in front of POST /hr/my-attendance/password.
 *
 * Blocks are marked as in schedulerTokens.js and checked by tests/schedulerCopies.test.js
 * whenever SCHEDULER_BACKEND_DIR is set. The copied lines use `supabase`, `Accounts` and
 * `refuse`; the stand-ins below give them the rows a test chooses.
 */

/* ── stand-ins for what the copied lines reach ── */

let usersTable = [];
let studentsTable = [];
let attendanceAccount = null;

/** supabase.from(t).select('*').eq(c, v).single(), the only shape auth.js uses. */
const supabase = {
  from(table) {
    const rows = table === 'users' ? usersTable : table === 'students' ? studentsTable : [];
    const filters = [];
    const query = {
      select: () => query,
      eq: (column, value) => {
        filters.push([column, value]);
        return query;
      },
      single: async () => {
        const hit = rows.filter((r) => filters.every(([c, v]) => r[c] === v));
        return hit.length === 1
          ? { data: { ...hit[0] }, error: null }
          : { data: null, error: { code: 'PGRST116', message: 'JSON object requested, multiple (or no) rows returned' } };
      },
    };
    return query;
  },
};

const Accounts = { getAccount: async () => attendanceAccount };

/* ── the copies ── */

// <scheduler file="middleware/auth.js" lines="6-106">
const auth = async (req, res, next) => {
  try {
    const token = req.header('Authorization')?.replace('Bearer ', '');

    if (!token) {
      return res.status(401).json({ error: 'No token provided' });
    }

    const decoded = jwt.verify(token, process.env.JWT_SECRET);

    // ---------------------------------------------------------
    // 1. CHECK IF TOKEN BELONGS TO A STUDENT
    // ---------------------------------------------------------
    if (decoded.role === 'student') {
      const { data: student, error } = await supabase
        .from('students')
        .select('*')
        .eq('id', decoded.id)
        .single();

      if (error || !student) {
        throw new Error('Student not found');
      }

      // Students are never super_admins
      student.role = 'student';

      req.user = student;
      req.userType = 'student';
      req.roleSet = expandRoles('student');
      req.hasRole = (role) => req.roleSet.has(role);
      req.isSuperAdmin = false;
      req.isCEO = false;
      req.isAccountsAdmin = false;
      req.locationId = student.location_id;

      return next();
    }

    // ---------------------------------------------------------
    // 2. CHECK IF TOKEN BELONGS TO FACULTY / ADMIN / STAFF / SUPER_ADMIN
    // ---------------------------------------------------------
    let userQuery;

    if (TEACHING_ROLES.has(decoded.role) && decoded.id) {
      // Teaching roles (faculty, hod) carry their faculty_id as `id` in the token.
      // A HOD is promoted from faculty and keeps teaching, so it resolves the same way.
      userQuery = supabase
        .from('users')
        .select('*')
        .eq('faculty_id', decoded.id)
        .single();
    } else {
      // Non-teaching, OR a teaching account with no faculty_id linked yet
      const userId = decoded.userId || decoded.id;
      userQuery = supabase
        .from('users')
        .select('*')
        .eq('id', userId)
        .single();
    }

    const { data: user, error } = await userQuery;

    if (error || !user) {
      throw new Error('User not found');
    }

    // Attach user to request
    req.user = user;

    // ---------------------------------------------------------
    // 3. ROLE-BASED ACCESS CONTROL (RBAC) INJECTION
    // ---------------------------------------------------------
    // We prioritize the role from the Database over the Token for security
    req.userType = user.role || decoded.role;

    // Inheritance-aware role checking, e.g. an admin_manager satisfies hasRole('admin').
    req.roleSet = expandRoles(req.userType);
    req.hasRole = (role) => req.roleSet.has(role);

    // Unchanged meaning: "bypass the branch/location filter". Roughly 141 call sites
    // depend on this flag, so its semantics must not drift. Branch-scoped roles
    // (hoo, hod, admin_manager) are absent from the set, so the existing
    // .eq('location_id', req.locationId) filtering applies to them untouched.
    req.isSuperAdmin = SEES_ALL_LOCATIONS.has(req.userType);

    req.isCEO = req.userType === ROLES.CEO;
    // Finance admin: all-centre visibility, and since the duty merge it also has
    // admin's permissions and is no longer read-only.
    req.isAccountsAdmin = req.userType === ROLES.ACCOUNTS_ADMIN;

    req.locationId = user.location_id;

    next();

  } catch (error) {
    console.error("Auth Middleware Error:", error.message);
    res.status(401).json({ error: 'Please authenticate' });
  }
};
// </scheduler>

/** middleware/punchAuth.js:21-34, whose body is copied as it is. */
function punchAuth(req, res, next) {
  // <scheduler file="middleware/punchAuth.js" lines="22-33">
  const token = req.header('Authorization')?.replace('Bearer ', '');
  const session = readPunchSession(token);
  if (session) {
    req.user = null;
    req.userType = null;
    req.punchEmployeeId = session.employeeId;
    // How and when it was earned: the controller checks it against the employee's attendance
    // login (turned off? password changed since?) and the password endpoint needs a fresh code.
    req.punchSession = session;
    return next();
  }
  return auth(req, res, next);
  // </scheduler>
}

// <scheduler file="services/attendancePunch.js" lines="241-242">
/** A code sign-in may set a password for this long afterwards. */
const PASSWORD_SET_WINDOW_MS = 15 * 60 * 1000;
// </scheduler>

// The copied gate reaches it as A.PASSWORD_SET_WINDOW_MS (const A = require('../../services/attendancePunch')).
const A = { PASSWORD_SET_WINDOW_MS };

// <scheduler file="controllers/hr/attendanceOtpController.js" lines="77-78">
const refuse = (status, code, message, extra = {}) =>
  Object.assign(new Error(message), { status, code, expose: true, extra });
// </scheduler>

/**
 * The gate at the top of setPassword (controllers/hr/attendanceOtpController.js:340-354): who may
 * set the attendance password. Resolves to true when the request may go on; rejects with the
 * Scheduler's refusal otherwise.
 */
async function setPasswordGate(req) {
  // <scheduler file="controllers/hr/attendanceOtpController.js" lines="341-354">
  const s = req.punchSession;
  if (!s) {
    throw refuse(403, 'PORTAL_ACCOUNT', 'Your portal password is changed from your profile, not here.');
  }
  const fresh = Date.now() - s.issuedAt <= A.PASSWORD_SET_WINDOW_MS;
  let allowed = fresh && s.method === 'otp';
  // The password HR gave must be replaced before the person can punch (passwordChangeDue in the
  // punch controller), so a session from it may set one for as long as it is still HR's.
  const account = await Accounts.getAccount(s.employeeId);
  const fromHr = s.method === 'pw' && !!account?.password_hash && !account.password_set_at;
  if (!allowed && fromHr) allowed = true;
  if (!allowed) {
    throw refuse(403, 'CODE_REQUIRED', 'To set your password, sign in with a code first ("Get a code").');
  }
  // </scheduler>
  return true;
}

/* ── running them ── */

/** An Express-like request with one header, and a response that records what it was sent. */
function exchangeFor(token) {
  const req = { header: (name) => (name.toLowerCase() === 'authorization' && token !== undefined ? `Bearer ${token}` : undefined) };
  const res = {
    statusCode: 200,
    body: undefined,
    status(code) { this.statusCode = code; return this; },
    json(body) { this.body = body; return this; },
  };
  return { req, res };
}

/** Runs a copied guard to the end: { passed, req, status, body }. */
async function run(guard, token) {
  const { req, res } = exchangeFor(token);
  let passed = false;
  await guard(req, res, () => { passed = true; });
  return { passed, req, status: passed ? null : res.statusCode, body: res.body };
}

module.exports = {
  /** The users and students rows auth.js finds. */
  useRows({ users = [], students = [] } = {}) {
    usersTable = users.map((u) => ({ ...u }));
    studentsTable = students.map((s) => ({ ...s }));
  },
  /** The hr_attendance_accounts row setPassword's gate reads. */
  useAttendanceAccount(account) {
    attendanceAccount = account ? { ...account } : null;
  },
  runAuth: (token) => run(auth, token),
  runPunchAuth: (token) => run(punchAuth, token),
  setPasswordGate,
  PASSWORD_SET_WINDOW_MS,
};
