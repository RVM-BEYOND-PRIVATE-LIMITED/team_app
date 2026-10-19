const { buildApp } = require('./helpers/app');
const { startDocumentsJob } = require('../src/jobs/documents');
const { quietErrors } = require('./helpers/expect');
const D = require('./helpers/documentsFixtures');

/** Phase 2C (KP 1): the weekly missing-documents reminder — who is told, and who is not. */

const NOW = new Date('2026-10-16T06:30:00.000Z');

const job = (world) => startDocumentsJob({
  store: world.store,
  now: () => NOW,
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

  it('does not remind the same person twice in one run, and a second run reminds them again', async () => {
    const world2 = world();
    const first = await job(world2).runOnce();
    const afterFirst = world2.db.tables.hr_ess_notifications.length;
    expect(first.reminded).toBe(afterFirst);
    // A second run inside the same process is the same walk: the job has no memory on purpose
    // (a weekly timer never runs twice), so a run is one reminder per person, always.
    const second = await job(world2).runOnce();
    expect(second.reminded).toBe(world2.db.tables.hr_ess_notifications.length - afterFirst);
    expect(world2.db.tables.hr_ess_notifications.filter((n) => n.employee_id === world2.people.faculty.employee.id))
      .toHaveLength(2);
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
