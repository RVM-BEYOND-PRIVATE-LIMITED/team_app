const { asyncRoute } = require('../lib/errors');
const { wallSettings } = require('../policy/wall');
const { MAX_PINNED } = require('../policy/wall');

/**
 * Task F8, the Wall's settings: who may post what, and the numbers every form is built from.
 *
 * KP decided the rules (16 Oct, decision 8): everyone posts, comments, reacts, praises and runs
 * polls; only HR, the CEO and super admins post announcements; HR hides anything, with a reason.
 * What is NOT here is a table: the build reads the rules from `src/policy/wall.js`, so a change is
 * a reviewed code change, not a row somebody can edit. `GET /api/ess/wall/settings` returns them,
 * with the badge catalogue, so the app renders its forms from the server's own rules.
 */

/** GET /api/ess/wall/settings — the rules document (F8). */
function getWallSettings() {
  return asyncRoute(async (_req, res) => {
    res.json(wallSettings());
  });
}

module.exports = { getWallSettings, MAX_PINNED };
