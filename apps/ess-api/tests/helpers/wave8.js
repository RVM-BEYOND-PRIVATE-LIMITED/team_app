const request = require('supertest');
const { buildApp, tokens, bearer } = require('./app');
const { call, get, post, put, del, shared } = require('./wave6a');
const { TICKET, SETTLED } = require('./wave7');
const H = require('./helpdeskFixtures');
const D = require('./documentsFixtures');

/**
 * Wave 8 (Phase 2C): My Documents, the profile-change requests, the bank details, the staff ID
 * card, and the Helpdesk's assign (KP 1 to KP 5, E3). One entry per documented status of every
 * route the phase adds. tests/contract.test.js merges it with the earlier waves: the routes
 * covered must be exactly the routes the app serves, and every documented status must be
 * provoked here.
 *
 * The scenarios run on the same in-memory app and the same fixtures as the other waves
 * (tests/helpers/app.js buildApp, tests/helpers/documentsFixtures.js), so a request here is the
 * real route, the real store and the real contract check.
 */

/** The fixture people's fixed employee ids: the faculty's record, the admin manager's, HR's. */
const FACULTY = H.uuid('e', 11);
const ADMIN_MANAGER = H.uuid('e', 6);

/** One person's documents, as the migration leaves them: a resume and an identity proof. */
const DOCS = (change = {}) => (w) => {
  D.seedDocumentTypes(w);
  w.tables.hr_ess_documents = [
    D.documentRow(FACULTY, 1, change),
    D.documentRow(FACULTY, 2, { doc_type: 'identity' }),
  ];
};

/** The full shelf: the 50 documents one person may hold, for the limit's refusal. */
const FULL_SHELF = (w) => {
  D.seedDocumentTypes(w);
  w.tables.hr_ess_documents = Array.from({ length: 50 }, (_, i) => D.documentRow(FACULTY, i + 1));
};

/** One open change request (E3), and one already answered. */
const OPEN_CR = (w) => { w.tables.hr_ess_change_requests = [D.changeRequestRow(FACULTY, 1)]; };
const DECIDED_CR = (w) => {
  w.tables.hr_ess_change_requests = [D.changeRequestRow(FACULTY, 1, {
    status: 'approved', decided_by_user_id: H.uuid('a', 9), decided_by_name: 'Test HR Manager',
    decided_at: D.AT, decision_note: 'Checked with the office.',
  })];
};

/** One saved bank-details row (KP 3). */
const BANK = (w) => { w.tables.hr_ess_bank_details = [D.bankRow(FACULTY)]; };

const changeBody = (change = {}) => ({
  field: 'address', new_value: 'House 14, Sector 22', reason: 'The record has the old house number.', ...change,
});
const bankBody = (change = {}) => ({
  bank_name: 'State Bank of India', branch_name: 'Faridabad Sector 21', account_number: '1234567890',
  ifsc_code: 'SBIN0001234', consent: true, consent_name: 'Test CAD Faculty', ...change,
});

/** The ticket address the assign scenarios repeat, and the assign body. */
const at = (suffix) => `/api/ess/helpdesk/tickets/${H.TICKET_ID(1)}${suffix || ''}`;
const assignBody = (employeeId, change = {}) => ({ employee_id: employeeId, ...change });

/** The verification link of the faculty's card, minted by their own read (KP, no sign-in). */
const mintLink = async (world) => {
  const card = await request(world.app).get('/api/ess/me/id-card').set(bearer(tokens.portal(world.people.faculty)));
  return card.body.card.verify_url.replace('/api/ess/id-card/verify/', '');
};
const verify = (app, token, world) => mintLink(world).then((link) => request(app).get(`/api/ess/id-card/verify/${link}`));

const WAVE_8 = {
  'GET /api/ess/me/documents': [
    ['200, my record', call('faculty', get('/api/ess/me/documents'), { setup: DOCS() })],
    ...shared('faculty', 'get', '/api/ess/me/documents', { table: 'hr_ess_documents', seed: D.seedDocumentTypes }),
  ],
  'POST /api/ess/me/documents': [
    ['201, a resume', call('faculty', post('/api/ess/me/documents', D.uploadBody()), { setup: D.seedDocumentTypes })],
    ['400 VALIDATION_FAILED, a type the list does not hold', call('faculty', post('/api/ess/me/documents', D.uploadBody({ doc_type: 'aadhaar' })), { setup: D.seedDocumentTypes })],
    ['400 VALIDATION_FAILED, others without a remark', call('faculty', post('/api/ess/me/documents', D.uploadBody({ doc_type: 'others' })), { setup: D.seedDocumentTypes })],
    ['409 DOCUMENT_LIMIT, the shelf is full', call('faculty', post('/api/ess/me/documents', D.uploadBody()), { setup: FULL_SHELF })],
    ...shared('faculty', 'post', '/api/ess/me/documents', { body: D.uploadBody(), table: 'hr_ess_documents', seed: D.seedDocumentTypes }),
  ],
  'GET /api/ess/me/documents/{id}/file': [
    ['200, a signed link', call('faculty', get(`/api/ess/me/documents/${D.DOCUMENT_ID(1)}/file`), { setup: DOCS() })],
    ['400 VALIDATION_FAILED, not an id', call('faculty', get('/api/ess/me/documents/not-an-id/file'))],
    ['404 NOT_FOUND, somebody else\'s', call('hod', get(`/api/ess/me/documents/${D.DOCUMENT_ID(1)}/file`), { setup: DOCS() })],
    ...shared('faculty', 'get', `/api/ess/me/documents/${D.DOCUMENT_ID(1)}/file`, { table: 'hr_ess_documents', seed: DOCS() }),
  ],
  'GET /api/ess/hr/employees/{id}/documents': [
    ['200, one person\'s record', call('hr', get(`/api/ess/hr/employees/${FACULTY}/documents`), { setup: DOCS() })],
    ['200, the identity row held back from HR Executive', call('hr_executive', get(`/api/ess/hr/employees/${FACULTY}/documents`), { setup: DOCS() })],
    ['400 VALIDATION_FAILED, not an id', call('hr', get('/api/ess/hr/employees/not-an-id/documents'))],
    ['403 HR_ACCESS_DENIED, not HR\'s desk', call('faculty', get(`/api/ess/hr/employees/${FACULTY}/documents`), { setup: DOCS() })],
    ['404 NOT_FOUND, nobody there', call('hr', get(`/api/ess/hr/employees/${H.uuid('e', 99)}/documents`), { setup: D.seedDocumentTypes })],
    ...shared('hr', 'get', `/api/ess/hr/employees/${FACULTY}/documents`, { table: 'hr_ess_document_types', seed: D.seedDocumentTypes }),
  ],
  'GET /api/ess/hr/employees/{id}/documents/{documentId}/file': [
    ['200, HR opens the identity file', call('hr', get(`/api/ess/hr/employees/${FACULTY}/documents/${D.DOCUMENT_ID(2)}/file`), { setup: DOCS() })],
    ['400 VALIDATION_FAILED, not an id', call('hr', get(`/api/ess/hr/employees/${FACULTY}/documents/not-an-id/file`))],
    ['403 DOCUMENT_IDENTITY_ROLE, the gated type', call('hr_executive', get(`/api/ess/hr/employees/${FACULTY}/documents/${D.DOCUMENT_ID(2)}/file`), { setup: DOCS() })],
    ['404 NOT_FOUND, no such document', call('hr', get(`/api/ess/hr/employees/${FACULTY}/documents/${D.DOCUMENT_ID(9)}/file`), { setup: DOCS() })],
    ...shared('hr', 'get', `/api/ess/hr/employees/${FACULTY}/documents/${D.DOCUMENT_ID(1)}/file`, { table: 'hr_ess_documents', seed: DOCS() }),
  ],
  'POST /api/ess/hr/employees/{id}/documents/{documentId}/verify': [
    ['200, verified', call('hr', post(`/api/ess/hr/employees/${FACULTY}/documents/${D.DOCUMENT_ID(1)}/verify`), { setup: DOCS() })],
    ['400 VALIDATION_FAILED, a field it does not take', call('hr', post(`/api/ess/hr/employees/${FACULTY}/documents/${D.DOCUMENT_ID(1)}/verify`, { note: 'Fine.' }), { setup: DOCS() })],
    ['403 HR_ACCESS_DENIED, not HR\'s desk', call('faculty', post(`/api/ess/hr/employees/${FACULTY}/documents/${D.DOCUMENT_ID(1)}/verify`), { setup: DOCS() })],
    ['404 NOT_FOUND, no such document', call('hr', post(`/api/ess/hr/employees/${FACULTY}/documents/${D.DOCUMENT_ID(9)}/verify`), { setup: DOCS() })],
    ['409 DOCUMENT_REVIEWED, already verified', call('hr', post(`/api/ess/hr/employees/${FACULTY}/documents/${D.DOCUMENT_ID(1)}/verify`), {
      setup: DOCS({ status: 'verified', verified_at: D.AT, verified_by_name: 'Test HR Manager' }),
    })],
    ...shared('hr', 'post', `/api/ess/hr/employees/${FACULTY}/documents/${D.DOCUMENT_ID(1)}/verify`, { table: 'hr_ess_documents', seed: DOCS() }),
  ],
  'POST /api/ess/hr/employees/{id}/documents/{documentId}/reject': [
    ['200, rejected', call('hr', post(`/api/ess/hr/employees/${FACULTY}/documents/${D.DOCUMENT_ID(1)}/reject`, { reason: 'The scan is unreadable.' }), { setup: DOCS() })],
    ['400 VALIDATION_FAILED, no reason', call('hr', post(`/api/ess/hr/employees/${FACULTY}/documents/${D.DOCUMENT_ID(1)}/reject`, { reason: '  ' }), { setup: DOCS() })],
    ['403 HR_ACCESS_DENIED, not HR\'s desk', call('faculty', post(`/api/ess/hr/employees/${FACULTY}/documents/${D.DOCUMENT_ID(1)}/reject`, { reason: 'Unreadable.' }), { setup: DOCS() })],
    ['404 NOT_FOUND, no such document', call('hr', post(`/api/ess/hr/employees/${FACULTY}/documents/${D.DOCUMENT_ID(9)}/reject`, { reason: 'Unreadable.' }), { setup: DOCS() })],
    ['409 DOCUMENT_REVIEWED, already rejected', call('hr', post(`/api/ess/hr/employees/${FACULTY}/documents/${D.DOCUMENT_ID(1)}/reject`, { reason: 'Unreadable.' }), {
      setup: DOCS({ status: 'rejected', rejection_reason: 'Blurry.', verified_at: D.AT, verified_by_name: 'Test HR Manager' }),
    })],
    ...shared('hr', 'post', `/api/ess/hr/employees/${FACULTY}/documents/${D.DOCUMENT_ID(1)}/reject`, { body: { reason: 'Unreadable.' }, table: 'hr_ess_documents', seed: DOCS() }),
  ],
  'DELETE /api/ess/hr/employees/{id}/documents/{documentId}': [
    ['204, removed', call('hr', del(`/api/ess/hr/employees/${FACULTY}/documents/${D.DOCUMENT_ID(1)}`), { setup: DOCS() })],
    ['400 VALIDATION_FAILED, not an id', call('hr', del(`/api/ess/hr/employees/${FACULTY}/documents/not-an-id`))],
    ['403 HR_ACCESS_DENIED, not HR\'s desk', call('faculty', del(`/api/ess/hr/employees/${FACULTY}/documents/${D.DOCUMENT_ID(1)}`), { setup: DOCS() })],
    ['404 NOT_FOUND, no such document', call('hr', del(`/api/ess/hr/employees/${FACULTY}/documents/${D.DOCUMENT_ID(9)}`), { setup: DOCS() })],
    ...shared('hr', 'delete', `/api/ess/hr/employees/${FACULTY}/documents/${D.DOCUMENT_ID(1)}`, { table: 'hr_ess_documents', seed: DOCS() }),
  ],
  'GET /api/ess/me/change-requests': [
    ['200, my asks', call('faculty', get('/api/ess/me/change-requests'), { setup: OPEN_CR })],
    ...shared('faculty', 'get', '/api/ess/me/change-requests', { table: 'hr_ess_change_requests', seed: OPEN_CR }),
  ],
  'POST /api/ess/me/change-requests': [
    ['201, an ask', call('faculty', post('/api/ess/me/change-requests', changeBody()))],
    ['400 VALIDATION_FAILED, a field it does not take', call('faculty', post('/api/ess/me/change-requests', changeBody({ field: 'salary' })))],
    ['400 VALIDATION_FAILED, no reason', call('faculty', post('/api/ess/me/change-requests', changeBody({ reason: 'hi' })))],
    ['409 CHANGE_ALREADY_OPEN, one open ask per field', call('faculty', post('/api/ess/me/change-requests', changeBody()), { setup: OPEN_CR })],
    ...shared('faculty', 'post', '/api/ess/me/change-requests', { body: changeBody(), table: 'hr_ess_change_requests', seed: OPEN_CR }),
  ],
  'GET /api/ess/hr/change-requests': [
    ['200, the queue', call('hr', get('/api/ess/hr/change-requests'), { setup: OPEN_CR })],
    ['400 VALIDATION_FAILED, a status it does not take', call('hr', get('/api/ess/hr/change-requests?status=roof'))],
    ['403 HR_ACCESS_DENIED, not HR\'s desk', call('faculty', get('/api/ess/hr/change-requests'))],
    ...shared('hr', 'get', '/api/ess/hr/change-requests', { table: 'hr_ess_change_requests', seed: OPEN_CR }),
  ],
  'POST /api/ess/hr/change-requests/{id}/decide': [
    ['200, approved', call('hr', post(`/api/ess/hr/change-requests/${D.CHANGE_ID(1)}/decide`, { decision: 'approved' }), { setup: OPEN_CR })],
    ['400 VALIDATION_FAILED, a decision it does not take', call('hr', post(`/api/ess/hr/change-requests/${D.CHANGE_ID(1)}/decide`, { decision: 'maybe' }), { setup: OPEN_CR })],
    ['403 HR_ACCESS_DENIED, not HR\'s desk', call('faculty', post(`/api/ess/hr/change-requests/${D.CHANGE_ID(1)}/decide`, { decision: 'approved' }))],
    ['404 NOT_FOUND, no such request', call('hr', post(`/api/ess/hr/change-requests/${D.CHANGE_ID(9)}/decide`, { decision: 'approved' }), { setup: OPEN_CR })],
    ['409 ALREADY_DECIDED, answered once', call('hr', post(`/api/ess/hr/change-requests/${D.CHANGE_ID(1)}/decide`, { decision: 'approved' }), { setup: DECIDED_CR })],
    ...shared('hr', 'post', `/api/ess/hr/change-requests/${D.CHANGE_ID(1)}/decide`, { body: { decision: 'approved' }, table: 'hr_ess_change_requests', seed: OPEN_CR }),
  ],
  'GET /api/ess/me/bank-details': [
    ['200, mine', call('faculty', get('/api/ess/me/bank-details'), { setup: BANK })],
    ['200, none saved yet', call('faculty', get('/api/ess/me/bank-details'))],
    ...shared('faculty', 'get', '/api/ess/me/bank-details', { table: 'hr_ess_bank_details', seed: BANK }),
  ],
  'PUT /api/ess/me/bank-details': [
    ['200, saved, with the consent stamped', call('faculty', put('/api/ess/me/bank-details', bankBody()), { setup: BANK })],
    ['400 VALIDATION_FAILED, an account number that is not one', call('faculty', put('/api/ess/me/bank-details', bankBody({ account_number: '12345' })))],
    ['400 VALIDATION_FAILED, no consent', call('faculty', put('/api/ess/me/bank-details', bankBody({ consent: false })))],
    ...shared('faculty', 'put', '/api/ess/me/bank-details', { body: bankBody(), table: 'hr_ess_bank_details', seed: BANK }),
  ],
  'GET /api/ess/hr/employees/{id}/bank-details': [
    ['200, masked, audited', call('hr', get(`/api/ess/hr/employees/${FACULTY}/bank-details`), { setup: BANK })],
    ['400 VALIDATION_FAILED, not an id', call('hr', get('/api/ess/hr/employees/not-an-id/bank-details'))],
    ['403 HR_ACCESS_DENIED, not HR\'s desk', call('faculty', get(`/api/ess/hr/employees/${FACULTY}/bank-details`))],
    ['404 NOT_FOUND, none saved', call('hr', get(`/api/ess/hr/employees/${H.uuid('e', 99)}/bank-details`))],
    ...shared('hr', 'get', `/api/ess/hr/employees/${FACULTY}/bank-details`, { table: 'hr_ess_bank_details', seed: BANK }),
  ],
  'GET /api/ess/me/id-card': [
    ['200, my card', call('faculty', get('/api/ess/me/id-card'))],
    ...shared('faculty', 'get', '/api/ess/me/id-card'),
  ],
  'GET /api/ess/id-card/verify/{token}': [
    ['200, what the card shows', call('faculty', verify)],
    ['401 ID_CARD_BAD_TOKEN, not a token', async () => {
      const { app } = buildApp();
      return request(app).get('/api/ess/id-card/verify/not-a-token');
    }],
    ['429 RATE_LIMITED, per address', async () => {
      const world = buildApp({ limits: { idCardVerify: { windowMs: 60 * 1000, limit: 1 } } });
      await request(world.app).get('/api/ess/id-card/verify/not-a-token');
      return request(world.app).get('/api/ess/id-card/verify/not-a-token');
    }],
    ['503 UNAVAILABLE, the database away', async () => {
      const world = buildApp();
      const link = await mintLink(world);
      world.db.outage = 'error';
      return request(world.app).get(`/api/ess/id-card/verify/${link}`);
    }],
  ],
  'POST /api/ess/helpdesk/tickets/{id}/assign': [
    ['200, the team hands it over', call('admin', post(at('/assign'), assignBody(ADMIN_MANAGER)), { setup: TICKET() })],
    ['400 VALIDATION_FAILED, not an employee id', call('admin', post(at('/assign'), assignBody('not-an-id')), { setup: TICKET() })],
    ['400 VALIDATION_FAILED, somebody off the queue', call('admin', post(at('/assign'), assignBody(FACULTY)), { setup: TICKET() })],
    ['403 HELPDESK_AGENT_ONLY, oversight reads but does not act', call('hr', post(at('/assign'), assignBody(ADMIN_MANAGER)), { setup: TICKET() })],
    ['404 NOT_FOUND, no such ticket', call('admin', post(`/api/ess/helpdesk/tickets/${H.TICKET_ID(9)}/assign`, assignBody(ADMIN_MANAGER)), { setup: TICKET() })],
    ['409 HELPDESK_NOT_LIVE, settled', call('admin', post(at('/assign'), assignBody(ADMIN_MANAGER)), { setup: TICKET(SETTLED) })],
    ...shared('admin', 'post', at('/assign'), { body: assignBody(ADMIN_MANAGER), table: 'hr_ess_helpdesk_assignments', seed: TICKET() }),
  ],
};

module.exports = { WAVE_8, DOCS, OPEN_CR, DECIDED_CR, BANK, changeBody, bankBody, assignBody, verify };
