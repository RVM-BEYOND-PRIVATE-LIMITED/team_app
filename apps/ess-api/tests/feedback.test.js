const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { NOW } = require('./helpers/constants');
const { MESSAGES } = require('../src/lib/errors');
const { expectRefusal, expectInvalid, quietErrors, CALLERS, guardOutcome } = require('./helpers/expect');
const {
  PNG_BASE64, JPEG_BASE64, FEEDBACK_ID, CONTEXT, feedbackRow, withScreenshot, SEEDED,
} = require('./helpers/feedbackFixtures');

/** #151: in-app feedback, sent by anybody signed in and read by super admins only. */

const SEND = '/api/ess/feedback';
const LIST = '/api/ess/admin/feedback';
const SHOT = (id) => `/api/ess/admin/feedback/${id}/screenshot`;

const send = (app, token, body) => request(app).post(SEND).set(bearer(token)).send(body);
const list = (app, token, query = '') => request(app).get(`${LIST}${query}`).set(bearer(token));
const shot = (app, token, id) => request(app).get(SHOT(id)).set(bearer(token));

const NO_CONTEXT = {
  screen: null, app_version: null, build_number: null, platform: null, os_version: null, device_model: null,
};

describe('POST /api/ess/feedback', () => {
  it.each([
    ['a portal login', (p) => tokens.portal(p.faculty), 'faculty'],
    ['an attendance session', (p) => tokens.attendance(p.attendance), 'attendance'],
  ])('takes feedback from %s, as the caller, and answers a receipt only', async (_label, token, who) => {
    const { app, db, people } = buildApp();
    const res = await send(app, token(people), { kind: 'bug', message: '  The punch button stays grey.  ', context: CONTEXT });
    expect(res.status).toBe(201);
    expect(res.body).toEqual({
      feedback: { id: expect.any(String), kind: 'bug', has_screenshot: false, created_at: expect.any(String) },
    });
    expect(Date.parse(res.body.feedback.created_at)).toBe(NOW.getTime());
    const stored = db.tables.hr_ess_feedback;
    expect(stored).toHaveLength(1);
    expect(stored[0]).toMatchObject({
      employee_id: people[who].employee.id, kind: 'bug', message: 'The punch button stays grey.', ...CONTEXT, screenshot_path: null,
    });
    expect(db.storageCalls).toEqual([]);
  });

  it('stores no context when the app sends none, or sends null', async () => {
    const { app, db, people } = buildApp();
    expect((await send(app, tokens.portal(people.faculty), { kind: 'other', message: 'Just saying hello.' })).status).toBe(201);
    expect((await send(app, tokens.portal(people.faculty), { kind: 'other', message: 'Hello again.', context: null, screenshot: null })).status).toBe(201);
    for (const row of db.tables.hr_ess_feedback) expect(row).toMatchObject(NO_CONTEXT);
  });

  it('trims context and stores a blank field as null', async () => {
    const { app, db, people } = buildApp();
    await send(app, tokens.portal(people.faculty), { kind: 'bug', message: 'It froze on me.', context: { screen: ' /helpdesk ', platform: '   ' } });
    expect(db.tables.hr_ess_feedback[0]).toMatchObject({ ...NO_CONTEXT, screen: '/helpdesk' });
  });

  it('takes no employee id from the body, so nobody can send in somebody else\'s name', async () => {
    const { app, people } = buildApp();
    const res = await send(app, tokens.portal(people.faculty), { kind: 'bug', message: 'It froze on me.', employee_id: people.hr.employee.id });
    expectInvalid(res, MESSAGES.UNKNOWN_FIELD);
  });

  const png = (data = PNG_BASE64) => ({ content_type: 'image/png', data_base64: data });
  it.each([
    ['no kind', { message: 'It froze on me.' }, MESSAGES.FEEDBACK_KIND],
    ['another kind', { kind: 'praise', message: 'It froze on me.' }, MESSAGES.FEEDBACK_KIND],
    ['no message', { kind: 'bug' }, MESSAGES.FEEDBACK_MESSAGE],
    ['a message of spaces', { kind: 'bug', message: '        ' }, MESSAGES.FEEDBACK_MESSAGE],
    ['a message under 5 characters', { kind: 'bug', message: 'bad' }, MESSAGES.FEEDBACK_MESSAGE],
    ['a message over 2,000 characters', { kind: 'bug', message: 'x'.repeat(2001) }, MESSAGES.FEEDBACK_MESSAGE],
    ['a message that is not text', { kind: 'bug', message: 12345 }, MESSAGES.FEEDBACK_MESSAGE],
    ['a context that is a list', { kind: 'bug', message: 'It froze on me.', context: ['/home'] }, MESSAGES.FEEDBACK_CONTEXT],
    ['a context with an unknown key', { kind: 'bug', message: 'It froze on me.', context: { phone: '9876543210' } }, MESSAGES.FEEDBACK_CONTEXT],
    ['a context value that is not text', { kind: 'bug', message: 'It froze on me.', context: { build_number: 7 } }, MESSAGES.FEEDBACK_CONTEXT],
    ['a screen over 200 characters', { kind: 'bug', message: 'It froze on me.', context: { screen: `/${'x'.repeat(200)}` } }, MESSAGES.FEEDBACK_CONTEXT],
    ['a device model over 120 characters', { kind: 'bug', message: 'It froze on me.', context: { device_model: 'x'.repeat(121) } }, MESSAGES.FEEDBACK_CONTEXT],
    ['a screenshot that is text', { kind: 'bug', message: 'It froze on me.', screenshot: PNG_BASE64 }, MESSAGES.FEEDBACK_SCREENSHOT],
    ['a screenshot with an unknown key', { kind: 'bug', message: 'It froze on me.', screenshot: { ...png(), name: 'a.png' } }, MESSAGES.FEEDBACK_SCREENSHOT],
    ['a GIF', { kind: 'bug', message: 'It froze on me.', screenshot: { content_type: 'image/gif', data_base64: PNG_BASE64 } }, MESSAGES.FEEDBACK_SCREENSHOT],
    ['a screenshot that is not base64', { kind: 'bug', message: 'It froze on me.', screenshot: png('this is not base64 at all!') }, MESSAGES.FEEDBACK_SCREENSHOT],
    ['a JPEG sent as a PNG', { kind: 'bug', message: 'It froze on me.', screenshot: png(JPEG_BASE64) }, MESSAGES.FEEDBACK_SCREENSHOT],
    ['a PDF sent as a PNG', { kind: 'bug', message: 'It froze on me.', screenshot: png(Buffer.from('%PDF-1.7 a document that is no image').toString('base64')) }, MESSAGES.FEEDBACK_SCREENSHOT],
    ['a list for a body', [{ kind: 'bug' }], MESSAGES.BODY_NOT_OBJECT],
  ])('refuses %s with 400, and stores nothing', async (_label, body, message) => {
    const { app, db, people } = buildApp();
    expectInvalid(await send(app, tokens.portal(people.faculty), body), message);
    expect(db.tables.hr_ess_feedback || []).toEqual([]);
    expect(db.storageCalls).toEqual([]);
  });

  it('refuses a screenshot over 2 MB', async () => {
    const { app, people } = buildApp();
    const big = Buffer.concat([Buffer.from(PNG_BASE64, 'base64'), Buffer.alloc(2 * 1024 * 1024)]).toString('base64');
    expectInvalid(await send(app, tokens.portal(people.faculty), { kind: 'bug', message: 'It froze on me.', screenshot: { content_type: 'image/png', data_base64: big } }), MESSAGES.FEEDBACK_SCREENSHOT_SIZE);
  });

  it('counts 2,000 characters as characters, not UTF-16 units', async () => {
    const { app, people } = buildApp();
    expect((await send(app, tokens.portal(people.faculty), { kind: 'suggestion', message: '👍'.repeat(2000) })).status).toBe(201);
  });

  it.each([
    ['a PNG', 'image/png', PNG_BASE64, 'png'],
    ['a JPEG', 'image/jpeg', JPEG_BASE64, 'jpg'],
  ])('keeps %s in the ESS bucket under feedback/, and never answers its path', async (_label, contentType, data, ext) => {
    const { app, db, people } = buildApp();
    const res = await send(app, tokens.attendance(people.attendance), {
      kind: 'bug', message: 'Look at this screen.', screenshot: { content_type: contentType, data_base64: data },
    });
    expect(res.status).toBe(201);
    expect(res.body.feedback.has_screenshot).toBe(true);
    expect(JSON.stringify(res.body)).not.toContain('feedback/');

    const size = Buffer.from(data, 'base64').length;
    const [upload] = db.storageCalls;
    expect(db.storageCalls).toHaveLength(1);
    expect(upload).toMatchObject({ op: 'upload', bucket: 'ESS', size, options: { contentType, upsert: false } });
    expect(upload.path).toMatch(new RegExp(`^feedback/${people.attendance.employee.id}/[0-9a-f-]{36}\\.${ext}$`));
    expect(db.tables.hr_ess_feedback[0]).toMatchObject({ screenshot_path: upload.path, screenshot_content_type: contentType, screenshot_bytes: size });
  });

  it('removes the uploaded screenshot when the row cannot be written', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    db.dropTable('hr_ess_feedback');
    const res = await send(app, tokens.portal(people.faculty), { kind: 'bug', message: 'Look at this screen.', screenshot: { content_type: 'image/png', data_base64: PNG_BASE64 } });
    expectRefusal(res, 503, 'MODULE_NOT_INSTALLED');
    expect(db.storageCalls.map((c) => c.op)).toEqual(['upload', 'remove']);
    expect(db.storageCalls[1].paths).toEqual([db.storageCalls[0].path]);
  });

  it('answers 429 past 20 items a day, in its own words', async () => {
    const { app, people } = buildApp({ limits: { feedback: { windowMs: 24 * 60 * 60 * 1000, limit: 2 } } });
    const token = tokens.portal(people.faculty);
    for (let i = 0; i < 2; i++) expect((await send(app, token, { kind: 'bug', message: `Item number ${i}` })).status).toBe(201);
    const res = await send(app, token, { kind: 'bug', message: 'One too many.' });
    expect(res.status).toBe(429);
    expect(res.body.error).toBe(MESSAGES.FEEDBACK_LIMIT);
  });

  it('takes a body big enough for a 2 MB screenshot', async () => {
    const { app, people } = buildApp();
    const nearlyTwoMb = Buffer.concat([Buffer.from(PNG_BASE64, 'base64'), Buffer.alloc(2 * 1024 * 1024 - 100)]).toString('base64');
    const res = await send(app, tokens.portal(people.faculty), { kind: 'bug', message: 'A full-size screenshot.', screenshot: { content_type: 'image/png', data_base64: nearlyTwoMb } });
    expect(res.status).toBe(201);
  });
});

describe('GET /api/ess/admin/feedback', () => {
  it.each(CALLERS)('%s', async (who, token) => {
    const { app, people } = buildApp();
    const res = await list(app, token(people));
    const refusal = guardOutcome(who, ['super_admin'], 'FEEDBACK_ACCESS_DENIED');
    if (refusal) expectRefusal(res, 403, refusal);
    else expect(res.status).toBe(200);
  });

  it('refuses the CEO in its own words: the role is exact, nothing inherits it', async () => {
    const { app, people } = buildApp();
    const res = await list(app, tokens.portal(people.ceo));
    expectRefusal(res, 403, 'FEEDBACK_ACCESS_DENIED');
    expect(res.body.error).toBe(MESSAGES.FEEDBACK_ACCESS_DENIED);
  });

  it('lists everybody\'s feedback newest first, with who sent it and the context, never a bucket path', async () => {
    const { app, people } = buildApp({ setup: SEEDED });
    const res = await list(app, tokens.portal(people.super_admin));
    expect(res.status).toBe(200);
    const faculty = people.faculty.employee;
    expect(res.body).toEqual({
      feedback: [
        {
          id: FEEDBACK_ID(2), kind: 'bug', message: 'Feedback number 2.', context: NO_CONTEXT, has_screenshot: true,
          created_at: '2026-10-16T06:02:00+00:00',
          employee: { id: faculty.id, full_name: faculty.full_name, employee_code: faculty.employee_code ?? null },
        },
        {
          id: FEEDBACK_ID(1), kind: 'suggestion', message: 'Feedback number 1.', context: CONTEXT, has_screenshot: false,
          created_at: '2026-10-16T06:01:00+00:00',
          employee: { id: faculty.id, full_name: faculty.full_name, employee_code: faculty.employee_code ?? null },
        },
      ],
      next_before: null,
    });
    expect(JSON.stringify(res.body)).not.toContain('feedback/');
  });

  it('filters to one kind', async () => {
    const { app, people } = buildApp({ setup: SEEDED });
    const res = await list(app, tokens.portal(people.super_admin), '?kind=suggestion');
    expect(res.body.feedback.map((f) => f.id)).toEqual([FEEDBACK_ID(1)]);
    expect((await list(app, tokens.portal(people.super_admin), '?kind=all')).body.feedback).toHaveLength(2);
  });

  it('pages 100 at a time with ?before=<next_before>', async () => {
    const { app, people } = buildApp({
      setup: (w) => {
        const id = w.people.faculty.employee.id;
        w.tables.hr_ess_feedback = Array.from({ length: 101 }, (_, i) => feedbackRow(id, i + 1, {
          created_at: new Date(Date.UTC(2026, 9, 16, 6, 0, i)).toISOString().replace('.000Z', '+00:00'),
        }));
      },
    });
    const token = tokens.portal(people.super_admin);
    const first = await list(app, token);
    expect(first.body.feedback).toHaveLength(100);
    expect(first.body.feedback[0].id).toBe(FEEDBACK_ID(101));
    expect(first.body.next_before).toBe(first.body.feedback[99].created_at);
    const second = await list(app, token, `?before=${encodeURIComponent(first.body.next_before)}`);
    expect(second.body.feedback.map((f) => f.id)).toEqual([FEEDBACK_ID(1)]);
    expect(second.body.next_before).toBeNull();
  });

  it.each([
    ['an unknown kind', '?kind=praise', MESSAGES.FEEDBACK_KIND_FILTER],
    ['two kinds', '?kind=bug&kind=other', MESSAGES.FEEDBACK_KIND_FILTER],
    ['a before that is not a time', '?before=yesterday', MESSAGES.FEEDBACK_BEFORE],
    ['two befores', '?before=2026-10-16&before=2026-10-17', MESSAGES.FEEDBACK_BEFORE],
  ])('refuses %s with 400', async (_label, query, message) => {
    const { app, people } = buildApp();
    expectInvalid(await list(app, tokens.portal(people.super_admin), query), message);
  });
});

describe('GET /api/ess/admin/feedback/:id/screenshot', () => {
  it('answers a 300-second signed link, and audits the opening first', async () => {
    const { app, db, people } = buildApp({ setup: SEEDED });
    const res = await shot(app, tokens.portal(people.super_admin), FEEDBACK_ID(2));
    expect(res.status).toBe(200);
    const path = withScreenshot(people.faculty.employee.id).screenshot_path;
    expect(res.body).toEqual({
      file: {
        url: `https://storage.test/ESS/${path}?token=test-signed&expires=300`,
        name: `feedback-${FEEDBACK_ID(2)}.png`,
        content_type: 'image/png',
        expires_in: 300,
      },
    });
    const audit = db.tables.hr_ess_audit.filter((a) => a.action === 'feedback.screenshot_opened');
    expect(audit).toHaveLength(1);
    expect(audit[0]).toMatchObject({
      actor_employee_id: people.super_admin.employee.id,
      target_employee_id: people.faculty.employee.id,
      details: { feedback_id: FEEDBACK_ID(2) },
    });
  });

  it('refuses the link when the audit cannot be written', async () => {
    quietErrors();
    const { app, db, people } = buildApp({ setup: SEEDED });
    db.dropTable('hr_ess_audit');
    const res = await shot(app, tokens.portal(people.super_admin), FEEDBACK_ID(2));
    expect(res.status).toBe(503);
    expect(JSON.stringify(res.body)).not.toContain('storage.test');
  });

  it.each([
    ['an item with no screenshot', FEEDBACK_ID(1), MESSAGES.FEEDBACK_NO_SCREENSHOT],
    ['an item that does not exist', FEEDBACK_ID(9), MESSAGES.FEEDBACK_NOT_FOUND],
  ])('answers 404 for %s', async (_label, id, message) => {
    const { app, people } = buildApp({ setup: SEEDED });
    const res = await shot(app, tokens.portal(people.super_admin), id);
    expectRefusal(res, 404, 'NOT_FOUND');
    expect(res.body.error).toBe(message);
  });

  it.each(CALLERS)('%s', async (who, token) => {
    const { app, people } = buildApp({ setup: SEEDED });
    const res = await shot(app, token(people), FEEDBACK_ID(2));
    const refusal = guardOutcome(who, ['super_admin'], 'FEEDBACK_ACCESS_DENIED');
    if (refusal) expectRefusal(res, 403, refusal);
    else expect(res.status).toBe(200);
  });

  it('refuses an id that is not a UUID', async () => {
    const { app, people } = buildApp();
    expectInvalid(await shot(app, tokens.portal(people.super_admin), 'nope'), MESSAGES.INVALID_ID);
  });
});
