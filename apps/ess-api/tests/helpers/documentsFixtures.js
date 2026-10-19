const { uuid, CAT } = require('./helpdeskFixtures');

/**
 * Phase 2C's own fixtures: the document types as the migration seeds them, one document row,
 * one change request and one bank-details row of any state. The Helpdesk's fixtures
 * (helpdeskFixtures.js) hold the category ids and the uuid helper the assign tests need.
 *
 * The rows are written as db/migrations/20261110000001 to 20261110000003 declare them, defaults
 * included. Fixed ids, so a failing test is easy to read.
 */

const DOCUMENT_ID = (n) => uuid('cd', n);
const CHANGE_ID = (n) => uuid('ce', n);

/** The fixture's clock: 16 Oct 2026, 10:30 IST — the same instant the other fixtures use. */
const AT = '2026-10-16T05:00:00+00:00';

/** The document types, as db/migrations/20261110000001 seeds them (KP 1's list, KP 19 Oct). */
function documentTypeRows() {
  return [
    { slug: 'resume', name: 'Resume', is_mandatory: false, sort: 10, created_at: AT },
    { slug: 'identity', name: 'Identity document', is_mandatory: true, sort: 20, created_at: AT },
    { slug: 'certificate', name: 'Certificate', is_mandatory: false, sort: 30, created_at: AT },
    { slug: 'offer', name: 'Offer letter', is_mandatory: true, sort: 40, created_at: AT },
    { slug: 'joining', name: 'Joining letter', is_mandatory: true, sort: 50, created_at: AT },
    { slug: 'experience', name: 'Experience letter', is_mandatory: false, sort: 60, created_at: AT },
    { slug: 'exit', name: 'Exit letter', is_mandatory: false, sort: 70, created_at: AT },
    { slug: 'other', name: 'Other document', is_mandatory: false, sort: 80, created_at: AT },
    { slug: 'others', name: 'Other (say what it is)', is_mandatory: false, sort: 90, created_at: AT },
  ];
}

const seedDocumentTypes = (w) => {
  w.tables.hr_ess_document_types = documentTypeRows();
};

/** One hr_ess_documents row: a pending resume by default, its file in the ESS bucket. */
function documentRow(employeeId, n, change = {}) {
  return {
    id: DOCUMENT_ID(n),
    employee_id: employeeId,
    doc_type: 'resume',
    file_name: `resume-${n}.pdf`,
    storage_path: `documents/${employeeId}/00000000-0000-4000-8000-00000000000${n}.pdf`,
    content_type: 'application/pdf',
    size_bytes: 120_000,
    remark: null,
    status: 'pending',
    verified_by_user_id: null,
    verified_by_name: null,
    verified_at: null,
    rejection_reason: null,
    created_at: AT,
    updated_at: AT,
    ...change,
  };
}

/** One hr_ess_change_requests row: an open address correction by default (E3). */
function changeRequestRow(employeeId, n, change = {}) {
  return {
    id: CHANGE_ID(n),
    employee_id: employeeId,
    field: 'address',
    old_value: 'House 12, Sector 21',
    new_value: 'House 14, Sector 22',
    reason: 'The record has the old house number.',
    status: 'open',
    decided_by_user_id: null,
    decided_by_name: null,
    decided_at: null,
    decision_note: null,
    created_at: AT,
    updated_at: AT,
    ...change,
  };
}

/** One hr_ess_bank_details row (KP 3): the consent already stamped. */
function bankRow(employeeId, change = {}) {
  return {
    employee_id: employeeId,
    bank_name: 'State Bank of India',
    branch_name: 'Faridabad Sector 21',
    account_number: '1234567890',
    ifsc_code: 'SBIN0001234',
    upi_id: null,
    consent_given_at: AT,
    consent_name: 'Test CAD Faculty',
    updated_by_user_id: null,
    updated_by_name: null,
    created_at: AT,
    updated_at: AT,
    ...change,
  };
}

/** A small base64 PDF: a valid upload body's data, 24 bytes decoded. */
const PDF_B64 = Buffer.from('%PDF-1.4 test bytes for the ESS').toString('base64');

/** An upload body: a resume by default; `change` sets any field. */
function uploadBody(change = {}) {
  return {
    doc_type: 'resume',
    file_name: 'my-resume.pdf',
    content_type: 'application/pdf',
    data_base64: PDF_B64,
    ...change,
  };
}

module.exports = {
  uuid,
  DOCUMENT_ID,
  CHANGE_ID,
  CAT,
  AT,
  documentTypeRows,
  seedDocumentTypes,
  documentRow,
  changeRequestRow,
  bankRow,
  PDF_B64,
  uploadBody,
};
