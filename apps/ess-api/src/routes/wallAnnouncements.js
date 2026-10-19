const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const { bodyWith, requiredText, idParam, oneQueryValue, invalid } = require('../lib/validate');
const { istDay } = require('../lib/time');
const { LIST_LIMITS } = require('../lib/store');
const { MAX_PINNED, canAnnounce, canModerate, audienceView } = require('../policy/wall');
const { attachmentsFrom, storeAttachments, notFound } = require('../lib/wallKit');
const { resolveAudience, audienceLabel, countsOf } = require('../lib/wallAudience');
const { announcementView } = require('./wallViews');
const { notifyAnnouncement } = require('../lib/wallNotify');

/**
 * Task F5, staff announcements: HR's (and the CEO's and super admins'; decision 8) notices to an
 * audience of branches, departments, roles or named people, published now or scheduled, with a
 * closing date, a read and acknowledgement count for the sender, and up to three pinned.
 *
 * Nothing here touches the Scheduler's student notices: the tables are the ESS's own
 * (db/migrations/20261108000003_hr_ess_announcements.sql), and no id, path or query is shared.
 *
 * The audience is resolved ONCE, when the announcement is published, into one row per person
 * (hr_ess_announcement_audience). That is what makes the counts exact, the reminder honest ("sent
 * to 40, read by 12, acknowledged by 7") and the feed one read: "sent to me" is a row.
 *
 * Email and push are log-only (KP, 19 Oct: no provider yet). The in-app rows are written here;
 * the push worker delivers them, and the deploy's log says push is log-only without `FIREBASE_*`.
 */

/** Whether this caller is the sender, or HR (who may see how any announcement did). */
const seesSenderView = (auth, row) => row.employee_id === auth.employee.id || canModerate(auth.kind, auth.role);

/** A past or future instant written ISO with an offset, as `publish_at` must be. */
function instantFrom(value) {
  if (typeof value !== 'string') return undefined;
  const text = value.trim();
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:\d{2})$/.test(text)) return undefined;
  const at = new Date(text);
  return Number.isNaN(at.getTime()) ? undefined : at;
}

/** A real calendar day, written YYYY-MM-DD. */
const isDay = (v) => {
  if (typeof v !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(v)) return false;
  const d = new Date(`${v}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === v;
};

/**
 * POST /api/ess/wall/announcements — post one, now or scheduled (F5).
 * { title, body, audience?, attachments?, needs_ack?, closes_on?, publish_at?, pinned? }
 */
function createAnnouncement({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    if (!canAnnounce(req.auth.kind, req.auth.role)) throw new HttpError(403, 'NOT_AN_ANNOUNCER', MESSAGES.WALL_ANNOUNCE_DENIED);
    const body = bodyWith(req, ['title', 'body', 'audience', 'attachments', 'needs_ack', 'closes_on', 'publish_at', 'pinned']);
    const title = requiredText(body.title, { min: 3, max: 200, message: MESSAGES.WALL_ANNOUNCEMENT_TITLE });
    const text = requiredText(body.body, { min: 3, max: 5000, message: MESSAGES.WALL_ANNOUNCEMENT_BODY });
    const audience = audienceView(body.audience);
    if (!audience) throw invalid(MESSAGES.WALL_ANNOUNCEMENT_AUDIENCE);
    if (body.needs_ack !== undefined && typeof body.needs_ack !== 'boolean') throw invalid(MESSAGES.WALL_ANNOUNCEMENT_CLOSES);
    if (body.pinned !== undefined && typeof body.pinned !== 'boolean') throw invalid(MESSAGES.WALL_ANNOUNCEMENT_PIN_LIMIT);
    const needsAck = body.needs_ack === true;
    const today = istDay(now());
    let closesOn = null;
    if (body.closes_on !== undefined && body.closes_on !== null && body.closes_on !== '') {
      if (!isDay(body.closes_on)) throw invalid(MESSAGES.WALL_ANNOUNCEMENT_CLOSES);
      if (body.closes_on < today) throw invalid(MESSAGES.WALL_ANNOUNCEMENT_CLOSES_PAST);
      closesOn = body.closes_on;
    }
    if (needsAck !== (closesOn !== null)) throw invalid(MESSAGES.WALL_ANNOUNCEMENT_CLOSES);

    const at = now();
    let publishAt = null;
    if (body.publish_at !== undefined && body.publish_at !== null && body.publish_at !== '') {
      publishAt = instantFrom(body.publish_at);
      if (!publishAt) throw invalid(MESSAGES.WALL_ANNOUNCEMENT_PUBLISH);
      if (publishAt.getTime() <= at.getTime()) throw invalid(MESSAGES.WALL_ANNOUNCEMENT_PUBLISH_PAST);
    }
    const pinned = body.pinned === true;
    if (pinned) {
      const pinnedCount = await store.countPinnedAnnouncements();
      if (pinnedCount >= MAX_PINNED) throw new HttpError(409, 'PIN_LIMIT', MESSAGES.WALL_ANNOUNCEMENT_PIN_LIMIT);
    }
    const files = attachmentsFrom(body, { folder: 'announcement', employeeId: employee.id });
    const stored = await storeAttachments(store, files);
    const created = await store.createAnnouncement({
      employee_id: employee.id,
      title,
      body: text,
      attachments: stored,
      audience,
      publish_at: publishAt ? publishAt.toISOString() : at.toISOString(),
      published_at: publishAt ? null : at.toISOString(),
      needs_ack: needsAck,
      closes_on: closesOn,
      pinned,
      created_at: at.toISOString(),
      updated_at: at.toISOString(),
    });
    // Published now: the audience is resolved and everyone hears at once. Scheduled: the job does
    // both when the time arrives (src/jobs/wall.js).
    let counts = { sent: 0, read: 0, acknowledged: 0, not_acknowledged: 0 };
    if (!publishAt) counts = await publishNow(store, created, employee);
    res.status(201).json({
      announcement: await announcementView(store, created, {
        me: employee.id,
        author: employee,
        audienceLabel: await audienceLabel(store, audience),
      }),
      counts,
      scheduled: Boolean(publishAt),
    });
  });
}

/**
 * Publishing: the audience is resolved and its rows written, then everybody hears (F5). Answers
 * the counts. Never throws for a notification failure -- notify is best effort by design.
 */
async function publishNow(store, row) {
  const people = await resolveAudience(store, row.audience);
  if (people.length) {
    await store.addAudienceRows(people.map((p) => ({ announcement_id: row.id, employee_id: p.id })));
  }
  await notifyAnnouncement({
    store,
    announcement: row,
    employeeIds: people.map((p) => p.id),
    needsAck: row.needs_ack === true,
  });
  return countsOf(store, row.id);
}

/** GET /api/ess/wall/announcements — the announcements sent to me, pinned first (F5). */
function listAnnouncements({ store }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const limit = LIST_LIMITS.announcementsInbox;
    const audienceRows = await store.listMyAudienceRows(employee.id, limit);
    const rows = await store.listAnnouncementsFor(audienceRows, limit);
    const truncated = rows.length > limit;
    const shown = rows.slice(0, limit);
    // Pinned first, then newest: what the Wall's banner shows.
    const ordered = [...shown].sort((a, b) => (
      (b.pinned === true) - (a.pinned === true)
      || Date.parse(b.published_at) - Date.parse(a.published_at)
    ));
    const announcements = [];
    for (const row of ordered) {
      const read = await store.getAnnouncementRead(row.id, employee.id);
      announcements.push(await announcementView(store, row, {
        me: employee.id,
        author: await store.getEmployeeCard(row.employee_id),
        read,
      }));
    }
    res.json({ announcements, truncated });
  });
}

/** GET /api/ess/wall/announcements/{id} — one, if it was sent to me, or I sent it (F5). */
function getAnnouncement({ store }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const id = idParam(req.params.id);
    const row = await store.getAnnouncement(id);
    if (!row || row.deleted_at) throw notFound(MESSAGES.WALL_ANNOUNCEMENT_NOT_FOUND);
    const sender = seesSenderView(req.auth, row);
    // A draft or a scheduled one is its sender's own until it is published.
    if (!row.published_at && !sender) throw notFound(MESSAGES.WALL_ANNOUNCEMENT_NOT_FOUND);
    const audience = row.published_at ? await store.listAudienceRows(id) : [];
    const mine = audience.some((a) => a.employee_id === employee.id);
    if (row.published_at && !mine && !sender) throw notFound(MESSAGES.WALL_ANNOUNCEMENT_NOT_FOUND);
    const read = mine ? await store.getAnnouncementRead(id, employee.id) : null;
    const view = await announcementView(store, row, {
      me: employee.id,
      author: await store.getEmployeeCard(row.employee_id),
      read,
      audienceLabel: sender ? await audienceLabel(store, row.audience) : null,
    });
    if (sender) view.counts = await countsOf(store, id);
    res.json({ announcement: view });
  });
}

/** PATCH /api/ess/wall/announcements/{id} { title?, body?, pinned? } — the sender's own (F5). */
function editAnnouncement({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const id = idParam(req.params.id);
    const body = bodyWith(req, ['title', 'body', 'pinned']);
    const row = await store.getAnnouncement(id);
    if (!row || row.deleted_at) throw notFound(MESSAGES.WALL_ANNOUNCEMENT_NOT_FOUND);
    if (row.employee_id !== employee.id) throw new HttpError(403, 'NOT_YOURS', MESSAGES.WALL_ANNOUNCEMENT_DELETE);
    const patch = {};
    if (body.title !== undefined) patch.title = requiredText(body.title, { min: 3, max: 200, message: MESSAGES.WALL_ANNOUNCEMENT_TITLE });
    if (body.body !== undefined) patch.body = requiredText(body.body, { min: 3, max: 5000, message: MESSAGES.WALL_ANNOUNCEMENT_BODY });
    if (body.pinned !== undefined) {
      if (typeof body.pinned !== 'boolean') throw invalid(MESSAGES.WALL_ANNOUNCEMENT_PIN_LIMIT);
      if (body.pinned === true && row.pinned !== true) {
        const pinnedCount = await store.countPinnedAnnouncements();
        if (pinnedCount >= MAX_PINNED) throw new HttpError(409, 'PIN_LIMIT', MESSAGES.WALL_ANNOUNCEMENT_PIN_LIMIT);
      }
      patch.pinned = body.pinned;
    }
    if (!Object.keys(patch).length) throw invalid(MESSAGES.NOTHING_TO_CHANGE);
    patch.updated_at = now().toISOString();
    if (patch.title !== undefined || patch.body !== undefined) patch.edited_at = row.edited_at ?? patch.updated_at;
    const saved = await store.updateAnnouncement(id, patch);
    res.json({
      announcement: await announcementView(store, saved, {
        me: employee.id,
        author: employee,
        audienceLabel: await audienceLabel(store, saved.audience),
      }),
    });
  });
}

/** DELETE /api/ess/wall/announcements/{id} — the sender's own always (F5). */
function deleteAnnouncement({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const id = idParam(req.params.id);
    bodyWith(req, []);
    const row = await store.getAnnouncement(id);
    if (!row || row.deleted_at) throw notFound(MESSAGES.WALL_ANNOUNCEMENT_NOT_FOUND);
    if (row.employee_id !== employee.id) throw new HttpError(403, 'NOT_YOURS', MESSAGES.WALL_ANNOUNCEMENT_DELETE);
    await store.updateAnnouncement(id, { deleted_at: now().toISOString(), updated_at: now().toISOString() });
    res.status(204).end();
  });
}

/** POST /api/ess/wall/announcements/{id}/read — 204, first open (F5). */
function readAnnouncement({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const id = idParam(req.params.id);
    bodyWith(req, []);
    const row = await store.getAnnouncement(id);
    if (!row || row.deleted_at || !row.published_at) throw notFound(MESSAGES.WALL_ANNOUNCEMENT_NOT_FOUND);
    const audience = await store.listAudienceRows(id);
    if (!audience.some((a) => a.employee_id === employee.id)) {
      throw new HttpError(403, 'NOT_IN_AUDIENCE', MESSAGES.WALL_NOT_IN_AUDIENCE);
    }
    const at = now().toISOString();
    const existing = await store.getAnnouncementRead(id, employee.id);
    if (!existing) {
      await store.createAnnouncementRead({ announcement_id: id, employee_id: employee.id, read_at: at });
      const fresh = await store.getAnnouncement(id);
      await store.updateAnnouncement(id, { read_count: (fresh.read_count || 0) + 1 });
    }
    res.status(204).end();
  });
}

/** POST /api/ess/wall/announcements/{id}/ack — the acknowledgement button (F5). */
function ackAnnouncement({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const id = idParam(req.params.id);
    bodyWith(req, []);
    const row = await store.getAnnouncement(id);
    if (!row || row.deleted_at || !row.published_at) throw notFound(MESSAGES.WALL_ANNOUNCEMENT_NOT_FOUND);
    if (row.needs_ack !== true) throw invalid(MESSAGES.WALL_ANNOUNCEMENT_ACK);
    const audience = await store.listAudienceRows(id);
    if (!audience.some((a) => a.employee_id === employee.id)) {
      throw new HttpError(403, 'NOT_IN_AUDIENCE', MESSAGES.WALL_NOT_IN_AUDIENCE);
    }
    const today = istDay(now());
    if (row.closes_on && String(row.closes_on) < today) {
      throw new HttpError(409, 'ACK_CLOSED', MESSAGES.WALL_ACK_CLOSED);
    }
    const at = now().toISOString();
    const existing = await store.getAnnouncementRead(id, employee.id);
    if (!existing) {
      await store.createAnnouncementRead({ announcement_id: id, employee_id: employee.id, read_at: at, ack_at: at });
      const fresh = await store.getAnnouncement(id);
      await store.updateAnnouncement(id, { read_count: (fresh.read_count || 0) + 1, ack_count: (fresh.ack_count || 0) + 1 });
    } else if (!existing.ack_at) {
      await store.ackAnnouncement(id, employee.id, at);
      const fresh = await store.getAnnouncement(id);
      await store.updateAnnouncement(id, { ack_count: (fresh.ack_count || 0) + 1 });
    }
    const read = await store.getAnnouncementRead(id, employee.id);
    res.json({ read_at: read.read_at, ack_at: read.ack_at });
  });
}

/** GET /api/ess/wall/announcements/{id}/counts — the sender's own numbers (F5). */
function announcementCounts({ store }) {
  return asyncRoute(async (req, res) => {
    const id = idParam(req.params.id);
    const row = await store.getAnnouncement(id);
    if (!row || row.deleted_at) throw notFound(MESSAGES.WALL_ANNOUNCEMENT_NOT_FOUND);
    if (!seesSenderView(req.auth, row)) throw new HttpError(403, 'NOT_YOURS', MESSAGES.WALL_ANNOUNCEMENT_DELETE);
    res.json({ counts: await countsOf(store, id), closes_on: row.closes_on ?? null, needs_ack: row.needs_ack === true });
  });
}

/** GET /api/ess/wall/hr/announcements — the sender's own list, drafts and scheduled included (F5). */
function listMyAnnouncements({ store }) {
  return asyncRoute(async (req, res) => {
    if (!canAnnounce(req.auth.kind, req.auth.role) && !canModerate(req.auth.kind, req.auth.role)) {
      throw new HttpError(403, 'NOT_AN_ANNOUNCER', MESSAGES.WALL_ANNOUNCE_DENIED);
    }
    const limit = LIST_LIMITS.myAnnouncements;
    const rows = await store.listMyAnnouncements(req.auth.employee.id, limit);
    const truncated = rows.length > limit;
    const shown = rows.slice(0, limit);
    const raw = oneQueryValue(req.query.status);
    const status = raw === undefined || raw === null || raw === '' ? 'all' : raw;
    if (!['all', 'draft', 'published'].includes(status)) throw invalid(MESSAGES.WALL_ANNOUNCEMENT_STATUS);
    const filtered = status === 'all'
      ? shown
      : shown.filter((r) => (status === 'draft' ? !r.published_at : Boolean(r.published_at)));
    const announcements = [];
    for (const row of filtered) {
      announcements.push(await announcementView(store, row, {
        me: req.auth.employee.id,
        author: req.auth.employee,
        audienceLabel: await audienceLabel(store, row.audience),
      }));
    }
    res.json({ announcements, truncated });
  });
}

module.exports = {
  createAnnouncement,
  listAnnouncements,
  getAnnouncement,
  editAnnouncement,
  deleteAnnouncement,
  readAnnouncement,
  ackAnnouncement,
  announcementCounts,
  listMyAnnouncements,
  seesSenderView,
};
