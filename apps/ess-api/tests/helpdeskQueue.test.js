const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { MESSAGES } = require('../src/lib/errors');
const { expectRefusal, expectInvalid, quietErrors } = require('./helpers/expect');
const H = require('./helpers/helpdeskFixtures');

/** Phase 2B, task G5: the team's queue — whose categories, whose tickets, whose names. */

const QUEUE = '/api/ess/helpdesk/queue';

const queue = (app, token, query = '') => request(app).get(`${QUEUE}${query}`).set(bearer(token));

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

describe('GET /api/ess/helpdesk/queue', () => {
  it('shows the categories the role serves, newest first, with the overdue minutes', async () => {
    const { app, people } = world({ setup: (w) => {
      w.tables.hr_ess_helpdesk_tickets = [
        // On time: no first response yet, but the deadline is ahead.
        H.ticketRow(w.people.faculty.employee.id, 1),
        // Past its first-response deadline since Thursday 10:00 IST: 450 + 180 working minutes.
        H.ticketRow(w.people.faculty.employee.id, 2, {
          created_at: '2026-10-15T05:00:00+00:00', first_response_due_at: '2026-10-15T04:30:00+00:00',
          resolution_due_at: '2026-10-20T09:30:00+00:00',
        }),
        // Another category's ticket: not the admins' queue.
        H.ticketRow(w.people.faculty.employee.id, 3, { category_id: H.CAT('payroll'), priority: 'high' }),
        // Settled: off the live queue, on the resolved filter.
        H.ticketRow(w.people.faculty.employee.id, 4, { status: 'resolved', resolved_at: H.AT }),
      ];
    } });
    const res = await queue(app, tokens.portal(people.admin));
    expect(res.status).toBe(200);
    expect(res.body.categories.map((c) => c.slug)).toEqual(['it_lab', 'facility']);
    expect(res.body.tickets.map((t) => t.ref)).toEqual(['HD-0001', 'HD-0002']);
    expect(res.body.tickets[0].overdue_minutes).toBeNull();
    expect(res.body.tickets[1].overdue_minutes).toBe(630);
  });

  it('holds to a status, to one of the caller\'s own categories, and refuses the rest', async () => {
    const { app, people } = world({ setup: (w) => {
      w.tables.hr_ess_helpdesk_tickets = [
        H.ticketRow(w.people.faculty.employee.id, 1),
        H.ticketRow(w.people.faculty.employee.id, 2, { status: 'resolved', resolved_at: H.AT }),
      ];
    } });
    const open = await queue(app, tokens.portal(people.admin), '?status=open');
    expect(open.body.tickets.map((t) => t.ref)).toEqual(['HD-0001']);
    const all = await queue(app, tokens.portal(people.admin), '?status=all');
    expect(all.body.tickets).toHaveLength(2);
    expectInvalid(await queue(app, tokens.portal(people.admin), '?status=withdrawn'), MESSAGES.HELPDESK_QUEUE_STATUS);
    const lab = await queue(app, tokens.portal(people.admin), '?category=it_lab&status=all');
    expect(lab.body.tickets).toHaveLength(2);
    expectInvalid(await queue(app, tokens.portal(people.admin), '?category=payroll'), MESSAGES.HELPDESK_CATEGORY);
  });

  it('serves each team its own categories, and the CEO an empty queue', async () => {
    const { app, people } = world({ setup: (w) => {
      w.tables.hr_ess_helpdesk_tickets = [
        H.ticketRow(w.people.faculty.employee.id, 1, { category_id: H.CAT('payroll') }),
        H.ticketRow(w.people.faculty.employee.id, 2, { category_id: H.CAT('hr_documents') }),
      ];
    } });
    const accounts = await queue(app, tokens.portal(people.accounts_admin));
    expect(accounts.body.tickets.map((t) => t.ref)).toEqual(['HD-0001']);
    const hr = await queue(app, tokens.portal(people.hr));
    expect(hr.body.tickets.map((t) => t.ref)).toEqual(['HD-0002']);
    // Exact membership (G5): the CEO inherits admin duties in the Scheduler, but no category
    // names him, so his queue is empty — not a refusal, just nothing to show.
    const ceo = await queue(app, tokens.portal(people.ceo));
    expect(ceo.status).toBe(200);
    expect(ceo.body.tickets).toEqual([]);
    expect(ceo.body.categories).toEqual([]);
  });

  it('hides an anonymous raiser from the team, and shows them to HR', async () => {
    const { app, people } = world({ setup: (w) => {
      w.tables.hr_ess_helpdesk_tickets = [
        H.ticketRow(w.people.faculty.employee.id, 1, { category_id: H.CAT('grievance'), anonymous: true, priority: 'high' }),
        H.ticketRow(w.people.faculty.employee.id, 2, { category_id: H.CAT('hr_documents'), anonymous: true }),
        H.ticketRow(w.people.faculty.employee.id, 3, { category_id: H.CAT('it_lab'), anonymous: true }),
      ];
    } });
    // HR is the grievance queue, and HR's own roles see an anonymous raiser's name (G4).
    const grievance = await queue(app, tokens.portal(people.hr), '?category=grievance');
    expect(grievance.body.tickets[0].raised_by.full_name).toBe('Test CAD Faculty');
    // The same in HR's own categories, for the HR Executive too.
    const named = await queue(app, tokens.portal(people.hr), '?category=hr_documents');
    expect(named.body.tickets[0].raised_by.full_name).toBe('Test CAD Faculty');
    const exec = await queue(app, tokens.portal(people.hr_executive), '?category=hr_documents');
    expect(exec.body.tickets[0].raised_by.full_name).toBe('Test CAD Faculty');
    // The admins' queue hides an anonymous raiser: they are not HR's own roles.
    const anonymousLab = await queue(app, tokens.portal(people.admin), '?category=it_lab&status=all');
    expect(anonymousLab.body.tickets.find((t) => t.ref === 'HD-0003')).toBeTruthy();
    expect(anonymousLab.body.tickets.find((t) => t.ref === 'HD-0003').raised_by).toBeNull();
    // The CEO has no grievance queue at all (G4); an unknown category to him is refused.
    const ceo = await queue(app, tokens.portal(people.ceo));
    expect(ceo.status).toBe(200);
    expect(ceo.body.tickets).toEqual([]);
  });

  it('refuses an attendance session with the portal refusal, and answers 503s', async () => {
    quietErrors();
    const { app, people, db } = world();
    expectRefusal(await queue(app, tokens.attendance(people.attendance)), 403, 'PORTAL_LOGIN_REQUIRED');
    db.dropTable('hr_ess_helpdesk_tickets');
    expectRefusal(await queue(app, tokens.portal(people.admin)), 503, 'MODULE_NOT_INSTALLED');
  });
});
