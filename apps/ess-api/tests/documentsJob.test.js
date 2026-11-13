const { buildApp } = require('./helpers/app');
const { startDocumentsJob } = require('../src/jobs/documents');
const { quietErrors } = require('./helpers/expect');
const D = require('./helpers/documentsFixtures');

/** Phase 2C (KP 1): the weekly missing-documents reminder — who is told, and who is not. */

const NOW = new Date('2026-10-16T06:30:00.000Z');

const job = (world, now = NOW) => startDocumentsJob({
  store: world.store,
  now: () => now,
  log: { log: () => {}, error: () => {} },
  immediate: false,
  intervalMs: 7 * 24 * 60 * 60 * 1000,
});

/** A world with the document types seeded, as the migration leaves them. */
const world = (options = {}) => {
  const userSetup = options.setup;
  return buildApp({
    ...options,
    setup: (w) => {
      D.seedDocumentTypes(w);
      if (userSetup) userSetup(w);
    },
  });
};

describe('the documents job: the weekly reminder', () => {
  it('reminds the people missing a mandatory document, by name, in the documents category', async () => {
    const world2 = world();
    const out = await job(world2).runOnce();
    // Nobody in the fixture holds any document: everybody on strength is reminded, one row each.
    const told = world2.db.tables.hr_ess_notifications;
    expect(out.reminded).toBe(told.length);
    expect(told.length).toBeGreaterThan(1);
    expect(told.every((n) => n.category === 'documents')).toBe(true);
    expect(told[0]).toMatchObject({
      title: 'Documents missing',
      body: 'Your record is missing: Identity document, Offer letter, Joining letter. Upload them in My Documents.',
      data: {},
    });
    expect(new Set(told.map((n) => n.employee_id)).size).toBe(told.length);
  });

  it('skips whoever already holds each mandatory document, whatever its state', async () => {
    const world2 = world({ setup: (w) => {
      w.tables.hr_ess_documents = [
        // The faculty holds all three mandatory types (a pending one still counts as held).
        D.documentRow(w.people.faculty.employee.id, 1, { doc_type: 'identity' }),
        D.documentRow(w.people.faculty.employee.id, 2, { doc_type: 'offer', status: 'rejected', rejection_reason: 'Blurry.' }),
        D.documentRow(w.people.faculty.employee.id, 3, { doc_type: 'joining', status: 'verified', verified_at: D.AT }),
        // The HR manager holds one of the three: still reminded about the rest.
        D.documentRow(w.people.hr.employee.id, 4, { doc_type: 'offer' }),
      ];
    } });
    const out = await job(world2).runOnce();
    expect(out.reminded).toBe(world2.db.tables.hr_ess_notifications.length);
    const ids = world2.db.tables.hr_ess_notifications.map((n) => n.employee_id);
    expect(ids).not.toContain(world2.people.faculty.employee.id);
    expect(ids).toContain(world2.people.hr.employee.id);
  });

  it('does not remind the same person twice in one run, and a restart in the same week sends nothing', async () => {
    const world2 = world();
    const first = await job(world2).runOnce();
    const afterFirst = world2.db.tables.hr_ess_notifications.length;
    expect(first.reminded).toBe(afterFirst);
    expect(afterFirst).toBeGreaterThan(1);
    // The job now remembers each week (team_app #49): the boot run a deploy adds finds the
    // week's row and sends nothing, however many times the process starts.
    const second = await job(world2).runOnce();
    expect(second.reminded).toBe(0);
    expect(world2.db.tables.hr_ess_notifications).toHaveLength(afterFirst);
    expect(world2.db.tables.hr_ess_notifications.filter((n) => n.employee_id === world2.people.faculty.employee.id))
      .toHaveLength(1);
    expect(world2.db.tables.hr_ess_job_runs).toHaveLength(1);
    expect(world2.db.tables.hr_ess_job_runs[0]).toMatchObject({ job: 'documents_weekly', period_key: '2026-W42', status: 'done' });
  });

  it('a start in the next week sends the reminders again', async () => {
    const world2 = world();
    await job(world2).runOnce();
    const afterFirst = world2.db.tables.hr_ess_notifications.length;
    // The Friday after: the following ISO week, so the claim no longer holds this one.
    const nextWeek = new Date('2026-10-23T06:30:00.000Z');
    const second = await job(world2, nextWeek).runOnce();
    expect(second.reminded).toBe(afterFirst);
    expect(world2.db.tables.hr_ess_notifications).toHaveLength(afterFirst * 2);
    expect(world2.db.tables.hr_ess_job_runs).toHaveLength(2);
    expect(world2.db.tables.hr_ess_job_runs.map((r) => r.period_key)).toEqual(['2026-W42', '2026-W43']);
  });

  it('releases the week when the send fails, so the next start in the same week sends', async () => {
    // Everybody holds all three mandatory types except the faculty, so one send is the whole
    // week's work and its failure is the run's.
    const world2 = world({ setup: (w) => {
      const missing = w.people.faculty.employee.id;
      w.tables.hr_ess_documents = w.tables.hr_employees
        .filter((e) => e.id !== missing)
        .flatMap((e, i) => ['identity', 'offer', 'joining'].map((doc_type, j) => (
          D.documentRow(e.id, i * 3 + j + 1, { doc_type }))));
    } });
    const send = world2.store.createNotification;
    let first = true;
    world2.store.createNotification = async (row) => {
      if (first) {
        first = false;
        throw new Error('TEST database away');
      }
      return send(row);
    };
    const failed = await job(world2).runOnce();
    expect(failed.reminded).toBe(0);
    expect(world2.db.tables.hr_ess_notifications ?? []).toHaveLength(0);
    // No row is left behind, not even a failed one: the next start in the week may try again.
    expect(world2.db.tables.hr_ess_job_runs ?? []).toHaveLength(0);
    const again = await job(world2).runOnce();
    expect(again.reminded).toBe(1);
    expect(world2.db.tables.hr_ess_notifications).toHaveLength(1);
    expect(world2.db.tables.hr_ess_job_runs[0]).toMatchObject({ period_key: '2026-W42', status: 'done' });
  });

  it('follows the database flag: a type marked not mandatory stops being asked for', async () => {
    const world2 = world({ setup: (w) => {
      // HR has turned the offer letter off (KP can, with one UPDATE).
      w.tables.hr_ess_document_types = D.documentTypeRows().map((t) => (
        t.slug === 'offer' ? { ...t, is_mandatory: false } : t));
    } });
    const out = await job(world2).runOnce();
    expect(out.reminded).toBeGreaterThan(0);
    expect(world2.db.tables.hr_ess_notifications[0].body)
      .toBe('Your record is missing: Identity document, Joining letter. Upload them in My Documents.');
  });

  it('answers quietly when nothing is missing, and writes nothing when the reminders cannot', async () => {
    quietErrors();
    const full = world({ setup: (w) => {
      // Everybody on strength holds all three: nobody is reminded.
      w.tables.hr_ess_documents = w.tables.hr_employees.flatMap((e, i) => (
        ['identity', 'offer', 'joining'].map((doc_type, j) => D.documentRow(e.id, i * 3 + j + 1, { doc_type }))));
    } });
    const done = await job(full).runOnce();
    expect(done.reminded).toBe(0);
    expect(full.db.tables.hr_ess_notifications ?? []).toHaveLength(0);
    // The reminders are best effort: a table that will not take them fails nobody's run.
    const away = world();
    away.db.dropTable('hr_ess_notifications');
    const failed = await job(away).runOnce();
    expect(failed.reminded).toBe(0);
  });
});
