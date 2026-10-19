const { dmy } = require('../policy/notifications');
const { badgeById } = require('../policy/wall');

/**
 * The Wall's notifications (tasks F1 to F8, D6, D7), written as in-app rows by the events
 * themselves: a mention, a reply to my comment, praise for me, an announcement sent to me, an
 * announcement asking me to acknowledge it, and a poll I voted in that has closed. The push
 * worker (src/jobs/push.js) delivers them; nothing here pushes by itself.
 *
 * Every one is best effort, exactly as D6's are: a notification that cannot be written never
 * fails the post, the comment or the praise it is about, and the failure goes to the pm2 log. The
 * wall's own routes never wait on this succeeding.
 *
 * A notification carries ids only (`data`), never a copy of a body: the app opens the post.
 */

/** One row per person, skipping the person who did the thing and anybody mentioned twice. */
async function writeEach(store, employeeIds, build) {
  for (const employeeId of [...new Set(employeeIds.filter(Boolean))]) {
    try {
      await store.createNotification({ employee_id: employeeId, ...build() });
    } catch (e) {
      console.error(`[ess] wall notification for ${employeeId} failed: ${e && e.message ? e.message : e}`);
    }
  }
}

/** 'X mentioned you in a post' to each mentioned person (F1, F2). */
async function notifyMentions({ store, author, mentioned, postId, commentId = null }) {
  try {
    const where = commentId ? 'a comment' : 'a post';
    await writeEach(store, mentioned.map((m) => m.id), () => ({
      category: 'mentions',
      title: `${author.full_name} mentioned you`,
      body: `${author.full_name} mentioned you in ${where} on the Wall.`,
      data: { post_id: postId, ...(commentId ? { comment_id: commentId } : {}) },
    }));
  } catch (e) {
    console.error(`[ess] wall mention notification failed: ${e && e.message ? e.message : e}`);
  }
}

/** 'X replied to your comment' to the comment's author (F2). */
async function notifyReply({ store, author, repliedToEmployeeId, postId, commentId }) {
  if (!repliedToEmployeeId || repliedToEmployeeId === author.id) return;
  try {
    await writeEach(store, [repliedToEmployeeId], () => ({
      category: 'replies',
      title: `${author.full_name} replied to you`,
      body: `${author.full_name} replied to your comment on the Wall.`,
      data: { post_id: postId, comment_id: commentId },
    }));
  } catch (e) {
    console.error(`[ess] wall reply notification failed: ${e && e.message ? e.message : e}`);
  }
}

/** 'X praised you' to the person praised (F3). */
async function notifyPraise({ store, author, praisedEmployeeId, postId, badge }) {
  if (!praisedEmployeeId || praisedEmployeeId === author.id) return;
  try {
    const label = badgeById(badge);
    await writeEach(store, [praisedEmployeeId], () => ({
      category: 'praise',
      title: `${author.full_name} praised you`,
      body: `${author.full_name} gave you ${label ? label.label : 'a badge'} on the Wall.`,
      data: { post_id: postId, ...(badge ? { badge } : {}) },
    }));
  } catch (e) {
    console.error(`[ess] wall praise notification failed: ${e && e.message ? e.message : e}`);
  }
}

/** 'New announcement: <title>' to everybody it reached, and the acknowledgement ask with it (F5). */
async function notifyAnnouncement({ store, announcement, employeeIds, needsAck }) {
  try {
    const data = { announcement_id: announcement.id };
    await writeEach(store, employeeIds, () => ({
      category: 'announcements',
      title: 'New announcement',
      body: `${announcement.title}${announcement.closes_on ? ` Acknowledge by ${dmy(announcement.closes_on)}.` : ''}`,
      data,
    }));
    // The ask is its own category, so a person can turn the reminder off without losing the
    // announcement itself.
    if (needsAck) {
      await writeEach(store, employeeIds, () => ({
        category: 'acknowledgements',
        title: 'Please acknowledge',
        body: `${announcement.title} needs your acknowledgement${announcement.closes_on ? ` by ${dmy(announcement.closes_on)}` : ''}.`,
        data,
      }));
    }
  } catch (e) {
    console.error(`[ess] wall announcement notification failed: ${e && e.message ? e.message : e}`);
  }
}

/** 'Still waiting for your acknowledgement' to those who have not, on the reminder day (F5). */
async function notifyAckReminder({ store, announcement, employeeIds }) {
  try {
    await writeEach(store, employeeIds, () => ({
      category: 'acknowledgements',
      title: 'Please acknowledge',
      body: `${announcement.title} closes on ${dmy(announcement.closes_on)} and your acknowledgement is still due.`,
      data: { announcement_id: announcement.id },
    }));
  } catch (e) {
    console.error(`[ess] wall acknowledgement reminder failed: ${e && e.message ? e.message : e}`);
  }
}

/** 'The poll has closed' to those who voted (F4). */
async function notifyPollClosed({ store, poll, voterEmployeeIds }) {
  try {
    await writeEach(store, voterEmployeeIds, () => ({
      category: 'polls',
      title: 'Poll closed',
      body: `${pollBody(poll)} has closed. See the results on the Wall.`,
      data: { post_id: poll.id },
    }));
  } catch (e) {
    console.error(`[ess] wall poll notification failed: ${e && e.message ? e.message : e}`);
  }
}

/** A poll is a post whose body is the question. */
const pollBody = (poll) => poll.body;

module.exports = {
  notifyMentions,
  notifyReply,
  notifyPraise,
  notifyAnnouncement,
  notifyAckReminder,
  notifyPollClosed,
};
