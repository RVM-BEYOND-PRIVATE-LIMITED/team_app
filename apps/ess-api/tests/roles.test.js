const path = require('path');
const roles = require('../src/policy/roles');
const hrPolicy = require('../src/policy/hrPolicy');

/**
 * src/policy/roles.js and src/policy/hrPolicy.js are copies of the Scheduler's config/roles.js
 * and of the role sets in its config/hrPolicy.js (ADR-0008). Point SCHEDULER_BACKEND_DIR at a
 * Scheduler_Backend checkout to compare them; without it the comparison is skipped and only
 * the copies' own shape is checked.
 */

const HR_SETS = ['HR_ROLES', 'HR_WRITE_ROLES', 'HR_ATTENDANCE_ROLES', 'ATTENDANCE_OVERRIDE_ROLES', 'ATTENDANCE_ACCOUNT_ROLES'];
const sorted = (set) => [...set].sort();

const dir = process.env.SCHEDULER_BACKEND_DIR;

describe('the role copy', () => {
  it('keeps the inheritance the capability rules rely on', () => {
    expect([...roles.expandRoles('ceo')].sort()).toEqual(['admin', 'ceo', 'super_admin']);
    expect([...roles.expandRoles('hod')].sort()).toEqual(['faculty', 'hod']);
    expect([...roles.expandRoles('hr')]).toEqual(['hr']);
    // HR Executive must not inherit hr, or it would gain attendance.
    expect([...roles.expandRoles('hr_executive')]).toEqual(['hr_executive']);
    expect(roles.roleSatisfies('admin_manager', 'admin')).toBe(true);
    expect(roles.roleSatisfies('hr', 'admin')).toBe(false);
    expect(roles.rolesSatisfying('admin').sort()).toEqual(['accounts_admin', 'admin', 'admin_manager', 'ceo', 'hoo', 'super_admin']);
    expect([...roles.TEACHING_ROLES].sort()).toEqual(['faculty', 'hod']);
    // The sign-in resolver offers these every branch, as the web's dropdown does.
    expect([...roles.NO_BRANCH_ROLES].sort()).toEqual(['accounts_admin', 'bot_readonly', 'ceo', 'hr', 'hr_executive', 'super_admin']);
  });

  it('names every role the database enum has', () => {
    expect(Object.values(roles.ROLES).sort()).toEqual([
      'accounts_admin', 'admin', 'admin_manager', 'bot_readonly', 'ceo', 'faculty', 'hod', 'hod_placement',
      'hoo', 'hr', 'hr_executive', 'student', 'super_admin',
    ]);
  });

  describe.skipIf(!dir)('matches config/roles.js in SCHEDULER_BACKEND_DIR', () => {
    const scheduler = dir ? require(path.join(dir, 'config', 'roles.js')) : null;

    it('has the same role names', () => {
      expect(roles.ROLES).toEqual(scheduler.ROLES);
    });

    it('has the same inheritance', () => {
      expect(roles.INHERITS).toEqual(scheduler.INHERITS);
    });

    it('expands every role the same way', () => {
      for (const role of Object.values(scheduler.ROLES)) {
        expect([...roles.expandRoles(role)].sort(), role).toEqual([...scheduler.expandRoles(role)].sort());
      }
    });

    it('has the same teaching, all-centre and no-branch roles', () => {
      expect([...roles.TEACHING_ROLES].sort()).toEqual([...scheduler.TEACHING_ROLES].sort());
      expect([...roles.SEES_ALL_LOCATIONS].sort()).toEqual([...scheduler.SEES_ALL_LOCATIONS].sort());
      expect([...roles.NO_BRANCH_ROLES].sort()).toEqual([...scheduler.NO_BRANCH_ROLES].sort());
    });
  });
});

describe('the HR role-set copy', () => {
  it('keeps HR Executive out of every attendance set, and in the HR ones', () => {
    expect(sorted(hrPolicy.ATTENDANCE_OVERRIDE_ROLES)).toEqual(['ceo', 'hr', 'super_admin']);
    expect(sorted(hrPolicy.HR_ROLES)).toEqual(['ceo', 'hr', 'hr_executive', 'super_admin']);
    for (const name of ['HR_ATTENDANCE_ROLES', 'ATTENDANCE_OVERRIDE_ROLES', 'ATTENDANCE_ACCOUNT_ROLES']) {
      expect(hrPolicy[name].has('hr_executive'), name).toBe(false);
    }
  });

  describe.skipIf(!dir)('matches config/hrPolicy.js in SCHEDULER_BACKEND_DIR', () => {
    const scheduler = dir ? require(path.join(dir, 'config', 'hrPolicy.js')) : null;

    it.each(HR_SETS)('%s has the same roles', (name) => {
      expect(sorted(hrPolicy[name])).toEqual(sorted(scheduler[name]));
    });
  });
});
