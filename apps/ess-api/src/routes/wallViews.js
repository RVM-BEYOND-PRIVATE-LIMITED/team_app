const { badgeById } = require('../policy/wall');

/**
 * What a Wall row looks like coming back (tasks F1 to F6): one shape the app reads for the feed,
 * one post, a profile's praise strip and the comments. Nothing internal is ever sent: the hidden
 * and deleted bookkeeping, who hid what and who voted what stay server-side (F4, F7).
 *
 * Every attachment is a `path` in the ESS's own bucket plus a fresh 300-second signed link, made
 * on every read, exactly as the profile's photo link is (E10). The stored path is never returned
 * raw: the app only ever follows the link.
 */

/** One attachment, with its signed link. */
async function attachmentView(store, file) {
  return {
    name: file.name ?? null,
    content_type: file.content_type ?? null,
    url: await store.signedEssUrl(file.path),
  };
}

/** F1: every attachment of a row, each with its link. */
async function filesOf(store, attachments) {
  const out = [];
  for (const file of attachments || []) out.push(await attachmentView(store, file));
  return out;
}

/** The author of a row, as staff read a name; null once the row is deleted. */
const authorView = (employee) => (employee ? {
  id: employee.id,
  full_name: employee.full_name,
  employee_code: employee.employee_code ?? null,
  designation: employee.designation ?? null,
} : null);

/** A person a post is about (a wish's subject, a praise's receiver, somebody mentioned). */
const aboutView = (employee) => (employee ? {
  id: employee.id,
  full_name: employee.full_name,
  employee_code: employee.employee_code ?? null,
} : null);

/**
 * One feed row. `me` is who is reading: it decides `mine`. A deleted row comes back as the two
 * lines the app needs to keep the thread's shape, and nothing else.
 */
async function postView(store, row, { me, author = null, about = null, mentioned = [], myReaction = undefined, poll = undefined }) {
  if (row.deleted_at) {
    return {
      id: row.id, deleted: true, kind: row.kind, scope: row.scope, author: null,
      mine: row.employee_id === me, deleted_at: row.deleted_at,
    };
  }
  const counts = row.reaction_counts || {};
  const view = {
    id: row.id,
    kind: row.kind,
    scope: row.scope,
    branch_id: row.branch_id ?? null,
    author: authorView(author),
    mine: row.employee_id === me,
    body: row.body,
    attachments: await filesOf(store, row.attachments),
    mentions: mentioned.map(aboutView),
    about: aboutView(about),
    edited: row.edited_at != null,
    edited_at: row.edited_at ?? null,
    created_at: row.created_at,
    updated_at: row.updated_at,
    hidden: row.hidden_at != null,
  };
  if (myReaction !== undefined) view.my_reaction = myReaction ? myReaction.reaction : null;
  if (row.kind === 'praise') {
    const badge = badgeById(row.badge);
    view.badge = badge ? { id: badge.id, label: badge.label } : null;
  }
  if (row.kind === 'wish') {
    view.occasion = row.occasion ?? null;
    return view;
  }
  view.reactions = { counts, total: Object.values(counts).reduce((n, v) => n + (Number(v) || 0), 0) };
  view.comment_count = row.comment_count || 0;
  if (row.kind === 'poll' && poll) view.poll = poll;
  return view;
}

/**
 * The poll block of a post: its options with their counts, my own votes, and whether it is still
 * open. Its own rules live in ../lib/wallKit.js; this is the re-export the routes import.
 */
const { pollView } = require('../lib/wallKit');

/**
 * One comment or reply as the app reads it, with its own reactions and, for a comment, replies.
 * A hidden comment (F7) keeps its place in the thread but loses its words for everybody but HR
 * and its author: the app shows "hidden by HR" and the reason is HR's record, never the reader's.
 */
function commentView(row, { me, author = null, mentioned = [], myReaction = undefined, replies = [], seesHidden = false }) {
  if (row.deleted_at) {
    return { id: row.id, deleted: true, mine: row.employee_id === me, deleted_at: row.deleted_at, replies: [] };
  }
  if (row.hidden_at && !seesHidden) {
    return {
      id: row.id,
      post_id: row.post_id,
      parent_id: row.parent_id ?? null,
      hidden: true,
      body: null,
      author: null,
      mine: false,
      mentions: [],
      reactions: { counts: {}, total: 0 },
      reply_count: row.reply_count || 0,
      created_at: row.created_at,
      updated_at: row.updated_at,
      edited: row.edited_at != null,
      replies: replies.map((reply) => commentView(reply.row, {
        me,
        seesHidden: false,
        replies: [],
      })),
    };
  }
  const counts = row.reaction_counts || {};
  const view = {
    id: row.id,
    post_id: row.post_id,
    parent_id: row.parent_id ?? null,
    author: authorView(author),
    mine: row.employee_id === me,
    body: row.body,
    mentions: mentioned.map(aboutView),
    reactions: { counts, total: Object.values(counts).reduce((n, v) => n + (Number(v) || 0), 0) },
    reply_count: row.reply_count || 0,
    created_at: row.created_at,
    updated_at: row.updated_at,
    edited: row.edited_at != null,
    hidden: row.hidden_at != null,
    replies: replies.map((reply) => commentView(reply.row, {
      me,
      author: reply.author,
      mentioned: reply.mentioned,
      myReaction: reply.myReaction,
      seesHidden,
    })),
  };
  if (myReaction !== undefined) view.my_reaction = myReaction ? myReaction.reaction : null;
  return view;
}

/** An announcement as a reader sees it (F5): never the audience list, never who read it. */
async function announcementView(store, row, { me, author = null, read = null, audienceLabel = null }) {
  return {
    id: row.id,
    title: row.title,
    body: row.body,
    attachments: await filesOf(store, row.attachments),
    author: authorView(author),
    mine: row.employee_id === me,
    audience_label: audienceLabel,
    needs_ack: row.needs_ack === true,
    closes_on: row.closes_on ?? null,
    pinned: row.pinned === true,
    publish_at: row.publish_at ?? null,
    published_at: row.published_at ?? null,
    created_at: row.created_at,
    edited: row.edited_at != null,
    read_at: read ? read.read_at : null,
    ack_at: read ? read.ack_at : null,
  };
}

module.exports = { attachmentView, filesOf, authorView, aboutView, postView, pollView, commentView, announcementView };
