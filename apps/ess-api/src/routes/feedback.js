const crypto = require('crypto');
const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const {
  bodyWith, requiredText, optionalText, chars, idParam, invalid, isPlainObject, oneQueryValue,
} = require('../lib/validate');
const { recordBefore } = require('../lib/audit');
const { LIST_LIMITS } = require('../lib/store');
const {
  FEEDBACK_KINDS, CONTEXT_FIELDS, SCREENSHOT_CONTENT_TYPES, MAX_SCREENSHOT_BYTES, MESSAGE_MIN, MESSAGE_MAX,
} = require('../policy/feedback');

/**
 * In-app feedback (#151): a bug report, a suggestion or anything else about the Team app, sent
 * from the floating Feedback button on any screen, and the super admins' list of them. The rules
 * (kinds, who reads, the context fields and the screenshot) are policy/feedback.js.
 *
 * The sender gets a receipt, never the list: there is no status and no reply yet. The list never
 * carries the screenshot's bucket path; a super admin opens it through a 300-second signed link,
 * and that opening is audited first (recordBefore), because a screenshot can show anybody's data.
 */

const BASE64 = /^[A-Za-z0-9+/]+={0,2}$/;
const KIND_FILTERS = [...FEEDBACK_KINDS, 'all'];
const CONTEXT_KEYS = Object.keys(CONTEXT_FIELDS);

/** The context the app attached: every field null unless it sent short text for it. */
function contextFrom(value) {
  const out = Object.fromEntries(CONTEXT_KEYS.map((k) => [k, null]));
  if (value === undefined || value === null) return out;
  if (!isPlainObject(value) || Object.keys(value).some((k) => !CONTEXT_KEYS.includes(k))) {
    throw invalid(MESSAGES.FEEDBACK_CONTEXT);
  }
  for (const key of CONTEXT_KEYS) {
    const text = optionalText(value[key]);
    if (text === undefined || (text && chars(text) > CONTEXT_FIELDS[key])) throw invalid(MESSAGES.FEEDBACK_CONTEXT);
    out[key] = text;
  }
  return out;
}

/** The optional screenshot, decoded and checked: its type is what it says and what its bytes show. */
function screenshotFrom(value) {
  if (value === undefined || value === null) return null;
  if (!isPlainObject(value) || Object.keys(value).some((k) => !['content_type', 'data_base64'].includes(k))) {
    throw invalid(MESSAGES.FEEDBACK_SCREENSHOT);
  }
  const type = SCREENSHOT_CONTENT_TYPES[value.content_type];
  const data = value.data_base64;
  if (typeof value.content_type !== 'string' || !type) throw invalid(MESSAGES.FEEDBACK_SCREENSHOT);
  if (typeof data !== 'string' || data.length < 16 || !BASE64.test(data)) throw invalid(MESSAGES.FEEDBACK_SCREENSHOT);
  const buffer = Buffer.from(data, 'base64');
  if (!buffer.length || buffer.length > MAX_SCREENSHOT_BYTES) throw invalid(MESSAGES.FEEDBACK_SCREENSHOT_SIZE);
  if (buffer.length < type.magic.length || !buffer.subarray(0, type.magic.length).equals(type.magic)) {
    throw invalid(MESSAGES.FEEDBACK_SCREENSHOT);
  }
  return { buffer, content_type: value.content_type, ext: type.ext };
}

/** What the sender is told: that it arrived, and nothing a later read would add. */
const receipt = (r) => ({
  id: r.id,
  kind: r.kind,
  has_screenshot: Boolean(r.screenshot_path),
  created_at: r.created_at,
});

const card = (e) => (e ? { id: e.id, full_name: e.full_name, employee_code: e.employee_code ?? null } : null);

/** One item as a super admin reads it: everything but the bucket path. */
const reviewView = (r, employee) => ({
  id: r.id,
  kind: r.kind,
  message: r.message,
  context: Object.fromEntries(CONTEXT_KEYS.map((k) => [k, r[k] ?? null])),
  has_screenshot: Boolean(r.screenshot_path),
  created_at: r.created_at,
  employee: card(employee),
});

/** POST /api/ess/feedback { kind, message, context?, screenshot? }: send feedback about the app. */
function createFeedback({ store }) {
  return asyncRoute(async (req, res) => {
    const body = bodyWith(req, ['kind', 'message', 'context', 'screenshot']);
    if (!FEEDBACK_KINDS.includes(body.kind)) throw invalid(MESSAGES.FEEDBACK_KIND);
    const message = requiredText(body.message, { min: MESSAGE_MIN, max: MESSAGE_MAX, message: MESSAGES.FEEDBACK_MESSAGE });
    const context = contextFrom(body.context);
    const shot = screenshotFrom(body.screenshot);
    const { employee } = req.auth;

    const row = {
      employee_id: employee.id,
      kind: body.kind,
      message,
      ...context,
      screenshot_path: null,
      screenshot_content_type: null,
      screenshot_bytes: null,
    };
    if (shot) {
      // The bytes go up first, as My Documents' do; a row that then fails takes its file with it.
      row.screenshot_path = `feedback/${employee.id}/${crypto.randomUUID()}.${shot.ext}`;
      row.screenshot_content_type = shot.content_type;
      row.screenshot_bytes = shot.buffer.length;
      await store.uploadEssObject(row.screenshot_path, shot.buffer, shot.content_type);
    }
    let created;
    try {
      created = await store.createFeedback(row);
    } catch (e) {
      if (row.screenshot_path) await store.removeEssObjects([row.screenshot_path]);
      throw e;
    }
    res.status(201).json({ feedback: receipt(created) });
  });
}

/** GET /api/ess/admin/feedback?kind=bug|suggestion|other|all&before=: the super admins' list, newest first. */
function listFeedback({ store }) {
  return asyncRoute(async (req, res) => {
    const rawKind = oneQueryValue(req.query.kind);
    const kind = rawKind === undefined || rawKind === '' ? 'all' : rawKind;
    if (!KIND_FILTERS.includes(kind)) throw invalid(MESSAGES.FEEDBACK_KIND_FILTER);
    const before = oneQueryValue(req.query.before);
    if (before === null || (before && Number.isNaN(Date.parse(before)))) throw invalid(MESSAGES.FEEDBACK_BEFORE);

    const rows = await store.listFeedback({ kind: kind === 'all' ? null : kind, before: before || null });
    const truncated = rows.length > LIST_LIMITS.feedback;
    const page = rows.slice(0, LIST_LIMITS.feedback);
    const people = new Map((await store.listEmployeeCards(page.map((r) => r.employee_id))).map((e) => [e.id, e]));
    res.json({
      feedback: page.map((r) => reviewView(r, people.get(r.employee_id))),
      // The app pages with ?before=<next_before>: the last row's created_at.
      next_before: truncated && page.length ? page[page.length - 1].created_at : null,
    });
  });
}

/** GET /api/ess/admin/feedback/:id/screenshot: a 300-second signed link to one item's screenshot. */
function getFeedbackScreenshot({ store }) {
  return asyncRoute(async (req, res) => {
    const id = idParam(req.params.id);
    const row = await store.getFeedback(id);
    if (!row) throw new HttpError(404, 'NOT_FOUND', MESSAGES.FEEDBACK_NOT_FOUND);
    if (!row.screenshot_path) throw new HttpError(404, 'NOT_FOUND', MESSAGES.FEEDBACK_NO_SCREENSHOT);
    // Written before the link leaves the server; a failed write refuses the read (503).
    await recordBefore(store, req, {
      action: 'feedback.screenshot_opened',
      targetEmployeeId: row.employee_id,
      details: { feedback_id: row.id },
    });
    const url = await store.signedEssUrl(row.screenshot_path);
    if (!url) throw new HttpError(503, 'UNAVAILABLE', MESSAGES.UNAVAILABLE);
    const ext = SCREENSHOT_CONTENT_TYPES[row.screenshot_content_type]?.ext || 'png';
    res.json({
      file: { url, name: `feedback-${row.id}.${ext}`, content_type: row.screenshot_content_type, expires_in: 300 },
    });
  });
}

module.exports = { createFeedback, listFeedback, getFeedbackScreenshot };
