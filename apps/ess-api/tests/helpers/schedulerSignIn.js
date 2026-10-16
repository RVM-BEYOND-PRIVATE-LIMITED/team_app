const { NO_BRANCH_ROLES, SEES_ALL_LOCATIONS } = require('../../src/policy/roles');
const { isActive } = require('./schedulerRules');

/**
 * How the Scheduler's two sign-ins find an account for what was typed, copied verbatim from
 * Scheduler_Backend at c28b9ca, so tests/signIn.test.js can show that the one-field resolver
 * (src/policy/signIn.js) finds the same people the Scheduler would:
 *
 *   the portal login       findAccountsByIdentifier and resolveLoginCandidate
 *                          (controllers/userController.js)
 *   the attendance sign-in readIdentifier, readLoginIdentifier, findEmployee and
 *                          requireAttendanceLogin (controllers/hr/attendanceOtpController.js),
 *                          with normaliseIndianMobile (utils/sms.js), phoneDigits
 *                          (services/hrPhones.js) and reachable (services/attendanceAccounts.js)
 *
 * Blocks are marked as in schedulerTokens.js and checked by tests/schedulerCopies.test.js whenever
 * SCHEDULER_BACKEND_DIR is set. The copied isActive reads the real clock, as in the Scheduler, so
 * the tests give these copies people whose standing does not depend on the day.
 */

/* ── stand-ins for what the copied lines reach ── */

let usersTable = [];
let employeesTable = [];
let accountsTable = [];

/** Reads one PostgREST double-quoted value, undoing the quoting findAccountsByIdentifier applies. */
function readQuoted(text, start) {
  if (text[start] !== '"') return null;
  let value = '';
  for (let i = start + 1; i < text.length; i++) {
    if (text[i] === '\\') { value += text[i + 1]; i += 1; } else if (text[i] === '"') return { value, end: i + 1 };
    else value += text[i];
  }
  return null;
}

const supabase = {
  from(table) {
    const query = {
      select: () => query,
      /** or=(username.eq."x",phone_number.eq."x"): the one filter findAccountsByIdentifier sends. */
      or: async (filter) => {
        const first = filter.startsWith('username.eq.') ? readQuoted(filter, 'username.eq.'.length) : null;
        const rest = first && filter.slice(first.end);
        const second = rest && rest.startsWith(',phone_number.eq.') ? readQuoted(rest, ',phone_number.eq.'.length) : null;
        if (!second || first.value !== second.value || second.end !== rest.length) {
          return { data: null, error: { code: 'PGRST100', message: `failed to parse logic tree (${filter})` } };
        }
        return { data: usersTable.filter((u) => u.username === first.value || u.phone_number === first.value).map((u) => ({ ...u })), error: null };
      },
      /** .eq('is_archived', false), the one filter findEmployee sends. */
      eq: async (column, value) => ({ data: (table === 'hr_employees' ? employeesTable : []).filter((r) => r[column] === value).map((r) => ({ ...r })), error: null }),
    };
    return query;
  },
};

const notInstalled = (error) => error;
const Accounts = { getAccount: async (employeeId) => accountsTable.find((a) => a.employee_id === employeeId) || null };

// <scheduler file="controllers/hr/attendanceOtpController.js" lines="77-78">
const refuse = (status, code, message, extra = {}) =>
  Object.assign(new Error(message), { status, code, expose: true, extra });
// </scheduler>

/* ── the copies ── */

// <scheduler file="utils/sms.js" lines="66-72">
/** Ten digits, or null. Never guesses. */
const normaliseIndianMobile = (raw) => {
  let d = String(raw ?? '').replace(/\D+/g, '');
  if (d.length === 12 && d.startsWith('91')) d = d.slice(2);
  if (d.length === 11 && d.startsWith('0')) d = d.slice(1);
  return /^[6-9]\d{9}$/.test(d) ? d : null;
};
// </scheduler>

// <scheduler file="services/hrPhones.js" lines="47-52">
const phoneDigits = (value) => {
  let digits = String(value ?? '').replace(/\D/g, '');
  if (digits.length === 12 && digits.startsWith('91')) digits = digits.slice(2);
  else if (digits.length === 11 && digits.startsWith('0')) digits = digits.slice(1);
  return digits;
};
// </scheduler>

// <scheduler file="services/attendanceAccounts.js" lines="55-62">
/** The main phone as ten digits, when it is a real Indian mobile; otherwise null. */
const mainMobile = (phone) => {
  const d = phoneDigits(phone);
  return /^[6-9]\d{9}$/.test(d) ? d : null;
};

/** Can a sign-in code reach this person at all? */
const reachable = (emp) => !!(mainMobile(emp.phone) || /@/.test(String(emp.email || '')));
// </scheduler>

// <scheduler file="controllers/hr/attendanceOtpController.js" lines="92-172">
/** What was typed: an email, or a ten-digit Indian mobile. */
function readIdentifier(raw) {
  const s = String(raw ?? '').trim();
  if (!s) return { error: 'Enter the phone number or email on your employee record.' };
  if (s.includes('@')) {
    const email = s.toLowerCase();
    if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return { error: 'That is not a valid email address.' };
    return { channel: 'email', email };
  }
  const mobile = normaliseIndianMobile(s);
  if (!mobile) return { error: 'Enter a ten-digit Indian mobile number, or your email.' };
  return { channel: 'sms', mobile };
}

/** The main phone on the HR record, as ten comparable digits, or null. */
const mainNumber = (e) => {
  const d = phoneDigits(e.phone);
  return d && d.length === 10 ? d : null;
};
const extraNumbers = (e) =>
  (Array.isArray(e.additional_phones) ? e.additional_phones : []).map(phoneDigits).filter((d) => d && d.length === 10);

/**
 * What was typed at the PASSWORD sign-in: the main phone, the email, or the employee code.
 * The code is the one identifier a person can read off their ID card without HR's help.
 */
function readLoginIdentifier(raw) {
  const s = String(raw ?? '').trim();
  if (!s) return { error: 'Enter your phone number, email or employee code.' };
  if (s.includes('@')) return readIdentifier(s);
  const mobile = normaliseIndianMobile(s);
  if (mobile) return { channel: 'sms', mobile };
  if (/^[A-Za-z0-9][A-Za-z0-9/_-]{1,39}$/.test(s)) return { channel: 'code', code: s.toLowerCase() };
  return { error: 'Enter your phone number, email or employee code.' };
}

/**
 * The one active employee whose MAIN phone, email -- or, at the password sign-in, employee
 * code -- this is, or the refusal saying why not.
 */
async function findEmployee(id) {
  const { data, error } = await supabase.from('hr_employees')
    .select('id, full_name, employee_code, email, phone, additional_phones, user_id, is_archived, employment_status, date_of_exit')
    .eq('is_archived', false);
  if (error) throw notInstalled(error);
  const owns = (e) => (id.channel === 'email'
    ? String(e.email || '').trim().toLowerCase() === id.email
    : id.channel === 'code'
      ? String(e.employee_code || '').trim().toLowerCase() === id.code
      : mainNumber(e) === id.mobile);
  const matches = (data || []).filter(owns);
  const live = matches.filter(isActive);
  const what = id.channel === 'email' ? 'email' : id.channel === 'code' ? 'employee code' : 'phone number';
  if (live.length === 1) return live[0];
  if (live.length > 1) {
    throw refuse(409, 'AMBIGUOUS', `This ${what} is on more than one employee record. Ask HR to correct it.`);
  }
  if (matches.length) throw refuse(403, 'NOT_ACTIVE', 'Your employee record is not active, so punching is closed.');
  if (id.channel === 'sms' && (data || []).some((e) => isActive(e) && extraNumbers(e).includes(id.mobile))) {
    throw refuse(404, 'NOT_MAIN_PHONE',
      'This number is on your employee record as an extra number, not the main one. Ask HR to set it as your main phone number, or sign in with your email.');
  }
  throw refuse(404, 'NOT_FOUND',
    `We could not find an employee with this ${what}. Ask HR to add it to your employee record, or contact the tech team.`);
}

/**
 * RVM, 2026-10-14: somebody not on the portal may sign in to punch only once HR has created an
 * attendance login for them. Somebody who IS on the portal is pointed at it -- their portal
 * login already carries the Punch button, and a second way in would be a second thing to lose.
 */
async function requireAttendanceLogin(emp) {
  const account = await Accounts.getAccount(emp.id);
  if (account && account.status === 'active') return account;
  if (emp.user_id) {
    throw refuse(403, 'HAS_PORTAL_LOGIN', 'You have a portal login. Sign in to the portal and use the Punch button at the top.');
  }
  throw refuse(403, 'NO_ATTENDANCE_LOGIN', account
    ? 'Your attendance login is turned off. Ask HR.'
    : 'You do not have an attendance login yet. Ask HR to create one for you.');
}
// </scheduler>

// <scheduler file="controllers/userController.js" lines="271-279">
const findAccountsByIdentifier = async (identifier) => {
  const quoted = `"${String(identifier).replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
  const { data, error } = await supabase
    .from("users")
    .select("*")
    .or(`username.eq.${quoted},phone_number.eq.${quoted}`);
  if (error) throw error;
  return data || [];
};
// </scheduler>

// <scheduler file="controllers/userController.js" lines="296-305">
const resolveLoginCandidate = (candidates, locationId) => {
  if (candidates.length === 1) return candidates[0];

  const only = (list) => (list.length === 1 ? list[0] : null);

  return only(candidates.filter((u) => u.location_id === locationId))
    || only(candidates.filter((u) => u.location_id === null && NO_BRANCH_ROLES.has(u.role)))
    || only(candidates.filter((u) => SEES_ALL_LOCATIONS.has(u.role)))
    || null;
};
// </scheduler>

/**
 * What the attendance sign-in does with an identifier up to the password or the code: the
 * employee and their login, or the refusal's code. Mirrors the order of passwordLogin
 * (attendanceOtpController.js:392-406): read the identifier, find the one employee, require the
 * login.
 */
async function attendanceSignIn(typed) {
  const id = readLoginIdentifier(typed);
  if (id.error) return { refused: 'BAD_IDENTIFIER' };
  try {
    const employee = await findEmployee(id);
    const account = await requireAttendanceLogin(employee);
    return { employee, account };
  } catch (e) {
    if (e && e.expose) return { refused: e.code };
    throw e;
  }
}

module.exports = {
  /** The users, hr_employees and hr_attendance_accounts rows the copies read. */
  useRows({ users = [], employees = [], accounts = [] } = {}) {
    usersTable = users.map((u) => ({ ...u }));
    employeesTable = employees.map((e) => ({ ...e }));
    accountsTable = accounts.map((a) => ({ ...a }));
  },
  normaliseIndianMobile,
  phoneDigits,
  mainMobile,
  reachable,
  readIdentifier,
  readLoginIdentifier,
  mainNumber,
  findEmployee,
  requireAttendanceLogin,
  findAccountsByIdentifier,
  resolveLoginCandidate,
  attendanceSignIn,
};
