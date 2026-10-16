const { TEST_JWT_SECRET } = require('./helpers/constants');

// The verbatim Scheduler code in tests/helpers reads process.env.JWT_SECRET, as it does in the
// Scheduler. The ESS itself reads the secret only from its config, which the tests build with
// the same value.
process.env.JWT_SECRET = TEST_JWT_SECRET;
