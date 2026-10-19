const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const { bodyWith, requiredText, optionalText, chars, idParam, invalid } = require('../lib/validate');

/**
 * Task D5: the phone registers its FCM token after sign-in, and revokes it on sign-out. One
 * install, one row: registering a token that another row holds moves it to the caller and lifts
 * any revocation, which is what a reinstalled or handed-over phone does.
 *
 * The token is never sent back: the app already has it, and no reply needs it.
 */

/** FCM tokens never carry control characters; a JSON string can smuggle one into the column. */
const hasControlCharacters = (value) => [...value].some((ch) => {
  const code = ch.charCodeAt(0);
  return code < 32 || code === 127;
});

const deviceView = (d) => ({
  id: d.id,
  platform: d.platform,
  device_label: d.device_label ?? null,
  install_id: d.install_id ?? null,
  created_at: d.created_at,
  updated_at: d.updated_at,
  last_seen_at: d.last_seen_at,
});

/** POST /api/ess/push-devices { token, device_label?, install_id? } */
function registerPushDevice({ store, now }) {
  return asyncRoute(async (req, res) => {
    const body = bodyWith(req, ['token', 'device_label', 'install_id']);
    const token = requiredText(body.token, { min: 20, max: 4096, message: MESSAGES.PUSH_TOKEN });
    if (hasControlCharacters(token)) throw invalid(MESSAGES.PUSH_TOKEN);
    const label = optionalText(body.device_label);
    if (label === undefined || (label && chars(label) > 80)) throw invalid(MESSAGES.PUSH_DEVICE_LABEL);
    const install = optionalText(body.install_id);
    if (install === undefined || (install && chars(install) > 128)) throw invalid(MESSAGES.BAD_INSTALL_ID);

    const at = now().toISOString();
    const saved = await store.registerPushDevice({
      employee_id: req.auth.employee.id,
      token,
      platform: 'android',
      device_label: label,
      install_id: install,
      updated_at: at,
      last_seen_at: at,
      revoked_at: null,
    });
    res.status(201).json({ device: deviceView(saved) });
  });
}

/** DELETE /api/ess/push-devices/{id}: sign-out stops the pushes to this phone. */
function revokePushDevice({ store, now }) {
  return asyncRoute(async (req, res) => {
    const id = idParam(req.params.id);
    const out = await store.revokePushDevice(id, req.auth.employee.id, now().toISOString());
    if (!out) throw new HttpError(404, 'NOT_FOUND', MESSAGES.PUSH_DEVICE_NOT_FOUND);
    res.status(204).end();
  });
}

module.exports = { registerPushDevice, revokePushDevice, deviceView };
