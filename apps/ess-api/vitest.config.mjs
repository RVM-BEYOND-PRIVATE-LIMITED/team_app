import { defineConfig } from 'vitest/config';

/**
 * The ESS is CommonJS throughout, as the Scheduler is. Vitest 4 cannot be `require`d, so its
 * globals are switched on instead and the test files keep using `require` for the code under
 * test (the Scheduler's vitest.config.mjs does the same).
 *
 * The tests never reach a real database: they build the app on an in-memory stand-in for the
 * Supabase client (tests/helpers/fakeSupabase.js).
 */
export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    include: ['tests/**/*.test.js'],
    setupFiles: ['./tests/setup.js'],
    // A test that silences console.error for an expected failure gets it back for the next one.
    restoreMocks: true,
    reporters: ['default'],
  },
});
