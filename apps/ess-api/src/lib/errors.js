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
  SIGN_IN_ALREADY_KEPT: 'That sign-in has already been used to stay signed in. Please sign in again.',
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
  HR_ACCESS_DENIED: 'Only HR, the CEO and super admins can open this.',
  ATTENDANCE_OVERRIDE_DENIED: 'Only HR, the CEO and super admins can do this.',
  PORTAL_LOGIN_REQUIRED: 'HR tools need your portal login. Sign in with your username or login phone.',

  // Request bodies and query strings.
  BODY_NOT_OBJECT: 'The request body must be a JSON object.',
  UNKNOWN_FIELD: 'The request has a field the server does not take.',
  INVALID_ID: 'That is not a valid id.',
  DATE_FORMAT: 'Dates must be real days written YYYY-MM-DD.',
  DATE_RANGE: 'from must be on or before to, and at most 366 days before it.',
  DATE_OUT_OF_RANGE: 'Dates must be from 2000-01-01 to 2099-12-31.',
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
  RECORD_CHANGED: 'Somebody else changed this record while you were saving. Open it again and try once more.',

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

  // C1-C12: requests, leave and approvals. The words the contract quotes; the codes the app reads
  // are the keys, except where an outcome shares another endpoint's code (CL_LIMIT, DAY_OUT_OF_RANGE).
  ATTENDANCE_REQUEST_TYPE: 'Choose the kind of attendance request: on duty, fix a day or excuse a late.',
  LEAVE_REQUEST_TYPE: 'Choose casual leave or leave without pay.',
  REQUEST_REASON: 'Say the reason, in 5 to 1,000 characters.',
  REQUEST_PLACE: 'Say where the duty is, in 1 to 120 characters.',
  REQUEST_TIMES: 'Give the corrected in or out times as HH:MM (24-hour).',
  REQUEST_TIMES_NEEDED: 'Give the in time, the out time, or both.',
  REQUEST_FUTURE: 'That day has not happened yet.',
  REQUEST_WINDOW: 'Requests can be for this month or last month only.',
  REQUEST_CLOSED: "Last month's requests closed on the 5th. Ask HR.",
  DUPLICATE_REQUEST: 'You already have a request for that day. Wait for it to be decided.',
  LIMIT_REACHED: "That is over this type's monthly limit. Check the balance on the form.",
  REQUEST_NOT_FOUND: 'That request was not found.',
  REQUEST_NOT_PENDING: 'Only a pending request can be withdrawn.',
  DECIDE_DECISION: 'Mark the request approved or rejected.',
  DECIDE_NOTE: 'Keep the note to 1,000 characters.',
  DECIDE_REJECT_NOTE: 'Say why the request is rejected, in at least 3 characters. The employee sees it.',
  ALREADY_DECIDED: 'That request has already been decided.',
  NOT_AN_APPROVER: "Only the person's manager or HR can decide this request.",
  NOT_LATE: 'That day is not a late arrival.',
  TIMES_INCOMPLETE: 'The day would still be missing an in or out time. Ask the employee for the full times.',
  DAY_LOCKED: 'That day is recorded as leave, a week off or a holiday. Change the day first.',
  CL_TAKEN: "This month's CL is already taken. Reject this request, or approve it as leave without pay.",
  CANNOT_CANCEL: 'Only an approved request can be cancelled.',
  CANCEL_REASON: 'Say why it is cancelled, in 3 to 200 characters.',
  APPROVAL_STATUS: 'status must be pending, approved, rejected, withdrawn, cancelled or all.',
  LIMIT_TYPE: 'Choose a request type to change.',
  LIMIT_VALUE: 'Give a whole number of requests (or minutes for short leave), or null for no limit.',
  BALANCES_MONTH: 'Look at this month or last month.',

  // D5-D8: push devices and notifications.
  PUSH_TOKEN: "The phone's push token is missing or not valid.",
  PUSH_DEVICE_LABEL: 'Keep the phone name to 80 characters.',
  PUSH_DEVICE_NOT_FOUND: 'That phone was not found.',
  NOTIFICATION_NOT_FOUND: 'That notification was not found.',
  NOTIFICATION_SETTINGS: 'Choose the notification categories: approvals, decisions, priority_tasks, mentions, replies, praise, announcements, acknowledgements or polls.',

  // E1-E12: Me and My Team.
  PHOTO_FORMAT: 'Send the photo as base64 image data (JPEG, PNG or WebP).',
  PHOTO_SIZE: 'A photo must be up to 1 MB after the app compresses it.',
  PHOTO_TYPE: 'A photo must be a JPEG, PNG or WebP image.',
  DIRECTORY_QUERY: 'Search by name or employee code, up to 60 characters.',
  DEPARTMENT_ID: 'department_id must be a department id.',
  DEPARTMENT_NOT_FOUND: 'That department was not found.',
  TEAM_FILTER: 'filter must be all, not_in, late or on_leave.',

  // F1-F9: the Wall.
  WALL_POST_BODY: 'Say something in 1 to 2,000 characters.',
  WALL_POST_KIND: 'Choose a post, praise, a wish or a poll.',
  WALL_SCOPE: "Choose the wall: 'org' for everybody, or 'branch' with your branch.",
  WALL_WRONG_BRANCH: 'That is not your branch. A branch post goes on your own branch wall.',
  WALL_ATTACHMENTS: 'Send up to 5 photos or PDFs, each with its own base64 data and content type.',
  WALL_POST_NOT_FOUND: 'That post was not found, or it has been removed.',
  WALL_OWN_POST: 'That is not your post.',
  WALL_EDIT_WINDOW: 'Posts can be changed for 15 minutes. Ask HR if something must change after that.',
  WALL_DELETE_ANNOUNCEMENT: 'An announcement cannot be deleted from the Wall. Ask HR.',
  WALL_HIDE_REASON: 'Say why it is hidden, in 3 to 200 characters.',
  WALL_NOT_HIDDEN: 'That is not hidden, so there is nothing to restore.',

  // F2: comments, replies and reactions.
  WALL_COMMENT_BODY: 'Say something in 1 to 1,000 characters.',
  WALL_COMMENT_NOT_FOUND: 'That comment was not found, or it has been removed.',
  WALL_OWN_COMMENT: 'That is not your comment.',
  WALL_REPLY_DEPTH: 'A reply cannot have replies of its own. Reply to the comment above instead.',
  WALL_REPLY_OTHER_POST: 'That comment is on another post.',
  WALL_REACTION: 'Choose one of the six reactions: like, love, laugh, clap, insightful or curious.',
  WALL_REACTION_ANNOUNCEMENT: 'Announcements are not reacted to. Acknowledge them instead.',
  WALL_REACTIONS_NONE: 'Nobody has reacted yet.',

  // F3: praise, and F6: wishes.
  WALL_PRAISE_BADGE: 'Choose one of the RVM badges.',
  WALL_PRAISE_WHY: 'Say why, in 3 to 280 characters.',
  WALL_PRAISE_SELF: 'Praise goes to somebody else. Ask a colleague to praise you.',
  WALL_WISH_OCCASION: "A wish is for a birthday or a work anniversary ('birthday' or 'anniversary').",
  WALL_WISH_SELF: 'Send your own birthday wishes to somebody else — a wish is for a colleague.',
  WALL_ALREADY_WISHED: 'You have already wished them this year. One wish each is enough.',

  // F4: polls.
  WALL_POLL_QUESTION: 'Ask a question in 3 to 300 characters.',
  WALL_POLL_OPTIONS: 'Give 2 to 10 options, each 1 to 120 characters.',
  WALL_POLL_CLOSES: 'Give the closing day, YYYY-MM-DD, within a year.',
  WALL_POLL_PAST: 'That closing day has already gone.',
  WALL_POLL_NOT_POLL: 'That post is not a poll.',
  WALL_POLL_CLOSED: 'This poll has closed.',
  WALL_POLL_OPTIONS_LOCKED: 'The options are fixed now that somebody has voted.',
  WALL_POLL_OPTION_UNKNOWN: 'That is not one of this poll\'s options.',
  WALL_POLL_SINGLE: 'Choose one option.',
  WALL_POLL_CHOICE: 'Choose at least one option.',

  // F5: announcements.
  WALL_ANNOUNCE_DENIED: 'Only HR, the CEO and super admins can post announcements.',
  WALL_ANNOUNCEMENT_TITLE: 'Give the announcement a title of 3 to 200 characters.',
  WALL_ANNOUNCEMENT_BODY: 'Write the announcement, in 3 to 5,000 characters.',
  WALL_ANNOUNCEMENT_AUDIENCE: 'The audience takes all, branch_ids, department_ids, roles or employee_ids.',
  WALL_ANNOUNCEMENT_PUBLISH: 'publish_at must be a real time, YYYY-MM-DDTHH:MM:SS with an offset.',
  WALL_ANNOUNCEMENT_PUBLISH_PAST: 'publish_at has already gone. Leave it out to publish now.',
  WALL_ANNOUNCEMENT_CLOSES: 'An announcement that needs acknowledgement needs a closing day, YYYY-MM-DD.',
  WALL_ANNOUNCEMENT_CLOSES_PAST: 'The closing day has already gone.',
  WALL_ANNOUNCEMENT_NOT_FOUND: 'That announcement was not found.',
  WALL_ANNOUNCEMENT_DELETE: 'Only the person who posted an announcement deletes it.',
  WALL_ANNOUNCEMENT_PIN_LIMIT: 'Up to 3 announcements can be pinned. Unpin one first.',
  WALL_ANNOUNCEMENT_ACK: 'That announcement does not need an acknowledgement.',
  WALL_ANNOUNCEMENT_STATUS: 'status must be all, draft or published.',
  WALL_ACK_CLOSED: 'This announcement has closed. Ask HR.',
  WALL_NOT_IN_AUDIENCE: 'That announcement was not sent to you.',

  // F6: celebrations.
  WALL_CELEBRATIONS: 'look_for_days must be between 1 and 90, or give a single date.',

  // F7, F8: moderation, reports and the rules document.
  WALL_REPORT_TARGET: 'Report a post or a comment, by post_id or comment_id.',
  WALL_REPORT_REASON: 'Say what is wrong, in 3 to 280 characters.',
  WALL_REPORT_DETAIL: 'Keep the detail to 500 characters.',
  WALL_ALREADY_REPORTED: 'You have already reported this. HR is looking at it.',
  WALL_REPORT_NOT_FOUND: 'That report was not found, or it has already been answered.',
  WALL_MODERATE_DENIED: 'Only HR can hide a post or a comment.',
  WALL_ALREADY_HIDDEN: 'That is already hidden.',
  WALL_MODERATION_QUEUE: 'status must be open, hidden, kept or all.',
  MODERATION_LIMIT: 'That is more than the Wall allows one person in a day. Try again tomorrow.',
  WALL_REACTION_LIMIT: 'That is more reactions than the Wall allows in a minute. Try again in a moment.',
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
