const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const { bodyWith, requiredText, optionalText, idParam, oneQueryValue, invalid, isUuid, chars } = require('../lib/validate');
const { LIST_LIMITS } = require('../lib/store');
const { attachmentsFrom, storeAttachments } = require('../lib/wallKit');
const {
  notFound, loadTicket, peopleForTicket, categoriesById, holidaysBetween, statusFilter,
  ticketView, messageView, eventRow, commentRow, overdueMinutesOf, activeCategories,
} = require('../lib/helpdeskKit');
const { recordBefore } = require('../lib/audit');
const { mirrorRaised, closeRegisterForTicket } = require('../lib/infraMirror');
const {
  STATUSES, ACTIVE_STATUSES, AGENT_TRANSITIONS, RAISER_CLOSES_FROM, REOPEN_DAYS,
  RATING_MIN, RATING_MAX, canRead, canAct, seesRaiser, dueTimes, holidaysFor, isQueueRole,
} = require('../policy/helpdesk');
const {
  notifyRaised, notifyComment, notifyClaimed, notifyAssigned, notifyStatus, notifyReopened,
} = require('../lib/helpdeskNotify');

/**
 * The Helpdesk's tickets (Phase 2B, tasks G2 to G5): the raise, the raiser's own list, one
 * ticket with its thread, and the moves the two sides make. The rules live in
 * policy/helpdesk.js; this file only asks its questions.
 *
 * Every act keeps the same two refusals (G4): somebody who cannot even see the ticket is told
 * it does not exist (404), and somebody who sees it but is not the raiser or the category's team
 * is told only the team can act (403 HELPDESK_AGENT_ONLY). A confidential ticket read by nobody
 * in particular is audited before it is sent (lib/audit.js recordBefore), as an HR read of
 * personal details is.
 */

/**
 * G3's "overdue by" for a whole list: the holidays fetched once for the oldest ticket forwards,
 * then each row judged against its own branch's calendar.
 */
async function overdueMap(store, rows, nowDate) {
  if (!rows.length) return new Map();
  const oldest = rows.reduce((min, r) => (r.created_at < min ? r.created_at : min), rows[0].created_at);
  const holidayRows = await store.listHolidays(String(oldest).slice(0, 10), nowDate.toISOString().slice(0, 10));
  const out = new Map();
  for (const row of rows) {
    out.set(row.id, overdueMinutesOf(row, nowDate, holidaysFor(holidayRows, row.branch_id ?? null)));
  }
  return out;
}

/**
 * Who is asking, and what they may do (G4, G5). The raiser and the category's queue roles act;
 * whoever merely reads (HR's oversight) is refused the act, and whoever cannot see the ticket is
 * told it was never there.
 */
function assertActor(row, req, category) {
  const isRaiser = row.created_by === req.auth.employee.id;
  const agent = canAct(req.auth.role, category);
  if (!isRaiser && !agent) {
    if (canRead(req.auth.role, row, category)) {
      throw new HttpError(403, 'HELPDESK_AGENT_ONLY', MESSAGES.HELPDESK_AGENT_ONLY);
    }
    throw notFound(MESSAGES.HELPDESK_TICKET_NOT_FOUND);
  }
  return { isRaiser, agent };
}

/** POST /api/ess/helpdesk/tickets { category, subject, body, anonymous?, attachments? } — raise one (G2). */
function createTicket({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const form = bodyWith(req, ['category', 'subject', 'body', 'anonymous', 'attachments']);
    const slug = typeof form.category === 'string' ? form.category.trim() : '';
    if (!slug) throw invalid(MESSAGES.HELPDESK_CATEGORY);
    const category = (await activeCategories(store)).find((c) => c.slug === slug);
    if (!category) throw notFound(MESSAGES.HELPDESK_CATEGORY_NOT_FOUND);
    if (!category.is_ticket) throw invalid(MESSAGES.HELPDESK_NOT_A_TICKET);
    const subject = requiredText(form.subject, { min: 3, max: 200, message: MESSAGES.HELPDESK_SUBJECT });
    const text = requiredText(form.body, { min: 3, max: 2000, message: MESSAGES.HELPDESK_BODY });
    const anonymous = form.anonymous === undefined || form.anonymous === null ? false : form.anonymous;
    if (typeof anonymous !== 'boolean') throw invalid(MESSAGES.HELPDESK_ANONYMOUS);

    const files = attachmentsFrom(form, { folder: 'helpdesk', employeeId: employee.id });
    const stored = await storeAttachments(store, files);

    const at = now().toISOString();
    // G3: the deadlines are worked out at raise, on the raiser's branch's calendar, and stored.
    const holidays = await holidaysBetween(store, at,
      new Date(Date.parse(at) + 60 * 86400000).toISOString(), employee.branch_id);
    const dues = dueTimes(new Date(at), category, holidays);
    const created = await store.createHelpdeskTicket({
      created_by: employee.id,
      category_id: category.id,
      priority: category.priority,
      subject,
      body: text,
      attachments: stored,
      anonymous,
      branch_id: employee.branch_id ?? null,
      first_response_due_at: dues.first_response_due_at.toISOString(),
      resolution_due_at: dues.resolution_due_at.toISOString(),
      created_at: at,
      updated_at: at,
    });
    await store.createHelpdeskMessage(eventRow(created.id, 'opened', {}, at, employee.id));
    await notifyRaised({ store, ticket: created, category, raiserName: anonymous ? null : employee.full_name });
    // G6 (2D): a lab or facility ticket gets one summary row in the Admin Manager's register.
    // Best effort: the raise is the record and never fails because the register cannot be written.
    await mirrorRaised({ store, ticket: created, category, raiser: employee, raiserUserId: req.auth.userId ?? null, at });
    res.status(201).json({
      ticket: await ticketView(store, created, {
        category, raiser: employee, assignee: null, me: employee.id, seesName: true,
      }),
    });
  });
}

/** GET /api/ess/helpdesk/tickets?status= — my tickets, newest first (G2). */
function listMyTickets({ store, now }) {
  return asyncRoute(async (req, res) => {
    const statuses = statusFilter(oneQueryValue(req.query.status), STATUSES, MESSAGES.HELPDESK_STATUS_FILTER);
    const employee = req.auth.employee;
    const rows = await store.listMyHelpdeskTickets(employee.id, statuses, LIST_LIMITS.helpdeskTickets);
    const cats = await categoriesById(store);
    const overdue = await overdueMap(store, rows, now());
    const helpers = await store.listEmployeeCards([...new Set(rows.map((r) => r.assignee_id).filter(Boolean))]);
    const byId = new Map(helpers.map((p) => [p.id, p]));
    const tickets = [];
    for (const row of rows) {
      tickets.push(await ticketView(store, row, {
        category: cats.get(row.category_id),
        raiser: employee,
        assignee: byId.get(row.assignee_id) || null,
        me: employee.id,
        seesName: true,
        overdueMinutes: overdue.get(row.id) ?? null,
      }));
    }
    res.json({ tickets });
  });
}

/** GET /api/ess/helpdesk/tickets/:id — one ticket, with its thread (G2, G4). */
function getTicket({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { row, category } = await loadTicket(store, idParam(req.params.id));
    const isRaiser = row.created_by === req.auth.employee.id;
    if (!isRaiser && !canRead(req.auth.role, row, category)) {
      throw notFound(MESSAGES.HELPDESK_TICKET_NOT_FOUND);
    }
    // A confidential ticket read by anybody but its raiser is audited first, and a failure to
    // write the audit row refuses the read, as an HR read of personal details is.
    if (category.confidential && !isRaiser) {
      await recordBefore(store, req, { action: 'helpdesk.ticket.read', details: { ticket_id: row.id, ref: row.ref } });
    }
    const { raiser, assignee } = await peopleForTicket(store, row);
    const nowDate = now();
    const holidays = await holidaysBetween(store, row.created_at, nowDate.toISOString(), row.branch_id);
    const messages = await store.listHelpdeskMessages(row.id, LIST_LIMITS.helpdeskMessages);
    const authors = await store.listEmployeeCards([...new Set(messages.map((m) => m.employee_id).filter(Boolean))]);
    const byId = new Map(authors.map((p) => [p.id, p]));
    // G6: the register's summary row, when this category is mirrored and the link was made.
    const link = await store.getInfraLinkForTicket(row.id);
    const infraRow = link && link.state === 'linked' ? await store.getInfraTicket(link.infra_ticket_id) : null;
    res.json({
      ticket: await ticketView(store, row, {
        category, raiser, assignee, me: req.auth.employee.id,
        seesName: !row.anonymous || isRaiser || seesRaiser(req.auth.role, row),
        overdueMinutes: overdueMinutesOf(row, nowDate, holidays),
        infra: infraRow
          ? { ticket_no: infraRow.ticket_no ?? null, status: infraRow.status, closed_on: infraRow.closed_on ?? null }
          : null,
      }),
      messages: messages.map((m) => messageView(m, { author: byId.get(m.employee_id) || null })),
    });
  });
}

/** POST /api/ess/helpdesk/tickets/:id/comments { body } — a comment, by the raiser or the team (G5). */
function createComment({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const { row, category } = await loadTicket(store, idParam(req.params.id));
    const { agent } = assertActor(row, req, category);
    const text = requiredText(bodyWith(req, ['body']).body,
      { min: 1, max: 2000, message: MESSAGES.HELPDESK_COMMENT_BODY });
    const at = now().toISOString();
    const message = await store.createHelpdeskMessage(commentRow(row.id, employee.id, text, at));
    // The team's first act on a ticket is its first response (G3).
    if (agent && row.first_response_at == null) {
      await store.updateHelpdeskTicket(row.id, { first_response_at: at, updated_at: at });
    }
    await notifyComment({
      store, ticket: row, commentByEmployeeId: employee.id,
      raiserId: row.created_by, assigneeId: row.assignee_id,
    });
    res.status(201).json({ message: messageView(message, { author: employee }) });
  });
}

/** POST /api/ess/helpdesk/tickets/:id/withdraw — the raiser takes an open ticket back (G2). */
function withdrawTicket({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const { row, category } = await loadTicket(store, idParam(req.params.id));
    const { isRaiser } = assertActor(row, req, category);
    if (!isRaiser) throw new HttpError(403, 'HELPDESK_AGENT_ONLY', MESSAGES.HELPDESK_AGENT_ONLY);
    if (row.status !== 'open') throw new HttpError(409, 'HELPDESK_NOT_OPEN', MESSAGES.HELPDESK_NOT_OPEN);
    const at = now().toISOString();
    const updated = await store.updateHelpdeskTicket(row.id, { status: 'withdrawn', updated_at: at });
    await store.createHelpdeskMessage(eventRow(row.id, 'withdrawn', { from: row.status }, at, employee.id));
    await closeRegisterForTicket({ store, ticketId: row.id, at });
    const people = await peopleForTicket(store, updated);
    res.json({
      ticket: await ticketView(store, updated, {
        category, raiser: people.raiser, assignee: people.assignee, me: employee.id, seesName: true,
      }),
    });
  });
}

/** POST /api/ess/helpdesk/tickets/:id/reopen — the raiser takes a settled ticket back up (G2). */
function reopenTicket({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const { row, category } = await loadTicket(store, idParam(req.params.id));
    const { isRaiser } = assertActor(row, req, category);
    if (!isRaiser) throw new HttpError(403, 'HELPDESK_AGENT_ONLY', MESSAGES.HELPDESK_AGENT_ONLY);
    if (row.status !== 'resolved' && row.status !== 'closed') {
      throw new HttpError(409, 'HELPDESK_NOT_CLOSED', MESSAGES.HELPDESK_NOT_CLOSED);
    }
    const settled = row.closed_at ?? row.resolved_at;
    if (settled && Date.parse(settled) < now().getTime() - REOPEN_DAYS * 86400000) {
      throw new HttpError(409, 'HELPDESK_REOPEN_WINDOW', MESSAGES.HELPDESK_REOPEN_WINDOW);
    }
    const at = now().toISOString();
    // The reopen is a fresh ticket to the SLA: the deadlines are worked out again, the first
    // response and the escalation start over, and the closed episode stays in the thread.
    const holidays = await holidaysBetween(store, at,
      new Date(Date.parse(at) + 60 * 86400000).toISOString(), row.branch_id);
    const dues = dueTimes(new Date(at), category, holidays);
    const updated = await store.updateHelpdeskTicket(row.id, {
      status: 'open',
      reopened_at: at,
      resolved_at: null,
      closed_at: null,
      closed_by_employee_id: null,
      closing_reason: null,
      rating: null,
      first_response_at: null,
      first_response_due_at: dues.first_response_due_at.toISOString(),
      resolution_due_at: dues.resolution_due_at.toISOString(),
      escalation_level: 0,
      updated_at: at,
    });
    await store.createHelpdeskMessage(eventRow(row.id, 'reopened', { from: row.status }, at, employee.id));
    await notifyReopened({
      store, ticket: updated, assigneeId: row.assignee_id, raiserName: employee.full_name,
    });
    const people = await peopleForTicket(store, updated);
    res.json({
      ticket: await ticketView(store, updated, {
        category, raiser: people.raiser, assignee: people.assignee, me: employee.id, seesName: true,
      }),
    });
  });
}

/** POST /api/ess/helpdesk/tickets/:id/close { closing_reason, rating? } — the raiser closes it (G2). */
function closeTicket({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const { row, category } = await loadTicket(store, idParam(req.params.id));
    const { isRaiser } = assertActor(row, req, category);
    if (!isRaiser) throw new HttpError(403, 'HELPDESK_AGENT_ONLY', MESSAGES.HELPDESK_AGENT_ONLY);
    if (!RAISER_CLOSES_FROM.includes(row.status)) {
      throw new HttpError(409, 'HELPDESK_TRANSITION', MESSAGES.HELPDESK_TRANSITION);
    }
    const form = bodyWith(req, ['closing_reason', 'rating']);
    const reason = requiredText(form.closing_reason, { min: 3, max: 280, message: MESSAGES.HELPDESK_CLOSE_REASON });
    const rating = form.rating === undefined || form.rating === null ? null : form.rating;
    if (rating !== null && (!Number.isInteger(rating) || rating < RATING_MIN || rating > RATING_MAX)) {
      throw invalid(MESSAGES.HELPDESK_RATING);
    }
    const at = now().toISOString();
    const updated = await store.updateHelpdeskTicket(row.id, {
      status: 'closed',
      closed_at: at,
      closed_by_employee_id: employee.id,
      closing_reason: reason,
      rating,
      updated_at: at,
    });
    await store.createHelpdeskMessage(eventRow(row.id, 'closed', {
      from: row.status, reason, rating,
    }, at, employee.id));
    await closeRegisterForTicket({ store, ticketId: row.id, at });
    const people = await peopleForTicket(store, updated);
    res.json({
      ticket: await ticketView(store, updated, {
        category, raiser: people.raiser, assignee: people.assignee, me: employee.id, seesName: true,
      }),
    });
  });
}

/** POST /api/ess/helpdesk/tickets/:id/claim — a team member takes the ticket (G5). */
function claimTicket({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const { row, category } = await loadTicket(store, idParam(req.params.id));
    const { agent } = assertActor(row, req, category);
    if (!agent) throw new HttpError(403, 'HELPDESK_AGENT_ONLY', MESSAGES.HELPDESK_AGENT_ONLY);
    if (!ACTIVE_STATUSES.includes(row.status)) {
      throw new HttpError(409, 'HELPDESK_NOT_LIVE', MESSAGES.HELPDESK_NOT_LIVE);
    }
    if (row.assignee_id && row.assignee_id !== employee.id) {
      throw new HttpError(409, 'HELPDESK_ALREADY_CLAIMED', MESSAGES.HELPDESK_ALREADY_CLAIMED);
    }
    let fresh = row;
    if (!row.assignee_id) {
      const at = now().toISOString();
      const patch = {
        assignee_id: employee.id,
        claimed_at: at,
        first_response_at: row.first_response_at ?? at,
        updated_at: at,
      };
      // The claim starts the work: an open ticket moves to in progress with it (G2).
      if (row.status === 'open') patch.status = 'in_progress';
      fresh = await store.updateHelpdeskTicket(row.id, patch);
      await store.createHelpdeskMessage(eventRow(row.id, 'claimed', { employee_id: employee.id }, at, employee.id));
      await notifyClaimed({ store, ticket: fresh, raiserId: row.created_by, assigneeName: employee.full_name });
    }
    // A second claim by the same person is the same claim: the ticket comes back as it is.
    const { raiser, assignee } = await peopleForTicket(store, fresh);
    res.json({ ticket: await ticketView(store, fresh, { category, raiser, assignee, me: employee.id, seesName: true }) });
  });
}

/** POST /api/ess/helpdesk/tickets/:id/status { status } — a team move on the lifecycle (G2, G5). */
function moveTicketStatus({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const { row, category } = await loadTicket(store, idParam(req.params.id));
    const { agent } = assertActor(row, req, category);
    if (!agent) throw new HttpError(403, 'HELPDESK_AGENT_ONLY', MESSAGES.HELPDESK_AGENT_ONLY);
    const to = bodyWith(req, ['status']).status;
    if (!['in_progress', 'on_hold', 'resolved'].includes(to)) throw invalid(MESSAGES.HELPDESK_STATUS);
    if (to === 'on_hold' && !category.allows_hold) throw invalid(MESSAGES.HELPDESK_HOLD);
    if (!AGENT_TRANSITIONS[row.status].includes(to)) {
      throw new HttpError(409, 'HELPDESK_TRANSITION', MESSAGES.HELPDESK_TRANSITION);
    }
    const at = now().toISOString();
    const patch = {
      status: to,
      first_response_at: row.first_response_at ?? at,
      updated_at: at,
    };
    if (to === 'resolved') patch.resolved_at = at;
    const updated = await store.updateHelpdeskTicket(row.id, patch);
    await store.createHelpdeskMessage(eventRow(row.id, 'status_changed', { from: row.status, to }, at, employee.id));
    if (to === 'resolved') await closeRegisterForTicket({ store, ticketId: row.id, at });
    await notifyStatus({
      store, ticket: updated, raiserId: row.created_by, status: to, byName: employee.full_name,
    });
    const people = await peopleForTicket(store, updated);
    res.json({
      ticket: await ticketView(store, updated, {
        category, raiser: people.raiser, assignee: people.assignee, me: employee.id, seesName: true,
      }),
    });
  });
}

/**
 * POST /api/ess/helpdesk/tickets/:id/assign { employee_id, note? } — assign it to a named
 * handler (Phase 2C, KP 5). The team only: the person must hold one of the category's queue
 * roles, checked through their login (employee → user → users.role), and the ticket must still
 * be live. The assignment is stamped with who pointed it there (assigned_by_*), the history row
 * keeps every move (a reassign does not overwrite who had it first), and the thread's `assigned`
 * event shows it on the screen the raiser and the team read.
 */
function assignTicket({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const { row, category } = await loadTicket(store, idParam(req.params.id));
    const { agent } = assertActor(row, req, category);
    if (!agent) throw new HttpError(403, 'HELPDESK_AGENT_ONLY', MESSAGES.HELPDESK_AGENT_ONLY);
    if (!ACTIVE_STATUSES.includes(row.status)) {
      throw new HttpError(409, 'HELPDESK_NOT_LIVE', MESSAGES.HELPDESK_NOT_LIVE);
    }

    const form = bodyWith(req, ['employee_id', 'note']);
    if (typeof form.employee_id !== 'string' || !isUuid(form.employee_id)) {
      throw invalid(MESSAGES.HELPDESK_ASSIGNEE);
    }
    const note = optionalText(form.note);
    if (note === undefined || (note && chars(note) > 500)) throw invalid(MESSAGES.HELPDESK_ASSIGN_NOTE);

    // The queue's own rule, checked through the login: only a role the category serves can be
    // handed a ticket (KP 5).
    const link = await store.getEmployeeLink(form.employee_id.toLowerCase());
    if (!link || link.is_archived) throw notFound(MESSAGES.HELPDESK_ASSIGNEE_NOT_FOUND);
    let role = null;
    if (link.user_id) {
      const user = await store.getUser(link.user_id);
      role = user ? user.role : null;
    }
    if (!role || !isQueueRole(role, category.queue_roles)) {
      throw invalid(MESSAGES.HELPDESK_ASSIGNEE_ROLE);
    }

    // Assigning to the person who already has it is the same assignment: the ticket answers as it is.
    if (row.assignee_id === link.id) {
      const people = await peopleForTicket(store, row);
      return res.json({
        ticket: await ticketView(store, row, { category, raiser: people.raiser, assignee: people.assignee, me: employee.id, seesName: true }),
      });
    }

    const at = now().toISOString();
    const updated = await store.updateHelpdeskTicket(row.id, {
      assignee_id: link.id,
      // The claim stamp the lifecycle's CHECK asks for, kept when the ticket already had one.
      claimed_at: row.claimed_at ?? at,
      assigned_by_employee_id: employee.id,
      assigned_by_name: employee.full_name,
      assigned_at: at,
      // A named handler is the team at work: the first response and the open ticket both start.
      first_response_at: row.first_response_at ?? at,
      status: row.status === 'open' ? 'in_progress' : row.status,
      updated_at: at,
    });
    await store.createHelpdeskAssignment({
      ticket_id: row.id,
      from_employee_id: row.assignee_id ?? null,
      to_employee_id: link.id,
      assigned_by_user_id: req.auth.userId,
      assigned_by_name: employee.full_name,
      note: note || null,
      created_at: at,
    });
    await store.createHelpdeskMessage(eventRow(row.id, 'assigned', {
      employee_id: link.id, from: row.assignee_id ?? null,
    }, at, employee.id));
    await notifyAssigned({ store, ticket: updated, assigneeId: link.id, byName: employee.full_name });
    const people = await peopleForTicket(store, updated);
    res.json({
      ticket: await ticketView(store, updated, { category, raiser: people.raiser, assignee: people.assignee, me: employee.id, seesName: true }),
    });
  });
}

module.exports = {
  createTicket,
  listMyTickets,
  getTicket,
  createComment,
  withdrawTicket,
  reopenTicket,
  closeTicket,
  claimTicket,
  assignTicket,
  moveTicketStatus,
};
