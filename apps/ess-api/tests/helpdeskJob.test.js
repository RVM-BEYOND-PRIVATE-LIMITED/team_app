const { buildApp } = require('./helpers/app');
const { startHelpdeskJob } = require('../src/jobs/helpdesk');
const { quietErrors } = require('./helpers/expect');
const H = require('./helpers/helpdeskFixtures');

/** Phase 2B, task G3: the hourly escalation job — three stages, each once. */

const NOW = new Date('2026-10-16T06:30:00.000Z');

const job = (world) => startHelpdeskJob({
  store: world.store,
  now: () => NOW,
  log: { log: () => {}, error: () => {} },
  immediate: false,
  intervalMs: 60 * 60 * 1000,
});

describe('the Helpdesk job: escalations', () => {
  it('tells the queue roles when a first response is overdue, once', async () => {
    const world = buildApp({ setup: (w) => {
      H.seedCategories(w);
      w.tables.hr_ess_helpdesk_tickets = [
        // Past its first-response deadline since Thursday morning; nobody has answered.
        H.ticketRow(w.people.faculty.employee.id, 1, {
          created_at: '2026-10-15T03:00:00+00:00', first_response_due_at: '2026-10-15T03:30:00+00:00',
          resolution_due_at: '2026-10-20T09:30:00+00:00',
        }),
        // Answered: nothing to escalate.
        H.ticketRow(w.people.faculty.employee.id, 2, {
          created_at: '2026-10-15T03:00:00+00:00', first_response_due_at: '2026-10-15T03:30:00+00:00',
          resolution_due_at: '2026-10-20T09:30:00+00:00', first_response_at: '2026-10-15T04:00:00+00:00',
        }),
      ];
    } });
    const out = await job(world).runOnce();
    expect(out.escalated).toBe(1);
    const told = world.db.tables.hr_ess_notifications.filter((n) => n.category === 'helpdesk');
    expect(told.map((n) => n.employee_id).sort()).toEqual([world.people.admin.employee.id, world.people.admin_manager.employee.id].sort());
    expect(told[0]).toMatchObject({ title: 'HD-0001 needs a first response' });
    const row = world.db.tables.hr_ess_helpdesk_tickets.find((t) => t.ref === 'HD-0001');
    expect(row.escalation_level).toBe(1);
    // A second run changes nothing: the stage was told once.
    const again = await job(world).runOnce();
    expect(again.escalated).toBe(0);
    expect(world.db.tables.hr_ess_notifications).toHaveLength(2);
  });

  it('tells the HoO past the resolution deadline, and the CEO a full span past it', async () => {
    quietErrors();
    const world = buildApp({ setup: (w) => {
      H.seedCategories(w);
      w.tables.hr_ess_helpdesk_tickets = [
        // Answered, but unresolved: past the resolution deadline, and past a full resolution
        // span past it (48 working hours from Monday the 12th runs out on Thursday the 15th).
        H.ticketRow(w.people.faculty.employee.id, 1, {
          created_at: '2026-10-12T04:00:00+00:00', first_response_at: '2026-10-12T05:00:00+00:00',
          first_response_due_at: '2026-10-13T06:00:00+00:00', resolution_due_at: '2026-10-08T09:30:00+00:00',
        }),
      ];
    } });
    const out = await job(world).runOnce();
    expect(out.escalated).toBe(2);
    const told = world.db.tables.hr_ess_notifications;
    expect(told.filter((n) => n.employee_id === world.people.hoo.employee.id)).toHaveLength(1);
    expect(told.filter((n) => n.employee_id === world.people.ceo.employee.id)).toHaveLength(1);
    expect(told.find((n) => n.title === 'HD-0001 is overdue')).toBeTruthy();
    expect(told.find((n) => n.title === 'HD-0001 needs you')).toBeTruthy();
    const row = world.db.tables.hr_ess_helpdesk_tickets[0];
    expect(row.escalation_level).toBe(3);
  });

  it('walks only the tickets still being worked, and only one stage a stamp', async () => {
    const world = buildApp({ setup: (w) => {
      H.seedCategories(w);
      w.tables.hr_ess_helpdesk_tickets = [
        H.ticketRow(w.people.faculty.employee.id, 1, { status: 'resolved', resolved_at: H.AT }),
        H.ticketRow(w.people.faculty.employee.id, 2, { status: 'closed', closed_at: H.AT, closing_reason: 'Sorted.' }),
        H.ticketRow(w.people.faculty.employee.id, 3, { status: 'withdrawn' }),
        // Already told about the first response: the next stage is not due yet.
        H.ticketRow(w.people.faculty.employee.id, 4, {
          created_at: '2026-10-15T03:00:00+00:00', first_response_due_at: '2026-10-15T03:30:00+00:00',
          resolution_due_at: '2026-10-20T09:30:00+00:00', escalation_level: 1,
        }),
      ];
    } });
    const out = await job(world).runOnce();
    expect(out.escalated).toBe(0);
    expect(world.db.rows('hr_ess_notifications')).toEqual([]);
  });
});
