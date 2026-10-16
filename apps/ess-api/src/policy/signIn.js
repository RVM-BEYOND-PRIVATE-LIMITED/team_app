const { isActive } = require('./employment');
const { isStaffRole } = require('./staff');

/**
 * The one-field sign-in (task A5; decision 4 in docs/03-decisions.md): which of the Scheduler's two
 * sign-ins a typed identifier belongs to, so the app can ask for the right password or code without
 * knowing the person's login type in advance. The credentials themselves still go to the Scheduler,
 * unchanged (ADR-0004, ADR-0018).
 *
 * A person is an employee. An identifier answers for one person or for nobody:
 *
 *   portal login     an account the Scheduler's portal login would find for it, exactly as that
 *                    login finds one: users.username or users.phone_number, as typed
 *                    (controllers/userController.js:271-279), answered `as_typed` with every
 *                    branch for the person to choose from, as the web's dropdown offers. Also an account found by users.email, or through an employee code,
 *                    email or main phone on the HR record that is linked to it
 *                    (hr_employees.user_id), answered `username_or_phone`: the portal login takes
 *                    only those two, so the app asks for one.
 *   attendance login an employee the Scheduler's attendance sign-in would find for it: main phone,
 *                    email or employee code, compared as it compares them
 *                    (controllers/hr/attendanceOtpController.js:93-156), with the methods that
 *                    login can use now. A person who also has a portal login is answered portal:
 *                    the portal login carries their role, and the Scheduler points such a person
 *                    at the portal (HAS_PORTAL_LOGIN, :163-172).
 *
 * Only logins the app could use count. An account that is not staff (the connector identity, a
 * student), one linked to nobody (a desk login: KP, 16 Oct, no desk logins in the app), one whose
 * person has left: none of them is a person here. Nobody, or more than one person, is `unknown`,
 * in the same shape and after the same database requests (routes/signIn.js) whatever the reason,
 * so this tells a caller no more than the Scheduler's own sign-ins already do. Nothing identifying
 * goes back: no user id, username, phone, email, role or branch (branchChoice).
 */

/* ── the Scheduler's own comparisons, mirrored line for line ──
 * tests/signIn.test.js holds each against the verbatim copy in tests/helpers/schedulerSignIn.js. */

/** normaliseIndianMobile (utils/sms.js:66-72): ten digits, or null. */
function normaliseIndianMobile(raw) {
  let d = String(raw ?? '').replace(/\D+/g, '');
  if (d.length === 12 && d.startsWith('91')) d = d.slice(2);
  if (d.length === 11 && d.startsWith('0')) d = d.slice(1);
  return /^[6-9]\d{9}$/.test(d) ? d : null;
}

/** phoneDigits (services/hrPhones.js:47-52): digits, with a +91 or a trunk 0 taken off. */
function phoneDigits(value) {
  let digits = String(value ?? '').replace(/\D/g, '');
  if (digits.length === 12 && digits.startsWith('91')) digits = digits.slice(2);
  else if (digits.length === 11 && digits.startsWith('0')) digits = digits.slice(1);
  return digits;
}

/** mainNumber (attendanceOtpController.js:107-110): the HR record's main phone as ten digits, or null. */
function mainNumber(employee) {
  const d = phoneDigits(employee.phone);
  return d && d.length === 10 ? d : null;
}

/** reachable (services/attendanceAccounts.js:55-62): can a sign-in code be sent to this person at all? */
function reachable(employee) {
  const d = phoneDigits(employee.phone);
  return /^[6-9]\d{9}$/.test(d) || /@/.test(String(employee.email || ''));
}

/**
 * readLoginIdentifier (attendanceOtpController.js:118-126), with readIdentifier's email check
 * (:93-104): { channel: 'email'|'sms'|'code', ... }, or null where those refuse the value.
 */
function readAttendanceIdentifier(raw) {
  const s = String(raw ?? '').trim();
  if (!s) return null;
  if (s.includes('@')) {
    const email = s.toLowerCase();
    if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return null;
    return { channel: 'email', email };
  }
  const mobile = normaliseIndianMobile(s);
  if (mobile) return { channel: 'sms', mobile };
  if (/^[A-Za-z0-9][A-Za-z0-9/_-]{1,39}$/.test(s)) return { channel: 'code', code: s.toLowerCase() };
  return null;
}

/** findEmployee's `owns` (attendanceOtpController.js:137-141). */
function owns(employee, id) {
  if (id.channel === 'email') return String(employee.email || '').trim().toLowerCase() === id.email;
  if (id.channel === 'code') return String(employee.employee_code || '').trim().toLowerCase() === id.code;
  return mainNumber(employee) === id.mobile;
}

/* ── the resolver's own rules ── */

/** The longest identifier taken: an email address's limit, far past any username or code. */
const IDENTIFIER_MAX = 254;

/**
 * The identifier as typed, or null when there is nothing to look up. Not trimmed: the portal
 * login compares exactly what it is sent, so `as_typed` means "send exactly this".
 */
function readTyped(value) {
  if (typeof value !== 'string' || value.length > IDENTIFIER_MAX || !value.trim()) return null;
  return value;
}

/**
 * One rate-limit bucket per identifier: any spelling of one mobile number is one bucket, and
 * anything else is compared without case or surrounding spaces.
 */
function signInKey(typed) {
  const id = readAttendanceIdentifier(typed);
  return id && id.channel === 'sms' ? `sms:${id.mobile}` : `text:${String(typed ?? '').trim().toLowerCase()}`;
}

/**
 * The employees the attendance sign-in would find for this identifier: not archived (the list is
 * read that way), matching, and still on strength (findEmployee, attendanceOtpController.js:132-145).
 */
function employeesOwning(employees, typed, today) {
  const id = readAttendanceIdentifier(typed);
  return id ? employees.filter((e) => owns(e, id) && isActive(e, today)) : [];
}

/**
 * The branches the app offers with the portal login: every one, in the web's order, for every
 * account, so the person chooses as they do on the web.
 *
 * Never the account's own branch, and never a reply that differs by role. The question needs no
 * token, and an answer shaped by the account would say which logins are the CEO's, super admins'
 * and HR's (the roles that may have no branch, config/roles.js NO_BRANCH_ROLES) and which branch
 * everybody else is at: neither of which the Scheduler's own login tells anybody. The login still
 * finds the right account from any branch: a lone account from any name, and one that shares its
 * identifier by the branch, then by the password (resolveLoginCandidate and the password
 * fallback, userController.js:296-305, 376-382, 426-436).
 */
function branchChoice(locations) {
  return { location_names: [...locations].sort((a, b) => Number(a.id) - Number(b.id)).map((l) => l.name) };
}

const UNKNOWN = Object.freeze({ kind: 'unknown' });

/**
 * @param {object} facts            everything read for one identifier (routes/signIn.js)
 * @param {object[]} facts.asTyped  users whose username or phone_number is exactly what was typed
 * @param {object[]} facts.byEmail  users whose email is what was typed
 * @param {object[]} facts.owning   employeesOwning()
 * @param {object[]} facts.linkedUsers  the users rows the owning employees are linked to
 * @param {object[]} facts.employees    every employee not archived
 * @param {object[]} facts.logins       attendance logins { employee_id, status }
 * @param {object[]} facts.withPassword attendance logins that have a password { employee_id }
 * @param {object[]} facts.locations    { id, name }
 * @param {string} facts.today          the IST day
 */
function resolveSignIn({ asTyped, byEmail, owning, linkedUsers, employees, logins, withPassword, locations, today }) {
  // The live employee each linked login belongs to; a login linked to a leaver has nobody.
  const employeeOf = new Map(employees.filter((e) => e.user_id && isActive(e, today)).map((e) => [e.user_id, e]));
  /** employee id -> { employee, user (their portal login, or null), asTyped } */
  const people = new Map();

  const portalLogin = (user, typedAsIs) => {
    if (!user || !isStaffRole(user.role)) return;
    const employee = employeeOf.get(user.id);
    if (!employee) return;
    const known = people.get(employee.id);
    people.set(employee.id, { employee, user, asTyped: typedAsIs || Boolean(known && known.asTyped) });
  };

  asTyped.forEach((user) => portalLogin(user, true));
  byEmail.forEach((user) => portalLogin(user, false));
  const usersById = new Map(linkedUsers.map((u) => [u.id, u]));
  for (const employee of owning) {
    const user = employee.user_id ? usersById.get(employee.user_id) : null;
    if (user && isStaffRole(user.role)) portalLogin(user, false);
    else if (!people.has(employee.id)) people.set(employee.id, { employee, user: null, asTyped: false });
  }

  if (people.size !== 1) return { ...UNKNOWN };
  const [{ employee, user, asTyped: typedAsIs }] = people.values();

  if (user) {
    return typedAsIs
      ? { kind: 'portal', login_with: 'as_typed', ...branchChoice(locations) }
      : { kind: 'portal', login_with: 'username_or_phone' };
  }

  // An attendance login that is missing or switched off can do nothing now: no methods, and the
  // app tells the person to ask HR, as the Scheduler's NO_ATTENDANCE_LOGIN would.
  const login = logins.find((l) => l.employee_id === employee.id);
  if (!login || login.status !== 'active') return { kind: 'attendance', methods: [] };
  const methods = [];
  // A code goes to the main mobile or the email on the HR record (otp/request), so it needs one.
  if (reachable(employee)) methods.push('code');
  // A password once one exists: the person's own, or the one HR gave.
  if (withPassword.some((l) => l.employee_id === employee.id)) methods.push('password');
  return { kind: 'attendance', methods };
}

module.exports = {
  IDENTIFIER_MAX,
  normaliseIndianMobile,
  phoneDigits,
  mainNumber,
  reachable,
  readAttendanceIdentifier,
  owns,
  readTyped,
  signInKey,
  employeesOwning,
  branchChoice,
  resolveSignIn,
};
