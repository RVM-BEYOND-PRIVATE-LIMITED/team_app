const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { MESSAGES } = require('../src/lib/errors');
const { HELPDESK_CATEGORIES, dueTimes } = require('../src/policy/helpdesk');
const { expectRefusal, expectInvalid, quietErrors } = require('./helpers/expect');
const H = require('./helpers/helpdeskFixtures');

/** Phase 2B, tasks G1 to G5: the raise, the raiser's own list, one ticket, and the moves. */

const CATEGORIES = '/api/ess/helpdesk/categories';
const TICKETS = '/api/ess/helpdesk/tickets';

const raise = (app, token, body) => request(app).post(TICKETS).set(bearer(token)).send(body);
const mine = (app, token, query = '') => request(app).get(`${TICKETS}${query}`).set(bearer(token));
const show = (app, token, id) => request(app).get(`${TICKETS}/${id}`).set(bearer(token));
const act = (app, token, id, what, body = {}) => request(app).post(`${TICKETS}/${id}/${what}`).set(bearer(token)).send(body);

const raiseBody = (change = {}) => ({
  category: 'it_lab',
  subject: 'The lab PCs will not start.',
  body: 'Six machines in Lab 2 stay on the boot screen; the morning batch is waiting.',
  ...change,
});

/** A world with the categories seeded, as the migration leaves them; a caller's own setup runs after. */
const world = (options = {}) => {
  const userSetup = options.setup;
  return buildApp({
    ...options,
    setup: (w) => {
      H.seedCategories(w);
      if (userSetup) userSetup(w);
    },
  });
};

describe('GET /api/ess/helpdesk/categories', () => {
  it('hands over the brief\'s six categories, the four links, and the rules document', async () => {
    const { app, people } = world();
    const res = await request(app).get(CATEGORIES).set(bearer(tokens.portal(people.faculty)));
    expect(res.status).toBe(200);
    expect(res.body.categories.map((c) => c.slug)).toEqual(HELPDESK_CATEGORIES.map((c) => c.slug));
    expect(res.body.categories[0]).toMatchObject({
      slug: 'it_lab', name: 'IT and lab equipment', is_ticket: true, flow: null,
      allows_hold: true, priority: 'medium', first_response_hours: 8, resolution_hours: 48,
    });
    expect(res.body.categories.find((c) => c.slug === 'leave_link')).toMatchObject({ is_ticket: false, flow: 'leave' });
    expect(res.body.settings).toMatchObject({ reopen_days: 7, rating: { min: 1, max: 5 }, anonymous: true, attachments: true });
  });
});

describe('POST /api/ess/helpdesk/tickets', () => {
  it('raises a ticket, numbered from the sequence, with the SLA deadlines stored', async () => {
    const { app, people, db } = world();
    const res = await raise(app, tokens.portal(people.faculty), raiseBody());
    expect(res.status).toBe(201);
    expect(res.body.ticket).toMatchObject({
      ref: 'HD-0001',
      status: 'open',
      priority: 'medium',
      subject: raiseBody().subject,
      category: { slug: 'it_lab', allows_hold: true },
      raised_by: { id: people.faculty.employee.id, full_name: 'Test CAD Faculty' },
      assignee: null,
      mine: true,
      overdue_minutes: null,
    });
    // G3: the dues worked out on the raiser's calendar (12:00 IST Friday), the same sums again.
    const now = new Date('2026-10-16T06:30:00.000Z');
    const dues = dueTimes(now, HELPDESK_CATEGORIES[0], []);
    expect(res.body.ticket.first_response_due_at).toBe(dues.first_response_due_at.toISOString());
    expect(res.body.ticket.resolution_due_at).toBe(dues.resolution_due_at.toISOString());
    // The thread opens with the 'opened' event, and nothing is deleted.
    expect(db.tables.hr_ess_helpdesk_messages).toEqual([
      expect.objectContaining({ ticket_id: res.body.ticket.id, kind: 'event', event: 'opened', employee_id: people.faculty.employee.id }),
    ]);
  });

  it('tells the category\'s team, by role, in their own words', async () => {
    const { app, people, db } = world();
    await raise(app, tokens.portal(people.faculty), raiseBody());
    expect(db.tables.hr_ess_notifications.map((n) => n.employee_id).sort())
      .toEqual([people.admin.employee.id, people.admin_manager.employee.id].sort());
    expect(db.tables.hr_ess_notifications[0]).toMatchObject({
      category: 'helpdesk',
      title: 'Test CAD Faculty raised a ticket',
      data: { ref: 'HD-0001' },
    });
  });

  it('keeps an anonymous raiser out of the team\'s notification, and takes attachments', async () => {
    const { app, people, db } = world();
    const res = await raise(app, tokens.portal(people.faculty), raiseBody({ anonymous: true, attachments: [{ data_base64: require('./helpers/wallFixtures').PNG_B64, content_type: 'image/png', name: 'error.png' }] }));
    expect(res.status).toBe(201);
    expect(res.body.ticket.anonymous).toBe(true);
    expect(res.body.ticket.attachments[0].url).toMatch(/^https:\/\/storage\.test\/ESS\/helpdesk\//);
    expect(db.tables.hr_ess_notifications[0].title).toBe('Somebody raised a ticket');
  });

  it('refuses a category that is not on the list, a link, and a form that is not a form', async () => {
    const { app, people } = world();
    const token = tokens.portal(people.faculty);
    expectInvalid(await raise(app, token, raiseBody({ category: '' })), MESSAGES.HELPDESK_CATEGORY);
    expectRefusal(await raise(app, token, raiseBody({ category: 'nope' })), 404, 'NOT_FOUND');
    expectInvalid(await raise(app, token, raiseBody({ category: 'leave_link' })), MESSAGES.HELPDESK_NOT_A_TICKET);
    expectInvalid(await raise(app, token, raiseBody({ subject: 'hi' })), MESSAGES.HELPDESK_SUBJECT);
    expectInvalid(await raise(app, token, raiseBody({ body: 'x' })), MESSAGES.HELPDESK_BODY);
    expectInvalid(await raise(app, token, raiseBody({ anonymous: 'yes' })), MESSAGES.HELPDESK_ANONYMOUS);
    expectInvalid(await raise(app, token, raiseBody({ extra: 1 })), MESSAGES.UNKNOWN_FIELD);
  });

  it('answers its own daily rate limit, 503 before the migration and 503 with the database away', async () => {
    quietErrors();
    const limited = world({ limits: { helpdeskTickets: { windowMs: 60 * 60 * 1000, limit: 1 } } });
    await raise(limited.app, tokens.portal(limited.people.faculty), raiseBody());
    expectRefusal(await raise(limited.app, tokens.portal(limited.people.faculty), raiseBody()), 429, 'RATE_LIMITED');
    const { app, people, db } = world();
    db.dropTable('hr_ess_helpdesk_tickets');
    expectRefusal(await raise(app, tokens.portal(people.faculty), raiseBody()), 503, 'MODULE_NOT_INSTALLED');
    const away = world();
    away.db.outage = 'error';
    expectRefusal(await raise(away.app, tokens.portal(away.people.faculty), raiseBody()), 503, 'UNAVAILABLE');
  });
});

describe('GET /api/ess/helpdesk/tickets', () => {
  it('shows my tickets, newest first, and holds to a status', async () => {
    const { app, people } = world({ setup: (w) => {
      H.seedCategories(w);
      w.tables.hr_ess_helpdesk_tickets = [
        H.ticketRow(w.people.faculty.employee.id, 1),
        H.ticketRow(w.people.faculty.employee.id, 2, { status: 'resolved', resolved_at: H.AT, created_at: '2026-10-15T05:00:00+00:00' }),
        H.ticketRow(w.people.hr.employee.id, 3),
      ];
    } });
    const res = await mine(app, tokens.portal(people.faculty));
    expect(res.status).toBe(200);
    expect(res.body.tickets.map((t) => t.ref)).toEqual(['HD-0001', 'HD-0002']);
    expect(res.body.tickets[0].mine).toBe(true);
    expect(res.body.tickets[1].assignee).toBeNull();
    const open = await mine(app, tokens.portal(people.faculty), '?status=open');
    expect(open.body.tickets.map((t) => t.ref)).toEqual(['HD-0001']);
    expectInvalid(await mine(app, tokens.portal(people.faculty), '?status=nope'), MESSAGES.HELPDESK_STATUS_FILTER);
  });
});

describe('GET /api/ess/helpdesk/tickets/{id}', () => {
  it('shows one ticket with its thread, to the raiser and to the team', async () => {
    const { app, people } = world({ setup: (w) => {
      H.seedCategories(w);
      w.tables.hr_ess_helpdesk_tickets = [H.ticketRow(w.people.faculty.employee.id, 1)];
      w.tables.hr_ess_helpdesk_messages = [H.messageRow(H.TICKET_ID(1), 1, w.people.admin.employee.id)];
    } });
    const raiser = await show(app, tokens.portal(people.faculty), H.TICKET_ID(1));
    expect(raiser.status).toBe(200);
    expect(raiser.body.ticket.raised_by.full_name).toBe('Test CAD Faculty');
    expect(raiser.body.messages).toHaveLength(1);
    expect(raiser.body.messages[0]).toMatchObject({
      kind: 'comment', body: 'Checked the switch; two ports are dead.', author: { full_name: 'Test Branch Admin' },
    });
    const agent = await show(app, tokens.portal(people.admin), H.TICKET_ID(1));
    expect(agent.status).toBe(200);
    // HR's oversight reads a non-confidential ticket too.
    const oversight = await show(app, tokens.portal(people.hr), H.TICKET_ID(1));
    expect(oversight.status).toBe(200);
  });

  it('hides an anonymous raiser from the team, and shows them to HR and to themself', async () => {
    const { app, people } = world({ setup: (w) => {
      H.seedCategories(w);
      w.tables.hr_ess_helpdesk_tickets = [H.ticketRow(w.people.faculty.employee.id, 1, { anonymous: true })];
    } });
    const team = await show(app, tokens.portal(people.admin), H.TICKET_ID(1));
    expect(team.body.ticket.raised_by).toBeNull();
    const hrView = await show(app, tokens.portal(people.hr), H.TICKET_ID(1));
    expect(hrView.body.ticket.raised_by.full_name).toBe('Test CAD Faculty');
    const raiser = await show(app, tokens.portal(people.faculty), H.TICKET_ID(1));
    expect(raiser.body.ticket.raised_by.full_name).toBe('Test CAD Faculty');
  });

  it('keeps a confidential ticket to its team and its raiser, and audits HR\'s reads', async () => {
    quietErrors();
    const { app, people, db } = world({ setup: (w) => {
      H.seedCategories(w);
      w.tables.hr_ess_helpdesk_tickets = [
        H.ticketRow(w.people.faculty.employee.id, 1, { category_id: H.CAT('grievance'), priority: 'high' }),
      ];
    } });
    // The queue role reads it.
    const agent = await show(app, tokens.portal(people.hr), H.TICKET_ID(1));
    expect(agent.status).toBe(200);
    // The raiser reads it.
    const raiser = await show(app, tokens.portal(people.faculty), H.TICKET_ID(1));
    expect(raiser.status).toBe(200);
    // HR's oversight does not extend to a confidential one, and nobody else's either (G4).
    const ceo = await show(app, tokens.portal(people.ceo), H.TICKET_ID(1));
    expectRefusal(ceo, 404, 'NOT_FOUND');
    const admin = await show(app, tokens.portal(people.admin), H.TICKET_ID(1));
    expectRefusal(admin, 404, 'NOT_FOUND');
    // The oversight read is audited before it is answered.
    expect(db.tables.hr_ess_audit).toEqual([
      expect.objectContaining({ action: 'helpdesk.ticket.read', actor_employee_id: people.hr.employee.id }),
    ]);
  });

  it('answers 404 for no such ticket and 400 for an id that is not one', async () => {
    const { app, people } = world({ setup: (w) => { H.seedCategories(w); w.tables.hr_ess_helpdesk_tickets = []; } });
    expectRefusal(await show(app, tokens.portal(people.faculty), H.TICKET_ID(9)), 404, 'NOT_FOUND');
    expectInvalid(await show(app, tokens.portal(people.faculty), 'not-an-id'), MESSAGES.INVALID_ID);
  });

  it('refuses the read when the audit row cannot be written, and answers 503s', async () => {
    quietErrors();
    const { app, people, db } = world({ setup: (w) => {
      H.seedCategories(w);
      w.tables.hr_ess_helpdesk_tickets = [
        H.ticketRow(w.people.faculty.employee.id, 1, { category_id: H.CAT('grievance') }),
      ];
    } });
    db.outage = 'error';
    expectRefusal(await show(app, tokens.portal(people.hr), H.TICKET_ID(1)), 503, 'UNAVAILABLE');
  });
});

describe('POST /api/ess/helpdesk/tickets/{id}/comments', () => {
  it('takes a comment from the raiser and from the team, and stamps the first response', async () => {
    const { app, people, db } = world({ setup: (w) => {
      H.seedCategories(w);
      w.tables.hr_ess_helpdesk_tickets = [H.ticketRow(w.people.faculty.employee.id, 1)];
    } });
    const fromRaiser = await act(app, tokens.portal(people.faculty), H.TICKET_ID(1), 'comments', { body: 'Any update on this?' });
    expect(fromRaiser.status).toBe(201);
    expect(fromRaiser.body.message).toMatchObject({ kind: 'comment', body: 'Any update on this?', author: { full_name: 'Test CAD Faculty' } });
    // The team's first act is the first response (G3).
    const fromAgent = await act(app, tokens.portal(people.admin), H.TICKET_ID(1), 'comments', { body: 'Looking at the switch now.' });
    expect(fromAgent.status).toBe(201);
    const saved = db.tables.hr_ess_helpdesk_tickets.find((t) => t.id === H.TICKET_ID(1));
    expect(saved.first_response_at).toBeTruthy();
    // The other side hears about it.
    expect(db.tables.hr_ess_notifications.filter((n) => n.category === 'helpdesk')).toHaveLength(1);
  });

  it('refuses an empty comment, a reader who cannot act, and one who cannot see it', async () => {
    const { app, people } = world({ setup: (w) => {
      H.seedCategories(w);
      w.tables.hr_ess_helpdesk_tickets = [
        H.ticketRow(w.people.faculty.employee.id, 1),
        H.ticketRow(w.people.hr.employee.id, 2, { category_id: H.CAT('grievance') }),
      ];
    } });
    const token = tokens.portal(people.faculty);
    expectInvalid(await act(app, token, H.TICKET_ID(1), 'comments', { body: ' ' }), MESSAGES.HELPDESK_COMMENT_BODY);
    // HR's oversight sees the ticket but may not act on it (G5).
    expectRefusal(await act(app, tokens.portal(people.ceo), H.TICKET_ID(1), 'comments', { body: 'Noted.' }), 403, 'HELPDESK_AGENT_ONLY');
    // A stranger cannot even see the confidential one (G4).
    expectRefusal(await act(app, tokens.portal(people.admin), H.TICKET_ID(2), 'comments', { body: 'Hello.' }), 404, 'NOT_FOUND');
  });
});

describe('POST /api/ess/helpdesk/tickets/{id}/withdraw, /reopen, /close', () => {
  it('withdraws an open ticket, and only an open one', async () => {
    const { app, people, db } = world({ setup: (w) => {
      H.seedCategories(w);
      w.tables.hr_ess_helpdesk_tickets = [H.ticketRow(w.people.faculty.employee.id, 1)];
    } });
    const res = await act(app, tokens.portal(people.faculty), H.TICKET_ID(1), 'withdraw');
    expect(res.status).toBe(200);
    expect(res.body.ticket.status).toBe('withdrawn');
    expect(db.tables.hr_ess_helpdesk_messages.at(-1)).toMatchObject({ kind: 'event', event: 'withdrawn' });
    const again = await act(app, tokens.portal(people.faculty), H.TICKET_ID(1), 'withdraw');
    expectRefusal(again, 409, 'HELPDESK_NOT_OPEN');
  });

  it('closes with a reason and an optional rating, and refuses a rating that is not one', async () => {
    const { app, people, db } = world({ setup: (w) => {
      H.seedCategories(w);
      w.tables.hr_ess_helpdesk_tickets = [H.ticketRow(w.people.faculty.employee.id, 1, { status: 'in_progress' })];
    } });
    const token = tokens.portal(people.faculty);
    // The refusals of the form, before anything is closed.
    expectInvalid(await act(app, token, H.TICKET_ID(1), 'close', { closing_reason: 'ok' }), MESSAGES.HELPDESK_CLOSE_REASON);
    expectInvalid(await act(app, token, H.TICKET_ID(1), 'close', { closing_reason: 'Fine now.', rating: 6 }), MESSAGES.HELPDESK_RATING);
    const noRating = await act(app, tokens.portal(people.faculty), H.TICKET_ID(1), 'close', { closing_reason: 'Sorted it myself at the lab.' });
    expect(noRating.status).toBe(200);
    expect(noRating.body.ticket).toMatchObject({ status: 'closed', rating: null, closing_reason: 'Sorted it myself at the lab.' });
    expect(db.tables.hr_ess_helpdesk_messages.at(-1)).toMatchObject({ kind: 'event', event: 'closed' });
    // A second close cannot move a closed ticket.
    expectRefusal(await act(app, tokens.portal(people.faculty), H.TICKET_ID(1), 'close', { closing_reason: 'Again.' }), 409, 'HELPDESK_TRANSITION');
  });

  it('reopens a settled ticket inside the window, and refuses one outside it', async () => {
    const { app, people, db } = world({ setup: (w) => {
      H.seedCategories(w);
      w.tables.hr_ess_helpdesk_tickets = [
        H.ticketRow(w.people.faculty.employee.id, 1, {
          status: 'closed', resolved_at: '2026-10-15T05:00:00+00:00', closed_at: '2026-10-16T01:00:00+00:00',
          closed_by_employee_id: w.people.faculty.employee.id, closing_reason: 'Sorted it myself.', rating: 4,
        }),
        H.ticketRow(w.people.faculty.employee.id, 2, {
          status: 'closed', resolved_at: '2026-10-01T05:00:00+00:00', closed_at: '2026-10-01T06:00:00+00:00',
          closing_reason: 'Long settled.', created_at: '2026-10-01T05:00:00+00:00',
        }),
      ];
    } });
    const res = await act(app, tokens.portal(people.faculty), H.TICKET_ID(1), 'reopen');
    expect(res.status).toBe(200);
    expect(res.body.ticket).toMatchObject({ status: 'open', rating: null, closed_at: null, reopened_at: expect.any(String) });
    // The deadlines are worked out again from now (G2).
    const now = new Date('2026-10-16T06:30:00.000Z');
    const dues = dueTimes(now, HELPDESK_CATEGORIES[0], []);
    expect(res.body.ticket.first_response_due_at).toBe(dues.first_response_due_at.toISOString());
    expect(db.tables.hr_ess_helpdesk_messages.at(-1)).toMatchObject({ kind: 'event', event: 'reopened' });
    expectRefusal(await act(app, tokens.portal(people.faculty), H.TICKET_ID(2), 'reopen'), 409, 'HELPDESK_REOPEN_WINDOW');
    // An open ticket is not a settled one.
    const raised = await raise(app, tokens.portal(people.faculty), raiseBody());
    expectRefusal(await act(app, tokens.portal(people.faculty), raised.body.ticket.id, 'reopen'), 409, 'HELPDESK_NOT_CLOSED');
  });

  it('lets only the raiser withdraw, reopen and close', async () => {
    const { app, people } = world({ setup: (w) => {
      H.seedCategories(w);
      w.tables.hr_ess_helpdesk_tickets = [H.ticketRow(w.people.faculty.employee.id, 1, { status: 'in_progress' })];
    } });
    // The team can see the ticket but may not close it for the raiser.
    expectRefusal(await act(app, tokens.portal(people.admin), H.TICKET_ID(1), 'close', { closing_reason: 'We fixed it.' }), 403, 'HELPDESK_AGENT_ONLY');
    expectRefusal(await act(app, tokens.portal(people.admin), H.TICKET_ID(1), 'withdraw'), 403, 'HELPDESK_AGENT_ONLY');
  });
});

describe('POST /api/ess/helpdesk/tickets/{id}/claim and /status', () => {
  it('claims an open ticket, moves it to in progress, and stamps the first response', async () => {
    const { app, people, db } = world({ setup: (w) => {
      H.seedCategories(w);
      w.tables.hr_ess_helpdesk_tickets = [H.ticketRow(w.people.faculty.employee.id, 1)];
    } });
    const res = await act(app, tokens.portal(people.admin), H.TICKET_ID(1), 'claim');
    expect(res.status).toBe(200);
    expect(res.body.ticket).toMatchObject({ status: 'in_progress', assignee: { full_name: 'Test Branch Admin' } });
    const saved = db.tables.hr_ess_helpdesk_tickets.find((t) => t.id === H.TICKET_ID(1));
    expect(saved.assignee_id).toBe(people.admin.employee.id);
    expect(saved.first_response_at).toBeTruthy();
    expect(db.tables.hr_ess_helpdesk_messages.at(-1)).toMatchObject({ kind: 'event', event: 'claimed' });
    expect(db.tables.hr_ess_notifications.at(-1)).toMatchObject({ category: 'helpdesk', title: 'HD-0001 claimed' });
    // The same person claiming again is the same claim.
    expect((await act(app, tokens.portal(people.admin), H.TICKET_ID(1), 'claim')).status).toBe(200);
  });

  it('refuses a claim on somebody else\'s ticket, a settled one, and by a reader who cannot act', async () => {
    const { app, people } = world({ setup: (w) => {
      H.seedCategories(w);
      w.tables.hr_ess_helpdesk_tickets = [
        H.ticketRow(w.people.faculty.employee.id, 1, { assignee_id: w.people.admin_manager.employee.id, claimed_at: H.AT, status: 'in_progress' }),
        H.ticketRow(w.people.faculty.employee.id, 2, { status: 'resolved', resolved_at: H.AT }),
      ];
    } });
    expectRefusal(await act(app, tokens.portal(people.admin), H.TICKET_ID(1), 'claim'), 409, 'HELPDESK_ALREADY_CLAIMED');
    expectRefusal(await act(app, tokens.portal(people.admin), H.TICKET_ID(2), 'claim'), 409, 'HELPDESK_NOT_LIVE');
    // HR's oversight reads the ticket but is not the team (G5).
    expectRefusal(await act(app, tokens.portal(people.hr), H.TICKET_ID(1), 'claim'), 403, 'HELPDESK_AGENT_ONLY');
  });

  it('moves a ticket through the lifecycle, and holds only where the category allows', async () => {
    const { app, people, db } = world({ setup: (w) => {
      H.seedCategories(w);
      w.tables.hr_ess_helpdesk_tickets = [
        H.ticketRow(w.people.faculty.employee.id, 1),
        H.ticketRow(w.people.faculty.employee.id, 2, { category_id: H.CAT('payroll'), priority: 'high' }),
      ];
    } });
    const hold = await act(app, tokens.portal(people.admin), H.TICKET_ID(1), 'status', { status: 'on_hold' });
    expect(hold.status).toBe(200);
    expect(hold.body.ticket.status).toBe('on_hold');
    expect(db.tables.hr_ess_helpdesk_messages.at(-1)).toMatchObject({ event: 'status_changed', details: { from: 'open', to: 'on_hold' } });
    expect(db.tables.hr_ess_notifications.at(-1)).toMatchObject({ category: 'helpdesk', title: 'HD-0001 is on hold' });
    // Payroll cannot be held (G2), and paperwork does not allow it.
    expectInvalid(await act(app, tokens.portal(people.accounts_admin), H.TICKET_ID(2), 'status', { status: 'on_hold' }), MESSAGES.HELPDESK_HOLD);
    // A live ticket resolves, with the stamp.
    const resolved = await act(app, tokens.portal(people.admin), H.TICKET_ID(1), 'status', { status: 'resolved' });
    expect(resolved.body.ticket.status).toBe('resolved');
    const saved = db.tables.hr_ess_helpdesk_tickets.find((t) => t.id === H.TICKET_ID(1));
    expect(saved.resolved_at).toBeTruthy();
    // An open payroll ticket resolves, then cannot go back: only the raiser closes it.
    const payrollResolved = await act(app, tokens.portal(people.accounts_admin), H.TICKET_ID(2), 'status', { status: 'resolved' });
    expect(payrollResolved.status).toBe(200);
    expectRefusal(await act(app, tokens.portal(people.accounts_admin), H.TICKET_ID(2), 'status', { status: 'in_progress' }), 409, 'HELPDESK_TRANSITION');
    expectInvalid(await act(app, tokens.portal(people.accounts_admin), H.TICKET_ID(2), 'status', { status: 'closed' }), MESSAGES.HELPDESK_STATUS);
  });

  it('refuses a move by somebody who cannot act, and answers 503s', async () => {
    quietErrors();
    const { app, people, db } = world({ setup: (w) => {
      H.seedCategories(w);
      w.tables.hr_ess_helpdesk_tickets = [H.ticketRow(w.people.faculty.employee.id, 1)];
    } });
    expectRefusal(await act(app, tokens.portal(people.ceo), H.TICKET_ID(1), 'status', { status: 'in_progress' }), 403, 'HELPDESK_AGENT_ONLY');
    db.dropTable('hr_ess_helpdesk_messages');
    expectRefusal(await act(app, tokens.portal(people.admin), H.TICKET_ID(1), 'claim'), 503, 'MODULE_NOT_INSTALLED');
  });
});
