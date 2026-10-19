/**
 * The Helpdesk's notifications (Phase 2B, tasks G2 to G4), written as in-app rows by the events
 * themselves: a raise told to the team whose queue it lands in, a comment told to the other side,
 * a claim, a status move and a close told to the raiser, and the hourly job's escalations. The
 * push worker (src/jobs/push.js) delivers them; nothing here pushes by itself.
 *
 * Every one is best effort, exactly as the Wall's are: a notification that cannot be written
 * never fails the ticket it is about, and the failure goes to the pm2 log. The Helpdesk's own
 * routes never wait on this succeeding.
 *
 * A notification carries ids only (`data`), never a copy of a body: the app opens the ticket.
 * Anonymity is kept here too: the team is told "a new ticket" without a name, and only HR's own
 * roles (policy/helpdesk.js HR_ANONYMOUS_ROLES) are ever told who raised one.
 */

/** One row per person, skipping anyone named twice or the person who did the thing. */
async function writeEach(store, employeeIds, skip, build) {
  for (const employeeId of [...new Set(employeeIds.filter(Boolean))]) {
    if (employeeId === skip) continue;
    try {
      await store.createNotification({ employee_id: employeeId, ...build() });
    } catch (e) {
      console.error(`[ess] helpdesk notification for ${employeeId} failed: ${e && e.message ? e.message : e}`);
    }
  }
}

/** The queue roles' employee ids, whoever holds one of them right now. */
async function peopleForRoles(store, roles) {
  try {
    return await store.listEmployeeIdsForRoles(roles || []);
  } catch (e) {
    console.error(`[ess] helpdesk notification recipients failed: ${e && e.message ? e.message : e}`);
    return [];
  }
}

const ticketData = (ticket) => ({ ticket_id: ticket.id, ref: ticket.ref });

/**
 * G2: a raise told to the category's queue roles. An anonymous one is told without a name; a
 * confidential one says so in the words, but only the queue's own roles receive it either way.
 */
async function notifyRaised({ store, ticket, category, raiserName = null }) {
  try {
    const recipients = await peopleForRoles(store, category.queue_roles);
    const who = ticket.anonymous || !raiserName ? 'Somebody' : raiserName;
    const word = category.confidential ? 'confidential ticket' : 'ticket';
    await writeEach(store, recipients, ticket.created_by, () => ({
      category: 'helpdesk',
      title: `${who} raised a ${word}`,
      body: `${who} raised ${ticket.ref}: ${ticket.subject}.`,
      data: ticketData(ticket),
    }));
  } catch (e) {
    console.error(`[ess] helpdesk raise notification failed: ${e && e.message ? e.message : e}`);
  }
}

/** A comment told to the other side: the raiser hears the team, the assignee hears the raiser. */
async function notifyComment({ store, ticket, commentByEmployeeId, raiserId = null, assigneeId = null }) {
  try {
    await writeEach(store, [raiserId, assigneeId], commentByEmployeeId, () => ({
      category: 'helpdesk',
      title: `New comment on ${ticket.ref}`,
      body: `There is a new comment on ${ticket.ref}: ${ticket.subject}.`,
      data: ticketData(ticket),
    }));
  } catch (e) {
    console.error(`[ess] helpdesk comment notification failed: ${e && e.message ? e.message : e}`);
  }
}

/** A claim told to the raiser: "your ticket is with somebody" (G2). */
async function notifyClaimed({ store, ticket, raiserId, assigneeName = null }) {
  try {
    await writeEach(store, [raiserId], ticket.assignee_id, () => ({
      category: 'helpdesk',
      title: `${ticket.ref} claimed`,
      body: `${assigneeName || 'A team member'} is looking after ${ticket.ref}: ${ticket.subject}.`,
      data: ticketData(ticket),
    }));
  } catch (e) {
    console.error(`[ess] helpdesk claim notification failed: ${e && e.message ? e.message : e}`);
  }
}

/** A status move told to the raiser (G2). */
async function notifyStatus({ store, ticket, raiserId, status, byName = null }) {
  try {
    await writeEach(store, [raiserId], ticket.assignee_id, () => ({
      category: 'helpdesk',
      title: `${ticket.ref} is ${status.replace('_', ' ')}`,
      body: `${byName || 'The team'} moved ${ticket.ref} to ${status.replace('_', ' ')}.`,
      data: ticketData(ticket),
    }));
  } catch (e) {
    console.error(`[ess] helpdesk status notification failed: ${e && e.message ? e.message : e}`);
  }
}

/** A close told to the raiser, whoever closed it (G2). */
async function notifyClosed({ store, ticket, raiserId, closedByName = null }) {
  try {
    await writeEach(store, [raiserId], ticket.closed_by_employee_id, () => ({
      category: 'helpdesk',
      title: `${ticket.ref} closed`,
      body: `${closedByName || 'The team'} closed ${ticket.ref}: ${ticket.subject}.`,
      data: ticketData(ticket),
    }));
  } catch (e) {
    console.error(`[ess] helpdesk close notification failed: ${e && e.message ? e.message : e}`);
  }
}

/** A reopen told to whoever the ticket is with: the raiser has taken it back up (G2). */
async function notifyReopened({ store, ticket, assigneeId, raiserName = null }) {
  try {
    await writeEach(store, [assigneeId], ticket.created_by, () => ({
      category: 'helpdesk',
      title: `${ticket.ref} reopened`,
      body: `${raiserName || 'The raiser'} reopened ${ticket.ref}: ${ticket.subject}.`,
      data: ticketData(ticket),
    }));
  } catch (e) {
    console.error(`[ess] helpdesk reopen notification failed: ${e && e.message ? e.message : e}`);
  }
}

/** An assignment or reassignment told to the person it went to (KP 5). */
async function notifyAssigned({ store, ticket, assigneeId, byName = null }) {
  try {
    await writeEach(store, [assigneeId], null, () => ({
      category: 'helpdesk',
      title: `${ticket.ref} assigned to you`,
      body: `${byName || 'The team'} assigned ${ticket.ref}: ${ticket.subject} to you.`,
      data: ticketData(ticket),
    }));
  } catch (e) {
    console.error(`[ess] helpdesk assign notification failed: ${e && e.message ? e.message : e}`);
  }
}

/**
 * G3's escalation, one notification per stage (the row's escalation_level gates it in the job):
 *   level 1  the first response is overdue: the category's queue roles are told;
 *   level 2  it is unresolved past its resolution deadline: the HoO is told;
 *   level 3  it is unresolved a full resolution span past the deadline: the CEO is told.
 */
async function notifyEscalation({ store, ticket, level, recipients }) {
  try {
    const lines = {
      1: { title: `${ticket.ref} needs a first response`, body: `${ticket.ref} (${ticket.subject}) has had no first response in its SLA time.` },
      2: { title: `${ticket.ref} is overdue`, body: `${ticket.ref} (${ticket.subject}) is unresolved past its resolution deadline.` },
      3: { title: `${ticket.ref} needs you`, body: `${ticket.ref} (${ticket.subject}) is still unresolved long past its resolution deadline.` },
    };
    const words = lines[level];
    if (!words) return;
    await writeEach(store, recipients, ticket.created_by, () => ({
      category: 'helpdesk', ...words, data: ticketData(ticket),
    }));
  } catch (e) {
    console.error(`[ess] helpdesk escalation notification failed: ${e && e.message ? e.message : e}`);
  }
}

module.exports = {
  notifyRaised,
  notifyComment,
  notifyClaimed,
  notifyAssigned,
  notifyStatus,
  notifyClosed,
  notifyReopened,
  notifyEscalation,
};
