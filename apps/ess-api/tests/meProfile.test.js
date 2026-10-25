const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { MESSAGES } = require('../src/lib/errors');
const { expectRefusal, expectInvalid, quietErrors } = require('./helpers/expect');

/** Tasks E1, E10, E12: my profile, the timeline, and the photo. */

const PROFILE = '/api/ess/me/profile';
const PHOTO = '/api/ess/me/photo';
const PNG = Buffer.from('89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d4944415478da63fcffff3f030005fe02fea72d1e4b0000000049454e44ae426082', 'hex');
const PNG_B64 = PNG.toString('base64');

const event = (employeeId, n, change = {}) => ({
  id: `85000000-0000-4000-8000-${String(n).padStart(12, '0')}`,
  event_type: 'EMPLOYEE_CREATED', entity_type: 'employee', entity_id: employeeId, entity_label: 'Test',
  actor_user_id: null, actor_name: 'Test HR Manager', actor_role: 'hr', before: null,
  after: { secret_field: 'never read' }, changed_keys: [], metadata: {}, note: 'internal note',
  occurred_at: `2026-${String(n).padStart(2, '0')}-01T05:00:00+00:00`, ...change,
});

describe('GET /api/ess/me/profile', () => {
  it('shows Summary, Job, Personal and the Timeline, from the HR record, with a signed photo link', async () => {
    const { app, db, people } = buildApp({ setup: (w) => {
      w.people.attendance.employee.photo_path = 'hr/photos/attendance.jpg';
      w.tables.hr_ess_personal_details = [{
        employee_id: w.people.attendance.employee.id, date_of_birth: '1994-05-21', blood_group: 'B+',
        address_line1: 'House 12', address_line2: null, city: 'Faridabad', state: 'Haryana', pincode: '121007',
        emergency_name: 'Sunita Yadav', emergency_relation: 'Mother', emergency_phone: '9876543210',
        updated_at: '2026-10-10T05:00:00+00:00', updated_by_user_id: null, updated_by_name: null,
      }];
      w.tables.hr_activity_events = [
        event(w.people.attendance.employee.id, 1),
        event(w.people.attendance.employee.id, 2, { event_type: 'EMPLOYEE_UPDATED', changed_keys: ['designation'] }),
        event(w.people.attendance.employee.id, 3, { event_type: 'EMPLOYEE_REMARK_ADDED' }),
        event(w.people.attendance.employee.id, 4, { event_type: 'SOMETHING_NEW' }),
      ];
    } });
    const res = await request(app).get(PROFILE).set(bearer(tokens.attendance(people.attendance)));
    expect(res.status).toBe(200);
    expect(res.body.employee).toEqual({
      id: people.attendance.employee.id,
      full_name: 'Test Office Assistant',
      employee_code: 'RVM-050',
      designation: 'Office Assistant',
      department: { id: people.attendance.employee.department_id, name: 'Technical Training' },
      branch: { id: people.attendance.employee.branch_id, name: 'Faridabad' },
      manager: { id: people.admin_manager.employee.id, full_name: 'Test Admin Manager', designation: 'Admin Manager' },
      date_of_joining: '2025-06-01',
      employment_status: 'active',
      notice_period: false,
      email: null,
      phone: '9710000050',
      photo_url: expect.stringContaining('test-signed'),
    });
    expect(res.body.personal).toMatchObject({ date_of_birth: '1994-05-21', blood_group: 'B+' });
    // Only the two safe events, newest first; remarks and unknown types never appear.
    expect(res.body.timeline).toEqual([
      {
        id: '85000000-0000-4000-8000-000000000002',
        kind: 'DESIGNATION_CHANGED',
        title: 'Designation changed',
        at: '2026-02-01T05:00:00+00:00',
      },
      {
        id: '85000000-0000-4000-8000-000000000001',
        kind: 'JOINING_RECORDED',
        title: 'Joined RVM',
        at: '2026-01-01T05:00:00+00:00',
      },
    ]);
    expect(JSON.stringify(res.body)).not.toMatch(/secret_field|internal note|remark added/i);
    expect(db.queries.every((q) => !q.columns.includes('performance_tag') && !q.columns.includes('before') && !q.columns.includes('after')))
      .toBe(true);
  });

  it('gives every allowlisted event a stable kind, with the title unchanged, and keeps precedence', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      const id = w.people.attendance.employee.id;
      w.tables.hr_activity_events = [
        event(id, 1),
        event(id, 2, { event_type: 'EMPLOYEE_PROMOTED' }),
        event(id, 3, { event_type: 'EMPLOYEE_STATUS_CHANGED' }),
        event(id, 4, { event_type: 'EMPLOYEE_MANAGER_CHANGED' }),
        event(id, 5, { event_type: 'EMPLOYEE_CODE_ISSUED' }),
        event(id, 6, { event_type: 'EMPLOYEE_CODE_ASSIGNED' }),
        event(id, 7, { event_type: 'INCREMENT_DATE_CHANGED' }),
        event(id, 8, { event_type: 'EMPLOYEE_UPDATED', changed_keys: ['designation'] }),
        event(id, 9, { event_type: 'EMPLOYEE_UPDATED', changed_keys: ['branch_id'] }),
        event(id, 10, { event_type: 'EMPLOYEE_UPDATED', changed_keys: ['date_of_joining'] }),
        event(id, 11, { event_type: 'EMPLOYEE_UPDATED', changed_keys: ['phone'] }),
        event(id, 12, { event_type: 'EMPLOYEE_UPDATED', changed_keys: ['branch_id', 'designation'] }),
      ];
    } });
    const res = await request(app).get(PROFILE).set(bearer(tokens.attendance(people.attendance)));
    expect(res.status).toBe(200);
    expect(res.body.timeline.map(({ kind, title }) => ({ kind, title }))).toEqual([
      { kind: 'DESIGNATION_CHANGED', title: 'Designation changed' },
      { kind: 'TRIVIAL_UPDATE', title: 'Details updated' },
      { kind: 'JOINING_RECORDED', title: 'Joining date recorded' },
      { kind: 'BRANCH_CHANGED', title: 'Branch changed' },
      { kind: 'DESIGNATION_CHANGED', title: 'Designation changed' },
      { kind: 'INCREMENT_RECORDED', title: 'Increment date recorded' },
      { kind: 'CODE_ASSIGNED', title: 'Employee code set' },
      { kind: 'CODE_ISSUED', title: 'Employee code issued' },
      { kind: 'REPORTING_LINE_CHANGED', title: 'Reporting line changed' },
      { kind: 'STATUS_CHANGED', title: 'Employment status changed' },
      { kind: 'PROMOTED', title: 'Promoted' },
      { kind: 'JOINING_RECORDED', title: 'Joined RVM' },
    ]);
  });

  it('answers empty personal details when none are recorded, and 503 before a column exists', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    const res = await request(app).get(PROFILE).set(bearer(tokens.portal(people.faculty)));
    expect(res.body.personal).toEqual({
      date_of_birth: null, blood_group: null, address_line1: null, address_line2: null, city: null, state: null,
      pincode: null, emergency_name: null, emergency_relation: null, emergency_phone: null,
    });
    db.dropColumn('hr_employees', 'photo_updated_at');
    expectRefusal(await request(app).get(PROFILE).set(bearer(tokens.portal(people.faculty))), 503, 'MODULE_NOT_INSTALLED');
  });

  it('answers 401 with no token and 403 for a leaver', async () => {
    const { app, people } = buildApp({ setup: (w) => { w.people.faculty.employee.employment_status = 'exited'; } });
    expectRefusal(await request(app).get(PROFILE), 401, 'NOT_AUTHENTICATED');
    expectRefusal(await request(app).get(PROFILE).set(bearer(tokens.portal(people.faculty))), 403, 'NOT_ACTIVE');
  });
});

describe('PUT /api/ess/me/photo', () => {
  it('uploads the photo under my own path, points the record at it, and audits the change', async () => {
    const { app, db, people } = buildApp();
    const res = await request(app).put(PHOTO).set(bearer(tokens.attendance(people.attendance)))
      .send({ photo_base64: PNG_B64, content_type: 'image/png' });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ employee: { id: people.attendance.employee.id, photo_url: expect.stringContaining('test-signed') } });
    const [upload] = db.storageCalls;
    expect(upload).toMatchObject({ op: 'upload', bucket: 'documents', size: PNG.length });
    expect(upload.path).toMatch(new RegExp(`^hr/employee/${people.attendance.employee.id}/photo/[0-9a-f-]{36}_photo\\.png$`));
    const row = db.tables.hr_employees.find((e) => e.id === people.attendance.employee.id);
    expect(row.photo_path).toBe(upload.path);
    expect(db.tables.hr_ess_audit).toEqual([expect.objectContaining({ action: 'me.photo.updated' })]);
    // The old file is left where it is: deleting is irreversible.
    expect(db.storageCalls.filter((c) => c.op === 'remove')).toHaveLength(0);
  });

  it.each([
    ['a body with no photo', { content_type: 'image/png' }, MESSAGES.PHOTO_FORMAT],
    ['something that is not base64', { photo_base64: 'not base64 !!! at all', content_type: 'image/png' }, MESSAGES.PHOTO_FORMAT],
    ['a content type it does not take', { photo_base64: PNG_B64, content_type: 'application/pdf' }, MESSAGES.PHOTO_TYPE],
    ['a photo over 1 MB', { photo_base64: Buffer.alloc(1024 * 1024 + 1, 7).toString('base64'), content_type: 'image/jpeg' }, MESSAGES.PHOTO_SIZE],
    ['an unknown field', { photo_base64: PNG_B64, content_type: 'image/png', file_name: 'a.png' }, MESSAGES.UNKNOWN_FIELD],
  ])('refuses %s with 400', async (_label, body, message) => {
    const { app, people } = buildApp();
    expectInvalid(await request(app).put(PHOTO).set(bearer(tokens.attendance(people.attendance))).send(body), message);
  });

  it('answers 401 with no token and 403 for the desk login', async () => {
    const { app, people } = buildApp();
    expectRefusal(await request(app).put(PHOTO).send({ photo_base64: PNG_B64, content_type: 'image/png' }), 401, 'NOT_AUTHENTICATED');
    expectRefusal(await request(app).put(PHOTO).set(bearer(tokens.portal(people.desk))).send({ photo_base64: PNG_B64, content_type: 'image/png' }), 403, 'NOT_LINKED');
  });
});
