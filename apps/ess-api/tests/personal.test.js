const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { NOW } = require('./helpers/constants');
const { MESSAGES } = require('../src/lib/errors');
const { expectRefusal, expectInvalid, quietErrors, CALLERS, guardOutcome } = require('./helpers/expect');

/**
 * Task E9: personal details. The employee reads all of theirs and changes only the blood group
 * and the emergency contact; HR (hr, hr_executive, super_admin) reads and changes everybody
 * else's, and every HR read and change is in the audit trail.
 */

const MINE = '/api/ess/me/personal';
const theirs = (id) => `/api/ess/hr/employees/${id}/personal`;
const HR_ROLES = ['hr', 'hr_executive', 'ceo', 'super_admin'];

const EMPTY = {
  date_of_birth: null, blood_group: null, address_line1: null, address_line2: null, city: null, state: null, pincode: null,
  emergency_name: null, emergency_relation: null, emergency_phone: null, updated_at: null, updated_by_name: null,
};

const FULL = {
  date_of_birth: '1994-05-21',
  address_line1: 'House 12, Sector 15',
  address_line2: 'Near the market',
  city: 'Faridabad',
  state: 'Haryana',
  pincode: '121007',
  blood_group: 'B+',
  emergency_name: 'Sunita Yadav',
  emergency_relation: 'Mother',
  emergency_phone: '9876543210',
};

/** A stored row for the attendance employee, as HR would have written it. */
const storedFor = (people, change = {}) => ({
  employee_id: people.attendance.employee.id,
  ...FULL,
  updated_at: '2026-10-10T05:00:00.000Z',
  updated_by_user_id: people.hr.user.id,
  updated_by_name: 'Test HR Manager',
  ...change,
});

const withStored = (change) => ({
  setup: (w) => { w.tables.hr_ess_personal_details = [storedFor(w.people, change)]; },
});

const putMine = (app, token, body) => request(app).put(MINE).set(bearer(token)).send(body);
const putTheirs = (app, token, id, body) => request(app).put(theirs(id)).set(bearer(token)).send(body);

describe('GET /api/ess/me/personal', () => {
  it('answers every field as null before anything is recorded', async () => {
    const { app, people } = buildApp();
    const res = await request(app).get(MINE).set(bearer(tokens.attendance(people.attendance)));
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ personal: EMPTY });
  });

  it('answers the caller\'s own record, field for field, and nobody else\'s', async () => {
    const { app, people } = buildApp(withStored());
    const own = await request(app).get(MINE).set(bearer(tokens.attendance(people.attendance)));
    expect(own.body).toEqual({ personal: { ...FULL, updated_at: '2026-10-10T05:00:00.000Z', updated_by_name: 'Test HR Manager' } });
    // The same question from somebody else is about their own (empty) record.
    const other = await request(app).get(MINE).set(bearer(tokens.portal(people.faculty)));
    expect(other.body).toEqual({ personal: EMPTY });
    expect(JSON.stringify(own.body)).not.toMatch(/updated_by_user_id/);
  });

  it('writes no audit row: reading your own record is not HR reading somebody\'s', async () => {
    const { app, db, people } = buildApp(withStored());
    await request(app).get(MINE).set(bearer(tokens.attendance(people.attendance)));
    expect(db.tables.hr_ess_audit || []).toEqual([]);
  });

  it('answers 503 MODULE_NOT_INSTALLED, naming the table, before the migration', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    db.dropTable('hr_ess_personal_details');
    const res = await request(app).get(MINE).set(bearer(tokens.portal(people.faculty)));
    expectRefusal(res, 503, 'MODULE_NOT_INSTALLED');
    expect(res.body.error).toMatch(/hr_ess_personal_details/);
  });

  it('answers 401 with no token', async () => {
    const { app } = buildApp();
    expectRefusal(await request(app).get(MINE), 401, 'NOT_AUTHENTICATED');
  });
});

describe('PUT /api/ess/me/personal', () => {
  it('records the blood group and emergency contact, stamped with who wrote them', async () => {
    const { app, db, people } = buildApp();
    const res = await putMine(app, tokens.portal(people.faculty), {
      blood_group: ' ab+ ', emergency_name: '  Ravi Kumar ', emergency_relation: 'Brother', emergency_phone: '+91 98765 43210',
    });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      personal: {
        ...EMPTY, blood_group: 'AB+', emergency_name: 'Ravi Kumar', emergency_relation: 'Brother', emergency_phone: '9876543210',
        updated_at: NOW.toISOString(), updated_by_name: 'Test CAD Faculty',
      },
    });
    expect(db.tables.hr_ess_personal_details).toEqual([expect.objectContaining({
      employee_id: people.faculty.employee.id, updated_by_user_id: people.faculty.user.id,
    })]);
  });

  it('works for an attendance session, which has no users.id to record', async () => {
    const { app, db, people } = buildApp();
    const res = await putMine(app, tokens.attendance(people.attendance), { blood_group: 'O-' });
    expect(res.status).toBe(200);
    expect(db.tables.hr_ess_personal_details[0]).toMatchObject({ employee_id: people.attendance.employee.id, updated_by_user_id: null, blood_group: 'O-' });
  });

  it('keeps the fields it was not sent, HR\'s included', async () => {
    const { app, people } = buildApp(withStored());
    const res = await putMine(app, tokens.attendance(people.attendance), { blood_group: 'A-' });
    expect(res.body.personal).toMatchObject({ ...FULL, blood_group: 'A-', updated_by_name: 'Test Office Assistant' });
  });

  it('clears the emergency contact with nulls or empty text, all of it at once', async () => {
    const { app, people } = buildApp(withStored());
    const res = await putMine(app, tokens.attendance(people.attendance), { emergency_name: '', emergency_relation: null, emergency_phone: null });
    expect(res.status).toBe(200);
    expect(res.body.personal).toMatchObject({ emergency_name: null, emergency_relation: null, emergency_phone: null, date_of_birth: '1994-05-21' });
  });

  it.each(['date_of_birth', 'address_line1', 'address_line2', 'city', 'state', 'pincode'])(
    'refuses %s with 403 SENSITIVE_FIELD, even beside allowed fields, and changes nothing',
    async (field) => {
      const { app, db, people } = buildApp(withStored());
      const res = await putMine(app, tokens.attendance(people.attendance), { blood_group: 'O+', [field]: FULL[field] });
      expectRefusal(res, 403, 'SENSITIVE_FIELD');
      expect(res.body.error).toBe('Ask HR to change your date of birth or address.');
      expect(db.tables.hr_ess_personal_details[0].blood_group).toBe('B+');
      expect(db.writes()).toEqual([]);
    },
  );

  it('refuses a sensitive field sent as null too: clearing a date of birth is a change', async () => {
    const { app, people } = buildApp(withStored());
    expectRefusal(await putMine(app, tokens.attendance(people.attendance), { date_of_birth: null }), 403, 'SENSITIVE_FIELD');
  });

  it.each([
    ['an empty body', {}, MESSAGES.NOTHING_TO_CHANGE],
    ['a field the server does not take', { blood_group: 'O+', employee_id: 'e0000000-0000-4000-8000-000000000001' }, MESSAGES.UNKNOWN_FIELD],
    ['a blood group not on the list', { blood_group: 'C+' }, MESSAGES.BLOOD_GROUP],
    ['a blood group that is not text', { blood_group: 1 }, MESSAGES.BLOOD_GROUP],
    ['a landline', { emergency_name: 'Ravi', emergency_phone: '0129 2412345' }, MESSAGES.EMERGENCY_PHONE],
    ['nine digits', { emergency_name: 'Ravi', emergency_phone: '987654321' }, MESSAGES.EMERGENCY_PHONE],
    ['a number starting 5', { emergency_name: 'Ravi', emergency_phone: '5876543210' }, MESSAGES.EMERGENCY_PHONE],
    ['a phone as a number', { emergency_name: 'Ravi', emergency_phone: 9876543210 }, MESSAGES.EMERGENCY_PHONE],
    ['a name over 100 characters', { emergency_name: 'x'.repeat(101), emergency_phone: '9876543210' }, MESSAGES.EMERGENCY_NAME],
    ['a relation over 50 characters', { emergency_name: 'Ravi', emergency_relation: 'x'.repeat(51), emergency_phone: '9876543210' }, MESSAGES.EMERGENCY_RELATION],
    ['a name with no phone', { emergency_name: 'Ravi' }, MESSAGES.EMERGENCY_INCOMPLETE],
    ['a phone with no name', { emergency_phone: '9876543210' }, MESSAGES.EMERGENCY_INCOMPLETE],
    ['a relation with no name', { emergency_relation: 'Brother' }, MESSAGES.EMERGENCY_INCOMPLETE],
    ['a list for a body', [{ blood_group: 'O+' }], MESSAGES.BODY_NOT_OBJECT],
  ])('refuses %s with 400', async (_label, body, message) => {
    const { app, people } = buildApp();
    expectInvalid(await putMine(app, tokens.portal(people.faculty), body), message);
  });

  it('refuses to leave half a contact behind when only the phone is cleared', async () => {
    const { app, people } = buildApp(withStored());
    expectInvalid(await putMine(app, tokens.attendance(people.attendance), { emergency_phone: null }), MESSAGES.EMERGENCY_INCOMPLETE);
  });

  it('answers 503 MODULE_NOT_INSTALLED before the migration', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    db.dropTable('hr_ess_personal_details');
    expectRefusal(await putMine(app, tokens.portal(people.faculty), { blood_group: 'O+' }), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('GET /api/ess/hr/employees/:id/personal', () => {
  it.each(CALLERS)('%s', async (who, token) => {
    const { app, people } = buildApp(withStored());
    const res = await request(app).get(theirs(people.attendance.employee.id)).set(bearer(token(people)));
    // Managers included: admin_manager manages the attendance employee and is still refused.
    const refused = guardOutcome(who, HR_ROLES, 'HR_ACCESS_DENIED');
    if (refused) {
      expectRefusal(res, 403, refused);
      expect(JSON.stringify(res.body)).not.toMatch(/1994|Haryana|9876543210/);
    } else {
      expect(res.status).toBe(200);
    }
  });

  it('answers the employee\'s record and writes who looked into the audit trail', async () => {
    const { app, db, people } = buildApp(withStored());
    const res = await request(app).get(theirs(people.attendance.employee.id)).set(bearer(tokens.portal(people.hr_executive)));
    expect(res.body).toEqual({
      employee: { id: people.attendance.employee.id, full_name: 'Test Office Assistant', employee_code: 'RVM-050' },
      personal: { ...FULL, updated_at: '2026-10-10T05:00:00.000Z', updated_by_name: 'Test HR Manager' },
    });
    expect(db.tables.hr_ess_audit).toEqual([{
      id: expect.any(String), at: NOW.toISOString(), actor_user_id: people.hr_executive.user.id,
      actor_employee_id: people.hr_executive.employee.id, actor_name: 'Test HR Executive', action: 'personal_details.read',
      target_employee_id: people.attendance.employee.id, details: {},
    }]);
  });

  it('answers an empty record for somebody with nothing recorded, and still audits the look', async () => {
    const { app, db, people } = buildApp();
    const res = await request(app).get(theirs(people.pune.employee.id)).set(bearer(tokens.portal(people.hr)));
    expect(res.body.personal).toEqual(EMPTY);
    expect(db.tables.hr_ess_audit).toHaveLength(1);
  });

  it('refuses the read with 503 when the audit row cannot be written, so nothing is seen unrecorded', async () => {
    quietErrors();
    const { app, db, people } = buildApp(withStored());
    db.dropTable('hr_ess_audit');
    const res = await request(app).get(theirs(people.attendance.employee.id)).set(bearer(tokens.portal(people.hr)));
    expectRefusal(res, 503, 'MODULE_NOT_INSTALLED');
    expect(res.body.error).toMatch(/hr_ess_audit/);
    expect(JSON.stringify(res.body)).not.toMatch(/1994/);
  });

  it('answers 404 NOT_FOUND for an employee who is not there, and 400 for an id that cannot be one', async () => {
    const { app, db, people } = buildApp();
    expectRefusal(await request(app).get(theirs('e0000000-0000-4000-8000-000000000999')).set(bearer(tokens.portal(people.hr))), 404, 'NOT_FOUND');
    expectInvalid(await request(app).get(theirs('RVM-050')).set(bearer(tokens.portal(people.hr))), MESSAGES.INVALID_ID);
    expect(db.tables.hr_ess_audit || []).toEqual([]);
  });

  it('answers 503 MODULE_NOT_INSTALLED before the migration', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    db.dropTable('hr_ess_personal_details');
    expectRefusal(await request(app).get(theirs(people.attendance.employee.id)).set(bearer(tokens.portal(people.hr))), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('PUT /api/ess/hr/employees/:id/personal', () => {
  it.each(CALLERS)('%s', async (who, token) => {
    const { app, db, people } = buildApp();
    const res = await putTheirs(app, token(people), people.attendance.employee.id, { date_of_birth: '1994-05-21' });
    const refused = guardOutcome(who, HR_ROLES, 'HR_ACCESS_DENIED');
    if (refused) {
      expectRefusal(res, 403, refused);
      expect(db.tables.hr_ess_personal_details || []).toEqual([]);
    } else {
      expect(res.status).toBe(200);
    }
  });

  it('sets every field, stamped with HR\'s name, and audits which fields changed but not their values', async () => {
    const { app, db, people } = buildApp();
    const res = await putTheirs(app, tokens.portal(people.hr), people.attendance.employee.id, FULL);
    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      employee: { id: people.attendance.employee.id, full_name: 'Test Office Assistant', employee_code: 'RVM-050' },
      personal: { ...FULL, updated_at: NOW.toISOString(), updated_by_name: 'Test HR Manager' },
    });
    expect(db.tables.hr_ess_personal_details[0].updated_by_user_id).toBe(people.hr.user.id);
    expect(db.tables.hr_ess_audit).toEqual([expect.objectContaining({
      action: 'personal_details.updated', actor_employee_id: people.hr.employee.id, target_employee_id: people.attendance.employee.id,
      details: {
        fields: ['date_of_birth', 'address_line1', 'address_line2', 'city', 'state', 'pincode',
          'blood_group', 'emergency_name', 'emergency_relation', 'emergency_phone'],
      },
    })]);
    expect(JSON.stringify(db.tables.hr_ess_audit)).not.toMatch(/1994|Haryana|9876543210|Sunita/);
  });

  it('changes only what it is sent, and lists only real changes in the audit', async () => {
    const { app, db, people } = buildApp(withStored());
    const res = await putTheirs(app, tokens.portal(people.super_admin), people.attendance.employee.id, { city: 'Delhi', state: 'Haryana' });
    expect(res.body.personal).toMatchObject({ ...FULL, city: 'Delhi' });
    expect(db.tables.hr_ess_audit[0].details).toEqual({ fields: ['city'] });
  });

  describe('the date of birth', () => {
    // NOW is 16 Oct 2026 in IST, so the latest date of birth is 16 Oct 2010.
    it.each([['1940-01-01'], ['2010-10-16'], ['1994-05-21']])('takes %s', async (dob) => {
      const { app, people } = buildApp();
      expect((await putTheirs(app, tokens.portal(people.hr), people.pune.employee.id, { date_of_birth: dob })).status).toBe(200);
    });

    it.each([['1939-12-31'], ['2010-10-17'], ['2030-01-01'], ['1994-02-30'], ['21-05-1994'], ['1994-5-21'], [19940521]])('refuses %s', async (dob) => {
      const { app, people } = buildApp();
      expectInvalid(await putTheirs(app, tokens.portal(people.hr), people.pune.employee.id, { date_of_birth: dob }), MESSAGES.DATE_OF_BIRTH);
    });

    it('counts sixteen years in IST: at 23:59 UTC on 16 Oct it is already the 17th', async () => {
      const { app, people } = buildApp({ now: new Date('2026-10-16T18:30:00.000Z') });
      const signed = new Date('2026-10-16T18:00:00.000Z');
      expect((await putTheirs(app, tokens.portal(people.hr, signed), people.pune.employee.id, { date_of_birth: '2010-10-17' })).status).toBe(200);
    });

    it('lets somebody born on 29 February turn sixteen on the 28th', async () => {
      const { app, people } = buildApp({ now: new Date('2024-02-28T06:30:00.000Z') });
      const signed = new Date('2024-02-28T06:29:00.000Z');
      expect((await putTheirs(app, tokens.portal(people.hr, signed), people.pune.employee.id, { date_of_birth: '2008-02-28' })).status).toBe(200);
      expectInvalid(await putTheirs(app, tokens.portal(people.hr, signed), people.pune.employee.id, { date_of_birth: '2008-02-29' }), MESSAGES.DATE_OF_BIRTH);
    });
  });

  it.each([
    ['a PIN code of 5 digits', { pincode: '12100' }, MESSAGES.PINCODE],
    ['a PIN code starting 0', { pincode: '012100' }, MESSAGES.PINCODE],
    ['a PIN code with letters', { pincode: '12100A' }, MESSAGES.PINCODE],
    ['a PIN code as a number', { pincode: 121007 }, MESSAGES.PINCODE],
    ['an address line over 200 characters', { address_line1: 'x'.repeat(201) }, MESSAGES.ADDRESS_FIELD],
    ['a city over 80 characters', { city: 'x'.repeat(81) }, MESSAGES.ADDRESS_FIELD],
    ['a state that is not text', { state: ['Haryana'] }, MESSAGES.ADDRESS_FIELD],
    ['a field the server does not take', { aadhaar: '1234 5678 9012' }, MESSAGES.UNKNOWN_FIELD],
    ['an empty body', {}, MESSAGES.NOTHING_TO_CHANGE],
  ])('refuses %s with 400', async (_label, body, message) => {
    const { app, people } = buildApp();
    expectInvalid(await putTheirs(app, tokens.portal(people.hr), people.pune.employee.id, body), message);
  });

  it('refuses an HR person their own record with 409 OWN_RECORD, and lets a colleague change it', async () => {
    const { app, db, people } = buildApp();
    expectRefusal(await putTheirs(app, tokens.portal(people.hr), people.hr.employee.id, { date_of_birth: '1990-01-01' }), 409, 'OWN_RECORD');
    expect(db.tables.hr_ess_personal_details || []).toEqual([]);
    expect((await putTheirs(app, tokens.portal(people.hr_executive), people.hr.employee.id, { date_of_birth: '1990-01-01' })).status).toBe(200);
  });

  it('answers 404 NOT_FOUND for an employee who is not there', async () => {
    const { app, people } = buildApp();
    expectRefusal(await putTheirs(app, tokens.portal(people.hr), 'e0000000-0000-4000-8000-000000000999', { city: 'Delhi' }), 404, 'NOT_FOUND');
  });

  it('still saves when the audit row cannot be written, and puts the entry in the log', async () => {
    const spy = quietErrors();
    const { app, db, people } = buildApp();
    db.dropTable('hr_ess_audit');
    expect((await putTheirs(app, tokens.portal(people.hr), people.pune.employee.id, { city: 'Pune' })).status).toBe(200);
    expect(spy).toHaveBeenCalledWith(expect.stringMatching(/AUDIT NOT WRITTEN.*personal_details\.updated/));
  });

  it('answers 503 MODULE_NOT_INSTALLED before the migration', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    db.dropTable('hr_ess_personal_details');
    expectRefusal(await putTheirs(app, tokens.portal(people.hr), people.pune.employee.id, { city: 'Pune' }), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('two saves of one record at the same moment', () => {
  /**
   * Holds the first save's write until the second save has written, after the first has read:
   * the interleaving in which a save that writes back the whole row it read undoes the other.
   */
  function interleave(db) {
    let firstRead;
    const firstHasRead = new Promise((resolve) => { firstRead = resolve; });
    let secondWrote;
    const secondHasWritten = new Promise((resolve) => { secondWrote = resolve; });
    let reads = 0;
    let writes = 0;
    const realFrom = db.from;
    db.from = (table) => {
      const q = realFrom(table);
      if (table !== 'hr_ess_personal_details') return q;
      const run = q.run.bind(q);
      q.run = async () => {
        if (q.op === 'select') {
          const out = await run();
          reads += 1;
          if (reads === 1) firstRead();
          return out;
        }
        writes += 1;
        if (writes === 1) {
          // Whichever write comes first belongs to the save that read first, which waits.
          await secondHasWritten;
          return run();
        }
        const out = await run();
        secondWrote();
        return out;
      };
      return q;
    };
    return { firstHasRead };
  }

  it("does not let an employee's own save undo HR's change to their date of birth", async () => {
    const { app, db, people } = buildApp({
      setup: (w) => { w.tables.hr_ess_personal_details = [{ employee_id: w.people.faculty.employee.id, date_of_birth: '1990-01-01', updated_at: '2026-10-01T00:00:00.000Z' }]; },
    });
    const { firstHasRead } = interleave(db);
    const target = people.faculty.employee.id;
    const mine = putMine(app, tokens.portal(people.faculty), { blood_group: 'O+' }).then((r) => r);
    await firstHasRead;
    const hr = putTheirs(app, tokens.portal(people.hr), target, { date_of_birth: '1985-05-05' }).then((r) => r);
    const [a, b] = await Promise.all([mine, hr]);
    expect([a.status, b.status]).toEqual([200, 200]);
    const row = db.tables.hr_ess_personal_details.find((r) => r.employee_id === target);
    expect(db.tables.hr_ess_audit.some((x) => x.action === 'personal_details.updated' && x.details.fields.includes('date_of_birth'))).toBe(true);
    expect(row.date_of_birth).toBe('1985-05-05');
    expect(row.blood_group).toBe('O+');
    // The employee is answered the record as it now stands, HR's change included.
    expect(a.body.personal).toMatchObject({ date_of_birth: '1985-05-05', blood_group: 'O+' });
  });

  it('keeps both of two HR people\'s changes to different fields', async () => {
    const { app, db, people } = buildApp(withStored());
    const { firstHasRead } = interleave(db);
    const target = people.attendance.employee.id;
    const first = putTheirs(app, tokens.portal(people.hr), target, { city: 'Gurugram' }).then((r) => r);
    await firstHasRead;
    const second = putTheirs(app, tokens.portal(people.super_admin), target, { pincode: '122001' }).then((r) => r);
    const [a, b] = await Promise.all([first, second]);
    expect([a.status, b.status]).toEqual([200, 200]);
    expect(db.tables.hr_ess_personal_details.find((r) => r.employee_id === target)).toMatchObject({ city: 'Gurugram', pincode: '122001', state: 'Haryana' });
  });

  it('answers 409 RECORD_CHANGED, and changes nothing, when the other save leaves half an emergency contact with this one', async () => {
    const { app, db, people } = buildApp(withStored());
    const { firstHasRead } = interleave(db);
    const target = people.attendance.employee.id;
    // The employee adds a relation to the contact they see; HR, meanwhile, removes the contact.
    const mine = putMine(app, tokens.attendance(people.attendance), { emergency_relation: 'Sister' }).then((r) => r);
    await firstHasRead;
    const hr = putTheirs(app, tokens.portal(people.hr), target, { emergency_name: null, emergency_phone: null, emergency_relation: null }).then((r) => r);
    const [a, b] = await Promise.all([mine, hr]);
    expect(b.status).toBe(200);
    expectRefusal(a, 409, 'RECORD_CHANGED');
    expect(db.tables.hr_ess_personal_details.find((r) => r.employee_id === target))
      .toMatchObject({ emergency_name: null, emergency_phone: null, emergency_relation: null });
  });

  it('writes only the fields sent, the employee id and the stamp', async () => {
    const { app, db, people } = buildApp(withStored());
    expect((await putMine(app, tokens.attendance(people.attendance), { blood_group: 'O+' })).status).toBe(200);
    const write = db.writes().find((w) => w.table === 'hr_ess_personal_details');
    expect(Object.keys(write.values[0]).sort()).toEqual(['blood_group', 'employee_id', 'updated_at', 'updated_by_name', 'updated_by_user_id']);
  });
});
