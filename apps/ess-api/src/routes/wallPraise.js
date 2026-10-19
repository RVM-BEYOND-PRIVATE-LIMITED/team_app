const { MESSAGES, asyncRoute } = require('../lib/errors');
const { bodyWith, requiredText, idParam, oneQueryValue, invalid } = require('../lib/validate');
const { LIST_LIMITS } = require('../lib/store');
const { PRAISE_MAX_CHARS, PRAISE_BADGES, badgeById, badgeView } = require('../policy/wall');
const { attachmentsFrom, storeAttachments, resolveMentions, peopleFor, badgeFrom, notFound } = require('../lib/wallKit');
const { postView } = require('./wallViews');
const { notifyMentions, notifyPraise } = require('../lib/wallNotify');

/**
 * Task F3, praise: one of the twelve fixed RVM badges (KP, 19 Oct: "the catalogue ships in
 * code"), a reason of up to 280 characters, and an optional photo. A certificate PDF is out of
 * scope here -- letters are Phase 3.
 *
 * Praise appears in the feed like any other post, and on the receiver's profile through
 * `GET /api/ess/me/praise` (the profile integration the phase left optional, built as its own
 * read so the profile screen can show a "Praise" strip without changing the profile's shape).
 *
 * Praise is about somebody else: the database refuses a badge given to yourself, and the route
 * says why before that.
 */

/** GET /api/ess/me/praise?employee_id= — praise for me (or for the person I name), newest first. */
function listPraise({ store }) {
  return asyncRoute(async (req, res) => {
    const asked = oneQueryValue(req.query.employee_id);
    if (asked !== undefined && asked !== null && asked !== '') idParam(asked);
    const employeeId = asked && asked !== '' ? asked.toLowerCase() : req.auth.employee.id;
    const rows = await store.listPraiseFor(employeeId, LIST_LIMITS.praiseFor);
    const people = await peopleFor(store, rows);
    const praise = [];
    for (const row of rows) {
      praise.push(await postView(store, row, {
        me: req.auth.employee.id,
        author: people.get(row.employee_id) || null,
        about: people.get(row.about_employee_id) || null,
        mentioned: (row.mentions || []).map((id) => people.get(id)).filter(Boolean),
        myReaction: await store.getMyPostReaction(row.id, req.auth.employee.id),
      }));
    }
    res.json({
      praise,
      // The badge catalogue, so the picker needs no second call (F3: it is fixed, in code).
      badges: PRAISE_BADGES.map(badgeView),
    });
  });
}

/** POST /api/ess/wall/praise { employee_id, badge, reason, scope?, attachments? } — praise somebody (F3). */
function createPraise({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const body = bodyWith(req, ['employee_id', 'badge', 'reason', 'scope', 'attachments', 'branch_id']);
    const aboutId = idParam(body.employee_id);
    if (aboutId === employee.id) throw invalid(MESSAGES.WALL_PRAISE_SELF);
    const badge = badgeFrom(body.badge);
    const reason = requiredText(body.reason, { min: 3, max: PRAISE_MAX_CHARS, message: MESSAGES.WALL_PRAISE_WHY });
    const target = await store.getEmployeeById(aboutId);
    if (!target) throw notFound(MESSAGES.EMPLOYEE_NOT_FOUND);

    const scope = body.scope === undefined || body.scope === null ? 'org' : body.scope;
    if (!['org', 'branch'].includes(scope)) throw invalid(MESSAGES.WALL_SCOPE);
    const branchId = scope === 'branch' ? (employee.branch_id ?? null) : null;
    if (scope === 'branch' && !branchId) throw invalid(MESSAGES.WALL_WRONG_BRANCH);
    const files = attachmentsFrom(body, { folder: 'praise', employeeId: employee.id });
    const at = now().toISOString();
    const stored = await storeAttachments(store, files);
    const mentioned = await resolveMentions(store, reason, { exclude: employee.id });
    const created = await store.createWallPost({
      employee_id: employee.id,
      kind: 'praise',
      scope,
      branch_id: branchId,
      body: reason,
      attachments: stored,
      mentions: mentioned.map((m) => m.id),
      badge,
      about_employee_id: aboutId,
      created_at: at,
      updated_at: at,
    });
    if (mentioned.length) {
      await store.createWallMentions(mentioned.map((m) => ({
        post_id: created.id, mentioned_id: m.id, mentioned_by_id: employee.id,
      })));
      await notifyMentions({ store, author: employee, mentioned, postId: created.id });
    }
    await notifyPraise({ store, author: employee, praisedEmployeeId: aboutId, postId: created.id, badge });
    const fresh = await store.getWallPost(created.id);
    res.status(201).json({
      post: await postView(store, fresh, {
        me: employee.id,
        author: employee,
        about: await store.getEmployeeCard(aboutId),
        mentioned,
        myReaction: null,
      }),
      badge: badgeById(badge),
    });
  });
}

module.exports = { listPraise, createPraise };
