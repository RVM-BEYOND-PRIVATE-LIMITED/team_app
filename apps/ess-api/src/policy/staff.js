const { ROLES } = require('./roles');

/**
 * Roles that are never staff, whatever else is true of them: a student, and the connector
 * identity, which cannot sign in at all (controllers/userController.js:399-413). employeeAuth
 * refuses them (403 NOT_AN_EMPLOYEE), a kept sign-in whose account turns into one ends, and the
 * one-field sign-in never offers one.
 */
const NOT_STAFF_ROLES = new Set([ROLES.STUDENT, ROLES.BOT_READONLY]);

const isStaffRole = (role) => !NOT_STAFF_ROLES.has(role);

module.exports = { NOT_STAFF_ROLES, isStaffRole };
