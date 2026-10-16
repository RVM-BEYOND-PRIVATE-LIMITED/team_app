const { loadConfig } = require('../../src/config');
const { createSupabaseStore } = require('../../src/lib/store');
const { createApp } = require('../../src/app');
const { createFakeSupabase } = require('./fakeSupabase');
const { company, STUDENT_ID } = require('./fixtures');
const { NOW, SIGNED_AT, TEST_ENV } = require('./constants');
const S = require('./schedulerTokens');

/**
 * The real app, on the real store, over an in-memory client: everything but the database is
 * production code.
 *
 * @param {object} [options]
 * @param {object} [options.env]     environment overrides, read through config.js as in production
 * @param {(world: {tables: object, people: object}) => void} [options.setup]  edit the fixture before the app sees it
 * @param {Date|(() => Date)} [options.now]  the app's clock; 16 Oct 2026 12:00 IST by default
 * @param {object} [options.limits]  smaller rate limits or health deadline
 */
function buildApp({ env = {}, setup, now = NOW, limits } = {}) {
  const config = loadConfig({ ...TEST_ENV, ...env });
  const world = company();
  if (setup) setup(world);
  const clock = typeof now === 'function' ? now : () => new Date(now.getTime());
  // The database's clock is the app's, so a DEFAULT now() column reads the test's time.
  const db = createFakeSupabase(world.tables, { now: clock });
  const store = createSupabaseStore(config, { client: db });
  const app = createApp({ config, store, now: clock, limits });
  return { app, db, store, config, people: world.people };
}

/** Tokens as the Scheduler issues them, signed a minute before NOW unless told otherwise. */
const tokens = {
  portal: (person, when = SIGNED_AT) => S.signedAt(when, () => S.portalLoginToken(person.user, 'Faridabad')),
  twoFactor: (person, when = SIGNED_AT) => S.signedAt(when, () => S.tokenFor(person.user, 'Faridabad')),
  attendance: (person, method = 'otp', when = SIGNED_AT) => S.signedAt(when, () => S.issuePunchSession(person.employee.id, method)),
  student: (when = SIGNED_AT) => S.signedAt(when, () => S.studentToken({ id: STUDENT_ID, name: 'Test Student', location_id: 1 })),
  undertaking: (when = SIGNED_AT) => S.signedAt(when, () => S.issueAdmissionUndertakingToken({ admissionId: 42, phoneNumber: '9876500000' })),
};

const bearer = (token) => ({ Authorization: `Bearer ${token}` });

module.exports = { buildApp, tokens, bearer };
