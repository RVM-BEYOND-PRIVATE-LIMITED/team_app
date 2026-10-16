/**
 * The one shape every refusal takes: { "error": "<message for staff>", "code": "UPPER_SNAKE" }.
 *
 * It is the Scheduler's shape (controllers/hr/_shared.js), so the app reads both services'
 * refusals the same way. The message is shown to the person as it is, so it is written for
 * staff, not for developers; the code is what the app branches on.
 *
 * 401 means one thing only: the token is absent or no longer good, and the app signs out on
 * it. Everything else that stops a request is a 403, 404, 429 or 503, so a database outage or
 * a missing HR link never signs anybody out (ADR-0006, J8 in docs/02-reconciliation.md).
 *
 * `extra` adds fields beside error and code, as the Scheduler's refuse() does
 * (controllers/hr/attendanceOtpController.js:77-90): a refused refresh says why, in `reason`.
 */
class HttpError extends Error {
  constructor(status, code, message, extra = null) {
    super(message);
    this.name = 'HttpError';
    this.status = status;
    this.code = code;
    this.extra = extra;
  }
}

const MESSAGES = Object.freeze({
  SIGN_IN: 'Please sign in.',
  SIGN_IN_AGAIN: 'Please sign in again.',
  SESSION_EXPIRED: 'Your sign-in has expired. Please sign in again.',
  PASSWORD_CHANGED: 'Your password was changed. Please sign in again.',
  NOT_AN_EMPLOYEE: 'Team RVM is for staff. Sign in with your staff login.',
  // The Scheduler's own wording (attendancePunchController.js MESSAGES), so both say the same.
  NOT_LINKED: 'Your login is not linked to an employee record yet. Ask HR or the tech team to link it.',
  NOT_ACTIVE: 'Your employee record is no longer active, so Team RVM is closed for this login. Ask HR if this is wrong.',
  NO_ATTENDANCE_LOGIN: 'You do not have an attendance login yet. Ask HR to create one for you.',
  ATTENDANCE_LOGIN_OFF: 'Your attendance login is turned off. Ask HR.',
  // The Scheduler's wording (attendancePunchController.js:196-197).
  PASSWORD_CHANGE_REQUIRED: 'Set your own password first. The password HR gave you only works once.',
  // Staying signed in (task A3).
  SIGN_IN_NOT_FRESH: 'To stay signed in on this phone, sign in again and keep the sign-in within 10 minutes.',
  ALREADY_EXCHANGED: 'This phone is already signed in. There is nothing more to do.',
  REFRESH_IN_PROGRESS: 'Your sign-in is being renewed. Try again in a moment.',
  SIGNED_OUT: 'You have signed out. Please sign in again.',
  SIGNED_OUT_FOR_SAFETY: 'For your safety you have been signed out. Please sign in again.',
  SESSION_UNLINKED: 'Your login is no longer linked to your employee record. Ask HR or the tech team.',
  SESSION_NOT_FOUND: 'That sign-in is not one of yours, or it has already ended.',
  BAD_INSTALL_ID: 'The app did not identify this phone correctly. Update the app and try again.',
  BAD_DEVICE_LABEL: 'The app sent a phone name the server cannot keep. Update the app and try again.',
  // One-field sign-in (task A5).
  BAD_IDENTIFIER: 'Enter your phone number, email, employee code or username.',
  RATE_LIMITED: 'Too many requests. Wait a minute and try again.',
  UNAVAILABLE: 'The server cannot reach the database right now. Try again in a minute.',
  MODULE_DISABLED: 'Team RVM is switched off on the server for now. Try again later.',
  NOT_FOUND: 'There is nothing at this address.',
  INVALID_JSON: 'The request body is not valid JSON.',
  PAYLOAD_TOO_LARGE: 'The request is too large.',
  UNSUPPORTED_MEDIA_TYPE: 'The request body is in a format the server does not accept.',
  BAD_REQUEST: 'The request could not be read.',
  INTERNAL_ERROR: 'Something went wrong on the server. Try again, and tell the tech team if it keeps happening.',

  // Who may use HR's tools. The codes are the Scheduler's own for the same refusals
  // (routes/hr.js:53 HR_ACCESS_DENIED, routes/hr.js:206 ATTENDANCE_OVERRIDE_DENIED).
  HR_ACCESS_DENIED: 'Only HR and super admins can open this.',
  ATTENDANCE_OVERRIDE_DENIED: 'Only HR, the CEO and super admins can do this.',
  PORTAL_LOGIN_REQUIRED: 'HR tools need your portal login. Sign in with your username or login phone.',

  // Request bodies and query strings.
  BODY_NOT_OBJECT: 'The request body must be a JSON object.',
  UNKNOWN_FIELD: 'The request has a field the server does not take.',
  INVALID_ID: 'That is not a valid id.',
  DATE_FORMAT: 'Dates must be real days written YYYY-MM-DD.',
  DATE_RANGE: 'from must be on or before to, and at most 366 days before it.',
  BRANCH_ID: 'branch_id must be a branch id.',
  BRANCH_NOT_FOUND: 'That branch was not found.',
  EMPLOYEE_NOT_FOUND: 'That employee was not found.',

  // A8: requests to correct or delete my data.
  DATA_REQUEST_KIND: 'Choose what you are asking for: correct or delete.',
  DATA_REQUEST_DETAILS: 'Say what should be corrected or deleted, in 5 to 2,000 characters.',
  TOO_MANY_OPEN_REQUESTS: 'You already have 5 requests waiting for HR. Wait for HR to answer them first.',
  DATA_REQUEST_STATUS_FILTER: 'status must be open, done, rejected or all.',
  RESOLVE_STATUS: 'Mark the request done or rejected.',
  RESOLVE_NOTE: 'Keep the note to 1,000 characters.',
  REJECT_NOTE_REQUIRED: 'Say why the request is rejected, in at least 3 characters. The employee sees it.',
  DATA_REQUEST_NOT_FOUND: 'That request was not found.',
  OWN_REQUEST: 'You cannot resolve your own request. Ask another HR person.',
  ALREADY_RESOLVED: 'That request has already been resolved.',

  // E9: personal details.
  SENSITIVE_FIELD: 'Ask HR to change your date of birth or address.',
  NOTHING_TO_CHANGE: 'Send at least one field to change.',
  DATE_OF_BIRTH: 'Date of birth must be a real date (YYYY-MM-DD) from 1940 on, at least 16 years ago.',
  BLOOD_GROUP: 'Blood group must be one of A+, A-, B+, B-, AB+, AB-, O+ or O-.',
  ADDRESS_FIELD: 'Each address line can be up to 200 characters, and the city and state up to 80.',
  PINCODE: 'The PIN code must be 6 digits.',
  EMERGENCY_NAME: 'The emergency contact name can be up to 100 characters.',
  EMERGENCY_RELATION: 'The relation can be up to 50 characters.',
  EMERGENCY_PHONE: 'The emergency contact phone must be a 10-digit Indian mobile number.',
  EMERGENCY_INCOMPLETE: 'An emergency contact needs both a name and a phone number, and a relation needs a name.',
  OWN_RECORD: 'You cannot change your own date of birth or address here. Ask another HR person.',

  // B14: mocked-location reports.
  MOCK_KIND: 'Only mocked punches are reported (kind "punch").',
  MOCK_LOCATION: 'latitude and longitude must both be valid coordinates or both be left out, and accuracy_m must be a number of metres.',
  MOCK_TEXT: 'provider can be up to 80 characters, app_version up to 40 and install_id up to 128.',
  REPORTS_RATE_LIMITED: 'Too many reports from this phone today. Try again tomorrow.',

  // B1: the day read. The code is the Scheduler's for its remarks window (attendancePunchController.js:572-574).
  DAY_OUT_OF_RANGE: 'You can look at a day of this month or last month.',

  // B8: HR's bulk phone reset.
  DEVICE_STATUS_FILTER: 'status must be active, revoked or all.',
  RESET_TARGET: 'Send either branch_id or employee_ids (1 to 500 employee ids), not both.',
  RESET_REASON: 'Say why the phones are being reset, in 3 to 200 characters.',
});

/** error and code first, and an extra field can never replace either of them. */
function sendError(res, status, code, message, extra = null) {
  const body = { error: message, code };
  for (const [key, value] of Object.entries(extra || {})) if (!(key in body)) body[key] = value;
  return res.status(status).json(body);
}

const notAuthenticated = (message = MESSAGES.SIGN_IN) => new HttpError(401, 'NOT_AUTHENTICATED', message);

/**
 * Express 4 does not catch a rejected promise from a handler: without this, a failed database
 * read would leave the request hanging instead of reaching the error handler.
 */
const asyncRoute = (fn) => (req, res, next) => {
  Promise.resolve().then(() => fn(req, res, next)).catch(next);
};

module.exports = { HttpError, MESSAGES, sendError, notAuthenticated, asyncRoute };
