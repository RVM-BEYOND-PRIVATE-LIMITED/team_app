const crypto = require('crypto');
const { chars } = require('./validate');
const { HttpError, MESSAGES } = require('./errors');
const {
  DOCUMENT_TYPES, DOCUMENT_CONTENT_TYPES, MAX_DOCUMENT_BYTES, canSeeRow, typeBySlug,
} = require('../policy/documents');

/**
 * The helpers My Documents' routes share (Phase 2C, KP 1 and KP 2): the one-file upload checked
 * against policy/documents.js's fixed list, the row it is stored as, and the one shape a
 * document comes back in. The rules live in the policy; this file only asks its questions.
 *
 * No Aadhaar number is ever stored: the row is the file, its name, and what the person said it
 * is (`remark`), nothing more.
 */

const invalid = (message) => new HttpError(400, 'VALIDATION_FAILED', message);
const BASE64 = /^[A-Za-z0-9+/]+={0,2}$/;

/**
 * The one file a POST /me/documents carries: { doc_type, file_name, content_type, data_base64,
 * remark? }. Everything is checked here, so both the person's route and HR's answers refuse the
 * same form the same way.
 */
function documentFrom(body, { employeeId }) {
  const docType = typeBySlug(body.doc_type);
  if (!docType) throw invalid(MESSAGES.DOCUMENT_TYPE);

  const contentType = body.content_type;
  const ext = DOCUMENT_CONTENT_TYPES[contentType];
  if (typeof contentType !== 'string' || !ext) throw invalid(MESSAGES.DOCUMENT_FILE);

  const data = body.data_base64;
  if (typeof data !== 'string' || chars(data) < 16 || !BASE64.test(data)) {
    throw invalid(MESSAGES.DOCUMENT_FILE);
  }
  const buffer = Buffer.from(data, 'base64');
  if (!buffer.length || buffer.length > MAX_DOCUMENT_BYTES) throw invalid(MESSAGES.DOCUMENT_SIZE);

  const fileName = typeof body.file_name === 'string' ? body.file_name.trim() : '';
  if (!fileName || chars(fileName) > 200) throw invalid(MESSAGES.DOCUMENT_NAME);

  const remark = typeof body.remark === 'string' ? body.remark.trim() : '';
  // The mystery-file rule: an `others` upload says what it is (the database CHECK holds this too).
  if (docType.ess_only && (!remark || chars(remark) < 3)) throw invalid(MESSAGES.DOCUMENT_REMARK);
  if (remark && (chars(remark) < 3 || chars(remark) > 500)) throw invalid(MESSAGES.DOCUMENT_REMARK);

  return {
    employee_id: employeeId,
    doc_type: docType.slug,
    file_name: fileName,
    storage_path: `documents/${employeeId}/${crypto.randomUUID()}.${ext}`,
    content_type: contentType,
    size_bytes: buffer.length,
    remark: remark || null,
    buffer,
  };
}

/**
 * One document as every read shows it: the facts and the review, never the bucket path (the
 * signed link carries the bytes) and never the reviewer's user id.
 */
function documentView(row) {
  return {
    id: row.id,
    employee_id: row.employee_id,
    doc_type: row.doc_type,
    file_name: row.file_name,
    content_type: row.content_type,
    size_bytes: row.size_bytes,
    remark: row.remark ?? null,
    status: row.status,
    verified_by_name: row.verified_by_name ?? null,
    verified_at: row.verified_at ?? null,
    rejection_reason: row.rejection_reason ?? null,
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

/**
 * HR's list with KP 2's gate applied per row: an identity document is dropped for a reader who
 * may not open one, rather than being shown with the file held back — a list either shows a
 * document exists or does not.
 */
function documentsForRole(rows, role) {
  return rows.filter((row) => canSeeRow(role, row.doc_type)).map(documentView);
}

/** The types, in the policy's order, for the response of every list. */
function typesView(rows) {
  const bySlug = new Map((rows || []).map((r) => [r.slug, r]));
  return DOCUMENT_TYPES.map((t) => {
    const row = bySlug.get(t.slug);
    return {
      slug: t.slug,
      name: row ? row.name : t.name,
      is_mandatory: row ? row.is_mandatory === true : t.mandatory,
      ess_only: t.ess_only === true,
      sort: row ? row.sort : 0,
    };
  });
}

module.exports = {
  documentFrom,
  documentView,
  documentsForRole,
  typesView,
};
