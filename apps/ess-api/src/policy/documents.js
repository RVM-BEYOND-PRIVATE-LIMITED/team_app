const { ROLES } = require('./roles');

/**
 * My Documents' product rules in one place (Phase 2C, KP 1 and KP 2). The routes enforce them,
 * GET /api/ess/me/documents hands the app the same type list, and the migration seeds the
 * hr_ess_document_types table from DOCUMENT_TYPES here — so a form, its refusal and the database
 * can never disagree.
 *
 * The types are FIXED in code (KP, 19 Oct 2026), exactly as the Helpdesk's categories are: a
 * change here is a reviewed code change and a migration re-run.
 *
 *   `others`  an ESS-only type for anything the list does not name; it requires a free-text
 *             remark saying what the file is, so HR is never handed a mystery file.
 *   `identity` the gated one: only the roles in IDENTITY_ROLES may open one, and every opening
 *             is audited. KP 2's rule, in one place.
 */
const DOCUMENT_TYPES = Object.freeze([
  Object.freeze({ slug: 'resume', name: 'Resume', mandatory: false, ess_only: false }),
  Object.freeze({ slug: 'identity', name: 'Identity document', mandatory: true, ess_only: false }),
  Object.freeze({ slug: 'certificate', name: 'Certificate', mandatory: false, ess_only: false }),
  Object.freeze({ slug: 'offer', name: 'Offer letter', mandatory: true, ess_only: false }),
  Object.freeze({ slug: 'joining', name: 'Joining letter', mandatory: true, ess_only: false }),
  Object.freeze({ slug: 'experience', name: 'Experience letter', mandatory: false, ess_only: false }),
  Object.freeze({ slug: 'exit', name: 'Exit letter', mandatory: false, ess_only: false }),
  Object.freeze({ slug: 'other', name: 'Other document', mandatory: false, ess_only: false }),
  // The ESS-only type: the remark is what says what the file is.
  Object.freeze({ slug: 'others', name: 'Other (say what it is)', mandatory: false, ess_only: true }),
]);

const typeBySlug = (slug) => DOCUMENT_TYPES.find((t) => t.slug === slug) || null;

/** Whether the list answers a type at all (the Scheduler's doc_type list plus the ESS's own). */
const isKnownType = (slug) => Boolean(typeBySlug(slug));

/**
 * KP 2: who may open an identity document. The HR Executive is deliberately NOT here: the
 * executive runs the document desk, and identity documents are the one thing that role may not
 * see. The roles are the Scheduler's own (src/policy/roles.js, the copy tests/roles.test.js
 * holds against the Scheduler at c28b9ca): `internal_committee` does not exist there, and no
 * role inherits into this set — it is exact membership, read by name.
 */
const IDENTITY_ROLES = Object.freeze([ROLES.HR, ROLES.CEO, ROLES.SUPER_ADMIN]);

/**
 * Who may work HR's side of the desk at all: the lists, the verify and reject marks, the delete.
 * HR Executive included; the identity gate is applied on top of this, per type.
 */
const HR_DOCUMENT_ROLES = Object.freeze([ROLES.HR, ROLES.HR_EXECUTIVE, ROLES.CEO, ROLES.SUPER_ADMIN]);

/** Whether this reader may open this document's file (KP 2). */
const canOpenFile = (role, docType) => (docType === 'identity' ? IDENTITY_ROLES.includes(role) : true);

/** Whether this reader may see this row at all in a list. */
const canSeeRow = (role, docType) => canOpenFile(role, docType);

/* ── the file's own rules ── */

/** What one document may arrive as. PDFs and scans; no video, no archives. */
const DOCUMENT_CONTENT_TYPES = Object.freeze({
  'application/pdf': 'pdf',
  'image/jpeg': 'jpg',
  'image/png': 'png',
});

const MAX_DOCUMENT_BYTES = 5 * 1024 * 1024; // 5 MB decoded, per file
/** One file per upload; a person's record takes up to this many rows. */
const MAX_DOCUMENTS_PER_PERSON = 50;

module.exports = {
  DOCUMENT_TYPES,
  typeBySlug,
  isKnownType,
  IDENTITY_ROLES,
  HR_DOCUMENT_ROLES,
  canOpenFile,
  canSeeRow,
  DOCUMENT_CONTENT_TYPES,
  MAX_DOCUMENT_BYTES,
  MAX_DOCUMENTS_PER_PERSON,
};
