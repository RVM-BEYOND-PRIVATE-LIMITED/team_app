const { MESSAGES, asyncRoute } = require('../lib/errors');
const { bodyWith, idParam, oneQueryValue, invalid } = require('../lib/validate');
const { REACTIONS } = require('../policy/wall');
const { notFound, peopleFor, seesHidden } = require('../lib/wallKit');

/**
 * Task F2, the reactions: six of them (like, love, laugh, clap, insightful, curious), one per
 * person per post AND per comment, and "tapping the count shows who reacted".
 *
 * A reaction is written once per person: the same person tapping a second emoji changes the row;
 * the DELETE takes it off. The counts on the post or comment row are rewritten from the reactions
 * table right after every change, so the feed's numbers and "who reacted" can never disagree for
 * long -- and never inside one request.
 */

/** One reaction the app sends must be one of the six. */
function reactionFrom(value) {
  if (!REACTIONS.includes(value)) throw invalid(MESSAGES.WALL_REACTION);
  return value;
}

/** The counts the reactions rows add up to, in the six's own order. */
function countsOf(rows) {
  const counts = {};
  for (const reaction of REACTIONS) {
    const n = rows.filter((r) => r.reaction === reaction).length;
    if (n) counts[reaction] = n;
  }
  return counts;
}

/** What every reaction reply carries: the totals and the caller's own, never a name list. */
const countView = (rows) => ({ counts: countsOf(rows), total: rows.length });

/** "Who reacted": one entry per reaction that has people, newest first (F2). */
async function breakdownOf(store, rows) {
  const people = await peopleFor(store, rows.map((r) => ({ employee_id: r.employee_id })));
  const out = [];
  for (const reaction of REACTIONS) {
    const here = rows.filter((r) => r.reaction === reaction);
    if (!here.length) continue;
    out.push({
      reaction,
      count: here.length,
      people: here.map((r) => {
        const person = people.get(r.employee_id);
        return {
          id: r.employee_id,
          full_name: person ? person.full_name : null,
          employee_code: person ? person.employee_code ?? null : null,
          reacted_at: r.created_at,
        };
      }),
    });
  }
  return out;
}

/** The one-reaction filter a "who reacted" query may carry. */
function onlyFrom(value) {
  if (value === undefined || value === null || value === '') return null;
  if (!REACTIONS.includes(value)) throw invalid(MESSAGES.WALL_REACTION);
  return value;
}

/** GET /api/ess/wall/posts/{id}/reactions?reaction= — who reacted, grouped by reaction (F2). */
function listPostReactions({ store }) {
  return asyncRoute(async (req, res) => {
    const id = idParam(req.params.id);
    const only = onlyFrom(oneQueryValue(req.query.reaction));
    const post = await store.getWallPost(id);
    if (!post || post.deleted_at || (post.hidden_at && !seesHidden(req.auth, post))) throw notFound(MESSAGES.WALL_POST_NOT_FOUND);
    const rows = await store.listReactionsForPost(id);
    const shown = only ? rows.filter((r) => r.reaction === only) : rows;
    res.json({ reactions: await breakdownOf(store, shown), total: rows.length });
  });
}

/** GET /api/ess/wall/comments/{id}/reactions?reaction= — the same, one level in (F2). */
function listCommentReactions({ store }) {
  return asyncRoute(async (req, res) => {
    const id = idParam(req.params.id);
    const only = onlyFrom(oneQueryValue(req.query.reaction));
    const comment = await store.getWallComment(id);
    if (!comment || comment.deleted_at) throw notFound(MESSAGES.WALL_COMMENT_NOT_FOUND);
    const rows = await store.listReactionsForComment(id);
    const shown = only ? rows.filter((r) => r.reaction === only) : rows;
    res.json({ reactions: await breakdownOf(store, shown), total: rows.length });
  });
}

/** The counts rewrite both replies share: the row is told what the table says, after the change. */
async function saveCounts(store, { postId, commentId, at }) {
  if (postId) {
    const rows = await store.listReactionsForPost(postId);
    await store.saveWallPostCounter(postId, { reaction_counts: countsOf(rows), updated_at: at });
    return rows;
  }
  const rows = await store.listReactionsForComment(commentId);
  await store.saveWallCommentCounter(commentId, { reaction_counts: countsOf(rows), updated_at: at });
  return rows;
}

/** PUT /api/ess/wall/posts/{id}/reaction { reaction } — mine, changed or added (F2). */
function putPostReaction({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const id = idParam(req.params.id);
    const body = bodyWith(req, ['reaction']);
    const reaction = reactionFrom(body.reaction);
    const post = await store.getWallPost(id);
    if (!post || post.deleted_at || (post.hidden_at && !seesHidden(req.auth, post))) throw notFound(MESSAGES.WALL_POST_NOT_FOUND);
    const at = now().toISOString();
    const mine = await store.getMyPostReaction(id, employee.id);
    if (!mine) {
      await store.createPostReaction({ post_id: id, employee_id: employee.id, reaction, created_at: at });
    } else if (mine.reaction !== reaction) {
      await store.updatePostReaction(mine.id, reaction);
    }
    const rows = await saveCounts(store, { postId: id, at });
    res.json({ ...countView(rows), my_reaction: rows.find((r) => r.employee_id === employee.id)?.reaction ?? null });
  });
}

/** DELETE /api/ess/wall/posts/{id}/reaction — my own reaction, off (F2). */
function deletePostReaction({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const id = idParam(req.params.id);
    bodyWith(req, []);
    const post = await store.getWallPost(id);
    if (!post || post.deleted_at || (post.hidden_at && !seesHidden(req.auth, post))) throw notFound(MESSAGES.WALL_POST_NOT_FOUND);
    const mine = await store.getMyPostReaction(id, employee.id);
    if (mine) await store.removePostReaction(mine.id);
    const rows = await saveCounts(store, { postId: id, at: now().toISOString() });
    res.json({ ...countView(rows), my_reaction: null });
  });
}

/** PUT /api/ess/wall/comments/{id}/reaction { reaction } — the same, one level in (F2). */
function putCommentReaction({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const id = idParam(req.params.id);
    const body = bodyWith(req, ['reaction']);
    const reaction = reactionFrom(body.reaction);
    const comment = await store.getWallComment(id);
    if (!comment || comment.deleted_at) throw notFound(MESSAGES.WALL_COMMENT_NOT_FOUND);
    const at = now().toISOString();
    const mine = await store.getMyCommentReaction(id, employee.id);
    if (!mine) {
      await store.createCommentReaction({ comment_id: id, employee_id: employee.id, reaction, created_at: at });
    } else if (mine.reaction !== reaction) {
      await store.updateCommentReaction(mine.id, reaction);
    }
    const rows = await saveCounts(store, { commentId: id, at });
    res.json({ ...countView(rows), my_reaction: rows.find((r) => r.employee_id === employee.id)?.reaction ?? null });
  });
}

/** DELETE /api/ess/wall/comments/{id}/reaction — my own, off (F2). */
function deleteCommentReaction({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const id = idParam(req.params.id);
    bodyWith(req, []);
    const comment = await store.getWallComment(id);
    if (!comment || comment.deleted_at) throw notFound(MESSAGES.WALL_COMMENT_NOT_FOUND);
    const mine = await store.getMyCommentReaction(id, employee.id);
    if (mine) await store.removeCommentReaction(mine.id);
    const rows = await saveCounts(store, { commentId: id, at: now().toISOString() });
    res.json({ ...countView(rows), my_reaction: null });
  });
}

module.exports = {
  listPostReactions,
  listCommentReactions,
  putPostReaction,
  deletePostReaction,
  putCommentReaction,
  deleteCommentReaction,
  countsOf,
};
