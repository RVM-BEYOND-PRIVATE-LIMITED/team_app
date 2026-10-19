const A = require('./wave6a');
const B = require('./wave6b');

/**
 * The Wall's scenario table (Phase 2A), in one export: every route it adds with one scenario for
 * every status the contract documents. tests/contract.test.js merges it with Waves 2 to 5.
 *
 * The two halves live in wave6a.js (posts, comments, reactions, praise, polls, settings) and
 * wave6b.js (announcements, celebrations, reports, moderation), each with its own small helpers,
 * so neither file is larger than the rest of the contract's tables added together.
 */
const WAVE_6 = { ...A.WAVE_6, ...B.WAVE_6B };

module.exports = { WAVE_6 };
