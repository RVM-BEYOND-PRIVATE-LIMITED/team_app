const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const { bodyWith, requiredText, optionalText, chars, idParam, oneQueryValue, invalid } = require('../lib/validate');
const { istDay, addDays } = require('../lib/time');
const { LIST_LIMITS } = require('../lib/store');
const { MAX_POLL_OPTIONS, MIN_POLL_OPTIONS, SCOPES, withinEditWindow } = require('../policy/wall');
const {
  attachmentsFrom, storeAttachments, resolveMentions, peopleFor, scopeFrom, kindFrom, notFound, pollView,
  privilegedOver, seesHidden,
} = require('../lib/wallKit');
const { postView, commentView } = require('./wallViews');
const { notifyMentions } = require('../lib/wallNotify');
const { recordAfter } = require('../lib/audit');

/**
 * Tasks F1 on the feed's own rows: the organisation wall and each branch's, one post with its
 * thread, and the author's 15-minute edit and always-available delete. Comments and replies are
 * wallComments.js, reactions wallReactions.js, and praise, polls and announcements their own
 * files -- one thing per file, as the tests are split.
 *
 * Who may do what, straight from decision 8: everyone posts; only the author edits and deletes
 * their own; HR hides anything with a reason (wallModeration.js).
 */

/** How the kinds this file creates are spelt, so a praise or a wish cannot slip through here. */
const FEED_KINDS = Object.freeze(['post', 'poll']);

/** One poll's whole block: its options, every vote, and the reader's own. */
async function pollOfRow(store, row, employeeId, day) {
  const [options, votes, myVotes] = await Promise.all([
    store.listPollOptions(row.id),
    store.listPollVotes(row.id),
    store.listMyPollVotes(row.id, employeeId),
  ]);
  return pollView(row, options, votes, myVotes, day);
}

/** The caller's own reaction on each of these posts, so the feed can show which button is lit. */
async function myReactionsFor(store, rows, employeeId) {
  const own = new Map();
  for (const row of rows) {
    if (row.deleted_at) continue;
    const mine = await store.getMyPostReaction(row.id, employeeId);
    if (mine) own.set(row.id, mine);
  }
  return own;
}

/** GET /api/ess/wall/posts?scope=&before= — the feed: the organisation's wall plus my branch's. */
function listWallPosts({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const rawScope = oneQueryValue(req.query.scope);
    const scope = rawScope === undefined || rawScope === null || rawScope === '' ? null : rawScope;
    if (scope && !SCOPES.includes(scope)) throw invalid(MESSAGES.WALL_SCOPE);
    const before = oneQueryValue(req.query.before);
    if (before !== undefined && before !== null && before !== '' && Number.isNaN(Date.parse(before))) {
      throw invalid(MESSAGES.WALL_POST_NOT_FOUND);
    }
    const limit = LIST_LIMITS.wallPosts;
    const rows = await store.listFeedPosts({
      branchId: employee.branch_id ?? null,
      scope,
      before: before || null,
      limit,
    });
    const truncated = rows.length > limit;
    // F7: a hidden post leaves the feed for everybody but its author and HR.
    const page = rows.slice(0, limit).filter((row) => !row.hidden_at || seesHidden(req.auth, row));
    const day = istDay(now());
    const [people, mine] = await Promise.all([
      peopleFor(store, page),
      myReactionsFor(store, page, employee.id),
    ]);
    const posts = [];
    for (const row of page) {
      posts.push(await postView(store, row, {
        me: employee.id,
        author: people.get(row.employee_id) || null,
        about: people.get(row.about_employee_id) || null,
        mentioned: (row.mentions || []).map((id) => people.get(id)).filter(Boolean),
        myReaction: mine.get(row.id) || null,
        poll: row.kind === 'poll' ? await pollOfRow(store, row, employee.id, day) : undefined,
      }));
    }
    res.json({
      posts,
      // The app pages with ?before=<next_before>: the last row's created_at.
      next_before: truncated && page.length ? page[page.length - 1].created_at : null,
      truncated,
    });
  });
}

/** GET /api/ess/wall/posts/{id} — one post, with its comments and their replies (F1, F2). */
function getWallPost({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const id = idParam(req.params.id);
    const row = await store.getWallPost(id);
    if (!row || row.deleted_at) throw notFound(MESSAGES.WALL_POST_NOT_FOUND);
    // F7: a hidden post is 404 for everybody but its author and HR, as if it were not there.
    if (row.hidden_at && !seesHidden(req.auth, row)) throw notFound(MESSAGES.WALL_POST_NOT_FOUND);
    const limit = LIST_LIMITS.wallComments;
    const comments = await store.listThreadComments(id, limit);
    const truncated = comments.length > limit;
    const shown = comments.slice(0, limit);
    const people = await peopleFor(store, [row, ...shown]);
    const [myReaction, poll] = await Promise.all([
      store.getMyPostReaction(id, employee.id),
      row.kind === 'poll' ? pollOfRow(store, row, employee.id, istDay(now())) : Promise.resolve(undefined),
    ]);
    const view = await postView(store, row, {
      me: employee.id,
      author: people.get(row.employee_id) || null,
      about: people.get(row.about_employee_id) || null,
      mentioned: (row.mentions || []).map((x) => people.get(x)).filter(Boolean),
      myReaction,
      poll,
    });
    const repliesByParent = new Map();
    for (const c of shown) {
      if (!c.parent_id) continue;
      if (!repliesByParent.has(c.parent_id)) repliesByParent.set(c.parent_id, []);
      repliesByParent.get(c.parent_id).push(c);
    }
    const commentsOut = [];
    for (const c of shown) {
      if (c.parent_id) continue;
      const replies = (repliesByParent.get(c.id) || []).map((r) => ({
        row: r,
        author: people.get(r.employee_id) || null,
        mentioned: (r.mentions || []).map((x) => people.get(x)).filter(Boolean),
      }));
      commentsOut.push(commentView(c, {
        me: employee.id,
        author: people.get(c.employee_id) || null,
        mentioned: (c.mentions || []).map((x) => people.get(x)).filter(Boolean),
        replies,
        // F7: HR and the comment's own author still read a hidden comment; everybody else is
        // shown that it is hidden, with no words and no name.
        seesHidden: privilegedOver(req.auth, c),
      }));
    }
    res.json({ post: { ...view, comments: commentsOut }, truncated });
  });
}

/**
 * The poll a create carries: the question is the post's body, and the shape is here (F4).
 * 2 to 10 options of up to 120 characters each, one or many choices, optionally anonymous, and a
 * closing day that has not gone.
 */
function pollCreate(raw, today) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw invalid(MESSAGES.WALL_POLL_OPTIONS);
  if (Object.keys(raw).some((k) => !['options', 'multiple', 'anonymous', 'closes_on'].includes(k))) {
    throw invalid(MESSAGES.WALL_POLL_OPTIONS);
  }
  const list = raw.options;
  if (!Array.isArray(list) || list.length < MIN_POLL_OPTIONS || list.length > MAX_POLL_OPTIONS) {
    throw invalid(MESSAGES.WALL_POLL_OPTIONS);
  }
  const options = list.map((label, i) => {
    const text = optionalText(label);
    if (!text || chars(text) > 120) throw invalid(MESSAGES.WALL_POLL_OPTIONS);
    return { option_key: `o${i + 1}`, label: text, position: i };
  });
  const closes = raw.closes_on;
  if (typeof closes !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(closes)) throw invalid(MESSAGES.WALL_POLL_CLOSES);
  const parsed = new Date(`${closes}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== closes) throw invalid(MESSAGES.WALL_POLL_CLOSES);
  if (closes > addDays(today, 365)) throw invalid(MESSAGES.WALL_POLL_CLOSES);
  if (closes < today) throw invalid(MESSAGES.WALL_POLL_PAST);
  for (const key of ['multiple', 'anonymous']) {
    if (raw[key] !== undefined && typeof raw[key] !== 'boolean') throw invalid(MESSAGES.WALL_POLL_OPTIONS);
  }
  return { options, multiple: raw.multiple === true, anonymous: raw.anonymous === true, closes_on: closes };
}

/** POST /api/ess/wall/posts { kind, body, scope?, attachments?, poll? } — a post or a poll. */
function createWallPost({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const body = bodyWith(req, ['kind', 'body', 'scope', 'branch_id', 'attachments', 'poll']);
    const kind = body.kind === undefined ? 'post' : kindFrom(body.kind);
    if (!FEED_KINDS.includes(kind)) throw invalid(MESSAGES.WALL_POST_KIND);
    const text = kind === 'poll'
      ? requiredText(body.body, { min: 3, max: 300, message: MESSAGES.WALL_POLL_QUESTION })
      : requiredText(body.body, { min: 1, max: 2000, message: MESSAGES.WALL_POST_BODY });
    const { scope, branchId } = scopeFrom(body, employee.branch_id ?? null);
    const files = attachmentsFrom(body, { folder: 'wall', employeeId: employee.id });
    const poll = kind === 'poll' ? pollCreate(body.poll, istDay(now())) : null;
    if (kind !== 'poll' && body.poll !== undefined) throw invalid(MESSAGES.UNKNOWN_FIELD);

    const at = now().toISOString();
    const stored = await storeAttachments(store, files);
    const mentioned = await resolveMentions(store, text, { exclude: employee.id });
    const created = await store.createWallPost({
      employee_id: employee.id,
      kind,
      scope,
      branch_id: branchId,
      body: text,
      attachments: stored,
      mentions: mentioned.map((m) => m.id),
      poll_multiple: poll ? poll.multiple : false,
      poll_anonymous: poll ? poll.anonymous : false,
      poll_closes_on: poll ? poll.closes_on : null,
      created_at: at,
      updated_at: at,
    });
    if (poll) {
      await store.createPollOptions(poll.options.map((o) => ({ post_id: created.id, ...o })));
    }
    if (mentioned.length) {
      await store.createWallMentions(mentioned.map((m) => ({
        post_id: created.id, mentioned_id: m.id, mentioned_by_id: employee.id,
      })));
      await notifyMentions({ store, author: employee, mentioned, postId: created.id });
    }
    const fresh = await store.getWallPost(created.id);
    res.status(201).json({
      post: await postView(store, fresh, {
        me: employee.id,
        author: employee,
        mentioned,
        myReaction: null,
        poll: poll ? await pollOfRow(store, fresh, employee.id, istDay(now())) : undefined,
      }),
    });
  });
}

/** PATCH /api/ess/wall/posts/{id} { body } — the author's own, for 15 minutes (F1). */
function editWallPost({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const id = idParam(req.params.id);
    const body = bodyWith(req, ['body']);
    const row = await store.getWallPostOwn(id);
    if (!row || row.deleted_at) throw notFound(MESSAGES.WALL_POST_NOT_FOUND);
    if (row.employee_id !== employee.id) throw new HttpError(403, 'NOT_YOURS', MESSAGES.WALL_OWN_POST);
    if (!withinEditWindow(row.created_at, now())) throw new HttpError(409, 'EDIT_WINDOW_CLOSED', MESSAGES.WALL_EDIT_WINDOW);
    const text = requiredText(body.body, { min: 1, max: 2000, message: MESSAGES.WALL_POST_BODY });
    const at = now().toISOString();
    const mentioned = await resolveMentions(store, text, { exclude: employee.id });
    const saved = await store.updateWallPost(id, {
      body: text,
      mentions: mentioned.map((m) => m.id),
      updated_at: at,
    });
    if (!saved) throw notFound(MESSAGES.WALL_POST_NOT_FOUND);
    // The first edit stamp wins, so `edited` means "has been edited", whoever wrote it.
    await store.markWallPostEdited(id, at);
    if (mentioned.length) {
      await store.createWallMentions(mentioned.map((m) => ({
        post_id: id, mentioned_id: m.id, mentioned_by_id: employee.id,
      })));
    }
    const fresh = await store.getWallPost(id);
    const people = await peopleFor(store, [fresh]);
    res.json({
      post: await postView(store, fresh, {
        me: employee.id,
        author: people.get(fresh.employee_id) || null,
        about: people.get(fresh.about_employee_id) || null,
        mentioned: (fresh.mentions || []).map((x) => people.get(x)).filter(Boolean),
        myReaction: await store.getMyPostReaction(id, employee.id),
      }),
    });
  });
}

/** DELETE /api/ess/wall/posts/{id} — the author's own, always (F1). */
function deleteWallPost({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const id = idParam(req.params.id);
    const row = await store.getWallPostOwn(id);
    if (!row || row.deleted_at) throw notFound(MESSAGES.WALL_POST_NOT_FOUND);
    if (row.employee_id !== employee.id) throw new HttpError(403, 'NOT_YOURS', MESSAGES.WALL_OWN_POST);
    const out = await store.deleteWallPost(id, now().toISOString());
    if (!out) throw notFound(MESSAGES.WALL_POST_NOT_FOUND);
    await recordAfter(store, req, {
      action: 'wall.post.deleted', targetEmployeeId: employee.id, details: { post_id: id },
    });
    res.status(204).end();
  });
}

module.exports = {
  listWallPosts,
  getWallPost,
  createWallPost,
  editWallPost,
  deleteWallPost,
  pollOfRow,
  pollCreate,
  myReactionsFor,
};
