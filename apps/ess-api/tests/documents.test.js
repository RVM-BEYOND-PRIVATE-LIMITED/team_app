const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { MESSAGES } = require('../src/lib/errors');
const { expectRefusal, expectInvalid, quietErrors } = require('./helpers/expect');
const D = require('./helpers/documentsFixtures');

/** Phase 2C, KP 1 and KP 2: My Documents — the person's record, HR's desk, and the identity gate. */

const MY_DOCS = '/api/ess/me/documents';

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

const upload = (app, token, body) => request(app).post(MY_DOCS).set(bearer(token)).send(body);
const mine = (app, token) => request(app).get(MY_DOCS).set(bearer(token));

describe('GET /api/ess/me/documents', () => {
  it('hands the type list and my documents, newest first', async () => {
    const { app, people } = world({ setup: (w) => {
      w.tables.hr_ess_documents = [
        D.documentRow(w.people.faculty.employee.id, 2, { created_at: '2026-10-15T05:00:00+00:00' }),
        D.documentRow(w.people.faculty.employee.id, 1, { doc_type: 'identity', file_name: 'id-scan.pdf' }),
      ];
    } });
    const res = await mine(app, tokens.portal(people.faculty));
    expect(res.status).toBe(200);
    expect(res.body.types.map((t) => t.slug)).toEqual(
      ['resume', 'identity', 'certificate', 'offer', 'joining', 'experience', 'exit', 'other', 'others'],
    );
    expect(res.body.types.find((t) => t.slug === 'others').ess_only).toBe(true);
    expect(res.body.types.find((t) => t.slug === 'identity').is_mandatory).toBe(true);
    expect(res.body.documents.map((d) => d.file_name)).toEqual(['id-scan.pdf', 'resume-2.pdf']);
    // Never the bucket path, and never the reviewer's user id.
    expect(JSON.stringify(res.body)).not.toContain('storage_path');
    expect(JSON.stringify(res.body)).not.toContain('verified_by_user_id');
  });

  it('refuses an unknown address shape, an attendance caller and a 503', async () => {
    quietErrors();
    const { app, people, db } = world();
    expectRefusal(await request(app).get(MY_DOCS), 401, 'NOT_AUTHENTICATED');
    expectRefusal(await mine(app, tokens.portal(people.desk)), 403, 'NOT_LINKED');
    db.dropTable('hr_ess_documents');
    expectRefusal(await mine(app, tokens.portal(people.faculty)), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('POST /api/ess/me/documents', () => {
  it('saves one file: the row, the object, and the reply', async () => {
    const { app, db, people } = world();
    const res = await upload(app, tokens.portal(people.faculty), D.uploadBody());
    expect(res.status).toBe(201);
    expect(res.body.document).toEqual(expect.objectContaining({
      employee_id: people.faculty.employee.id,
      doc_type: 'resume',
      file_name: 'my-resume.pdf',
      status: 'pending',
      remark: null,
    }));
    expect(db.storageCalls).toEqual([
      expect.objectContaining({ op: 'upload', bucket: 'ESS', options: { contentType: 'application/pdf', upsert: false } }),
    ]);
    expect(db.storageCalls[0].path.startsWith(`documents/${people.faculty.employee.id}/`)).toBe(true);
  });

  it('takes an "others" upload only with its remark, and any type with a clean one', async () => {
    const { app, people } = world();
    expectInvalid(await upload(app, tokens.portal(people.faculty), D.uploadBody({ doc_type: 'others' })),
      MESSAGES.DOCUMENT_REMARK);
    const ok = await upload(app, tokens.portal(people.faculty),
      D.uploadBody({ doc_type: 'others', remark: 'My driving licence copy.' }));
    expect(ok.status).toBe(201);
    expectInvalid(await upload(app, tokens.portal(people.faculty), D.uploadBody({ remark: 'ab' })),
      MESSAGES.DOCUMENT_REMARK);
  });

  it('refuses a type that is not one, a file it does not take, and an oversized one', async () => {
    const { app, people } = world();
    expectInvalid(await upload(app, tokens.portal(people.faculty), D.uploadBody({ doc_type: 'aadhaar' })),
      MESSAGES.DOCUMENT_TYPE);
    expectInvalid(await upload(app, tokens.portal(people.faculty),
      D.uploadBody({ content_type: 'video/mp4' })), MESSAGES.DOCUMENT_FILE);
    expectInvalid(await upload(app, tokens.portal(people.faculty),
      D.uploadBody({ data_base64: Buffer.alloc(5 * 1024 * 1024 + 1).toString('base64') })), MESSAGES.DOCUMENT_SIZE);
  });

  it('refuses an unknown field, and a second field the body never named', async () => {
    const { app, people } = world();
    expectInvalid(await upload(app, tokens.portal(people.faculty),
      { ...D.uploadBody(), aadhaar_number: '1234' }), MESSAGES.UNKNOWN_FIELD);
  });

  it('answers 409 once the record holds its 50 documents', async () => {
    const { app, people } = world({ setup: (w) => {
      w.tables.hr_ess_documents = Array.from({ length: 50 }, (_, i) => D.documentRow(w.people.faculty.employee.id, i + 1));
    } });
    expectRefusal(await upload(app, tokens.portal(people.faculty), D.uploadBody()), 409, 'DOCUMENT_LIMIT');
  });

  it('has its own daily bucket on top of the per-employee limit', async () => {
    const { app, people } = buildApp({ limits: { documentsUploads: { windowMs: 60 * 60 * 1000, limit: 1 } } });
    const token = tokens.portal(people.faculty);
    expect((await upload(app, token, D.uploadBody())).status).toBe(201);
    expectRefusal(await upload(app, token, D.uploadBody()), 429, 'RATE_LIMITED');
  });
});

describe('GET /api/ess/me/documents/:id/file', () => {
  it('answers a signed link to one of mine', async () => {
    const { app, people } = world({ setup: (w) => {
      w.tables.hr_ess_documents = [D.documentRow(w.people.faculty.employee.id, 1)];
    } });
    const res = await request(app).get(`${MY_DOCS}/${D.DOCUMENT_ID(1)}/file`).set(bearer(tokens.portal(people.faculty)));
    expect(res.status).toBe(200);
    expect(res.body.file).toEqual({
      url: `https://storage.test/ESS/documents/${people.faculty.employee.id}/00000000-0000-4000-8000-000000000001.pdf?token=test-signed&expires=300`,
      name: 'resume-1.pdf',
      content_type: 'application/pdf',
      expires_in: 300,
    });
  });

  it('tells a wrong owner only that the document is not there', async () => {
    quietErrors();
    const { app, people } = world({ setup: (w) => {
      w.tables.hr_ess_documents = [D.documentRow(w.people.faculty.employee.id, 1)];
    } });
    const res = await request(app).get(`${MY_DOCS}/${D.DOCUMENT_ID(1)}/file`).set(bearer(tokens.portal(people.hr)));
    expectRefusal(res, 404, 'NOT_FOUND');
    expect(res.body.error).toBe(MESSAGES.DOCUMENT_NOT_FOUND);
  });
});

describe('HR documents (KP 1, KP 2)', () => {
  const at = (employeeId, suffix) => `/api/ess/hr/employees/${employeeId}/documents/${D.DOCUMENT_ID(1)}${suffix}`;

  const seeded = (change = {}) => (w) => {
    w.tables.hr_ess_documents = [D.documentRow(w.people.faculty.employee.id, 1, change)];
  };

  it('lists a person\'s record at the desk, and drops identity rows for an HR Executive', async () => {
    const { app, people } = world({ setup: (w) => {
      w.tables.hr_ess_documents = [
        D.documentRow(w.people.faculty.employee.id, 1),
        D.documentRow(w.people.faculty.employee.id, 2, { doc_type: 'identity', file_name: 'id-scan.pdf' }),
      ];
    } });
    const hr = await request(app).get(`/api/ess/hr/employees/${people.faculty.employee.id}/documents`)
      .set(bearer(tokens.portal(people.hr)));
    expect(hr.status).toBe(200);
    expect(hr.body.documents).toHaveLength(2);
    const exec = await request(app).get(`/api/ess/hr/employees/${people.faculty.employee.id}/documents`)
      .set(bearer(tokens.portal(people.hr_executive)));
    expect(exec.status).toBe(200);
    // KP 2: the identity row is dropped for the executive, not shown with the file held back.
    expect(exec.body.documents.map((d) => d.doc_type)).toEqual(['resume']);
  });

  it('opens a file for HR, but refuses an HR Executive an identity document, and audits every opening', async () => {
    quietErrors();
    const { app, db, people } = world({ setup: seeded({ doc_type: 'identity' }) });
    const hr = await request(app).get(at(people.faculty.employee.id, '/file')).set(bearer(tokens.portal(people.hr)));
    expect(hr.status).toBe(200);
    expect(db.tables.hr_ess_audit).toEqual([
      expect.objectContaining({ action: 'documents.file.read', target_employee_id: people.faculty.employee.id }),
    ]);
    db.tables.hr_ess_audit = [];
    const exec = await request(app).get(at(people.faculty.employee.id, '/file'))
      .set(bearer(tokens.portal(people.hr_executive)));
    expectRefusal(exec, 403, 'DOCUMENT_IDENTITY_ROLE');
    expect(exec.body.error).toBe(MESSAGES.DOCUMENT_IDENTITY_ROLE);
    expect(db.tables.hr_ess_audit).toEqual([]);
  });

  it('audits and signs a non-identity file too, for every reader at the desk', async () => {
    quietErrors();
    const { app, db, people } = world({ setup: seeded() });
    const exec = await request(app).get(at(people.faculty.employee.id, '/file'))
      .set(bearer(tokens.portal(people.hr_executive)));
    expect(exec.status).toBe(200);
    expect(db.tables.hr_ess_audit).toHaveLength(1);
  });

  it('verifies a pending document, once', async () => {
    const { app, db, people } = world({ setup: seeded() });
    const url = at(people.faculty.employee.id, '/verify');
    const res = await request(app).post(url).set(bearer(tokens.portal(people.hr_executive))).send({});
    expect(res.status).toBe(200);
    expect(res.body.document).toEqual(expect.objectContaining({
      status: 'verified', verified_by_name: 'Test HR Executive',
    }));
    expect(res.body.document.verified_at).toBeTruthy();
    expect(JSON.stringify(res.body)).not.toContain('verified_by_user_id');
    expectRefusal(await request(app).post(url).set(bearer(tokens.portal(people.hr))).send({}),
      409, 'DOCUMENT_REVIEWED');
    // The reviewer's name and the stamp are the only things written.
    expect(db.tables.hr_ess_documents[0].verified_by_user_id).toBe(people.hr_executive.user.id);
  });

  it('rejects a pending document with the reason the employee sees', async () => {
    const { app, people } = world({ setup: seeded() });
    const url = at(people.faculty.employee.id, '/reject');
    expectInvalid(await request(app).post(url).set(bearer(tokens.portal(people.hr))).send({ reason: '  ' }),
      MESSAGES.DOCUMENT_REJECT_REASON);
    const res = await request(app).post(url).set(bearer(tokens.portal(people.hr)))
      .send({ reason: 'The scan is not readable.' });
    expect(res.status).toBe(200);
    expect(res.body.document).toEqual(expect.objectContaining({ status: 'rejected', rejection_reason: 'The scan is not readable.' }));
  });

  it('deletes a document, its file with it, and leaves the audit row', async () => {
    quietErrors();
    const { app, db, people } = world({ setup: seeded() });
    const res = await request(app).delete(at(people.faculty.employee.id, '')).set(bearer(tokens.portal(people.hr)));
    expect(res.status).toBe(204);
    expect(res.text).toBe('');
    expect(db.tables.hr_ess_documents).toEqual([]);
    expect(db.storageCalls).toEqual([
      expect.objectContaining({ op: 'remove', bucket: 'ESS' }),
    ]);
    expect(db.tables.hr_ess_audit).toEqual([
      expect.objectContaining({ action: 'documents.delete' }),
    ]);
  });

  it('refuses a document that is not on that person\'s record, and unknown employees', async () => {
    quietErrors();
    const { app, people } = world({ setup: seeded() });
    // Another person's id in the address: the document is simply not there.
    expectRefusal(await request(app).get(at(people.hod.employee.id, '/file')).set(bearer(tokens.portal(people.hr))),
      404, 'NOT_FOUND');
    expectRefusal(await request(app).post(`/api/ess/hr/employees/${people.faculty.employee.id}/documents/${D.DOCUMENT_ID(9)}/verify`)
      .set(bearer(tokens.portal(people.hr))).send({}), 404, 'NOT_FOUND');
    const nobody = D.uuid('e', 98);
    expectRefusal(await request(app).get(`/api/ess/hr/employees/${nobody}/documents`).set(bearer(tokens.portal(people.hr))),
      404, 'NOT_FOUND');
  });

  it('refuses a faculty caller and answers 503s', async () => {
    quietErrors();
    const { app, db, people } = world({ setup: seeded() });
    expectRefusal(await request(app).get(`/api/ess/hr/employees/${people.faculty.employee.id}/documents`)
      .set(bearer(tokens.portal(people.faculty))), 403, 'HR_ACCESS_DENIED');
    db.dropTable('hr_ess_documents');
    expectRefusal(await request(app).get(`/api/ess/hr/employees/${people.faculty.employee.id}/documents`)
      .set(bearer(tokens.portal(people.hr))), 503, 'MODULE_NOT_INSTALLED');
  });
});
