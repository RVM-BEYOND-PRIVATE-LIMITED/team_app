/**
 * Fixed values shared by the tests. Nothing here is a real secret or a real address: the tests
 * never connect to a database (tests/helpers/fakeSupabase.js).
 */

/** Long enough for config.js (32 characters or more) and obviously not production's. */
const TEST_JWT_SECRET = 'ess-tests-only-not-a-real-secret-0123456789';

/** The app's clock in most tests: 16 Oct 2026, 12:00 IST. */
const NOW = new Date('2026-10-16T06:30:00.000Z');

/** The IST day of NOW. */
const TODAY = '2026-10-16';

/** When most test tokens are signed: a minute before NOW. */
const SIGNED_AT = new Date(NOW.getTime() - 60 * 1000);

const TEST_ENV = Object.freeze({
  JWT_SECRET: TEST_JWT_SECRET,
  // Never contacted: the store is given an in-memory client.
  SUPABASE_URL: 'http://127.0.0.1:54321',
  SUPABASE_SERVICE_KEY: 'test-service-key-not-real',
});

module.exports = { TEST_JWT_SECRET, NOW, TODAY, SIGNED_AT, TEST_ENV };
