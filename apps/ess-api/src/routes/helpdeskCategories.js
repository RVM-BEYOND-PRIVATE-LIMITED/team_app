const { asyncRoute } = require('../lib/errors');
const { activeCategories, categoryView } = require('../lib/helpdeskKit');
const { helpdeskSettings } = require('../policy/helpdesk');

/**
 * G1, the rules screen: the category list a raise form is built from, and the rules around it
 * (the reopen window, the rating range, whether anonymous raising and attachments are on). One
 * read, no arguments: the categories are fixed in code and seeded by the migration, so the form
 * and the server's refusals can never disagree (the same thinking as the Wall's F8 settings).
 *
 * A non-ticket row (leave, WFH, an attendance fix, an asset request) comes back with its `flow`
 * set: the app opens that flow instead of a raise form. Raising on one is refused with
 * HELPDESK_NOT_A_TICKET, and this list is where the app learns which is which.
 */

/** GET /api/ess/helpdesk/categories — the category list and the rules document (G1). */
function listHelpdeskCategoriesRoute({ store }) {
  return asyncRoute(async (_req, res) => {
    const rows = await activeCategories(store);
    res.json({
      categories: rows.map(categoryView),
      settings: helpdeskSettings(rows),
    });
  });
}

module.exports = { listHelpdeskCategoriesRoute };
