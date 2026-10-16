const fs = require('fs');
const path = require('path');

/**
 * The verbatim Scheduler code in tests/helpers must still be the Scheduler's. Every block marked
 * `// <scheduler file="..." lines="...">` ... `// </scheduler>` is looked up in the Scheduler
 * checkout named by SCHEDULER_BACKEND_DIR, line by line with leading and trailing whitespace
 * ignored (the copies are re-indented, and the Scheduler's files have Windows line endings).
 * Without SCHEDULER_BACKEND_DIR only the markers are checked.
 */

const dir = process.env.SCHEDULER_BACKEND_DIR;
const HELPERS = ['helpers/schedulerTokens.js', 'helpers/schedulerRules.js', 'helpers/schedulerGuards.js', 'helpers/schedulerSignIn.js'];
const MARKED = /^[ \t]*\/\/ <scheduler file="([^"]+)" lines="([^"]+)">[ \t]*\r?\n([\s\S]*?)^[ \t]*\/\/ <\/scheduler>/gm;

const lines = (text) => text.split('\n').map((l) => l.trim()).filter(Boolean);

function blocks() {
  return HELPERS.flatMap((helper) => {
    const text = fs.readFileSync(path.join(__dirname, helper), 'utf8');
    return [...text.matchAll(MARKED)].map(([, file, range, code]) => ({ helper, file, range, code: lines(code) }));
  });
}

/** Whether `run` appears in `source` as consecutive lines. */
function containsRun(source, run) {
  for (let i = 0; i + run.length <= source.length; i++) {
    if (run.every((line, j) => source[i + j] === line)) return true;
  }
  return false;
}

describe('the verbatim Scheduler copies', () => {
  it('are all marked, with a file and a line range', () => {
    const found = blocks();
    expect(found.map((b) => `${b.file}:${b.range}`)).toEqual([
      'services/attendancePunch.js:205-239',
      'controllers/userController.js:498-512',
      'controllers/authSecurityController.js:19-31',
      'controllers/userController.js:797-801',
      'utils/admissionUndertakingToken.js:3-13',
      'services/attendanceAccounts.js:39-53',
      'services/attendancePunch.js:172',
      'controllers/hr/attendancePunchController.js:88-90',
      // schedulerGuards.js: what the Scheduler does with a token the ESS minted.
      'middleware/auth.js:6-106',
      'middleware/punchAuth.js:22-33',
      'services/attendancePunch.js:241-242',
      'controllers/hr/attendanceOtpController.js:77-78',
      'controllers/hr/attendanceOtpController.js:341-354',
      // schedulerSignIn.js: how its two sign-ins find an account.
      'controllers/hr/attendanceOtpController.js:77-78',
      'utils/sms.js:66-72',
      'services/hrPhones.js:47-52',
      'services/attendanceAccounts.js:55-62',
      'controllers/hr/attendanceOtpController.js:92-172',
      'controllers/userController.js:271-279',
      'controllers/userController.js:296-305',
    ]);
    for (const b of found) expect(b.code.length).toBeGreaterThan(0);
  });

  describe.skipIf(!dir)('match the Scheduler checkout in SCHEDULER_BACKEND_DIR', () => {
    it.each(blocks().map((b) => [`${b.file}:${b.range}`, b]))('%s', (_name, block) => {
      const source = lines(fs.readFileSync(path.join(dir, block.file), 'utf8'));
      expect(containsRun(source, block.code), `${block.helper} no longer matches ${block.file} (was lines ${block.range})`).toBe(true);
    });
  });
});
