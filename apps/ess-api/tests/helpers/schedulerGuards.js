const { readPunchSession } = require('./schedulerTokens');

/**
 * The Scheduler's own guards, so the tests can
 * hand them a token the ESS minted (src/lib/accessTokens.js) and see what the Scheduler does with
 * it: middleware/auth.js on every portal route, middleware/punchAuth.js on /hr/my-attendance, and
 * the gate in front of POST /hr/my-attendance/password.
 *
 * middleware/auth.js is loaded from the Scheduler checkout (see below); the small blocks that are
 * copied are marked as in schedulerTokens.js and checked by tests/schedulerCopies.test.js whenever
 * SCHEDULER_BACKEND_DIR is set. They use `supabase`, `Accounts` and `refuse`; the stand-ins below
 * give them the rows a test chooses.
 */

/* ── stand-ins for what the copied lines reach ── */

let usersTable = [];
let studentsTable = [];
// The HR records linked to a login: auth.js signs an account out when every one shows an exit.
let hrEmployeesTable = [];
let attendanceAccount = null;

/** supabase.from(t).select(...).eq(c, v), awaited directly or with .single(): the shapes auth.js uses. */
const supabase = {
  from(table) {
    const rows = table === 'users' ? usersTable
      : table === 'students' ? studentsTable
        : table === 'hr_employees' ? hrEmployeesTable : [];
    const filters = [];
    const query = {
      select: () => query,
      eq: (column, value) => {
        filters.push([column, value]);
        return query;
      },
      // Awaited without .single(): every matching row (the HR-exit check reads it this way).
      then: (resolve, reject) => Promise.resolve({
        data: rows.filter((r) => filters.every(([c, v]) => r[c] === v)).map((r) => ({ ...r })),
        error: null,
      }).then(resolve, reject),
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

/*
 * middleware/auth.js is NOT copied here. This repository is public and that file is the
 * Scheduler's own sign-in guard, so the tests load the real one from the checkout named by
 * SCHEDULER_BACKEND_DIR, with the stand-in database above in place of its db.js. Without that
 * variable the tests that need the guard are skipped (`hasSchedulerAuth` below); they run in the
 * Scheduler's own CI, which checks this repository out beside it.
 */
const SCHEDULER_DIR = process.env.SCHEDULER_BACKEND_DIR || null;

function loadSchedulerAuth() {
  const path = require('path');
  const dbPath = require.resolve(path.join(SCHEDULER_DIR, 'db.js'));
  const authPath = require.resolve(path.join(SCHEDULER_DIR, 'middleware', 'auth.js'));
  // The guard takes `supabase` from ../db when it loads: hand it the stand-in, never a database.
  require.cache[dbPath] = { id: dbPath, filename: dbPath, loaded: true, exports: supabase };
  delete require.cache[authPath];
  return require(authPath);
}

const auth = SCHEDULER_DIR
  ? loadSchedulerAuth()
  : async () => { throw new Error('This test needs SCHEDULER_BACKEND_DIR: the Scheduler sign-in guard is not copied into this repository.'); };

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
  useRows({ users = [], students = [], hrEmployees = [] } = {}) {
    hrEmployeesTable = hrEmployees.map((e) => ({ ...e }));
    usersTable = users.map((u) => ({ ...u }));
    studentsTable = students.map((s) => ({ ...s }));
  },
  /** The hr_attendance_accounts row setPassword's gate reads. */
  useAttendanceAccount(account) {
    attendanceAccount = account ? { ...account } : null;
  },
  /** Whether the Scheduler's own guard could be loaded (SCHEDULER_BACKEND_DIR is set). */
  hasSchedulerAuth: Boolean(SCHEDULER_DIR),
  runAuth: (token) => run(auth, token),
  runPunchAuth: (token) => run(punchAuth, token),
  setPasswordGate,
  PASSWORD_SET_WINDOW_MS,
};
