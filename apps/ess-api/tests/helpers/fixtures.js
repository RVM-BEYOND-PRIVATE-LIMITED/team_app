/**
 * A small company for the tests: one branch, two departments, one linked portal login for every
 * staff role, an employee with only an attendance login, and the accounts the ESS must refuse.
 *
 * The reporting lines (manager_id) are:
 *
 *   ceo ── super_admin, hoo, hr, hr_executive, accounts_admin, hod_placement
 *   hoo ── admin_manager, admin, hod
 *   hod ── faculty
 *   admin_manager ── attendance (no portal login)
 *
 * IDs are fixed so a failing test is easy to read. Every call returns fresh copies.
 */

const uuid = (prefix, n) => `${prefix}0000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

const BRANCH_ID = uuid('b', 1);
const DEPT_TECH_ID = uuid('d', 1);
const DEPT_HR_ID = uuid('d', 2);
const STUDENT_ID = uuid('c', 1);

/** [key, role, designation, department, manager key] */
const PORTAL_PEOPLE = [
  ['ceo', 'ceo', 'Chief Executive Officer', DEPT_TECH_ID, null],
  ['super_admin', 'super_admin', 'Super Admin', DEPT_TECH_ID, 'ceo'],
  ['hoo', 'hoo', 'Head of Operations', DEPT_TECH_ID, 'ceo'],
  ['hod', 'hod', 'CAD HOD', DEPT_TECH_ID, 'hoo'],
  ['hod_placement', 'hod_placement', 'HOD Placement', DEPT_TECH_ID, 'ceo'],
  ['admin_manager', 'admin_manager', 'Admin Manager', DEPT_TECH_ID, 'hoo'],
  ['admin', 'admin', 'Branch Admin', DEPT_TECH_ID, 'hoo'],
  ['accounts_admin', 'accounts_admin', 'Finance Admin', DEPT_TECH_ID, 'ceo'],
  ['hr', 'hr', 'HR Manager', DEPT_HR_ID, 'ceo'],
  ['hr_executive', 'hr_executive', 'HR Executive', DEPT_HR_ID, 'ceo'],
  ['faculty', 'faculty', 'CAD Faculty', DEPT_TECH_ID, 'hod'],
];

const TEACHING = new Set(['faculty', 'hod']);

function company() {
  const users = [];
  const employees = [];
  const people = {};

  PORTAL_PEOPLE.forEach(([key, role, designation, departmentId], i) => {
    const n = i + 1;
    const user = {
      id: uuid('a', n),
      username: `${key}.login`,
      phone_number: `98100000${String(n).padStart(2, '0')}`,
      password_hash: '$2b$10$fixture.hash.that.must.never.be.returned',
      role,
      faculty_id: TEACHING.has(role) ? uuid('f', n) : null,
      location_id: 1,
      email: `${key}@example.test`,
      created_at: '2025-01-01T00:00:00+00:00',
    };
    const employee = {
      id: uuid('e', n),
      employee_code: `RVM-${String(n).padStart(3, '0')}`,
      full_name: `Test ${designation}`,
      designation,
      department_id: departmentId,
      branch_id: BRANCH_ID,
      manager_id: null,
      email: `${key}@example.test`,
      phone: `97100000${String(n).padStart(2, '0')}`,
      date_of_joining: '2025-01-01',
      date_of_exit: null,
      employment_status: 'active',
      performance_tag: 'stable',
      is_archived: false,
      archive_reason: null,
      user_id: user.id,
      photo_path: `hr/photos/${key}.jpg`,
      geofence_exempt: false,
    };
    users.push(user);
    employees.push(employee);
    people[key] = { user, employee };
  });

  PORTAL_PEOPLE.forEach(([key, , , , managerKey]) => {
    if (managerKey) people[key].employee.manager_id = people[managerKey].employee.id;
  });

  // Staff with no portal login: an attendance login is their only sign-in.
  const attendanceEmployee = {
    id: uuid('e', 50),
    employee_code: 'RVM-050',
    full_name: 'Test Office Assistant',
    designation: 'Office Assistant',
    department_id: DEPT_TECH_ID,
    branch_id: BRANCH_ID,
    manager_id: people.admin_manager.employee.id,
    email: null,
    phone: '9710000050',
    date_of_joining: '2025-06-01',
    date_of_exit: null,
    employment_status: 'active',
    is_archived: false,
    user_id: null,
    geofence_exempt: false,
  };
  const attendanceAccount = {
    id: uuid('9', 50),
    employee_id: attendanceEmployee.id,
    status: 'active',
    password_hash: '$2b$10$fixture.attendance.hash.never.returned',
    password_set_at: '2026-10-02T04:00:00+00:00',
    sessions_valid_from: '2026-10-02T04:00:00.123456+00:00',
    failed_attempts: 0,
    locked_until: null,
  };
  employees.push(attendanceEmployee);
  people.attendance = { user: null, employee: attendanceEmployee, account: attendanceAccount };

  // A shared desk login with no HR record (decision: such logins cannot use the app).
  const deskUser = {
    id: uuid('a', 90),
    username: 'fbd.admin',
    phone_number: '9810000090',
    password_hash: '$2b$10$fixture.hash.that.must.never.be.returned',
    role: 'admin',
    faculty_id: null,
    location_id: 1,
  };
  users.push(deskUser);
  people.desk = { user: deskUser, employee: null };

  // The connector identity. It never signs in; if a token for it ever appeared, it is not staff.
  const botUser = {
    id: uuid('a', 91),
    username: 'control-room-bot',
    phone_number: null,
    password_hash: '!locked',
    role: 'bot_readonly',
    faculty_id: null,
    location_id: null,
  };
  users.push(botUser);
  people.bot = { user: botUser, employee: null };

  const tables = {
    users,
    hr_employees: employees,
    hr_branches: [{ id: BRANCH_ID, name: 'Faridabad', is_active: true, latitude: 28.4089, longitude: 77.3178, geofence_radius_m: 150 }],
    hr_departments: [
      { id: DEPT_TECH_ID, name: 'Technical Training', is_active: true, source: 'manual' },
      { id: DEPT_HR_ID, name: 'Human Resources', is_active: true, source: 'manual' },
    ],
    hr_attendance_accounts: [attendanceAccount],
    // The Scheduler's branches (users.location_id), in the order the web's dropdown lists them,
    // which is not alphabetical, so a test can tell the two orders apart.
    locations: LOCATIONS.map((l) => ({ ...l })),
    hr_ess_sessions: [],
  };
  return { tables, people };
}

const LOCATIONS = Object.freeze([
  { id: 1, name: 'Faridabad' },
  { id: 2, name: 'Pune' },
  { id: 3, name: 'Ahmedabad' },
  { id: 4, name: 'Lucknow' },
]);

/** An install id as the app makes one: random, once per install. */
const INSTALL_ID = 'install-0123456789abcdef';
const OTHER_INSTALL_ID = 'install-fedcba9876543210';

let sessionRows = 0;

/**
 * One hr_ess_sessions row, for a test that needs a sign-in the API did not make (somebody else's,
 * an expired one). Defaults to a live attendance sign-in of the attendance-only employee, made on
 * another install; set `refresh_hash` (lib/accessTokens.js refreshTokenHash, with the test secret)
 * for a row a test presents a token for.
 */
function sessionRow(overrides = {}) {
  sessionRows += 1;
  const id = overrides.id || uuid('5', sessionRows);
  return {
    id,
    family_id: id,
    employee_id: uuid('e', 50),
    login_kind: 'attendance',
    user_id: null,
    location_name: null,
    method: 'otp',
    signed_in_at: '2026-10-16T06:00:00.000Z',
    install_id: OTHER_INSTALL_ID,
    device_label: null,
    refresh_hash: String(sessionRows).padStart(64, '0'),
    created_at: '2026-10-16T06:00:00.000Z',
    last_used_at: '2026-10-16T06:00:00.000Z',
    expires_at: '2027-01-14T06:00:00.000Z',
    replaced_by: null,
    revoked_at: null,
    revoked_reason: null,
    ...overrides,
  };
}

module.exports = {
  company, uuid, sessionRow, BRANCH_ID, DEPT_TECH_ID, DEPT_HR_ID, STUDENT_ID, PORTAL_PEOPLE, LOCATIONS, INSTALL_ID, OTHER_INSTALL_ID,
};
