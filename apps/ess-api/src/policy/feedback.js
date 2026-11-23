const { ROLES } = require('./roles');

/**
 * In-app feedback (#151): what one item may carry, and who reads them.
 *
 * Any signed-in employee sends feedback, with either sign-in. Only super admins read it: the
 * role is named exactly and nothing inherits its way in (requireRoles), so the CEO, who inherits
 * super_admin's admin duties elsewhere, does not see this list unless it is added here (decided
 * with the product owner, 23 Nov 2026). db/migrations/20261231200000_hr_ess_feedback.sql holds
 * the same limits: change both.
 */

const FEEDBACK_KINDS = Object.freeze(['bug', 'suggestion', 'other']);

/** Who reads the feedback list and opens its screenshots. */
const FEEDBACK_REVIEW_ROLES = new Set([ROLES.SUPER_ADMIN]);

/** What the app attaches to an item, each optional, with its longest value in characters. */
const CONTEXT_FIELDS = Object.freeze({
  screen: 200,
  app_version: 40,
  build_number: 20,
  platform: 40,
  os_version: 80,
  device_model: 120,
});

/** One optional screenshot: PNG or JPEG, up to 2 MB decoded, recognised by its first bytes too. */
const SCREENSHOT_CONTENT_TYPES = Object.freeze({
  'image/png': { ext: 'png', magic: Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) },
  'image/jpeg': { ext: 'jpg', magic: Buffer.from([0xff, 0xd8, 0xff]) },
});
const MAX_SCREENSHOT_BYTES = 2 * 1024 * 1024;

const MESSAGE_MIN = 5;
const MESSAGE_MAX = 2000;

module.exports = {
  FEEDBACK_KINDS,
  FEEDBACK_REVIEW_ROLES,
  CONTEXT_FIELDS,
  SCREENSHOT_CONTENT_TYPES,
  MAX_SCREENSHOT_BYTES,
  MESSAGE_MIN,
  MESSAGE_MAX,
};
