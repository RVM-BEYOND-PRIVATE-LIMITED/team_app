const { MESSAGES } = require('../../src/lib/errors');
const { PORTAL_PEOPLE } = require('./fixtures');
const { tokens } = require('./app');

/** Shared expectations for the endpoint tests. */

/** A refusal in the house shape, with a message somebody can read. */
function expectRefusal(res, status, code) {
  expect(res.status, JSON.stringify(res.body)).toBe(status);
  expect(res.headers['content-type']).toMatch(/^application\/json/);
  expect(res.body).toEqual({ error: expect.any(String), code });
  expect(res.body.error.length).toBeGreaterThan(10);
}

/** A 400 VALIDATION_FAILED with exactly this message. */
function expectInvalid(res, message) {
  expectRefusal(res, 400, 'VALIDATION_FAILED');
  expect(res.body.error).toBe(message);
}

/** Expected database failures log to the console; the tests silence them. */
const quietErrors = () => vi.spyOn(console, 'error').mockImplementation(() => {});

/**
 * Every signed-in kind of caller, for the role tables: each portal role in the fixture and the
 * attendance-only employee. `token(people)` signs the caller's token.
 */
const CALLERS = [
  ...PORTAL_PEOPLE.map(([key]) => [key, (people) => tokens.portal(people[key])]),
  ['attendance', (people) => tokens.attendance(people.attendance)],
];

/**
 * What a role guard answers each caller: 200-ish (null) for the allowed roles, PORTAL_LOGIN_REQUIRED
 * for the attendance session, and `code` for every other role.
 */
const guardOutcome = (who, allowed, code) => {
  if (who === 'attendance') return 'PORTAL_LOGIN_REQUIRED';
  return allowed.includes(who) ? null : code;
};

/** The words the guard refuses with, so a test can check the reply says the right thing. */
const guardMessage = (code) => MESSAGES[code];

module.exports = { expectRefusal, expectInvalid, quietErrors, CALLERS, guardOutcome, guardMessage };
