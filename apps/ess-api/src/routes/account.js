const bcrypt = require('bcryptjs');
const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const { bodyWith, optionalText, chars } = require('../lib/validate');
const { recordAfter } = require('../lib/audit');

/**
 * Account & Security for the sessions the ESS owns (issue #10, option A/C).
 *
 * A portal sign-in already has every screen on the Scheduler. An attendance-only sign-in has
 * no users row, so the Scheduler's /api/me guard cannot answer it. This is the small surface
 * it does need:
 *
 *   GET  /api/ess/me/account    what this sign-in can show, and what it may change
 *   POST /api/ess/me/password   change the password this sign-in uses
 *
 * Email and phone are the login identifiers. For an attendance-only employee they live on the
 * HR record and are HR-managed: changing them here without proving the new address would be a
 * way to move somebody's sign-in. The screen says so, and HR's data-request flow (A8) is the
 * path. A portal login keeps using the Scheduler's own two-step change, which sends the code
 * to the new address. Nothing in the Scheduler changes.
 *
 * A password change ends every live ESS sign-in for the person, including this one: the app
 * signs out and asks for the new password. For an attendance login the update also moves
 * sessions_valid_from, the Scheduler's own cut-off that voids every punch session issued
 * before it. A portal password change stamps users.password_changed_at for the same reason.
 */

const PASSWORD_MIN = 8;
const PASSWORD_MAX = 128;

function readPassword(value, message) {
  const s = optionalText(value);
  if (!s || chars(s) < PASSWORD_MIN || chars(s) > PASSWORD_MAX) {
    throw new HttpError(400, 'INVALID_PASSWORD', message);
  }
  return s;
}

function accountRoutes({ store, now }) {
  const get = asyncRoute(async (req, res) => {
    const { kind, userId, role, employee } = req.auth;

    if (kind === 'portal') {
      const user = await store.getUserAccount(userId);
      if (!user) throw new HttpError(401, 'NOT_AUTHENTICATED', MESSAGES.SIGN_IN_AGAIN);
      return res.json({
        login_kind: 'portal',
        role: role ?? null,
        username: user.username ?? null,
        email: user.email ?? null,
        email_verified: Boolean(user.email_verified_at),
        phone_number: user.phone_number ?? null,
        two_factor_enabled: Boolean(user.two_factor_enabled),
        can_change_email: true,
        can_change_phone: true,
        can_change_password: true,
        can_use_two_factor: true,
        note: null,
      });
    }

    const contact = await store.getEmployeeContact(employee.id);
    return res.json({
      login_kind: 'attendance',
      role: null,
      username: employee.employee_code ?? contact?.employee_code ?? null,
      email: contact?.email ?? null,
      email_verified: Boolean(contact?.email),
      phone_number: contact?.phone ?? null,
      two_factor_enabled: false,
      can_change_email: false,
      can_change_phone: false,
      can_change_password: true,
      can_use_two_factor: false,
      note: MESSAGES.HR_MANAGES_CONTACT,
    });
  });

  const changePassword = asyncRoute(async (req, res) => {
    const body = bodyWith(req, ['current_password', 'new_password', 'confirm_password']);
    const newPassword = readPassword(body.new_password, MESSAGES.NEW_PASSWORD);
    if (body.confirm_password !== undefined && body.confirm_password !== body.new_password) {
      throw new HttpError(400, 'PASSWORD_MISMATCH', MESSAGES.PASSWORD_MISMATCH);
    }

    const { kind, employee } = req.auth;

    // A portal login has the Scheduler's own Account & Security, which changes all four
    // credentials in one place. Keeping one writer for a users row is the point: the ESS
    // writes only the attendance login's password, a table it already owns the flow for.
    if (kind === 'portal') throw new HttpError(409, 'USE_SCHEDULER', MESSAGES.PORTAL_ACCOUNT_CHANGE);

    const account = await store.getAttendancePasswordHash(employee.id);
    if (!account) throw new HttpError(403, 'NO_ATTENDANCE_LOGIN', MESSAGES.NO_ATTENDANCE_LOGIN);
    const currentHash = account.password_hash || null;

    // A first-time attendance login may have no hash yet: this is where the employee sets it.
    // Every other case proves the current password before replacing it.
    if (currentHash) {
      const current = optionalText(body.current_password);
      if (!current) throw new HttpError(400, 'CURRENT_PASSWORD_REQUIRED', MESSAGES.CURRENT_PASSWORD);
      if (!(await bcrypt.compare(current, currentHash))) {
        throw new HttpError(401, 'WRONG_PASSWORD', MESSAGES.WRONG_PASSWORD);
      }
    }

    const at = now().toISOString();
    const hash = await bcrypt.hash(newPassword, 10);

    // End the old sign-ins first. If the password write then fails, the person is signed out
    // but the old password is still the one that works: nothing is left half-changed.
    await store.revokeAllSessionsForEmployee(employee.id, at, 'password_changed');
    await store.updateAttendancePassword(employee.id, hash, at);

    await recordAfter(store, req, {
      action: 'account.password.changed',
      targetEmployeeId: employee.id,
      details: { login_kind: kind },
    });

    res.json({ ok: true, signed_out: true, message: MESSAGES.PASSWORD_SET });
  });

  return { get, changePassword };
}

module.exports = { accountRoutes };
