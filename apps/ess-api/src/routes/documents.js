const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const { bodyWith, requiredText, idParam } = require('../lib/validate');
const { LIST_LIMITS } = require('../lib/store');
const { documentFrom, documentView, documentsForRole, typesView } = require('../lib/documentsKit');
const { recordBefore, recordAfter } = require('../lib/audit');
const { canOpenFile, MAX_DOCUMENTS_PER_PERSON } = require('../policy/documents');

/**
 * My Documents (Phase 2C, KP 1 and KP 2): a person's own record of their papers — resume,
 * identity proof, certificates, the offer and joining letters — and HR's desk over the same
 * rows. The files live in the ESS's private bucket under `documents/`; every reply names the
 * facts and hands a 300-second signed link out (GET .../file), never the path or the bytes.
 *
 * KP 2's gate lives in policy/documents.js (IDENTITY_ROLES): only HR (the manager role), the CEO
 * and super admins may open an identity document — an HR Executive runs the desk but is refused
 * that one type with 403 DOCUMENT_IDENTITY_ROLE, and every opening is written to the audit trail
 * before the link leaves the server.
 */

/** A 404 in the documents' words. */
const notFound = (message) => new HttpError(404, 'NOT_FOUND', message);

/** GET /api/ess/me/documents — my record, with the type list the raise form reads (KP 1). */
function listMyDocuments({ store }) {
  return asyncRoute(async (req, res) => {
    const [types, rows] = await Promise.all([
      store.listDocumentTypes(),
      store.listMyDocuments(req.auth.employee.id),
    ]);
    const documents = rows.slice(0, LIST_LIMITS.documents);
    res.json({ types: typesView(types), documents: documents.map(documentView) });
  });
}

/** POST /api/ess/me/documents { doc_type, file_name, content_type, data_base64, remark? } — upload one (KP 1). */
function createMyDocument({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const form = bodyWith(req, ['doc_type', 'file_name', 'content_type', 'data_base64', 'remark']);
    const file = documentFrom(form, { employeeId: employee.id });

    const count = await store.countDocuments(employee.id);
    if (count >= MAX_DOCUMENTS_PER_PERSON) throw new HttpError(409, 'DOCUMENT_LIMIT', MESSAGES.DOCUMENT_LIMIT);

    // The bytes go up first; a row that then fails leaves an orphaned object, which the cleanup
    // job handles, rather than a row pointing at nothing.
    await store.uploadEssObject(file.storage_path, file.buffer, file.content_type);
    const row = { ...file };
    delete row.buffer;
    const created = await store.createDocument({ ...row, created_at: now().toISOString(), updated_at: now().toISOString() });
    res.status(201).json({ document: documentView(created) });
  });
}

/** GET /api/ess/me/documents/:id/file — a 300-second signed link to one of mine. */
function getMyDocumentFile({ store }) {
  return asyncRoute(async (req, res) => {
    const row = await store.getDocument(idParam(req.params.id));
    if (!row || row.employee_id !== req.auth.employee.id) {
      throw notFound(MESSAGES.DOCUMENT_NOT_FOUND);
    }
    const url = await store.signedEssUrl(row.storage_path);
    if (!url) throw new HttpError(503, 'UNAVAILABLE', MESSAGES.UNAVAILABLE);
    res.json({ file: { url, name: row.file_name, content_type: row.content_type, expires_in: 300 } });
  });
}

/** The person whose record HR is reading, or the 404 every HR document answer is. */
async function loadEmployee(store, id) {
  const employee = await store.getEmployeeById(id);
  if (!employee) throw notFound(MESSAGES.EMPLOYEE_NOT_FOUND);
  return employee;
}

/** The one document on that person's record, or the 404. */
async function loadEmployeeDocument(store, employeeId, documentId) {
  const row = await store.getDocument(documentId);
  if (!row || row.employee_id !== employeeId) throw notFound(MESSAGES.DOCUMENT_NOT_FOUND);
  return row;
}

/** GET /api/ess/hr/employees/:id/documents — one person's record at HR's desk (KP 1, KP 2). */
function listEmployeeDocuments({ store }) {
  return asyncRoute(async (req, res) => {
    const employeeId = idParam(req.params.id);
    await loadEmployee(store, employeeId);
    const [types, rows] = await Promise.all([
      store.listDocumentTypes(),
      store.listDocumentsFor(employeeId),
    ]);
    // KP 2: an identity document is dropped for a reader who may not open one, never shown
    // with the file held back.
    const documents = documentsForRole(rows.slice(0, LIST_LIMITS.hrDocuments), req.auth.role);
    res.json({ types: typesView(types), documents });
  });
}

/** GET /api/ess/hr/employees/:id/documents/:documentId/file — open one file (KP 2). */
function getEmployeeDocumentFile({ store }) {
  return asyncRoute(async (req, res) => {
    const { employeeId, documentId } = pathIds(req);
    await loadEmployee(store, employeeId);
    const row = await loadEmployeeDocument(store, employeeId, documentId);
    if (!canOpenFile(req.auth.role, row.doc_type)) {
      throw new HttpError(403, 'DOCUMENT_IDENTITY_ROLE', MESSAGES.DOCUMENT_IDENTITY_ROLE);
    }
    // KP 2: every opening is audited before the link leaves the server, identity or not — HR
    // reading somebody's papers is a read of their data (DPDP), as personal details are.
    await recordBefore(store, req, {
      action: 'documents.file.read',
      targetEmployeeId: employeeId,
      details: { document_id: row.id, doc_type: row.doc_type },
    });
    const url = await store.signedEssUrl(row.storage_path);
    if (!url) throw new HttpError(503, 'UNAVAILABLE', MESSAGES.UNAVAILABLE);
    res.json({ file: { url, name: row.file_name, content_type: row.content_type, expires_in: 300 } });
  });
}

/** The two ids an HR document address carries. */
function pathIds(req) {
  return { employeeId: idParam(req.params.id), documentId: idParam(req.params.documentId) };
}

/** POST /api/ess/hr/employees/:id/documents/:documentId/verify — mark it verified (KP 1). */
function verifyEmployeeDocument({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employeeId, documentId } = pathIds(req);
    bodyWith(req, []);
    await loadEmployee(store, employeeId);
    const row = await loadEmployeeDocument(store, employeeId, documentId);
    if (row.status !== 'pending') throw new HttpError(409, 'DOCUMENT_REVIEWED', MESSAGES.DOCUMENT_REVIEWED);
    const at = now().toISOString();
    const updated = await store.updateDocument(row.id, {
      status: 'verified',
      verified_by_user_id: req.auth.userId,
      verified_by_name: req.auth.employee.full_name,
      verified_at: at,
      updated_at: at,
    });
    res.json({ document: documentView(updated) });
  });
}

/** POST /api/ess/hr/employees/:id/documents/:documentId/reject { reason } — turn it away (KP 1). */
function rejectEmployeeDocument({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employeeId, documentId } = pathIds(req);
    const form = bodyWith(req, ['reason']);
    const reason = requiredText(form.reason, { min: 3, max: 500, message: MESSAGES.DOCUMENT_REJECT_REASON });
    await loadEmployee(store, employeeId);
    const row = await loadEmployeeDocument(store, employeeId, documentId);
    if (row.status !== 'pending') throw new HttpError(409, 'DOCUMENT_REVIEWED', MESSAGES.DOCUMENT_REVIEWED);
    const at = now().toISOString();
    const updated = await store.updateDocument(row.id, {
      status: 'rejected',
      rejection_reason: reason,
      verified_by_user_id: req.auth.userId,
      verified_by_name: req.auth.employee.full_name,
      verified_at: at,
      updated_at: at,
    });
    res.json({ document: documentView(updated) });
  });
}

/** DELETE /api/ess/hr/employees/:id/documents/:documentId — remove a document and its file (KP 1). */
function deleteEmployeeDocument({ store }) {
  return asyncRoute(async (req, res) => {
    const { employeeId, documentId } = pathIds(req);
    await loadEmployee(store, employeeId);
    const row = await loadEmployeeDocument(store, employeeId, documentId);
    const gone = await store.deleteDocument(row.id);
    if (gone) store.removeEssObjects([gone.storage_path]);
    await recordAfter(store, req, {
      action: 'documents.delete',
      targetEmployeeId: employeeId,
      details: { document_id: row.id, doc_type: row.doc_type },
    });
    res.status(204).send();
  });
}

module.exports = {
  listMyDocuments,
  createMyDocument,
  getMyDocumentFile,
  listEmployeeDocuments,
  getEmployeeDocumentFile,
  verifyEmployeeDocument,
  rejectEmployeeDocument,
  deleteEmployeeDocument,
};
