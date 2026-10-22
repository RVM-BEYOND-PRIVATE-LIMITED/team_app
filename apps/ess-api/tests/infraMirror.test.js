const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { istDay } = require('../src/lib/time');
const { startInfraJob } = require('../src/jobs/infra');
const H = require('./helpers/helpdeskFixtures');

/** G6 (Phase 2D): the Admin Manager's infra register mirror and its close-sync. */

const TICKETS = '/api/ess/helpdesk/tickets';
const raise = (app, token, body) => request(app).post(TICKETS).set(bearer(token)).send(body);
const act = (app, token, id, what, body = {}) => request(app).post(`${TICKETS}/${id}/${what}`).set(bearer(token)).send(body);

const body = (change = {}) => ({
  category: 'it_lab',
  subject: 'The lab PCs will not start.',
  body: 'Six machines in Lab 2 stay on the boot screen; the morning batch is waiting.',
  ...change,
});

const world = (setup) => buildApp({
  setup: (w) => {
    H.seedCategories(w);
    if (setup) setup(w);
  },
});

const runJob = async (w) => {
  const job = startInfraJob({
    store: w.store,
    now: () => new Date('2026-10-16T06:30:00Z'),
    immediate: false,
    intervalMs: 60 * 60 * 1000,
    log: { log: () => {}, error: () => {} },
  });
  try {
    return await job.runOnce();
  } finally {
    job.stop();
  }
};

describe('the infra register mirror at raise', () => {
  it('writes one A row for an IT/lab ticket, with the summary and the link', async () => {
    const w = world();
    const res = await raise(w.app, tokens.portal(w.people.faculty), body());
    expect(res.status).toBe(201);
    const infra = w.db.tables.infra_tickets;
    expect(infra).toHaveLength(1);
    expect(infra[0]).toMatchObject({
      location_id: 1, // Faridabad, by name
      audit_type: 'A',
      issue: `HD-0001: ${body().subject}`,
      owner: 'Test CAD Faculty',
      raised_by: w.people.faculty.user.id,
      status: 'open',
    });
    expect(infra[0].deadline).toBe(istDay(new Date(res.body.ticket.resolution_due_at)));
    expect(w.db.tables.hr_ess_infra_links).toEqual([
      expect.objectContaining({ ticket_id: res.body.ticket.id, infra_ticket_id: infra[0].id, state: 'linked' }),
    ]);

    const shown = await request(w.app).get(`${TICKETS}/${res.body.ticket.id}`).set(bearer(tokens.portal(w.people.faculty)));
    expect(shown.body.ticket.infra).toEqual({
      ticket_no: infra[0].ticket_no ?? null, status: 'open', closed_on: null,
    });
  });

  it('maps a facility ticket to D', async () => {
    const w = world();
    await raise(w.app, tokens.portal(w.people.faculty), body({ category: 'facility', subject: 'The AC in Lab 1 is dead.' }));
    expect(w.db.tables.infra_tickets[0]).toMatchObject({ audit_type: 'D' });
  });

  it('does not mirror payroll, HR documents, grievance or POSH', async () => {
    const w = world();
    for (const category of ['payroll', 'hr_documents', 'grievance', 'posh']) {
      const res = await raise(w.app, tokens.portal(w.people.faculty), body({ category }));
      expect(res.status).toBe(201);
    }
    expect(w.db.tables.infra_tickets ?? []).toEqual([]);
    expect(w.db.tables.hr_ess_infra_links ?? []).toEqual([]);
  });

  it("mirrors an anonymous ticket without the raiser's identity", async () => {
    const w = world();
    await raise(w.app, tokens.portal(w.people.faculty), body({ anonymous: true }));
    expect(w.db.tables.infra_tickets[0]).toMatchObject({ raised_by: null, owner: null });
  });

  it('keeps the ticket when the branch has no matching location, and retries it', async () => {
    const BRANCH = 'b1000000-0000-4000-8000-000000000001';
    const w = world((x) => {
      x.tables.hr_branches.push({ id: BRANCH, name: 'Mumbai', is_active: true });
      x.people.faculty.employee.branch_id = BRANCH;
    });
    const res = await raise(w.app, tokens.portal(w.people.faculty), body());
    expect(res.status).toBe(201);
    expect(w.db.tables.infra_tickets ?? []).toEqual([]);
    expect(w.db.tables.hr_ess_infra_links[0]).toMatchObject({ state: 'skipped', reason: 'branch_not_mapped' });

    // The data is fixed (the branch is renamed to a location the register knows), and the job runs.
    w.db.tables.hr_branches.find((b) => b.id === BRANCH).name = 'Pune';
    const out = await runJob(w);
    expect(out.linked).toBe(1);
    expect(w.db.tables.infra_tickets[0]).toMatchObject({ location_id: 2, audit_type: 'A' });
    expect(w.db.tables.hr_ess_infra_links[0]).toMatchObject({ state: 'linked' });
  });

  it('still raises the ticket when the register cannot be written', async () => {
    const w = world();
    w.db.dropTable('infra_tickets');
    const res = await raise(w.app, tokens.portal(w.people.faculty), body());
    expect(res.status).toBe(201);
    expect(w.db.tables.hr_ess_infra_links[0]).toMatchObject({ state: 'skipped', reason: 'mirror_failed' });
  });
});

describe('closing syncs both ways', () => {
  it('resolving the ticket closes its register row', async () => {
    const w = world();
    const res = await raise(w.app, tokens.portal(w.people.faculty), body());
    const id = res.body.ticket.id;
    // The team claims it and then resolves it.
    expect((await act(w.app, tokens.portal(w.people.admin), id, 'claim')).status).toBe(200);
    expect((await act(w.app, tokens.portal(w.people.admin), id, 'status', { status: 'resolved' })).status).toBe(200);
    expect(w.db.tables.infra_tickets[0]).toMatchObject({ status: 'closed', closed_on: '2026-10-16' });
  });

  it('logs and answers null when the link table is not there yet, rather than failing the process', async () => {
    const w = world();
    w.db.dropTable('hr_ess_infra_links');
    const out = await runJob(w);
    expect(out).toBeNull();
  });

  it('a register row closed by the Admin Manager resolves the ticket, once', async () => {
    const w = world();
    const res = await raise(w.app, tokens.portal(w.people.faculty), body());
    const id = res.body.ticket.id;
    w.db.tables.infra_tickets[0].status = 'closed';
    w.db.tables.infra_tickets[0].closed_on = '2026-10-16';

    const first = await runJob(w);
    expect(first.resolved).toBe(1);
    expect(w.db.tables.hr_ess_helpdesk_tickets.find((t) => t.id === id).status).toBe('resolved');
    expect(w.db.tables.hr_ess_helpdesk_messages.at(-1)).toMatchObject({
      ticket_id: id, kind: 'event', event: 'register_closed',
    });
    expect(w.db.tables.hr_ess_notifications.some((n) => n.employee_id === w.people.faculty.employee.id && n.category === 'helpdesk')).toBe(true);

    const second = await runJob(w);
    expect(second.resolved).toBe(0);
    expect(w.db.tables.hr_ess_helpdesk_messages.filter((m) => m.event === 'register_closed')).toHaveLength(1);
  });

  it('withdrawing the ticket closes its register row too', async () => {
    const w = world();
    const res = await raise(w.app, tokens.portal(w.people.faculty), body());
    expect((await act(w.app, tokens.portal(w.people.faculty), res.body.ticket.id, 'withdraw')).status).toBe(200);
    expect(w.db.tables.infra_tickets[0]).toMatchObject({ status: 'closed', closed_on: '2026-10-16' });
  });
});
