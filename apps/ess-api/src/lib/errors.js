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
