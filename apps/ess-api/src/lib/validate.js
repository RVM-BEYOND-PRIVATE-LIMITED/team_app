const { HttpError, MESSAGES } = require('./errors');

/**
 * The small checks every ESS form shares. Each refusal is a fixed message from MESSAGES, so the
 * contract can quote it word for word, and the code is VALIDATION_FAILED, the Scheduler's code
 * for the same thing (controllers/hr/_shared.js:22).
 *
 * The rule the Scheduler's helpers follow (controllers/hr/_shared.js:13-16) holds here too: an
 * absent value stays absent and a bad value is an error. Nothing is quietly turned into a
 * plausible value.
 */

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const isUuid = (v) => typeof v === 'string' && UUID_RE.test(v);

const invalid = (message, code = 'VALIDATION_FAILED') => new HttpError(400, code, message);

const isPlainObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

/** Characters as Postgres counts them: "ok 👍" is four, where .length says five (attendanceAdminController.js:63-65). */
const chars = (s) => Array.from(s).length;

/**
 * The JSON body as an object whose keys are all in `allowed`. A key the server does not take is
 * refused rather than ignored: a misspelt field would otherwise look saved and not be.
 */
function bodyWith(req, allowed) {
  const body = req.body;
  if (!isPlainObject(body)) throw invalid(MESSAGES.BODY_NOT_OBJECT);
  if (Object.keys(body).some((k) => !allowed.includes(k))) throw invalid(MESSAGES.UNKNOWN_FIELD);
  return body;
}

/**
 * Optional text: null for absent, null or blank; the trimmed string otherwise; undefined when
 * the value is not a string at all, which the caller refuses.
 */
function optionalText(v) {
  if (v === undefined || v === null) return null;
  if (typeof v !== 'string') return undefined;
  const s = v.trim();
  return s === '' ? null : s;
}

/** Trimmed text of min to max characters, or the given refusal. */
function requiredText(v, { min, max, message }) {
  const s = optionalText(v);
  if (!s || chars(s) < min || chars(s) > max) throw invalid(message);
  return s;
}

/** A route's :id. Not a UUID is a 400, as the Scheduler's uuid() makes it (controllers/hr/_shared.js:38-43). */
function idParam(value) {
  if (!isUuid(value)) throw invalid(MESSAGES.INVALID_ID);
  return value.toLowerCase();
}

/** A query parameter that is one value, never repeated (?status=a&status=b arrives as a list). */
function oneQueryValue(v) {
  if (v === undefined) return undefined;
  if (typeof v !== 'string') return null;
  return v.trim();
}

/**
 * The comparable digits of a phone number, exactly as the Scheduler works them out
 * (services/hrPhones.js:47-52): digits only, then the 91 country prefix of a 12-digit number or
 * the 0 trunk prefix of an 11-digit one removed.
 */
function phoneDigits(value) {
  let digits = String(value ?? '').replace(/\D/g, '');
  if (digits.length === 12 && digits.startsWith('91')) digits = digits.slice(2);
  else if (digits.length === 11 && digits.startsWith('0')) digits = digits.slice(1);
  return digits;
}

/** An Indian mobile number: 10 digits starting 6 to 9 (the TRAI mobile series). */
const INDIAN_MOBILE_RE = /^[6-9]\d{9}$/;

module.exports = {
  UUID_RE,
  isUuid,
  invalid,
  isPlainObject,
  chars,
  bodyWith,
  optionalText,
  requiredText,
  idParam,
  oneQueryValue,
  phoneDigits,
  INDIAN_MOBILE_RE,
};
