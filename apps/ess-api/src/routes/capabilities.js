const { asyncRoute } = require('../lib/errors');
const { istDay } = require('../lib/time');
const { isActive } = require('../policy/employment');
const { capabilitiesFor } = require('../policy/capabilities');

/**
 * GET /api/ess/me/capabilities (task A4): which tabs, sections and approvals the app offers
 * this person. The rules are in policy/capabilities.js; this only gathers the facts they need.
 *
 * Direct reports count only people still on strength, by the same rule that refuses a leaver
 * at sign-in, so somebody serving notice still counts and somebody past their last day does not.
 */
function capabilitiesRoute({ config, store, now }) {
  return asyncRoute(async (req, res) => {
    const { kind, role, employee } = req.auth;
    const today = istDay(now());
    const reports = await store.listDirectReports(employee.id);
    const directReports = reports.filter((r) => isActive(r, today)).length;
    // The numbers HR set (task C6), when the limits table is there. This is the app's launch
    // call: before the migration it answers with the code's own defaults, never a 503.
    let limitRows = null;
    try {
      limitRows = await store.getRequestLimits();
    } catch (e) {
      if (!(e && e.code === 'MODULE_NOT_INSTALLED')) throw e;
    }
    res.json(capabilitiesFor({ kind, role, directReports, pushEnabled: config.push.enabled, limitRows }));
  });
}

module.exports = { capabilitiesRoute };
