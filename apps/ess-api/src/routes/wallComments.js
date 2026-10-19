const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const { bodyWith, requiredText, idParam, invalid } = require('../lib/validate');
const { withinEditWindow } = require('../policy/wall');
const { resolveMentions, peopleFor, notFound, seesHidden } = require('../lib/wallKit');
const { commentView } = require('./wallViews');
const { notifyMentions, notifyReply } = require('../lib/wallNotify');
const { recordAfter } = require('../lib/audit');

/**
 * Task F2, the comments: comments with ONE level of replies, each carrying @mentions and the six
 * reactions (the reaction routes are wallReactions.js).
 *
 * The rules, from decision 8 and the brief: everyone comments; the author edits for 15 minutes and
 * always deletes their own; HR hides anything with a reason (wallModeration.js); a reply is a
 * reply of a comment and never of another reply.
 *
 * The post's own comment count and a comment's reply count are written back onto their rows so the
 * feed is one read; hr_ess_wall_comments is the truth, and a count that has drifted is corrected
 * the next time somebody comments.
 */

/** POST /api/ess/wall/posts/{id}/comments { body, parent_id? } — a comment or a reply (F2). */
function createWallComment({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const postId = idParam(req.params.id);
    const body = bodyWith(req, ['body', 'parent_id']);
    const text = requiredText(body.body, { min: 1, max: 1000, message: MESSAGES.WALL_COMMENT_BODY });
    const post = await store.getWallPostOwn(postId);
    if (!post || post.deleted_at) throw notFound(MESSAGES.WALL_POST_NOT_FOUND);
    if (post.hidden_at && !seesHidden(req.auth, post)) throw notFound(MESSAGES.WALL_POST_NOT_FOUND);
    let parent = null;
    if (body.parent_id !== undefined && body.parent_id !== null) {
      const parentId = idParam(body.parent_id);
      parent = await store.getWallCommentOwn(parentId);
      if (!parent || parent.deleted_at) throw notFound(MESSAGES.WALL_COMMENT_NOT_FOUND);
      if (parent.post_id !== postId) throw invalid(MESSAGES.WALL_REPLY_OTHER_POST);
      // One level of replies: a reply never has a reply of its own (F2).
      if (parent.parent_id) throw invalid(MESSAGES.WALL_REPLY_DEPTH);
    }
    const at = now().toISOString();
    const mentioned = await resolveMentions(store, text, { exclude: employee.id });
    const created = await store.createWallComment({
      post_id: postId,
      employee_id: employee.id,
      parent_id: parent ? parent.id : null,
      body: text,
      mentions: mentioned.map((m) => m.id),
      created_at: at,
      updated_at: at,
    });
    await recountComments(store, postId);
    if (parent) await bumpReplyCount(store, parent.id, 1);
    if (mentioned.length) {
      await store.createWallMentions(mentioned.map((m) => ({
        comment_id: created.id, mentioned_id: m.id, mentioned_by_id: employee.id,
      })));
      await notifyMentions({ store, author: employee, mentioned, postId, commentId: created.id });
    }
    // The comment's author hears about a reply, unless they wrote it themselves.
    if (parent && parent.employee_id !== employee.id) {
      await notifyReply({ store, author: employee, repliedToEmployeeId: parent.employee_id, postId, commentId: created.id });
    }
    res.status(201).json({
      comment: commentView(created, { me: employee.id, author: employee, mentioned, myReaction: null }),
    });
  });
}

/** The post's visible comment count, written back onto the row the feed reads (F2). */
async function recountComments(store, postId) {
  const count = await store.countWallComments(postId);
  await store.saveWallPostCounter(postId, { comment_count: count });
}

/** A reply moves its parent's reply_count: best effort; the comments table is the truth. */
async function bumpReplyCount(store, parentId, delta) {
  const parent = await store.getWallComment(parentId);
  if (!parent) return;
  await store.saveWallCommentCounter(parentId, { reply_count: Math.max(0, (parent.reply_count || 0) + delta) });
}

/** PATCH /api/ess/wall/comments/{id} { body } — the author's own, for 15 minutes (F2). */
function editWallComment({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const id = idParam(req.params.id);
    const body = bodyWith(req, ['body']);
    const row = await store.getWallComment(id);
    if (!row || row.deleted_at) throw notFound(MESSAGES.WALL_COMMENT_NOT_FOUND);
    if (row.employee_id !== employee.id) throw new HttpError(403, 'NOT_YOURS', MESSAGES.WALL_OWN_COMMENT);
    if (!withinEditWindow(row.created_at, now())) throw new HttpError(409, 'EDIT_WINDOW_CLOSED', MESSAGES.WALL_EDIT_WINDOW);
    const text = requiredText(body.body, { min: 1, max: 1000, message: MESSAGES.WALL_COMMENT_BODY });
    const at = now().toISOString();
    const mentioned = await resolveMentions(store, text, { exclude: employee.id });
    const saved = await store.updateWallComment(id, { body: text, mentions: mentioned.map((m) => m.id), updated_at: at });
    if (!saved) throw notFound(MESSAGES.WALL_COMMENT_NOT_FOUND);
    await store.markWallCommentEdited(id, at);
    if (mentioned.length) {
      await store.createWallMentions(mentioned.map((m) => ({
        comment_id: id, mentioned_id: m.id, mentioned_by_id: employee.id,
      })));
    }
    // Read back after the stamp, so the reply says "edited" as the app will see it.
    const fresh = await store.getWallComment(id);
    const people = await peopleFor(store, [fresh]);
    res.json({
      comment: commentView(fresh, {
        me: employee.id,
        author: people.get(fresh.employee_id) || null,
        mentioned,
        myReaction: await store.getMyCommentReaction(id, employee.id),
      }),
    });
  });
}

/** DELETE /api/ess/wall/comments/{id} — the author's own, always (F2). */
function deleteWallComment({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const id = idParam(req.params.id);
    const row = await store.getWallCommentOwn(id);
    if (!row || row.deleted_at) throw notFound(MESSAGES.WALL_COMMENT_NOT_FOUND);
    if (row.employee_id !== employee.id) throw new HttpError(403, 'NOT_YOURS', MESSAGES.WALL_OWN_COMMENT);
    const out = await store.deleteWallComment(id, now().toISOString());
    if (!out) throw notFound(MESSAGES.WALL_COMMENT_NOT_FOUND);
    await recountComments(store, row.post_id);
    if (row.parent_id) await bumpReplyCount(store, row.parent_id, -1);
    await recordAfter(store, req, {
      action: 'wall.comment.deleted', targetEmployeeId: employee.id, details: { post_id: row.post_id, comment_id: id },
    });
    res.status(204).end();
  });
}

module.exports = { createWallComment, editWallComment, deleteWallComment, recountComments, bumpReplyCount };
