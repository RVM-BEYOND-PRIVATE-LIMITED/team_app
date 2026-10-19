#!/usr/bin/env node
/**
 * The migration test (ADR-0021): team_app's migrations and rollbacks, run for real against a
 * throwaway Postgres. From the repository root: `npm run test:migrations`.
 *
 *   1. Start postgres:17-alpine in Docker with no port published; everything goes through
 *      `docker exec`, so nothing on this machine can reach it and no port can clash.
 *   2. Load db/test/scheduler-snapshot.sql: the Scheduler tables the foreign keys point at.
 *   3. Apply every db/migrations file in order, twice. KP applies them by hand and may run one
 *      again, so each must be safe to re-run.
 *   4. Check that every hr_ess_* table has row-level security on and no policy, so only the
 *      service role reads or writes it.
 *   5. Check that the constraints refuse what the ESS refuses, and that deleting an employee does
 *      what the comments in the migrations say.
 *   6. Apply the rollbacks in reverse order, twice.
 *   7. Check that no hr_ess_* table is left and that the Scheduler tables are as they were, then
 *      apply the migrations once more to show a rolled-back database takes them again.
 *   8. Remove the container, whatever happened.
 *
 * It needs Docker and nothing else: no npm package and no database of anyone's. It never connects
 * to a Supabase project.
 */

const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const DB_DIR = path.join(__dirname, '..');
const MIGRATIONS_DIR = path.join(DB_DIR, 'migrations');
const ROLLBACKS_DIR = path.join(DB_DIR, 'rollbacks');
const SNAPSHOT = path.join(__dirname, 'scheduler-snapshot.sql');

const IMAGE = 'postgres:17-alpine';
const CONTAINER = `team-rvm-migration-test-${process.pid}-${Date.now()}`;
const START_TIMEOUT_MS = 90 * 1000;

// <14 digits>_hr_ess_<module>.sql (ADR-0021).
const MIGRATION_NAME = /^\d{14}_hr_ess_[a-z0-9_]+\.sql$/;

const failures = [];
const ok = (message) => console.log(`ok      ${message}`);
const notOk = (message) => {
  failures.push(message);
  console.log(`NOT OK  ${message}`);
};

const sleep = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);

function docker(args, { input, allowFail = false } = {}) {
  const result = spawnSync('docker', args, { input, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
  if (result.error) throw new Error(`Docker could not be run (${result.error.message}). Is Docker installed and running?`);
  if (result.status !== 0 && !allowFail) {
    throw new Error(`docker ${args[0]} failed (exit ${result.status}):\n${(result.stderr || result.stdout || '').trim()}`);
  }
  return result;
}

// -X: ignore any psqlrc; ON_ERROR_STOP: the first error stops the file and fails the run.
const PSQL = ['exec', '-i', CONTAINER, 'psql', '-X', '-q', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres'];

/** Runs a whole SQL file's text, as KP would paste it into the SQL editor. */
function runSql(label, sql) {
  const result = docker([...PSQL, '-f', '-'], { input: sql, allowFail: true });
  if (result.status !== 0) throw new Error(`${label} failed:\n${(result.stderr || result.stdout).trim()}`);
}

/** One statement's rows, each as a 'a|b|c' line. */
function rows(sql) {
  const result = docker([...PSQL, '-t', '-A', '-F', '|', '-c', sql], { allowFail: true });
  if (result.status !== 0) throw new Error(`This query failed: ${sql}\n${(result.stderr || '').trim()}`);
  return result.stdout.split('\n').map((line) => line.trim()).filter(Boolean);
}

function waitForPostgres() {
  const deadline = Date.now() + START_TIMEOUT_MS;
  while (Date.now() < deadline) {
    // Over TCP inside the container. On first start the image sets the database up on a server
    // that listens on the socket only, then restarts it; a socket check could pass during the
    // set-up and the next statement fail in the restart.
    const ready = docker(['exec', CONTAINER, 'pg_isready', '-h', '127.0.0.1', '-U', 'postgres', '-d', 'postgres'], { allowFail: true });
    if (ready.status === 0) return;
    sleep(500);
  }
  throw new Error(`Postgres did not start within ${START_TIMEOUT_MS / 1000} seconds.`);
}

const read = (file) => fs.readFileSync(file, 'utf8');
const sqlFiles = (dir) => (fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => f.endsWith('.sql')).sort() : []);

/** The hr_ess_* tables each migration says it creates, in the order they are created. */
function tablesCreatedBy(files) {
  const out = [];
  for (const file of files) {
    for (const m of read(path.join(MIGRATIONS_DIR, file)).matchAll(/CREATE TABLE IF NOT EXISTS public\.(hr_ess_[a-z0-9_]+)/g)) out.push(m[1]);
  }
  return out;
}

const hrEssTables = () => rows("SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relkind = 'r' AND left(c.relname, 7) = 'hr_ess_' ORDER BY 1");

/** Every column of the Scheduler's tables, so a migration that altered one shows up. */
const schedulerColumns = () => rows("SELECT table_name || '.' || column_name || ' ' || data_type || ' ' || is_nullable || ' ' || coalesce(column_default, '-') FROM information_schema.columns WHERE table_schema = 'public' AND left(table_name, 7) <> 'hr_ess_' ORDER BY table_name, ordinal_position");

const schedulerConstraints = () => rows("SELECT conrelid::regclass || ' ' || conname || ' ' || pg_get_constraintdef(oid) FROM pg_constraint WHERE connamespace = 'public'::regnamespace AND left(conrelid::regclass::text, 7) <> 'hr_ess_' ORDER BY 1");

/**
 * One statement the database must refuse with this condition, run in its own block so the next
 * check starts clean. The employee and user rows it needs are made inside the block.
 */
function refusal(label, statement, condition = 'check_violation') {
  return {
    label,
    sql: `DO $check$
DECLARE
  e uuid := gen_random_uuid();
  u uuid := gen_random_uuid();
BEGIN
  INSERT INTO public.hr_employees (id) VALUES (e);
  INSERT INTO public.users (id) VALUES (u);
  BEGIN
    ${statement};
    RAISE EXCEPTION 'accepted';
  EXCEPTION WHEN ${condition} THEN NULL;
  END;
END $check$;`,
  };
}

const REFUSALS = [
  refusal('a blood group that is not one of the eight', "INSERT INTO public.hr_ess_personal_details (employee_id, blood_group) VALUES (e, 'Z+')"),
  refusal('a PIN code starting with 0', "INSERT INTO public.hr_ess_personal_details (employee_id, pincode) VALUES (e, '012345')"),
  refusal('a PIN code of five digits', "INSERT INTO public.hr_ess_personal_details (employee_id, pincode) VALUES (e, '11001')"),
  refusal('an emergency phone that is not an Indian mobile', "INSERT INTO public.hr_ess_personal_details (employee_id, emergency_phone) VALUES (e, '5123456789')"),
  refusal('an emergency phone with +91 still on it', "INSERT INTO public.hr_ess_personal_details (employee_id, emergency_phone) VALUES (e, '+919812345678')"),
  refusal('a date of birth before 1940', "INSERT INTO public.hr_ess_personal_details (employee_id, date_of_birth) VALUES (e, DATE '1939-12-31')"),
  refusal('an emergency contact name with no phone', "INSERT INTO public.hr_ess_personal_details (employee_id, emergency_name) VALUES (e, 'Asha Devi')"),
  refusal('an emergency phone with no name', "INSERT INTO public.hr_ess_personal_details (employee_id, emergency_phone) VALUES (e, '9812345678')"),
  refusal('an emergency relation with no name', "INSERT INTO public.hr_ess_personal_details (employee_id, emergency_relation) VALUES (e, 'Mother')"),
  refusal('a second personal-details row for one employee', "INSERT INTO public.hr_ess_personal_details (employee_id) VALUES (e), (e)", 'unique_violation'),
  refusal('personal details for nobody', 'INSERT INTO public.hr_ess_personal_details (employee_id) VALUES (gen_random_uuid())', 'foreign_key_violation'),
  refusal('a data request of an unknown kind', "INSERT INTO public.hr_ess_data_requests (employee_id, kind, details) VALUES (e, 'erase', 'Please erase it')"),
  refusal('a data request with blank details', "INSERT INTO public.hr_ess_data_requests (employee_id, kind, details) VALUES (e, 'delete', '   ')"),
  refusal('a data request over 2000 characters', "INSERT INTO public.hr_ess_data_requests (employee_id, kind, details) VALUES (e, 'delete', repeat('x', 2001))"),
  refusal('a closed data request with no time or resolver', "INSERT INTO public.hr_ess_data_requests (employee_id, kind, details, status) VALUES (e, 'delete', 'Please delete it', 'done')"),
  refusal('an open data request that says it was resolved', "INSERT INTO public.hr_ess_data_requests (employee_id, kind, details, resolved_at, resolved_by_name) VALUES (e, 'delete', 'Please delete it', now(), 'HR')"),
  refusal('a data request in an unknown status', "INSERT INTO public.hr_ess_data_requests (employee_id, kind, details, status, resolved_at, resolved_by_name) VALUES (e, 'delete', 'Please delete it', 'lost', now(), 'HR')"),
  refusal('a sixth open data request for one person', "INSERT INTO public.hr_ess_data_requests (employee_id, kind, details) SELECT e, 'correct', 'Request ' || g FROM generate_series(1, 5) g; INSERT INTO public.hr_ess_data_requests (employee_id, kind, details) VALUES (e, 'correct', 'One too many')"),
  refusal('a resolution note over 1000 characters', "INSERT INTO public.hr_ess_data_requests (employee_id, kind, details, status, resolved_at, resolved_by_name, resolution_note) VALUES (e, 'delete', 'Please delete it', 'done', now(), 'HR', repeat('x', 1001))"),
  refusal('a mocked-location report for a ping', "INSERT INTO public.hr_ess_mock_location_reports (employee_id, kind) VALUES (e, 'ping')"),
  refusal('a mocked-location report with a latitude and no longitude', "INSERT INTO public.hr_ess_mock_location_reports (employee_id, kind, latitude) VALUES (e, 'punch', 28.4)"),
  refusal('a mocked-location report off the globe', "INSERT INTO public.hr_ess_mock_location_reports (employee_id, kind, latitude, longitude) VALUES (e, 'punch', 91, 77)"),
  refusal('a negative accuracy', "INSERT INTO public.hr_ess_mock_location_reports (employee_id, kind, accuracy_m) VALUES (e, 'punch', -1)"),
  refusal('an install id over 128 characters', "INSERT INTO public.hr_ess_mock_location_reports (employee_id, kind, install_id) VALUES (e, 'punch', repeat('x', 129))"),
  refusal('a mocked-location report at a branch that is not there', "INSERT INTO public.hr_ess_mock_location_reports (employee_id, kind, branch_id) VALUES (e, 'punch', gen_random_uuid())", 'foreign_key_violation'),
  refusal('a mocked-location report for nobody', "INSERT INTO public.hr_ess_mock_location_reports (employee_id, kind) VALUES (gen_random_uuid(), 'punch')", 'foreign_key_violation'),
  refusal('a second trade of one Scheduler sign-in', `INSERT INTO public.hr_ess_sessions (id, family_id, employee_id, login_kind, user_id, signed_in_at, install_id, refresh_hash, expires_at)
      VALUES ('5b000000-0000-4000-8000-000000000001', '5b000000-0000-4000-8000-000000000001', e, 'portal', u, '2026-10-16T06:29:00Z', 'install-0123456789abcdef', repeat('a', 64), now() + interval '90 days'),
             ('5b000000-0000-4000-8000-000000000002', '5b000000-0000-4000-8000-000000000002', e, 'portal', u, '2026-10-16T06:29:00Z', 'install-fedcba9876543210', repeat('b', 64), now() + interval '90 days')`, 'unique_violation'),
  refusal('audit details that are not an object', "INSERT INTO public.hr_ess_audit (actor_name, action, details) VALUES ('HR', 'devices.reset', '[]'::jsonb)"),
  refusal('an audit action that is not a dotted name', "INSERT INTO public.hr_ess_audit (actor_name, action) VALUES ('HR', 'Reset Devices')"),
  refusal('an audit row with no actor name', "INSERT INTO public.hr_ess_audit (action) VALUES ('devices.reset')", 'not_null_violation'),
  refusal('an attendance request of a type it does not take', "INSERT INTO public.hr_ess_attendance_requests (employee_id, type, day, reason, place) VALUES (e, 'wfh', DATE '2026-10-16', 'Work from home, please.', 'Home')"),
  refusal('an on-duty request with no place', "INSERT INTO public.hr_ess_attendance_requests (employee_id, type, day, reason) VALUES (e, 'on_duty', DATE '2026-10-16', 'Client visit, please.')"),
  refusal('a fix-a-day request with no times', "INSERT INTO public.hr_ess_attendance_requests (employee_id, type, day, reason) VALUES (e, 'fix_a_day', DATE '2026-10-16', 'I forgot to punch out.')"),
  refusal('an excuse-late request carrying times', "INSERT INTO public.hr_ess_attendance_requests (employee_id, type, day, reason, fix_in) VALUES (e, 'excuse_late', DATE '2026-10-16', 'The bus was late.', TIME '09:00')"),
  refusal('a request reason of four characters', "INSERT INTO public.hr_ess_attendance_requests (employee_id, type, day, reason, place) VALUES (e, 'on_duty', DATE '2026-10-16', 'fix!', 'Site')"),
  refusal('a pending request that says it was decided', "INSERT INTO public.hr_ess_attendance_requests (employee_id, type, day, reason, place, decided_at, decided_by_name) VALUES (e, 'on_duty', DATE '2026-10-16', 'Client visit, please.', 'Site', now(), 'HR')"),
  refusal('a cancelled request with no cancel time', "INSERT INTO public.hr_ess_attendance_requests (employee_id, type, day, reason, place, decided_at, decided_by_name, status) VALUES (e, 'on_duty', DATE '2026-10-16', 'Client visit, please.', 'Site', now(), 'HR', 'cancelled')"),
  refusal('a leave request of a type it does not take', "INSERT INTO public.hr_ess_leave_requests (employee_id, type, day, reason) VALUES (e, 'sick', DATE '2026-10-16', 'I am not well.')"),
  refusal('a request limit of an unknown type', "INSERT INTO public.hr_ess_request_limits (type, limit_count) VALUES ('tea_break', 2)"),
  refusal('a minutes limit kept in the count column', "INSERT INTO public.hr_ess_request_limits (type, limit_count) VALUES ('short_leave', 5)"),
  refusal('a negative request limit', "INSERT INTO public.hr_ess_request_limits (type, limit_count) VALUES ('fix_a_day', -1)"),
  refusal('an archive in an unknown family', "INSERT INTO public.hr_ess_request_archives (family, request_id, employee_id) VALUES ('wall', gen_random_uuid(), e)"),
  refusal('a second archive for the same request and person', "INSERT INTO public.hr_ess_request_archives (family, request_id, employee_id) VALUES ('attendance', '7c000000-0000-4000-8000-000000000001', e), ('attendance', '7c000000-0000-4000-8000-000000000001', e)", 'unique_violation'),
  refusal('a history row with an unknown action', `INSERT INTO public.hr_ess_attendance_requests (id, employee_id, type, day, reason, place)
      VALUES ('7c000000-0000-4000-8000-000000000002', e, 'on_duty', DATE '2026-10-16', 'Client visit, please.', 'Site');
    INSERT INTO public.hr_ess_attendance_request_history (request_id, action)
      VALUES ('7c000000-0000-4000-8000-000000000002', 'read')`),
];

/** Rows the ESS writes must go in, take their defaults, and follow an employee's deletion. */
const ACCEPTED = `DO $check$
DECLARE
  e uuid := gen_random_uuid();
  hr uuid := gen_random_uuid();
  u uuid := gen_random_uuid();
  b uuid := gen_random_uuid();
  r record;
BEGIN
  INSERT INTO public.hr_employees (id) VALUES (e), (hr);
  INSERT INTO public.users (id) VALUES (u);
  INSERT INTO public.hr_branches (id) VALUES (b);

  INSERT INTO public.hr_ess_personal_details (employee_id, date_of_birth, blood_group, address_line1, city, state, pincode,
      emergency_name, emergency_relation, emergency_phone, updated_by_user_id, updated_by_name)
    VALUES (e, DATE '1990-04-12', 'AB+', '12 Sector 15', 'Faridabad', 'Haryana', '121007', 'Asha Devi', 'Mother', '9812345678', u, 'Test Person');
  INSERT INTO public.hr_ess_data_requests (employee_id, kind, details) VALUES (e, 'correct', 'My date of joining is wrong.');
  SELECT status, created_at, id INTO r FROM public.hr_ess_data_requests WHERE employee_id = e;
  IF r.status <> 'open' OR r.created_at IS NULL OR r.id IS NULL THEN RAISE EXCEPTION 'data request defaults'; END IF;
  UPDATE public.hr_ess_data_requests SET status = 'done', resolved_at = now(), resolved_by_user_id = u,
      resolved_by_name = 'Test HR', resolution_note = 'Corrected.' WHERE employee_id = e;
  -- Five open at once is the limit, and a resolved one does not count towards it.
  INSERT INTO public.hr_ess_data_requests (employee_id, kind, details) SELECT e, 'delete', 'Request ' || g FROM generate_series(1, 5) g;
  INSERT INTO public.hr_ess_mock_location_reports (employee_id, branch_id, kind, latitude, longitude, accuracy_m, provider, app_version, install_id, client_at)
    VALUES (e, b, 'punch', 28.4089, 77.3178, 3, 'gps', '1.0.0+1', 'install-1', now());
  INSERT INTO public.hr_ess_mock_location_reports (employee_id, kind) VALUES (e, 'punch');
  INSERT INTO public.hr_ess_audit (actor_user_id, actor_employee_id, actor_name, action, target_employee_id, details)
    VALUES (u, hr, 'Test HR', 'personal_details.read', e, '{"found": true}');
  INSERT INTO public.hr_ess_audit (actor_name, action) VALUES ('Test HR', 'data_request.resolved');
  IF (SELECT details FROM public.hr_ess_audit WHERE actor_employee_id IS NULL AND action = 'data_request.resolved') <> '{}'::jsonb THEN
    RAISE EXCEPTION 'audit details default';
  END IF;

  -- The employee's own rows go with the employee; the audit keeps whose record it was.
  DELETE FROM public.hr_employees WHERE id = e;
  IF EXISTS (SELECT 1 FROM public.hr_ess_personal_details WHERE employee_id = e) THEN RAISE EXCEPTION 'personal details kept'; END IF;
  IF EXISTS (SELECT 1 FROM public.hr_ess_data_requests WHERE employee_id = e) THEN RAISE EXCEPTION 'data requests kept'; END IF;
  IF EXISTS (SELECT 1 FROM public.hr_ess_mock_location_reports WHERE employee_id = e) THEN RAISE EXCEPTION 'reports kept'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.hr_ess_audit WHERE target_employee_id = e) THEN RAISE EXCEPTION 'audit lost the target'; END IF;

  -- A report keeps its place in the list when its branch goes: the branch goes null.
  INSERT INTO public.hr_ess_mock_location_reports (employee_id, branch_id, kind) VALUES (hr, b, 'punch');
  DELETE FROM public.hr_branches WHERE id = b;
  IF NOT EXISTS (SELECT 1 FROM public.hr_ess_mock_location_reports WHERE employee_id = hr AND branch_id IS NULL) THEN RAISE EXCEPTION 'report lost with its branch'; END IF;

  -- The actor's ids go null and the name stays.
  DELETE FROM public.hr_employees WHERE id = hr;
  DELETE FROM public.users WHERE id = u;
  SELECT actor_user_id, actor_employee_id, actor_name INTO r FROM public.hr_ess_audit WHERE target_employee_id = e;
  IF r.actor_user_id IS NOT NULL OR r.actor_employee_id IS NOT NULL OR r.actor_name <> 'Test HR' THEN RAISE EXCEPTION 'audit actor'; END IF;
END $check$;`;

/** The request functions, run for real: decide, withdraw, cancel, the morning job, and the
 * refusals they re-check. Everything the functions write is checked against what the endpoints
 * promise (docs/06-backend-phases.md, Phase 1C). Callers' identities are plain uuids: the
 * functions record them, never verify them (that is employeeAuth's job). */
const REQUEST_FLOW = `DO $check$
DECLARE
  e uuid := gen_random_uuid();
  m uuid := gen_random_uuid();
  u uuid := gen_random_uuid();
  b uuid := gen_random_uuid();
  v_today date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
  v_month date := date_trunc('month', v_today::timestamp)::date;
  v_out jsonb;
  v_row record;
  r_id uuid;
  second_id uuid;
BEGIN
  INSERT INTO public.hr_employees (id, full_name, branch_id) VALUES (e, 'Test Requester', b);
  INSERT INTO public.hr_employees (id, full_name) VALUES (m, 'Test Manager');
  INSERT INTO public.users (id) VALUES (u);
  INSERT INTO public.hr_branches (id) VALUES (b);

  -- The limits are seeded, in the one place HR can change them.
  IF (SELECT count(*) FROM public.hr_ess_request_limits) <> 7 THEN RAISE EXCEPTION 'the limits are not seeded'; END IF;
  IF (SELECT limit_count FROM public.hr_ess_request_limits WHERE type = 'fix_a_day') <> 3 THEN RAISE EXCEPTION 'the fix-a-day limit'; END IF;
  IF (SELECT limit_minutes FROM public.hr_ess_request_limits WHERE type = 'short_leave') <> 180 THEN RAISE EXCEPTION 'the short-leave limit'; END IF;

  -- Withdraw: the person's own, only while pending; nobody else's, and never leaked.
  INSERT INTO public.hr_ess_attendance_requests (employee_id, type, day, reason, place)
    VALUES (e, 'on_duty', v_today - 1, 'Client visit.', 'Faridabad') RETURNING id INTO r_id;
  IF (SELECT action FROM public.hr_ess_attendance_request_history WHERE request_id = r_id) <> 'filed' THEN
    RAISE EXCEPTION 'the filed history row';
  END IF;
  v_out := public.hr_ess_withdraw_attendance_request(r_id, m, now());
  IF v_out ->> 'outcome' <> 'not_found' THEN RAISE EXCEPTION 'a withdraw by somebody else: %', v_out; END IF;
  v_out := public.hr_ess_withdraw_attendance_request(r_id, e, now());
  IF v_out ->> 'outcome' <> 'withdrawn' THEN RAISE EXCEPTION 'the withdraw: %', v_out; END IF;
  v_out := public.hr_ess_withdraw_attendance_request(r_id, e, now());
  IF v_out ->> 'outcome' <> 'not_pending' THEN RAISE EXCEPTION 'a second withdraw: %', v_out; END IF;

  -- On duty on a past day: the approval writes the day; the cancel takes it away again.
  INSERT INTO public.hr_ess_attendance_requests (employee_id, type, day, reason, place)
    VALUES (e, 'on_duty', v_today - 1, 'College drive.', 'Pune centre') RETURNING id INTO r_id;
  v_out := public.hr_ess_decide_attendance_request(r_id, m, u, 'Test Manager', true, NULL, now(), 240);
  IF v_out ->> 'outcome' <> 'approved' OR NOT (v_out ->> 'day_written')::boolean THEN
    RAISE EXCEPTION 'the on-duty approval: %', v_out;
  END IF;
  SELECT status, note, source INTO v_row FROM public.hr_staff_attendance WHERE employee_id = e AND day = v_today - 1;
  IF v_row.status <> 'present' OR v_row.note <> 'On duty: Pune centre' OR v_row.source <> 'override' THEN
    RAISE EXCEPTION 'the on-duty day: %, %, %', v_row.status, v_row.note, v_row.source;
  END IF;
  v_out := public.hr_ess_decide_attendance_request(r_id, m, u, 'Test Manager', true, NULL, now(), 240);
  IF v_out ->> 'outcome' <> 'not_pending' THEN RAISE EXCEPTION 'a second decision: %', v_out; END IF;
  v_out := public.hr_ess_cancel_attendance_request(r_id, m, u, 'Test Manager', 'Not needed any more.', now());
  IF v_out ->> 'outcome' <> 'cancelled' THEN RAISE EXCEPTION 'the cancel: %', v_out; END IF;
  IF EXISTS (SELECT 1 FROM public.hr_staff_attendance WHERE employee_id = e AND day = v_today - 1) THEN
    RAISE EXCEPTION 'the cancelled on-duty day is still there';
  END IF;
  v_out := public.hr_ess_cancel_attendance_request(r_id, m, u, 'Test Manager', 'Again.', now());
  IF v_out ->> 'outcome' <> 'not_approved' THEN RAISE EXCEPTION 'a second cancel: %', v_out; END IF;

  -- Fix a day: the other side of the day is kept, the day is judged by its times, and the cancel
  -- puts back exactly the row the approval found.
  INSERT INTO public.hr_staff_attendance (employee_id, branch_id, day, status, source, first_in)
    VALUES (e, b, v_today - 2, 'absent', 'auto', ((v_today - 2) + TIME '09:00') AT TIME ZONE 'Asia/Kolkata');
  INSERT INTO public.hr_ess_attendance_requests (employee_id, type, day, reason, fix_out)
    VALUES (e, 'fix_a_day', v_today - 2, 'I forgot to punch out.', TIME '18:00') RETURNING id INTO r_id;
  v_out := public.hr_ess_decide_attendance_request(r_id, m, u, 'Test Manager', true, 'Checked with the branch.', now(), 240);
  IF v_out ->> 'outcome' <> 'approved' THEN RAISE EXCEPTION 'the fix approval: %', v_out; END IF;
  SELECT status, first_in, last_out, worked_minutes, source INTO v_row
    FROM public.hr_staff_attendance WHERE employee_id = e AND day = v_today - 2;
  IF v_row.status <> 'present' OR v_row.worked_minutes <> 540 OR v_row.source <> 'override'
     OR v_row.last_out <> (((v_today - 2) + TIME '18:00') AT TIME ZONE 'Asia/Kolkata') THEN
    RAISE EXCEPTION 'the fixed day: %, %, %, %', v_row.status, v_row.worked_minutes, v_row.source, v_row.last_out;
  END IF;
  v_out := public.hr_ess_cancel_attendance_request(r_id, m, u, 'Test Manager', 'Wrong day.', now());
  IF v_out ->> 'outcome' <> 'cancelled' THEN RAISE EXCEPTION 'the fix cancel: %', v_out; END IF;
  SELECT status, first_in, last_out, source INTO v_row
    FROM public.hr_staff_attendance WHERE employee_id = e AND day = v_today - 2;
  IF v_row.status <> 'absent' OR v_row.last_out IS NOT NULL OR v_row.source <> 'auto' THEN
    RAISE EXCEPTION 'the restored day: %, %, %', v_row.status, v_row.last_out, v_row.source;
  END IF;

  -- Excuse a late: the excuse lands on the day (HR's own fields), the cancel takes it back.
  INSERT INTO public.hr_staff_attendance (employee_id, day, status, source, late_minutes)
    VALUES (e, v_today - 3, 'present', 'self_punch', 20);
  INSERT INTO public.hr_ess_attendance_requests (employee_id, type, day, reason)
    VALUES (e, 'excuse_late', v_today - 3, 'The bus broke down.') RETURNING id INTO r_id;
  v_out := public.hr_ess_decide_attendance_request(r_id, m, u, 'Test Manager', true, NULL, now(), 240);
  IF v_out ->> 'outcome' <> 'approved' THEN RAISE EXCEPTION 'the excuse approval: %', v_out; END IF;
  SELECT late_excused, late_excused_by_name, late_excused_reason INTO v_row
    FROM public.hr_staff_attendance WHERE employee_id = e AND day = v_today - 3;
  IF NOT v_row.late_excused OR v_row.late_excused_by_name <> 'Test Manager' OR v_row.late_excused_reason <> 'The bus broke down.' THEN
    RAISE EXCEPTION 'the excused late: %, %, %', v_row.late_excused, v_row.late_excused_by_name, v_row.late_excused_reason;
  END IF;
  v_out := public.hr_ess_cancel_attendance_request(r_id, m, u, 'Test Manager', 'Not the one.', now());
  IF v_out ->> 'outcome' <> 'cancelled' THEN RAISE EXCEPTION 'the excuse cancel: %', v_out; END IF;
  IF (SELECT late_excused FROM public.hr_staff_attendance WHERE employee_id = e AND day = v_today - 3) THEN
    RAISE EXCEPTION 'the excuse is not undone';
  END IF;

  -- Not a late, and the future, are refused; a rejection needs a reason.
  INSERT INTO public.hr_staff_attendance (employee_id, day, status, source) VALUES (e, v_today - 4, 'present', 'self_punch');
  INSERT INTO public.hr_ess_attendance_requests (employee_id, type, day, reason)
    VALUES (e, 'excuse_late', v_today - 4, 'On time, I think.') RETURNING id INTO r_id;
  v_out := public.hr_ess_decide_attendance_request(r_id, m, u, 'Test Manager', true, NULL, now(), 240);
  IF v_out ->> 'outcome' <> 'not_late' THEN RAISE EXCEPTION 'an excuse of a day that is not late: %', v_out; END IF;
  INSERT INTO public.hr_ess_attendance_requests (employee_id, type, day, reason, fix_in, fix_out)
    VALUES (e, 'fix_a_day', v_today + 1, 'While I remember.', TIME '09:00', TIME '18:00') RETURNING id INTO r_id;
  v_out := public.hr_ess_decide_attendance_request(r_id, m, u, 'Test Manager', true, NULL, now(), 240);
  IF v_out ->> 'outcome' <> 'future' THEN RAISE EXCEPTION 'a fix of a future day: %', v_out; END IF;
  v_out := public.hr_ess_decide_attendance_request(r_id, m, u, 'Test Manager', false, NULL, now(), 240);
  IF v_out ->> 'outcome' <> 'note_required' THEN RAISE EXCEPTION 'a rejection with no reason: %', v_out; END IF;
  v_out := public.hr_ess_decide_attendance_request(r_id, m, u, 'Test Manager', false, 'Not yet.', now(), 240);
  IF v_out ->> 'outcome' <> 'rejected' THEN RAISE EXCEPTION 'the rejection: %', v_out; END IF;

  -- One CL a month: the first is approved, a second in the same month is refused, and cancelling
  -- the first makes room again. Leave may be recorded ahead.
  INSERT INTO public.hr_ess_leave_requests (employee_id, type, day, reason)
    VALUES (e, 'cl', v_month + 1, 'Family function.') RETURNING id INTO r_id;
  v_out := public.hr_ess_decide_leave_request(r_id, m, u, 'Test Manager', true, NULL, now());
  IF v_out ->> 'outcome' <> 'approved' THEN RAISE EXCEPTION 'the CL approval: %', v_out; END IF;
  INSERT INTO public.hr_ess_leave_requests (employee_id, type, day, reason)
    VALUES (e, 'cl', v_month + 2, 'One more.') RETURNING id INTO second_id;
  v_out := public.hr_ess_decide_leave_request(second_id, m, u, 'Test Manager', true, NULL, now());
  IF v_out ->> 'outcome' <> 'cl_limit' THEN RAISE EXCEPTION 'a second CL: %', v_out; END IF;
  v_out := public.hr_ess_cancel_leave_request(r_id, m, u, 'Test Manager', 'Moved it.', now());
  IF v_out ->> 'outcome' <> 'cancelled' THEN RAISE EXCEPTION 'the CL cancel: %', v_out; END IF;
  IF EXISTS (SELECT 1 FROM public.hr_staff_attendance WHERE employee_id = e AND day = v_month + 1 AND leave_type = 'cl') THEN
    RAISE EXCEPTION 'the cancelled CL is still on the day';
  END IF;
  v_out := public.hr_ess_decide_leave_request(second_id, m, u, 'Test Manager', true, NULL, now());
  IF v_out ->> 'outcome' <> 'approved' THEN RAISE EXCEPTION 'the CL after the cancel: %', v_out; END IF;

  -- The window: before last month is outside it; last month is open on the 5th and closed on the 6th.
  INSERT INTO public.hr_ess_leave_requests (employee_id, type, day, reason)
    VALUES (e, 'lwp', (v_month - interval '1 month')::date - 1, 'Long ago.') RETURNING id INTO r_id;
  v_out := public.hr_ess_decide_leave_request(r_id, m, u, 'Test Manager', true, NULL, now());
  IF v_out ->> 'outcome' <> 'too_old' THEN RAISE EXCEPTION 'a day before last month: %', v_out; END IF;
  INSERT INTO public.hr_ess_leave_requests (employee_id, type, day, reason)
    VALUES (e, 'lwp', (v_month - interval '1 month')::date + 3, 'Last month, unpaid.') RETURNING id INTO r_id;
  v_out := public.hr_ess_decide_leave_request(r_id, m, u, 'Test Manager', true, NULL,
    ((v_month + interval '5 days' + interval '6 hours') AT TIME ZONE 'Asia/Kolkata'));
  IF v_out ->> 'outcome' <> 'cutoff' THEN RAISE EXCEPTION 'last month after the 5th: %', v_out; END IF;
  v_out := public.hr_ess_decide_leave_request(r_id, m, u, 'Test Manager', true, NULL,
    ((v_month + interval '4 days' + interval '23 hours') AT TIME ZONE 'Asia/Kolkata'));
  IF v_out ->> 'outcome' <> 'approved' THEN RAISE EXCEPTION 'last month on the 5th: %', v_out; END IF;

  -- The morning job: an approved on-duty day with no row is written; a day that already has a row
  -- is left alone; running again changes nothing.
  INSERT INTO public.hr_ess_attendance_requests (employee_id, type, day, reason, place, status, decided_by_name, decided_at)
    VALUES (e, 'on_duty', v_today, 'Away on a course.', 'Ahmedabad', 'approved', 'Test Manager', now());
  v_out := public.hr_ess_on_duty_apply(v_today, now());
  IF (v_out ->> 'applied')::integer <> 1 THEN RAISE EXCEPTION 'the job applied %: %', v_out ->> 'applied', v_out; END IF;
  SELECT status, note INTO v_row FROM public.hr_staff_attendance WHERE employee_id = e AND day = v_today;
  IF v_row.status <> 'present' OR v_row.note <> 'On duty: Ahmedabad' THEN RAISE EXCEPTION 'the job day: %, %', v_row.status, v_row.note; END IF;
  v_out := public.hr_ess_on_duty_apply(v_today, now());
  IF (v_out ->> 'applied')::integer <> 0 THEN RAISE EXCEPTION 'a second run applied %', v_out ->> 'applied'; END IF;

  -- The employee's deletion takes the requests, their history and the archives with it.
  INSERT INTO public.hr_ess_leave_requests (employee_id, type, day, reason) VALUES (e, 'lwp', v_today, 'Unpaid.') RETURNING id INTO r_id;
  INSERT INTO public.hr_ess_request_archives (family, request_id, employee_id) VALUES ('leave', r_id, m);
  DELETE FROM public.hr_employees WHERE id = e;
  IF EXISTS (SELECT 1 FROM public.hr_ess_attendance_requests WHERE employee_id = e) THEN RAISE EXCEPTION 'requests kept'; END IF;
  IF EXISTS (SELECT 1 FROM public.hr_ess_leave_requests WHERE employee_id = e) THEN RAISE EXCEPTION 'leave requests kept'; END IF;
  IF EXISTS (SELECT 1 FROM public.hr_ess_attendance_request_history h
              LEFT JOIN public.hr_ess_attendance_requests q ON q.id = h.request_id
              WHERE q.id IS NULL) THEN RAISE EXCEPTION 'history kept'; END IF;
END $check$;`;

function check(label, fn) {
  try {
    const problem = fn();
    if (problem) notOk(`${label}: ${problem}`);
    else ok(label);
  } catch (e) {
    notOk(`${label}: ${e.message}`);
  }
}

function main() {
  const migrations = sqlFiles(MIGRATIONS_DIR);
  const rollbacks = sqlFiles(ROLLBACKS_DIR);
  if (!migrations.length) throw new Error(`No migrations in ${MIGRATIONS_DIR}.`);

  check('every migration is named <14 digits>_hr_ess_<module>.sql', () => {
    const wrong = migrations.filter((f) => !MIGRATION_NAME.test(f));
    return wrong.length ? `not so named: ${wrong.join(', ')}` : null;
  });
  check('every migration has a rollback of the same name, and every rollback a migration', () => {
    const lonely = [...migrations.filter((f) => !rollbacks.includes(f)), ...rollbacks.filter((f) => !migrations.includes(f))];
    return lonely.length ? `unpaired: ${lonely.join(', ')}` : null;
  });
  const expected = tablesCreatedBy(migrations);

  docker(['version', '--format', '{{.Server.Version}}']);
  console.log(`Starting ${IMAGE} as ${CONTAINER}`);
  docker(['run', '--detach', '--rm', '--name', CONTAINER, '--env', 'POSTGRES_HOST_AUTH_METHOD=trust', IMAGE]);
  try {
    waitForPostgres();
    runSql('db/test/scheduler-snapshot.sql', read(SNAPSHOT));
    const columnsBefore = schedulerColumns();
    const constraintsBefore = schedulerConstraints();

    for (const pass of [1, 2]) {
      for (const file of migrations) {
        check(`apply ${file}${pass === 2 ? ' again' : ''}`, () => runSql(file, read(path.join(MIGRATIONS_DIR, file))));
      }
    }

    check('the migrations create exactly the hr_ess_* tables they name', () => {
      const found = hrEssTables();
      const want = [...expected].sort();
      return JSON.stringify(found) === JSON.stringify(want) ? null : `found ${found.join(', ') || 'none'}; expected ${want.join(', ')}`;
    });
    check('row-level security is on for every hr_ess_* table', () => {
      const off = rows("SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relkind = 'r' AND left(c.relname, 7) = 'hr_ess_' AND NOT c.relrowsecurity ORDER BY 1");
      return off.length ? `off for ${off.join(', ')}` : null;
    });
    check('no hr_ess_* table has a policy, so nobody but the service role gets a row', () => {
      const policies = rows("SELECT tablename || ' ' || policyname FROM pg_policies WHERE schemaname = 'public' AND left(tablename, 7) = 'hr_ess_' ORDER BY 1");
      return policies.length ? `policies: ${policies.join(', ')}` : null;
    });
    check('the Scheduler tables are unchanged by the migrations', () => (
      JSON.stringify(schedulerColumns()) === JSON.stringify(columnsBefore)
        && JSON.stringify(schedulerConstraints()) === JSON.stringify(constraintsBefore) ? null : 'a column or constraint changed'));

    for (const { label, sql } of REFUSALS) check(`refuses ${label}`, () => runSql(label, sql));
    check('takes the rows the ESS writes, fills their defaults, and follows a deleted employee', () => runSql('the accepted rows', ACCEPTED));
    check('the request functions decide, withdraw and cancel as documented', () => runSql('the request flow', REQUEST_FLOW));

    for (const pass of [1, 2]) {
      for (const file of [...rollbacks].reverse()) {
        check(`roll back ${file}${pass === 2 ? ' again' : ''}`, () => runSql(file, read(path.join(ROLLBACKS_DIR, file))));
      }
    }
    check('no hr_ess_* table is left after the rollbacks', () => {
      const left = hrEssTables();
      return left.length ? `still there: ${left.join(', ')}` : null;
    });
    check('the Scheduler tables are unchanged by the rollbacks', () => (
      JSON.stringify(schedulerColumns()) === JSON.stringify(columnsBefore)
        && JSON.stringify(schedulerConstraints()) === JSON.stringify(constraintsBefore) ? null : 'a column or constraint changed'));

    for (const file of migrations) check(`apply ${file} after the rollbacks`, () => runSql(file, read(path.join(MIGRATIONS_DIR, file))));
  } finally {
    docker(['rm', '--force', CONTAINER], { allowFail: true });
    console.log(`Removed ${CONTAINER}`);
  }
}

try {
  main();
} catch (e) {
  notOk(e.message);
}
if (failures.length) {
  console.log(`\n${failures.length} check(s) failed.`);
  process.exit(1);
}
console.log('\nEvery migration check passed.');
