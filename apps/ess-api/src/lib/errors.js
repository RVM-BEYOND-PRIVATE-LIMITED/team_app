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
 */
class HttpError extends Error {
  constructor(status, code, message) {
    super(message);
    this.name = 'HttpError';
    this.status = status;
    this.code = code;
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

const sendError = (res, status, code, message) => res.status(status).json({ error: message, code });

const notAuthenticated = (message = MESSAGES.SIGN_IN) => new HttpError(401, 'NOT_AUTHENTICATED', message);

/**
 * Express 4 does not catch a rejected promise from a handler: without this, a failed database
 * read would leave the request hanging instead of reaching the error handler.
 */
const asyncRoute = (fn) => (req, res, next) => {
  Promise.resolve().then(() => fn(req, res, next)).catch(next);
};

module.exports = { HttpError, MESSAGES, sendError, notAuthenticated, asyncRoute };
