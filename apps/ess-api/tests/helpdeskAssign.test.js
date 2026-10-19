const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { MESSAGES } = require('../src/lib/errors');
const { expectRefusal, expectInvalid, quietErrors } = require('./helpers/expect');
const H = require('./helpers/helpdeskFixtures');

/** Phase 2C (KP 5): the team hands a ticket to a named handler — assign, reassign, refusals. */

const TICKETS = '/api/ess/helpdesk/tickets';

const act = (app, token, id, what, body = {}) => request(app).post(`${TICKETS}/${id}/${what}`).set(bearer(token)).send(body);
const assign = (app, token, id, body) => act(app, token, id, 'assign', body);

const assignBody = (employeeId, change = {}) => ({ employee_id: employeeId, ...change });

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

/** A live it_lab ticket raised by the faculty, the team's own category. */
const withTicket = (change = {}) => (w) => {
  w.tables.hr_ess_helpdesk_tickets = [H.ticketRow(w.people.faculty.employee.id, 1, change)];
};

describe('POST /api/ess/helpdesk/tickets/{id}/assign', () => {
  it('assigns a named handler, with the history row, the thread event and the first response', async () => {
    const { app, people, db } = world({ setup: withTicket() });
    const res = await assign(app, tokens.portal(people.admin), H.TICKET_ID(1),
      assignBody(people.admin_manager.employee.id, { note: 'Rekha has the spares.' }));
    expect(res.status).toBe(200);
    expect(res.body.ticket).toMatchObject({
      status: 'in_progress', assignee: { id: people.admin_manager.employee.id, full_name: 'Test Admin Manager' },
    });
    // The ticket keeps no assigned_by fields: the thread event and the history carry it.
    expect(JSON.stringify(res.body)).not.toContain('assigned_by');
    const saved = db.tables.hr_ess_helpdesk_tickets.find((t) => t.id === H.TICKET_ID(1));
    expect(saved).toMatchObject({
      assignee_id: people.admin_manager.employee.id,
      claimed_at: expect.any(String),
      first_response_at: expect.any(String),
      assigned_by_employee_id: people.admin.employee.id,
      assigned_by_name: 'Test Branch Admin',
    });
    expect(db.tables.hr_ess_helpdesk_assignments).toEqual([
      expect.objectContaining({
        ticket_id: H.TICKET_ID(1), from_employee_id: null,
        to_employee_id: people.admin_manager.employee.id,
        assigned_by_user_id: people.admin.user.id,
        note: 'Rekha has the spares.',
      }),
    ]);
    expect(db.tables.hr_ess_helpdesk_messages.at(-1)).toMatchObject({
      kind: 'event', event: 'assigned', details: { employee_id: people.admin_manager.employee.id, from: null },
    });
    // The person it went to is told, not the raiser.
    expect(db.tables.hr_ess_notifications).toEqual([
      expect.objectContaining({
        employee_id: people.admin_manager.employee.id, category: 'helpdesk',
        title: 'HD-0001 assigned to you',
      }),
    ]);
  });

  it('reassigns without losing who had it first, and keeps the claim stamp', async () => {
    const { app, people, db } = world({ setup: withTicket() });
    await assign(app, tokens.portal(people.admin), H.TICKET_ID(1), assignBody(people.admin_manager.employee.id));
    const first = db.tables.hr_ess_helpdesk_tickets.find((t) => t.id === H.TICKET_ID(1));
    const res = await assign(app, tokens.portal(people.admin_manager), H.TICKET_ID(1),
      assignBody(people.admin.employee.id, { note: 'Handing it back to the desk.' }));
    expect(res.status).toBe(200);
    expect(res.body.ticket.assignee.id).toBe(people.admin.employee.id);
    expect(db.tables.hr_ess_helpdesk_assignments).toHaveLength(2);
    expect(db.tables.hr_ess_helpdesk_assignments[1]).toMatchObject({
      from_employee_id: people.admin_manager.employee.id, to_employee_id: people.admin.employee.id,
    });
    const saved = db.tables.hr_ess_helpdesk_tickets.find((t) => t.id === H.TICKET_ID(1));
    expect(saved.claimed_at).toBe(first.claimed_at);
    expect(saved.assigned_by_name).toBe('Test Admin Manager');
    expect(db.tables.hr_ess_helpdesk_messages.at(-1)).toMatchObject({
      event: 'assigned', details: { employee_id: people.admin.employee.id, from: people.admin_manager.employee.id },
    });
  });

  it('answers the same ticket when it is assigned to whoever already has it', async () => {
    const { app, people, db } = world({ setup: withTicket() });
    await assign(app, tokens.portal(people.admin), H.TICKET_ID(1), assignBody(people.admin_manager.employee.id));
    const rows = db.tables.hr_ess_helpdesk_assignments.length;
    const res = await assign(app, tokens.portal(people.admin), H.TICKET_ID(1),
      assignBody(people.admin_manager.employee.id));
    expect(res.status).toBe(200);
    expect(res.body.ticket.assignee.id).toBe(people.admin_manager.employee.id);
    expect(db.tables.hr_ess_helpdesk_assignments).toHaveLength(rows);
    expect(db.tables.hr_ess_helpdesk_messages).toHaveLength(1); // the one 'assigned' event, no second
  });

  it('refuses the raiser, an overseer, a settled ticket and a bad form', async () => {
    const { app, people } = world({ setup: (w) => {
      withTicket()(w);
      w.tables.hr_ess_helpdesk_tickets.push(H.ticketRow(w.people.faculty.employee.id, 2, { status: 'resolved', resolved_at: H.AT }));
    } });
    const token = tokens.portal(people.faculty);
    // The raiser is not the team, even on their own ticket.
    expectRefusal(await assign(app, token, H.TICKET_ID(1),
      assignBody(people.admin_manager.employee.id)), 403, 'HELPDESK_AGENT_ONLY');
    // HR's oversight sees the ticket but may not assign it.
    expectRefusal(await assign(app, tokens.portal(people.hr), H.TICKET_ID(1),
      assignBody(people.admin_manager.employee.id)), 403, 'HELPDESK_AGENT_ONLY');
    // A settled ticket cannot be handed on.
    expectRefusal(await assign(app, tokens.portal(people.admin), H.TICKET_ID(2),
      assignBody(people.admin_manager.employee.id)), 409, 'HELPDESK_NOT_LIVE');
    // The form.
    expectInvalid(await assign(app, tokens.portal(people.admin), H.TICKET_ID(1),
      assignBody('not-an-id')), MESSAGES.HELPDESK_ASSIGNEE);
    expectInvalid(await assign(app, tokens.portal(people.admin), H.TICKET_ID(1),
      { note: 'x' }), MESSAGES.HELPDESK_ASSIGNEE);
    expectInvalid(await assign(app, tokens.portal(people.admin), H.TICKET_ID(1),
      assignBody(people.admin_manager.employee.id, { note: 'n'.repeat(501) })), MESSAGES.HELPDESK_ASSIGN_NOTE);
    expectInvalid(await assign(app, tokens.portal(people.admin), H.TICKET_ID(1),
      assignBody(people.admin_manager.employee.id, { note: 5 })), MESSAGES.HELPDESK_ASSIGN_NOTE);
  });

  it('refuses an assignee who does not hold the category\'s queue role, through their login', async () => {
    const { app, people } = world({ setup: withTicket() });
    // A faculty login is not the lab team, whatever their HR record says.
    expectInvalid(await assign(app, tokens.portal(people.admin), H.TICKET_ID(1),
      assignBody(people.faculty.employee.id)), MESSAGES.HELPDESK_ASSIGNEE_ROLE);
    // Staff with no login at all have no role to check.
    expectInvalid(await assign(app, tokens.portal(people.admin), H.TICKET_ID(1),
      assignBody(people.attendance.employee.id)), MESSAGES.HELPDESK_ASSIGNEE_ROLE);
  });

  it('tells an unknown assignee and a leaver the same 404, and answers 503s', async () => {
    quietErrors();
    const { app, people, db } = world({ setup: withTicket() });
    expectRefusal(await assign(app, tokens.portal(people.admin), H.TICKET_ID(1),
      assignBody(H.uuid('ee', 9))), 404, 'NOT_FOUND');
    // A leaver is the same: there is nobody to hand it to.
    const link = db.tables.hr_employees.find((e) => e.id === people.hod.employee.id);
    link.is_archived = true;
    expectRefusal(await assign(app, tokens.portal(people.admin), H.TICKET_ID(1),
      assignBody(people.hod.employee.id)), 404, 'NOT_FOUND');
    db.dropTable('hr_ess_helpdesk_assignments');
    expectRefusal(await assign(app, tokens.portal(people.admin), H.TICKET_ID(1),
      assignBody(people.admin_manager.employee.id)), 503, 'MODULE_NOT_INSTALLED');
  });
});
