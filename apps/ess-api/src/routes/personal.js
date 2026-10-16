const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const { bodyWith, optionalText, chars, idParam, invalid, phoneDigits, INDIAN_MOBILE_RE } = require('../lib/validate');
const { istDay, isCalendarDay, yearsBefore } = require('../lib/time');
const { recordBefore, recordAfter } = require('../lib/audit');

/**
 * Task E9: date of birth, blood group, address and emergency contact.
 *
 * hr_employees holds none of these (supabase/migrations/20260826000001_hrms_tables.sql:82-131 and
 * every later ALTER of it at c28b9ca), and the ESS never writes hr_employees (ADR-0018), so they
 * live in hr_ess_personal_details, one row per employee (ADR-0021).
 *
 * Who may do what (the brief: sensitive edits need HR's approval):
 *   the employee   reads all of it; changes only the blood group and the emergency contact. A
 *                  date of birth or an address field answers 403 SENSITIVE_FIELD: those changes
 *                  go through HR, and a request to change them comes in a later phase (E3).
 *   HR             (policy/hrAccess.js HR_RECORD_ROLES) reads and changes every field of
 *                  anybody else's record. Every read and every change is written to hr_ess_audit.
 *   nobody else    managers included.
 *
 * Fields not sent are left as they are; null or an empty string clears one.
 */

const BLOOD_GROUPS = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

/** The earliest date of birth taken (task brief). */
const OLDEST_BIRTH_DATE = '1940-01-01';
/** Staff are at least this old (task brief). */
const MIN_AGE_YEARS = 16;

const SENSITIVE_FIELDS = ['date_of_birth', 'address_line1', 'address_line2', 'city', 'state', 'pincode'];
const SELF_FIELDS = ['blood_group', 'emergency_name', 'emergency_relation', 'emergency_phone'];
const ALL_FIELDS = [...SENSITIVE_FIELDS, ...SELF_FIELDS];

/** Free text of up to `max` characters, trimmed; blank clears it. */
const text = (max, message) => (v) => {
  const s = optionalText(v);
  if (s === undefined || (s && chars(s) > max)) throw invalid(message);
  return s;
};

/** How each field is read from a request body, today being the IST day the request arrived. */
const PARSERS = {
  date_of_birth: (v, today) => {
    if (v === null || v === '') return null;
    if (!isCalendarDay(v) || v < OLDEST_BIRTH_DATE || v > yearsBefore(today, MIN_AGE_YEARS)) throw invalid(MESSAGES.DATE_OF_BIRTH);
    return v;
  },
  blood_group: (v) => {
    const s = optionalText(v);
    if (s === null) return null;
    const hit = typeof s === 'string' ? BLOOD_GROUPS.find((g) => g === s.toUpperCase().replace(/\s+/g, '')) : null;
    if (!hit) throw invalid(MESSAGES.BLOOD_GROUP);
    return hit;
  },
  address_line1: text(200, MESSAGES.ADDRESS_FIELD),
  address_line2: text(200, MESSAGES.ADDRESS_FIELD),
  city: text(80, MESSAGES.ADDRESS_FIELD),
  state: text(80, MESSAGES.ADDRESS_FIELD),
  pincode: (v) => {
    const s = optionalText(v);
    if (s === null) return null;
    // Six digits; Indian PIN codes never start with 0.
    if (typeof s !== 'string' || !/^[1-9]\d{5}$/.test(s)) throw invalid(MESSAGES.PINCODE);
    return s;
  },
  emergency_name: text(100, MESSAGES.EMERGENCY_NAME),
  emergency_relation: text(50, MESSAGES.EMERGENCY_RELATION),
  emergency_phone: (v) => {
    const s = optionalText(v);
    if (s === null) return null;
    if (typeof s !== 'string') throw invalid(MESSAGES.EMERGENCY_PHONE);
    // +91 98765 43210, 098765 43210 and 9876543210 are one number, as the Scheduler compares them.
    const digits = phoneDigits(s);
    if (!INDIAN_MOBILE_RE.test(digits)) throw invalid(MESSAGES.EMERGENCY_PHONE);
    return digits;
  },
};

const EMPTY = Object.freeze(Object.fromEntries(ALL_FIELDS.map((f) => [f, null])));

/** The reply's personal block: every field, null when not recorded. */
const view = (row) => ({
  ...Object.fromEntries(ALL_FIELDS.map((f) => [f, row ? row[f] ?? null : null])),
  updated_at: row ? row.updated_at ?? null : null,
  updated_by_name: row ? row.updated_by_name ?? null : null,
});

const card = (e) => ({ id: e.id, full_name: e.full_name, employee_code: e.employee_code ?? null });

/**
 * The fields of `body` (already checked to be among `allowed`), parsed, and checked against the
 * stored row as a whole. Returns only the parsed fields, which are all that is written, and the
 * names that changed.
 *
 * Only what was sent is written (store.savePersonalDetails), never the merged row: between this
 * read and the write somebody else may save the same record, and writing back the fields as read
 * would undo their change, an employee's save undoing HR's date of birth among them.
 */
function merge(body, stored, today) {
  const sent = Object.keys(body);
  if (!sent.length) throw invalid(MESSAGES.NOTHING_TO_CHANGE);
  const parsed = Object.fromEntries(sent.map((f) => [f, PARSERS[f](body[f], today)]));
  const before = { ...EMPTY, ...(stored ? Object.fromEntries(ALL_FIELDS.map((f) => [f, stored[f] ?? null])) : {}) };
  const after = { ...before, ...parsed };
  // A name with no number reaches nobody, and a number with no name tells HR nothing. Checked on
  // the record as read; hr_ess_personal_details_emergency_chk holds it on the row as written.
  if (Boolean(after.emergency_name) !== Boolean(after.emergency_phone) || (after.emergency_relation && !after.emergency_name)) {
    throw invalid(MESSAGES.EMERGENCY_INCOMPLETE);
  }
  const changed = ALL_FIELDS.filter((f) => after[f] !== before[f]);
  return { fields: parsed, changed };
}

/** The row to store, stamped with who wrote it. */
const stamped = (employeeId, fields, req, now) => ({
  employee_id: employeeId,
  ...fields,
  updated_at: now().toISOString(),
  updated_by_user_id: req.auth.userId ?? null,
  updated_by_name: req.auth.employee.full_name,
});

/**
 * Writes the row, or 409 RECORD_CHANGED when somebody else's save since the read leaves the
 * emergency contact half there with this one (the database's own check refuses it): the person
 * opens the record again and sees what is there now.
 */
async function save(store, row) {
  const saved = await store.savePersonalDetails(row);
  if (!saved) throw new HttpError(409, 'RECORD_CHANGED', MESSAGES.RECORD_CHANGED);
  return saved;
}

/** GET /api/ess/me/personal */
function getMyPersonal({ store }) {
  return asyncRoute(async (req, res) => {
    res.json({ personal: view(await store.getPersonalDetails(req.auth.employee.id)) });
  });
}

/** PUT /api/ess/me/personal { blood_group?, emergency_name?, emergency_relation?, emergency_phone? } */
function putMyPersonal({ store, now }) {
  return asyncRoute(async (req, res) => {
    const body = bodyWith(req, ALL_FIELDS);
    // Checked before anything else about the values, so the app hears "ask HR", not a format error.
    if (Object.keys(body).some((f) => SENSITIVE_FIELDS.includes(f))) {
      throw new HttpError(403, 'SENSITIVE_FIELD', MESSAGES.SENSITIVE_FIELD);
    }
    const employeeId = req.auth.employee.id;
    const stored = await store.getPersonalDetails(employeeId);
    const { fields } = merge(body, stored, istDay(now()));
    const saved = await save(store, stamped(employeeId, fields, req, now));
    res.json({ personal: view(saved) });
  });
}

/** The employee an HR route names, or 404. */
async function targetEmployee(store, id) {
  const employee = await store.getEmployeeCard(idParam(id));
  if (!employee) throw new HttpError(404, 'NOT_FOUND', MESSAGES.EMPLOYEE_NOT_FOUND);
  return employee;
}

/**
 * GET /api/ess/hr/employees/:id/personal. The audit row is written before the reply, and a
 * failure to write it refuses the read (lib/audit.js recordBefore).
 */
function getEmployeePersonal({ store }) {
  return asyncRoute(async (req, res) => {
    const employee = await targetEmployee(store, req.params.id);
    const row = await store.getPersonalDetails(employee.id);
    await recordBefore(store, req, { action: 'personal_details.read', targetEmployeeId: employee.id });
    res.json({ employee: card(employee), personal: view(row) });
  });
}

/**
 * PUT /api/ess/hr/employees/:id/personal, any of the fields.
 *
 * Not on one's own record (409 OWN_RECORD): HR approving its own date of birth or address is the
 * self-approval the brief's rule exists to stop, as with an HR person's own data request.
 */
function putEmployeePersonal({ store, now }) {
  return asyncRoute(async (req, res) => {
    const employee = await targetEmployee(store, req.params.id);
    const body = bodyWith(req, ALL_FIELDS);
    if (employee.id === req.auth.employee.id) throw new HttpError(409, 'OWN_RECORD', MESSAGES.OWN_RECORD);
    const stored = await store.getPersonalDetails(employee.id);
    const { fields, changed } = merge(body, stored, istDay(now()));
    const saved = await save(store, stamped(employee.id, fields, req, now));
    // The names of the fields that changed, never their values (lib/audit.js).
    await recordAfter(store, req, { action: 'personal_details.updated', targetEmployeeId: employee.id, details: { fields: changed } });
    res.json({ employee: card(employee), personal: view(saved) });
  });
}

module.exports = {
  getMyPersonal,
  putMyPersonal,
  getEmployeePersonal,
  putEmployeePersonal,
  BLOOD_GROUPS,
  SENSITIVE_FIELDS,
  SELF_FIELDS,
  ALL_FIELDS,
};
