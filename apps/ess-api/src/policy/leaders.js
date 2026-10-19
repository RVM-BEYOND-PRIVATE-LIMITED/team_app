const { ROLES } = require('./roles');

/**
 * Phase 2D (task H5): the leaders' overview. The CEO and a super admin see the whole
 * organisation at a glance; every other role has its own narrower views already (the team's day,
 * the approvals Inbox). The overview counts only -- no names, no pay, no performance -- so a
 * number can never leak what a card would.
 */
const LEADER_ROLES = new Set([ROLES.CEO, ROLES.SUPER_ADMIN]);

module.exports = { LEADER_ROLES };
