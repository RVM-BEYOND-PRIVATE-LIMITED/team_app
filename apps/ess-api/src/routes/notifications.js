const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const { bodyWith, idParam, invalid } = require('../lib/validate');
const { LIST_LIMITS } = require('../lib/store');
const { CATEGORIES, notificationView, settingsView } = require('../policy/notifications');

/**
 * Tasks D6 and D8: the notifications Inbox and the categories a person turns off.
 *
 * Every notification is an in-app row first (src/lib/notify.js writes the ESS's own events, the
 * push job imports priority tasks); the phone's push is the push worker's business. Reading a
 * notification is always the caller's own: somebody else's id is 404, as if it did not exist.
 */

/** GET /api/ess/notifications: newest first, at most 100, with the unread count. */
function listNotifications({ store }) {
  return asyncRoute(async (req, res) => {
    const employeeId = req.auth.employee.id;
    const rows = await store.listNotifications(employeeId);
    const truncated = rows.length > LIST_LIMITS.notifications;
    const shown = rows.slice(0, LIST_LIMITS.notifications);
    const unread = await store.countUnreadNotifications(employeeId);
    res.json({ notifications: shown.map(notificationView), unread, truncated });
  });
}

/** POST /api/ess/notifications/{id}/read: 204 whether or not it was already read. */
function readNotification({ store, now }) {
  return asyncRoute(async (req, res) => {
    const id = idParam(req.params.id);
    const employeeId = req.auth.employee.id;
    const row = await store.getNotification(id, employeeId);
    if (!row) throw new HttpError(404, 'NOT_FOUND', MESSAGES.NOTIFICATION_NOT_FOUND);
    if (!row.read_at) await store.markNotificationRead(id, employeeId, now().toISOString());
    res.status(204).end();
  });
}

/** POST /api/ess/notifications/read-all: marks what is unread and says how many. */
function readAllNotifications({ store, now }) {
  return asyncRoute(async (req, res) => {
    const marked = await store.markAllNotificationsRead(req.auth.employee.id, now().toISOString());
    res.json({ marked });
  });
}

/** GET /api/ess/notifications/settings: every category, on or off, and the quiet hours. */
function getSettings({ store }) {
  return asyncRoute(async (req, res) => {
    const row = await store.getNotificationSettings(req.auth.employee.id);
    res.json(settingsView(row));
  });
}

/** PUT /api/ess/notifications/settings { disabled_categories: [...] }. */
function putSettings({ store, now }) {
  return asyncRoute(async (req, res) => {
    const body = bodyWith(req, ['disabled_categories']);
    const list = body.disabled_categories;
    if (!Array.isArray(list) || list.some((c) => !CATEGORIES.includes(c))) {
      throw invalid(MESSAGES.NOTIFICATION_SETTINGS);
    }
    const disabled = [...new Set(list)];
    const saved = await store.saveNotificationSettings(req.auth.employee.id, {
      disabled_categories: disabled,
      updated_at: now().toISOString(),
    });
    res.json(settingsView(saved));
  });
}

module.exports = { listNotifications, readNotification, readAllNotifications, getSettings, putSettings };
