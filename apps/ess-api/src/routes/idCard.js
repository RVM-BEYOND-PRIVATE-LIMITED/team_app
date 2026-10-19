const { asyncRoute } = require('../lib/errors');
const { signVerifyToken, readVerifyToken, badToken } = require('../lib/idCardKit');

/**
 * The staff ID card (Phase 2C): the holder's own card from their HR record, with a verification
 * link the person they show it to can open with no sign-in at all.
 *
 * The link carries an HMAC-signed token (lib/idCardKit.js) under a key derived from the sign-ins'
 * own secret; a bad, forged or expired token is one 401, and the address is rate-limited per
 * IP in app.js, as the sign-in is. The verify answers only what the card itself shows: the
 * name, code, designation and branch, and never a photo, phone or anything else on the record.
 */

/** GET /api/ess/me/id-card — my card, with its verification link. */
function getMyIdCard({ store, config, now }) {
  return asyncRoute(async (req, res) => {
    const row = await store.getIdCardEmployee(req.auth.employee.id);
    const [branch, department] = await Promise.all([
      row.branch_id ? store.getBranch(row.branch_id) : null,
      row.department_id ? store.getDepartment(row.department_id) : null,
    ]);
    const card = {
      full_name: row.full_name,
      employee_code: row.employee_code,
      designation: row.designation,
      department_name: department ? department.name : null,
      branch_name: branch ? branch.name : null,
      photo_url: row.photo_path ? await store.signedPhotoUrl(row.photo_path) : null,
      verify_url: `/api/ess/id-card/verify/${signVerifyToken({
        jwtSecret: config.jwtSecret,
        employeeId: row.id,
        now: now(),
      })}`,
    };
    res.json({ card });
  });
}

/** GET /api/ess/id-card/verify/:token — what the card shows, no sign-in (rate-limited per IP). */
function verifyIdCard({ store, config, now }) {
  return asyncRoute(async (req, res) => {
    const verified = readVerifyToken(req.params.token, config.jwtSecret, now());
    if (!verified) throw badToken();
    const row = await store.getIdCardEmployee(verified.employeeId);
    if (!row || row.is_archived) throw badToken();
    const branch = row.branch_id ? await store.getBranch(row.branch_id) : null;
    res.json({
      valid: true,
      full_name: row.full_name,
      employee_code: row.employee_code,
      designation: row.designation,
      branch_name: branch ? branch.name : null,
    });
  });
}

module.exports = { getMyIdCard, verifyIdCard };
