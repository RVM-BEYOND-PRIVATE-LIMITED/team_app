const js = require('@eslint/js');
const globals = require('globals');

/**
 * ESLint for the ESS (ADR-0008). The rules that matter most are no-undef and no-unused-vars:
 * the Scheduler has no linter and has shipped handlers that used a name never defined.
 *
 * ecmaVersion 2023 is what Node 20 parses, so syntax newer than the oldest supported Node
 * fails here rather than on the server.
 */
module.exports = [
  { ignores: ['node_modules/**', 'coverage/**'] },
  js.configs.recommended,
  {
    files: ['**/*.js', '**/*.cjs'],
    languageOptions: {
      ecmaVersion: 2023,
      sourceType: 'commonjs',
      globals: { ...globals.node },
    },
    rules: {
      'no-undef': 'error',
      'no-unused-vars': ['error', { args: 'after-used', argsIgnorePattern: '^_', caughtErrors: 'all' }],
    },
  },
  {
    files: ['**/*.mjs'],
    languageOptions: { ecmaVersion: 2023, sourceType: 'module', globals: { ...globals.node } },
  },
  {
    // vitest runs with globals on (vitest.config.mjs), so the test files use describe/it/expect
    // without importing them.
    files: ['tests/**/*.js'],
    languageOptions: { globals: { ...globals.node, ...globals.vitest } },
  },
];
