const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const { bodyWith, requiredText, optionalText, idParam, chars } = require('../lib/validate');
const { recordBefore } = require('../lib/audit');

/**
 * Bank details (Phase 2C, KP 3): one row per person, which the person keeps themself, with the
 * consent the entry needs — the person sends `consent: true` and types their own name into
 * `consent_name`, and the save stamps `consent_given_at`, so the row carries the proof it was
 * entered knowingly, by them. Nothing is ever deleted by the app.
 *
 * The number is masked to everybody but its owner: HR's read answers the last four digits only,
 * and every HR read is written to the audit trail before the reply (lib/audit.js recordBefore).
 * No list response ever carries a bank row at all — there is no HR list of bank details.
 */

const invalid = (message) => new HttpError(400, 'VALIDATION_FAILED', message);
const notFound = (message) => new HttpError(404, 'NOT_FOUND', message);

/** The IFSC the RBI's shape holds: four letters, a zero, six letters or digits. */
const IFSC_RE = /^[A-Z]{4}0[A-Z0-9]{6}$/;
/** The account number the checks hold: 8 to 18 digits, Indian banks' range. */
const ACCOUNT_RE = /^[0-9]{8,18}$/;

/** One row as its owner reads it: everything, it is theirs. */
const bankDetailsView = (row) => ({
  bank_name: row.bank_name,
  branch_name: row.branch_name ?? null,
  account_number: row.account_number,
  ifsc_code: row.ifsc_code,
  upi_id: row.upi_id ?? null,
  consent_given_at: row.consent_given_at,
  consent_name: row.consent_name,
  updated_by_name: row.updated_by_name ?? null,
  created_at: row.created_at,
  updated_at: row.updated_at,
});

/** One row as HR reads it: the number masked to its last four digits, never the whole number. */
function bankDetailsMasked(row) {
  const account = String(row.account_number);
  return {
    bank_name: row.bank_name,
    branch_name: row.branch_name ?? null,
    account_number: `******${account.slice(-4)}`,
    ifsc_code: row.ifsc_code,
    upi_id: row.upi_id ?? null,
    consent_given_at: row.consent_given_at,
    consent_name: row.consent_name,
    updated_by_name: row.updated_by_name ?? null,
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

/** GET /api/ess/me/bank-details — mine, whole, or null while none is saved (KP 3). */
function getMyBankDetails({ store }) {
  return asyncRoute(async (req, res) => {
    const row = await store.getBankDetails(req.auth.employee.id);
    res.json({ bank_details: row ? bankDetailsView(row) : null });
  });
}

/** PUT /api/ess/me/bank-details { bank_name, branch_name?, account_number, ifsc_code, upi_id?, consent, consent_name } — save mine (KP 3). */
function putMyBankDetails({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee, userId } = req.auth;
    const form = bodyWith(req, ['bank_name', 'branch_name', 'account_number', 'ifsc_code', 'upi_id', 'consent', 'consent_name']);

    const bankName = requiredText(form.bank_name, { min: 2, max: 120, message: MESSAGES.BANK_NAME });
    const branchName = optionalText(form.branch_name);
    if (branchName === undefined || (branchName && (chars(branchName) < 2 || chars(branchName) > 120))) {
      throw invalid(MESSAGES.BANK_BRANCH);
    }

    const account = typeof form.account_number === 'string' ? form.account_number.replace(/\s/g, '') : '';
    if (!ACCOUNT_RE.test(account)) throw invalid(MESSAGES.BANK_ACCOUNT);

    const ifsc = typeof form.ifsc_code === 'string' ? form.ifsc_code.trim().toUpperCase() : '';
    if (!IFSC_RE.test(ifsc)) throw invalid(MESSAGES.BANK_IFSC);

    const upi = optionalText(form.upi_id);
    if (upi === undefined || (upi && (chars(upi) < 3 || chars(upi) > 60))) throw invalid(MESSAGES.BANK_UPI);

    // The consent the entry needs: explicit, and the name typed into it is the person's own.
    if (form.consent !== true) throw invalid(MESSAGES.BANK_CONSENT);
    const consentName = typeof form.consent_name === 'string' ? form.consent_name.trim() : '';
    if (!consentName || chars(consentName) > 120) throw invalid(MESSAGES.BANK_CONSENT_NAME);

    const at = now().toISOString();
    const saved = await store.upsertBankDetails({
      employee_id: employee.id,
      bank_name: bankName,
      branch_name: branchName,
      account_number: account,
      ifsc_code: ifsc,
      upi_id: upi,
      consent_given_at: at,
      consent_name: consentName,
      updated_by_user_id: userId,
      updated_by_name: employee.full_name,
    });
    res.json({ bank_details: bankDetailsView(saved) });
  });
}

/** GET /api/ess/hr/employees/:id/bank-details — HR reads one person's details, masked and audited (KP 3). */
function getEmployeeBankDetails({ store }) {
  return asyncRoute(async (req, res) => {
    const employeeId = idParam(req.params.id);
    const row = await store.getBankDetails(employeeId);
    // The audit goes first, and a failure refuses the read: nobody sees even the masked number
    // without the trail saying so.
    await recordBefore(store, req, {
      action: 'bank_details.read',
      targetEmployeeId: employeeId,
      details: { found: Boolean(row) },
    });
    if (!row) throw notFound(MESSAGES.NOT_FOUND);
    res.json({ bank_details: bankDetailsMasked(row) });
  });
}

module.exports = {
  getMyBankDetails,
  putMyBankDetails,
  getEmployeeBankDetails,
};
