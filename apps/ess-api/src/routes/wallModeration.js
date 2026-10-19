const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const { bodyWith, requiredText, optionalText, chars, idParam, oneQueryValue, invalid } = require('../lib/validate');
const { LIST_LIMITS } = require('../lib/store');
const { canModerate } = require('../policy/wall');
const { notFound } = require('../lib/wallKit');
const { recountComments } = require('./wallComments');
const { recordAfter } = require('../lib/audit');

/**
 * Task F7, moderation: anybody reports a post or a comment, the report goes to HR's queue, and HR
 * hides (or deletes) it with a reason. Every hiding action is written to hr_ess_audit as
 * 'wall.post.hidden' or 'wall.comment.hidden', and the undo as 'wall.post.restored' /
 * 'wall.comment.restored', so the moderation trail and the rows agree.
 *
 * Who moderates: decision 8's own words, "HR can hide anything, with a reason" (MODERATE_ROLES,
 * reused from the capability rules). The CEO and super admins read the queue and the trail; only
 * HR hides.
 */

/** The actions the moderation log reads, in one place so the contract and the route agree. */
const MODERATION_ACTIONS = Object.freeze([
  'wall.post.hidden', 'wall.post.restored', 'wall.post.deleted',
  'wall.comment.hidden', 'wall.comment.restored', 'wall.comment.deleted',
  'wall.report.resolved',
]);

/** The queue's status filter: what HR is looking at. */
const REPORT_STATUSES = Object.freeze(['open', 'hidden', 'kept']);

/** A reason HR must give to hide anything: 3 to 200 characters (F7). */
const hideReason = (value) => requiredText(value, { min: 3, max: 200, message: MESSAGES.WALL_HIDE_REASON });

/** POST /api/ess/wall/posts/{id}/reports { reason, detail? } — anybody reports (F7). */
function reportPost({ store }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const id = idParam(req.params.id);
    const body = bodyWith(req, ['reason', 'detail']);
    const reason = requiredText(body.reason, { min: 3, max: 280, message: MESSAGES.WALL_REPORT_REASON });
    const detail = optionalText(body.detail);
    if (detail === undefined || (detail && chars(detail) > 500)) throw invalid(MESSAGES.WALL_REPORT_DETAIL);
    const post = await store.getWallPostOwn(id);
    if (!post || post.deleted_at) throw notFound(MESSAGES.WALL_POST_NOT_FOUND);
    const made = await store.createWallReport({
      reporter_id: employee.id,
      post_id: id,
      reason,
      detail,
    }, false);
    if (!made) throw new HttpError(409, 'ALREADY_REPORTED', MESSAGES.WALL_ALREADY_REPORTED);
    res.status(201).json({ report: { post_id: id, status: 'open' } });
  });
}

/** POST /api/ess/wall/comments/{id}/reports { reason, detail? } — the same, one level in (F7). */
function reportComment({ store }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const id = idParam(req.params.id);
    const body = bodyWith(req, ['reason', 'detail']);
    const reason = requiredText(body.reason, { min: 3, max: 280, message: MESSAGES.WALL_REPORT_REASON });
    const detail = optionalText(body.detail);
    if (detail === undefined || (detail && chars(detail) > 500)) throw invalid(MESSAGES.WALL_REPORT_DETAIL);
    const comment = await store.getWallCommentOwn(id);
    if (!comment || comment.deleted_at) throw notFound(MESSAGES.WALL_COMMENT_NOT_FOUND);
    const made = await store.createWallReport({
      reporter_id: employee.id,
      comment_id: id,
      reason,
      detail,
    }, true);
    if (!made) throw new HttpError(409, 'ALREADY_REPORTED', MESSAGES.WALL_ALREADY_REPORTED);
    res.status(201).json({ report: { comment_id: id, status: 'open' } });
  });
}

/** GET /api/ess/wall/hr/reports?status= — HR's queue (F7). */
function listReports({ store }) {
  return asyncRoute(async (req, res) => {
    if (!canModerate(req.auth.kind, req.auth.role)) throw new HttpError(403, 'MODERATE_DENIED', MESSAGES.WALL_MODERATE_DENIED);
    const raw = oneQueryValue(req.query.status);
    const status = raw === undefined || raw === null || raw === '' ? 'open' : raw;
    if (status !== 'all' && !REPORT_STATUSES.includes(status)) throw invalid(MESSAGES.WALL_MODERATION_QUEUE);
    const rows = await store.listWallReports({ status: status === 'all' ? null : status, limit: LIST_LIMITS.reports });
    const truncated = rows.length > LIST_LIMITS.reports;
    const shown = rows.slice(0, LIST_LIMITS.reports);
    const people = await store.listEmployeeCards([...new Set(shown.map((r) => r.reporter_id))]);
    const byId = new Map(people.map((p) => [p.id, p]));
    const reports = [];
    for (const row of shown) {
      const target = row.post_id
        ? await store.getWallPost(row.post_id)
        : await store.getWallComment(row.comment_id);
      reports.push({
        id: row.id,
        target: row.post_id ? 'post' : 'comment',
        post_id: row.post_id ?? null,
        comment_id: row.comment_id ?? null,
        target_preview: target ? String(target.body || '').slice(0, 140) : null,
        target_deleted: Boolean(target && target.deleted_at),
        target_hidden: Boolean(target && target.hidden_at),
        reporter: byId.get(row.reporter_id) ? { id: row.reporter_id, full_name: byId.get(row.reporter_id).full_name } : { id: row.reporter_id, full_name: null },
        reason: row.reason,
        detail: row.detail ?? null,
        status: row.status,
        resolved_by_name: row.resolved_by_name ?? null,
        resolved_at: row.resolved_at ?? null,
        resolution_note: row.resolution_note ?? null,
        created_at: row.created_at,
      });
    }
    res.json({ reports, truncated });
  });
}

/** POST /api/ess/wall/posts/{id}/hide { reason } — HR hides a post (F7). */
function hidePost({ store, now }) {
  return asyncRoute(async (req, res) => {
    if (!canModerate(req.auth.kind, req.auth.role)) throw new HttpError(403, 'MODERATE_DENIED', MESSAGES.WALL_MODERATE_DENIED);
    const id = idParam(req.params.id);
    const body = bodyWith(req, ['reason']);
    const reason = hideReason(body.reason);
    const post = await store.getWallPost(id);
    if (!post || post.deleted_at) throw notFound(MESSAGES.WALL_POST_NOT_FOUND);
    if (post.hidden_at) throw new HttpError(409, 'ALREADY_HIDDEN', MESSAGES.WALL_ALREADY_HIDDEN);
    const at = now().toISOString();
    const saved = await store.moderateWallPost(id, {
      hidden_at: at,
      hidden_by_user_id: req.auth.userId ?? null,
      hidden_by_name: req.auth.employee.full_name,
      hide_reason: reason,
      updated_at: at,
    });
    await recordAfter(store, req, {
      action: 'wall.post.hidden',
      targetEmployeeId: post.employee_id,
      details: { post_id: id, reason },
    });
    res.json({ post: { id: saved.id, hidden: true, hidden_by_name: req.auth.employee.full_name, hide_reason: reason } });
  });
}

/** DELETE /api/ess/wall/posts/{id}/hide — HR takes the hide back (F7). */
function restorePost({ store }) {
  return asyncRoute(async (req, res) => {
    if (!canModerate(req.auth.kind, req.auth.role)) throw new HttpError(403, 'MODERATE_DENIED', MESSAGES.WALL_MODERATE_DENIED);
    const id = idParam(req.params.id);
    bodyWith(req, []);
    const post = await store.getWallPost(id);
    if (!post || post.deleted_at) throw notFound(MESSAGES.WALL_POST_NOT_FOUND);
    if (!post.hidden_at) throw new HttpError(409, 'NOT_HIDDEN', MESSAGES.WALL_NOT_HIDDEN);
    await store.moderateWallPost(id, {
      hidden_at: null, hidden_by_user_id: null, hidden_by_name: null, hide_reason: null,
    });
    await recordAfter(store, req, {
      action: 'wall.post.restored',
      targetEmployeeId: post.employee_id,
      details: { post_id: id },
    });
    res.json({ post: { id, hidden: false } });
  });
}

/** POST /api/ess/wall/comments/{id}/hide { reason } — HR hides a comment (F7). */
function hideComment({ store, now }) {
  return asyncRoute(async (req, res) => {
    if (!canModerate(req.auth.kind, req.auth.role)) throw new HttpError(403, 'MODERATE_DENIED', MESSAGES.WALL_MODERATE_DENIED);
    const id = idParam(req.params.id);
    const body = bodyWith(req, ['reason']);
    const reason = hideReason(body.reason);
    const comment = await store.getWallComment(id);
    if (!comment || comment.deleted_at) throw notFound(MESSAGES.WALL_COMMENT_NOT_FOUND);
    if (comment.hidden_at) throw new HttpError(409, 'ALREADY_HIDDEN', MESSAGES.WALL_ALREADY_HIDDEN);
    const at = now().toISOString();
    await store.moderateWallComment(id, {
      hidden_at: at,
      hidden_by_user_id: req.auth.userId ?? null,
      hidden_by_name: req.auth.employee.full_name,
      hide_reason: reason,
    });
    // A hidden comment leaves the count the post shows, as a deleted one does.
    await recountComments(store, comment.post_id);
    await recordAfter(store, req, {
      action: 'wall.comment.hidden',
      targetEmployeeId: comment.employee_id,
      details: { post_id: comment.post_id, comment_id: id, reason },
    });
    res.json({ comment: { id, hidden: true, hidden_by_name: req.auth.employee.full_name, hide_reason: reason } });
  });
}

/** DELETE /api/ess/wall/comments/{id}/hide — HR takes the hide back (F7). */
function restoreComment({ store }) {
  return asyncRoute(async (req, res) => {
    if (!canModerate(req.auth.kind, req.auth.role)) throw new HttpError(403, 'MODERATE_DENIED', MESSAGES.WALL_MODERATE_DENIED);
    const id = idParam(req.params.id);
    bodyWith(req, []);
    const comment = await store.getWallComment(id);
    if (!comment || comment.deleted_at) throw notFound(MESSAGES.WALL_COMMENT_NOT_FOUND);
    if (!comment.hidden_at) throw new HttpError(409, 'NOT_HIDDEN', MESSAGES.WALL_NOT_HIDDEN);
    await store.moderateWallComment(id, {
      hidden_at: null, hidden_by_user_id: null, hidden_by_name: null, hide_reason: null,
    });
    await recountComments(store, comment.post_id);
    await recordAfter(store, req, {
      action: 'wall.comment.restored',
      targetEmployeeId: comment.employee_id,
      details: { post_id: comment.post_id, comment_id: id },
    });
    res.json({ comment: { id, hidden: false } });
  });
}

/** POST /api/ess/wall/hr/reports/{id}/resolve { status, note? } — HR answers a report (F7). */
function resolveReport({ store, now }) {
  return asyncRoute(async (req, res) => {
    if (!canModerate(req.auth.kind, req.auth.role)) throw new HttpError(403, 'MODERATE_DENIED', MESSAGES.WALL_MODERATE_DENIED);
    const id = idParam(req.params.id);
    const body = bodyWith(req, ['status', 'note']);
    if (body.status !== 'hidden' && body.status !== 'kept') throw invalid(MESSAGES.WALL_MODERATION_QUEUE);
    const note = optionalText(body.note);
    if (note === undefined || (note && chars(note) > 200)) throw invalid(MESSAGES.WALL_REPORT_DETAIL);
    const report = await store.getWallReport(id);
    if (!report || report.status !== 'open') throw notFound(MESSAGES.WALL_REPORT_NOT_FOUND);
    const at = now().toISOString();
    const saved = await store.resolveWallReport(id, {
      status: body.status,
      resolved_by_user_id: req.auth.userId ?? null,
      resolved_by_name: req.auth.employee.full_name,
      resolved_at: at,
      resolution_note: note,
    });
    if (!saved) throw notFound(MESSAGES.WALL_REPORT_NOT_FOUND);
    await recordAfter(store, req, {
      action: 'wall.report.resolved',
      targetEmployeeId: null,
      details: { report_id: id, status: body.status },
    });
    res.json({
      report: {
        id,
        status: saved.status,
        resolved_by_name: saved.resolved_by_name,
        resolved_at: saved.resolved_at,
        resolution_note: saved.resolution_note ?? null,
      },
    });
  });
}

/** GET /api/ess/wall/hr/moderation-log — every hide, restore and resolved report (F7). */
function moderationLog({ store }) {
  return asyncRoute(async (req, res) => {
    if (!canModerate(req.auth.kind, req.auth.role)) throw new HttpError(403, 'MODERATE_DENIED', MESSAGES.WALL_MODERATE_DENIED);
    const rows = await store.listModerationLog(MODERATION_ACTIONS, LIST_LIMITS.moderationLog);
    res.json({
      entries: rows.map((r) => ({
        id: r.id,
        at: r.at,
        actor_name: r.actor_name ?? null,
        action: r.action,
        target_employee_id: r.target_employee_id ?? null,
        details: r.details ?? {},
      })),
    });
  });
}

module.exports = {
  reportPost,
  reportComment,
  listReports,
  hidePost,
  restorePost,
  hideComment,
  restoreComment,
  resolveReport,
  moderationLog,
  MODERATION_ACTIONS,
};
