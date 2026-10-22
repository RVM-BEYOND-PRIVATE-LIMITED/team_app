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
  o uuid := gen_random_uuid();
  b uuid := gen_random_uuid();
  u uuid := gen_random_uuid();
BEGIN
  INSERT INTO public.hr_employees (id) VALUES (e), (o);
  INSERT INTO public.hr_branches (id) VALUES (b);
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
  refusal('a push token that is too short', "INSERT INTO public.hr_ess_push_devices (employee_id, token) VALUES (e, 'short')"),
  refusal('a push token with a control character', "INSERT INTO public.hr_ess_push_devices (employee_id, token) VALUES (e, repeat('a', 19) || chr(9))"),
  refusal('a phone that is not Android', "INSERT INTO public.hr_ess_push_devices (employee_id, token, platform) VALUES (e, repeat('a', 20), 'ios')"),
  refusal('a second phone with the same token', "INSERT INTO public.hr_ess_push_devices (employee_id, token) VALUES (e, repeat('a', 20)), (e, repeat('a', 20))", 'unique_violation'),
  refusal('a notification of an unknown category', "INSERT INTO public.hr_ess_notifications (employee_id, category, title, body) VALUES (e, 'wall', 'Hello', 'Hello there.')"),
  refusal('a notification with a blank title', "INSERT INTO public.hr_ess_notifications (employee_id, category, title, body) VALUES (e, 'decisions', '  ', 'Hello there.')"),
  refusal('a notification whose data is not an object', "INSERT INTO public.hr_ess_notifications (employee_id, category, title, body, data) VALUES (e, 'decisions', 'Hello', 'Hello there.', '[]'::jsonb)"),
  refusal('a pushed notification with no mode', "INSERT INTO public.hr_ess_notifications (employee_id, category, title, body, pushed_at) VALUES (e, 'decisions', 'Hello', 'Hello there.', now())"),
  refusal('an unpushed notification with a mode', "INSERT INTO public.hr_ess_notifications (employee_id, category, title, body, push_mode) VALUES (e, 'decisions', 'Hello', 'Hello there.', 'fcm')"),
  refusal('a notification with a negative attempt count', "INSERT INTO public.hr_ess_notifications (employee_id, category, title, body, push_attempts) VALUES (e, 'decisions', 'Hello', 'Hello there.', -1)"),
  refusal('a second notification for the same priority task', `INSERT INTO public.hr_ess_notifications (employee_id, category, title, body, data)
      VALUES (e, 'priority_tasks', 'Task', 'Do the task.', '{"task_id": "7f000000-0000-4000-8000-000000000001"}'::jsonb),
             (e, 'priority_tasks', 'Task', 'Do the task.', '{"task_id": "7f000000-0000-4000-8000-000000000001"}'::jsonb)`, 'unique_violation'),
  refusal('a notification setting for an unknown category', "INSERT INTO public.hr_ess_notification_settings (employee_id, disabled_categories) VALUES (e, ARRAY['wall'])"),
  // F1-F7: the Wall's own tables and rules (db/migrations/20261108000001-3).
  refusal('a wall post of a kind it does not take', "INSERT INTO public.hr_ess_wall_posts (employee_id, kind, body) VALUES (e, 'notice', 'Hello there.')"),
  refusal('a branch post with no branch', "INSERT INTO public.hr_ess_wall_posts (employee_id, scope, body) VALUES (e, 'branch', 'Branch note.')"),
  refusal('an organisation post that names a branch', "INSERT INTO public.hr_ess_wall_posts (employee_id, scope, branch_id, body) VALUES (e, 'org', b, 'Org note.')"),
  refusal('a praise with no badge', "INSERT INTO public.hr_ess_wall_posts (employee_id, kind, body, about_employee_id) VALUES (e, 'praise', 'Well done.', o)"),
  refusal('a praise about yourself', "INSERT INTO public.hr_ess_wall_posts (employee_id, kind, body, badge, about_employee_id) VALUES (e, 'praise', 'Well done.', 'mentor', e)"),
  refusal('a wish with no occasion', "INSERT INTO public.hr_ess_wall_posts (employee_id, kind, body, about_employee_id) VALUES (e, 'wish', 'Many happy returns!', o)"),
  refusal('a wish over 200 characters', "INSERT INTO public.hr_ess_wall_posts (employee_id, kind, body, occasion, about_employee_id) VALUES (e, 'wish', repeat('x', 201), 'birthday', o)"),
  refusal('a poll with no closing day', "INSERT INTO public.hr_ess_wall_posts (employee_id, kind, body) VALUES (e, 'poll', 'Where shall we go?')"),
  refusal('a praise reason of two characters', "INSERT INTO public.hr_ess_wall_posts (employee_id, kind, body, badge, about_employee_id) VALUES (e, 'praise', 'ok', 'mentor', o)"),
  refusal('a hidden post with no reason', "INSERT INTO public.hr_ess_wall_posts (employee_id, body, hidden_at, hidden_by_name) VALUES (e, 'Hello.', now(), 'HR')"),
  refusal('a hide reason of one character', "INSERT INTO public.hr_ess_wall_posts (employee_id, body, hidden_at, hidden_by_name, hide_reason) VALUES (e, 'Hello.', now(), 'HR', 'x')"),
  refusal('a reaction on both a post and a comment', "INSERT INTO public.hr_ess_wall_reactions (post_id, comment_id, employee_id, reaction) VALUES (gen_random_uuid(), gen_random_uuid(), e, 'like')"),
  refusal('a reaction that is not one of the six', "INSERT INTO public.hr_ess_wall_reactions (post_id, employee_id, reaction) VALUES (gen_random_uuid(), e, 'wow')"),
  refusal('a second reaction on the same post by the same person', "INSERT INTO public.hr_ess_wall_posts (id, employee_id, body) VALUES ('a1000000-0000-4000-8000-000000000001', e, 'Hello.'); INSERT INTO public.hr_ess_wall_reactions (post_id, employee_id, reaction) VALUES ('a1000000-0000-4000-8000-000000000001', e, 'like'), ('a1000000-0000-4000-8000-000000000001', e, 'love')", 'unique_violation'),
  refusal('a second vote by the same person on one option', "INSERT INTO public.hr_ess_wall_posts (id, employee_id, kind, body, poll_closes_on) VALUES ('a1000000-0000-4000-8000-000000000003', e, 'poll', 'Where shall we go?', DATE '2026-11-01'); INSERT INTO public.hr_ess_wall_poll_options (id, post_id, option_key, label, position) VALUES ('a3000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000003', 'o1', 'Chaat', 0); INSERT INTO public.hr_ess_wall_poll_votes (post_id, option_id, voter_employee_id) VALUES ('a1000000-0000-4000-8000-000000000003', 'a3000000-0000-4000-8000-000000000001', e), ('a1000000-0000-4000-8000-000000000003', 'a3000000-0000-4000-8000-000000000001', e)", 'unique_violation'),
  refusal('a wish for yourself is refused before the wish book', "INSERT INTO public.hr_ess_wall_posts (id, employee_id, kind, body, occasion, about_employee_id) VALUES ('a1000000-0000-4000-8000-000000000004', e, 'wish', 'Happy birthday to me!', 'birthday', e)"),
  refusal('two wishes for one person in a year', "INSERT INTO public.hr_ess_wall_posts (id, employee_id, kind, body, occasion, about_employee_id) VALUES ('a1000000-0000-4000-8000-000000000005', e, 'wish', 'Many happy returns!', 'birthday', o), ('a1000000-0000-4000-8000-000000000006', e, 'wish', 'And again!', 'birthday', o); INSERT INTO public.hr_ess_wall_wishes (post_id, about_id, wisher_id, occasion, year) VALUES ('a1000000-0000-4000-8000-000000000005', o, e, 'birthday', 2026), ('a1000000-0000-4000-8000-000000000006', o, e, 'birthday', 2026)", 'unique_violation'),
  refusal('the same person twice in one audience', "INSERT INTO public.hr_ess_announcements (id, employee_id, title, body) VALUES ('a5000000-0000-4000-8000-000000000001', e, 'Diwali holiday', 'The office is closed.'); INSERT INTO public.hr_ess_announcement_audience (announcement_id, employee_id) VALUES ('a5000000-0000-4000-8000-000000000001', e), ('a5000000-0000-4000-8000-000000000001', e)", 'unique_violation'),
  refusal('the same person twice in one audience\'s read state', "INSERT INTO public.hr_ess_announcements (id, employee_id, title, body) VALUES ('a5000000-0000-4000-8000-000000000002', e, 'Diwali holiday', 'The office is closed.'); INSERT INTO public.hr_ess_announcement_reads (announcement_id, employee_id) VALUES ('a5000000-0000-4000-8000-000000000002', e), ('a5000000-0000-4000-8000-000000000002', e)", 'unique_violation'),
  refusal('a wish book entry with no post', "INSERT INTO public.hr_ess_wall_wishes (post_id, about_id, wisher_id, occasion, year) VALUES (gen_random_uuid(), o, e, 'birthday', 2026)", 'foreign_key_violation'),
  refusal('an announcement with a duplicate post id', "INSERT INTO public.hr_ess_announcements (id, employee_id, title, body) VALUES ('a5000000-0000-4000-8000-000000000003', e, 'One', 'The office is closed.'), ('a5000000-0000-4000-8000-000000000003', e, 'Two', 'The office is closed.')", 'unique_violation'),
  refusal('a report that names both a post and a comment', "INSERT INTO public.hr_ess_wall_reports (reporter_id, post_id, comment_id, reason) VALUES (e, gen_random_uuid(), gen_random_uuid(), 'Not for the wall.')"),
  refusal('a report with no reason', "INSERT INTO public.hr_ess_wall_reports (reporter_id, post_id, reason) VALUES (e, gen_random_uuid(), 'hm')"),
  refusal('a resolved report with no resolver', "INSERT INTO public.hr_ess_wall_reports (reporter_id, post_id, reason, status) VALUES (e, gen_random_uuid(), 'Not for the wall.', 'kept')"),
  refusal('an open report that says it was answered', "INSERT INTO public.hr_ess_wall_reports (reporter_id, post_id, reason, resolved_at, resolved_by_name) VALUES (e, gen_random_uuid(), 'Not for the wall.', now(), 'HR')"),
  refusal('an announcement that needs an acknowledgement with no closing day', "INSERT INTO public.hr_ess_announcements (employee_id, title, body, needs_ack) VALUES (e, 'Diwali holiday', 'The office is closed.', true)"),
  refusal('an announcement with a closing day and no acknowledgement', "INSERT INTO public.hr_ess_announcements (employee_id, title, body, closes_on) VALUES (e, 'Diwali holiday', 'The office is closed.', DATE '2026-11-05')"),
  refusal('an announcement with a title of two characters', "INSERT INTO public.hr_ess_announcements (employee_id, title, body) VALUES (e, 'Hi', 'The office is closed.')"),
  refusal('an announcement published before it was scheduled', "INSERT INTO public.hr_ess_announcements (employee_id, title, body, publish_at, published_at) VALUES (e, 'Diwali holiday', 'The office is closed.', now(), now() - interval '1 hour')"),
  refusal('an acknowledgement before the read', "INSERT INTO public.hr_ess_announcements (id, employee_id, title, body) VALUES ('a5000000-0000-4000-8000-000000000004', e, 'Diwali holiday', 'The office is closed.'); INSERT INTO public.hr_ess_announcement_reads (announcement_id, employee_id, read_at, ack_at) VALUES ('a5000000-0000-4000-8000-000000000004', e, now(), now() - interval '1 hour')"),
  refusal('a helpdesk ticket with no such category', `INSERT INTO public.hr_ess_helpdesk_tickets (created_by, category_id, priority, subject, body, first_response_due_at, resolution_due_at)
    VALUES (e, gen_random_uuid(), 'medium', 'The lab PCs will not start.', 'Six machines in Lab 2 stay on the boot screen.', now(), now())`, 'foreign_key_violation'),
  refusal('a helpdesk ticket in an unknown status', `INSERT INTO public.hr_ess_helpdesk_tickets (created_by, category_id, priority, subject, body, status, first_response_due_at, resolution_due_at)
    VALUES (e, (SELECT id FROM public.hr_ess_helpdesk_categories WHERE slug = 'it_lab'), 'medium', 'The lab PCs will not start.', 'Six machines in Lab 2 stay on the boot screen.', 'lost', now(), now())`),
  refusal('a helpdesk ticket of an unknown priority', `INSERT INTO public.hr_ess_helpdesk_tickets (created_by, category_id, priority, subject, body, first_response_due_at, resolution_due_at)
    VALUES (e, (SELECT id FROM public.hr_ess_helpdesk_categories WHERE slug = 'it_lab'), 'top', 'The lab PCs will not start.', 'Six machines in Lab 2 stay on the boot screen.', now(), now())`),
  refusal('a helpdesk ticket closed with no time or reason', `INSERT INTO public.hr_ess_helpdesk_tickets (created_by, category_id, priority, subject, body, status, first_response_due_at, resolution_due_at)
    VALUES (e, (SELECT id FROM public.hr_ess_helpdesk_categories WHERE slug = 'it_lab'), 'medium', 'The lab PCs will not start.', 'Six machines in Lab 2 stay on the boot screen.', 'closed', now(), now())`),
  refusal('a helpdesk rating of six', `INSERT INTO public.hr_ess_helpdesk_tickets (created_by, category_id, priority, subject, body, status, closed_at, closing_reason, rating, first_response_due_at, resolution_due_at)
    VALUES (e, (SELECT id FROM public.hr_ess_helpdesk_categories WHERE slug = 'it_lab'), 'medium', 'The lab PCs will not start.', 'Six machines in Lab 2 stay on the boot screen.', 'closed', now(), 'Fixed in the end.', 6, now(), now())`),
  refusal('a helpdesk rating on a ticket that is not closed', `INSERT INTO public.hr_ess_helpdesk_tickets (created_by, category_id, priority, subject, body, rating, first_response_due_at, resolution_due_at)
    VALUES (e, (SELECT id FROM public.hr_ess_helpdesk_categories WHERE slug = 'it_lab'), 'medium', 'The lab PCs will not start.', 'Six machines in Lab 2 stay on the boot screen.', 5, now(), now())`),
  refusal('a helpdesk comment with no body', `INSERT INTO public.hr_ess_helpdesk_tickets (created_by, category_id, priority, subject, body, first_response_due_at, resolution_due_at)
    VALUES (e, (SELECT id FROM public.hr_ess_helpdesk_categories WHERE slug = 'it_lab'), 'medium', 'The lab PCs will not start.', 'Six machines in Lab 2 stay on the boot screen.', now(), now());
    INSERT INTO public.hr_ess_helpdesk_messages (ticket_id, employee_id) SELECT id, e FROM public.hr_ess_helpdesk_tickets WHERE created_by = e`),
  refusal('a helpdesk event with no event name', `INSERT INTO public.hr_ess_helpdesk_tickets (created_by, category_id, priority, subject, body, first_response_due_at, resolution_due_at)
    VALUES (e, (SELECT id FROM public.hr_ess_helpdesk_categories WHERE slug = 'it_lab'), 'medium', 'The lab PCs will not start.', 'Six machines in Lab 2 stay on the boot screen.', now(), now());
    INSERT INTO public.hr_ess_helpdesk_messages (ticket_id, kind) SELECT id, 'event' FROM public.hr_ess_helpdesk_tickets WHERE created_by = e`),
  refusal('a helpdesk subject of two characters', `INSERT INTO public.hr_ess_helpdesk_tickets (created_by, category_id, priority, subject, body, first_response_due_at, resolution_due_at)
    VALUES (e, (SELECT id FROM public.hr_ess_helpdesk_categories WHERE slug = 'it_lab'), 'medium', 'No', 'Six machines in Lab 2 stay on the boot screen.', now(), now())`),
  // G6: the infra link's own shape (db/migrations/20261112000001_hr_ess_infra_links.sql).
  refusal('a skipped infra link that carries a register id', `INSERT INTO public.hr_ess_helpdesk_tickets (created_by, category_id, priority, subject, body, first_response_due_at, resolution_due_at)
    VALUES (e, (SELECT id FROM public.hr_ess_helpdesk_categories WHERE slug = 'it_lab'), 'medium', 'The lab PCs will not start.', 'Six machines in Lab 2 stay on the boot screen.', now(), now());
    INSERT INTO public.hr_ess_infra_links (ticket_id, state, infra_ticket_id)
    SELECT id, 'skipped', gen_random_uuid() FROM public.hr_ess_helpdesk_tickets WHERE created_by = e`),
  refusal('a linked infra link with no register id', `INSERT INTO public.hr_ess_helpdesk_tickets (created_by, category_id, priority, subject, body, first_response_due_at, resolution_due_at)
    VALUES (e, (SELECT id FROM public.hr_ess_helpdesk_categories WHERE slug = 'it_lab'), 'medium', 'The lab PCs will not start.', 'Six machines in Lab 2 stay on the boot screen.', now(), now());
    INSERT INTO public.hr_ess_infra_links (ticket_id, state)
    SELECT id, 'linked' FROM public.hr_ess_helpdesk_tickets WHERE created_by = e`),
  // Phase 2C: the Documents', change requests' and bank details' own tables and rules
  // (db/migrations/20261110000001-3).
  refusal('a document of an unknown type', "INSERT INTO public.hr_ess_documents (employee_id, doc_type, file_name, storage_path, content_type, size_bytes) VALUES (e, 'passport', 'ID card.pdf', 'documents/' || e || '/id.pdf', 'application/pdf', 1000)", 'foreign_key_violation'),
  refusal('an others document that does not say what it is', "INSERT INTO public.hr_ess_documents (employee_id, doc_type, file_name, storage_path, content_type, size_bytes) VALUES (e, 'others', 'Something.pdf', 'documents/' || e || '/s.pdf', 'application/pdf', 1000)"),
  refusal('a change request about a field it does not take', "INSERT INTO public.hr_ess_change_requests (employee_id, field, new_value, reason) VALUES (e, 'email', 'me@example.com', 'It is not my email.')"),
  refusal('a second open change request for the same field', "INSERT INTO public.hr_ess_change_requests (employee_id, field, new_value, reason) VALUES (e, 'address', 'House 14, Sector 22', 'We moved houses.'), (e, 'address', 'House 15, Sector 22', 'We moved again.')", 'unique_violation'),
  refusal('an IFSC of the wrong shape', "INSERT INTO public.hr_ess_bank_details (employee_id, bank_name, account_number, ifsc_code, consent_given_at, consent_name) VALUES (e, 'State Bank of India', '1234567890', 'SBIN1234', now(), 'Test Person')"),
  refusal('an account number with letters in it', "INSERT INTO public.hr_ess_bank_details (employee_id, bank_name, account_number, ifsc_code, consent_given_at, consent_name) VALUES (e, 'State Bank of India', '12345678AB', 'SBIN0001234', now(), 'Test Person')"),
  refusal('a second bank row for one person', "INSERT INTO public.hr_ess_bank_details (employee_id, bank_name, account_number, ifsc_code, consent_given_at, consent_name) VALUES (e, 'State Bank of India', '1234567890', 'SBIN0001234', now(), 'Test Person'), (e, 'HDFC Bank', '1234567891', 'HDFC0001234', now(), 'Test Person')", 'unique_violation'),
  // Phase 2D: the short-leave shapes (20261111000001) and the escalation trail (20261111000002).
  refusal('a short leave with no minutes', "INSERT INTO public.hr_ess_attendance_requests (employee_id, type, day, reason) VALUES (e, 'short_leave', DATE '2026-10-16', 'An hour at the bank.')"),
  refusal('a short leave of no minutes', "INSERT INTO public.hr_ess_attendance_requests (employee_id, type, day, reason, minutes) VALUES (e, 'short_leave', DATE '2026-10-16', 'An hour at the bank.', 0)"),
  refusal('a short leave of more than a day', "INSERT INTO public.hr_ess_attendance_requests (employee_id, type, day, reason, minutes) VALUES (e, 'short_leave', DATE '2026-10-16', 'An hour at the bank.', 481)"),
  refusal('an excuse carrying minutes', "INSERT INTO public.hr_ess_attendance_requests (employee_id, type, day, reason, minutes) VALUES (e, 'excuse_late', DATE '2026-10-16', 'The bus broke down.', 60)"),
  refusal('an escalation of an unknown family', "INSERT INTO public.hr_ess_approval_escalations (family, request_id, to_employee_id, reason) VALUES ('wall', gen_random_uuid(), o, 'Nobody decided it.')"),
  refusal('a second escalation for the same request and person', "INSERT INTO public.hr_ess_approval_escalations (family, request_id, to_employee_id, reason) VALUES ('attendance', '7d000000-0000-4000-8000-000000000001', o, 'Nobody decided it.'), ('attendance', '7d000000-0000-4000-8000-000000000001', o, 'Nobody decided it.')", 'unique_violation'),
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
  v_sl_day date;
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

  -- Short leave (Phase 2D, C3): the approval excuses the late it covers, and the cancel undoes
  -- it. The day is clamped inside the window, so the check holds on any day of the month.
  v_sl_day := greatest(v_month, v_today - 5);
  INSERT INTO public.hr_staff_attendance (employee_id, day, status, source, late_minutes)
    VALUES (e, v_sl_day, 'present', 'self_punch', 45);
  INSERT INTO public.hr_ess_attendance_requests (employee_id, type, day, reason, minutes)
    VALUES (e, 'short_leave', v_sl_day, 'An hour at the bank.', 60) RETURNING id INTO r_id;
  v_out := public.hr_ess_decide_attendance_request(r_id, m, u, 'Test Manager', true, NULL, now(), 240);
  IF v_out ->> 'outcome' <> 'approved' THEN RAISE EXCEPTION 'the short-leave approval: %', v_out; END IF;
  SELECT late_excused, late_excused_by_name INTO v_row
    FROM public.hr_staff_attendance WHERE employee_id = e AND day = v_sl_day;
  IF NOT v_row.late_excused OR v_row.late_excused_by_name <> 'Test Manager' THEN
    RAISE EXCEPTION 'the short-leave excuse: %, %', v_row.late_excused, v_row.late_excused_by_name;
  END IF;
  v_out := public.hr_ess_cancel_attendance_request(r_id, m, u, 'Test Manager', 'Wrong window.', now());
  IF v_out ->> 'outcome' <> 'cancelled' THEN RAISE EXCEPTION 'the short-leave cancel: %', v_out; END IF;
  IF (SELECT late_excused FROM public.hr_staff_attendance WHERE employee_id = e AND day = v_sl_day) THEN
    RAISE EXCEPTION 'the short-leave excuse is not undone';
  END IF;
  DELETE FROM public.hr_staff_attendance WHERE employee_id = e AND day = v_sl_day;

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

/** The Wall's tables as the ESS writes them (tasks F1 to F7): the defaults every row takes, the
 * counters the routes keep, the wish book's one-each rule, and the cascade when an employee goes. */
const WALL_ROWS = `DO $check$
DECLARE
  e uuid := gen_random_uuid();
  o uuid := gen_random_uuid();
  hr uuid := gen_random_uuid();
  u uuid := gen_random_uuid();
  b uuid := gen_random_uuid();
  post uuid;
  comment uuid;
  option_id uuid;
  r record;
BEGIN
  INSERT INTO public.hr_employees (id, full_name, branch_id) VALUES (e, 'Test Author', b), (o, 'Test Other', b), (hr, 'Test HR', b);
  INSERT INTO public.users (id) VALUES (u);
  INSERT INTO public.hr_branches (id) VALUES (b);

  -- A post takes its defaults (scope, empty attachments, counters) and can be edited and hidden.
  INSERT INTO public.hr_ess_wall_posts (employee_id, body) VALUES (e, 'A note for the whole team.') RETURNING id INTO post;
  SELECT scope, attachments, reaction_counts, comment_count, kind INTO r FROM public.hr_ess_wall_posts WHERE id = post;
  IF r.scope <> 'org' OR r.attachments <> '[]'::jsonb OR r.reaction_counts <> '{}'::jsonb
     OR r.comment_count <> 0 OR r.kind <> 'post' THEN
    RAISE EXCEPTION 'post defaults: %, %, %, %, %', r.scope, r.attachments, r.reaction_counts, r.comment_count, r.kind;
  END IF;
  UPDATE public.hr_ess_wall_posts SET edited_at = now(), body = 'Corrected.' WHERE id = post;
  UPDATE public.hr_ess_wall_posts SET hidden_at = now(), hidden_by_user_id = u, hidden_by_name = 'Test HR', hide_reason = 'Not for the wall.' WHERE id = post;
  UPDATE public.hr_ess_wall_posts SET hidden_at = NULL, hidden_by_user_id = NULL, hidden_by_name = NULL, hide_reason = NULL WHERE id = post;

  -- A comment, its replies and the six reactions; the counters are the routes' own.
  INSERT INTO public.hr_ess_wall_comments (post_id, employee_id, body) VALUES (post, o, 'Well said.') RETURNING id INTO comment;
  INSERT INTO public.hr_ess_wall_comments (post_id, employee_id, parent_id, body) VALUES (post, e, comment, 'Thank you.');
  INSERT INTO public.hr_ess_wall_reactions (post_id, employee_id, reaction) VALUES (post, o, 'clap'), (post, hr, 'love');
  INSERT INTO public.hr_ess_wall_reactions (comment_id, employee_id, reaction) VALUES (comment, hr, 'like');
  UPDATE public.hr_ess_wall_posts SET reaction_counts = '{"clap": 1, "love": 1}'::jsonb, comment_count = 2 WHERE id = post;
  IF (SELECT sum((value)::int) FROM jsonb_each_text((SELECT reaction_counts FROM public.hr_ess_wall_posts WHERE id = post))) <> 2 THEN
    RAISE EXCEPTION 'the reaction counts';
  END IF;

  -- A poll with its options and a vote; the option set is frozen by the stamp, and a voter's own
  -- vote is one row per option.
  INSERT INTO public.hr_ess_wall_posts (employee_id, kind, body, poll_closes_on) VALUES (o, 'poll', 'Where shall we go?', DATE '2026-11-01') RETURNING id INTO post;
  INSERT INTO public.hr_ess_wall_poll_options (post_id, option_key, label, position) VALUES (post, 'o1', 'Chaat', 0) RETURNING id INTO option_id;
  INSERT INTO public.hr_ess_wall_poll_options (post_id, option_key, label, position) VALUES (post, 'o2', 'Dosa', 1);
  INSERT INTO public.hr_ess_wall_poll_votes (post_id, option_id, voter_employee_id) VALUES (post, option_id, e);
  SELECT voter_employee_id INTO r FROM public.hr_ess_wall_poll_votes WHERE post_id = post;
  IF r.voter_employee_id <> e THEN RAISE EXCEPTION 'the vote'; END IF;
  UPDATE public.hr_ess_wall_posts SET options_locked_at = now(), poll_closed_at = now() WHERE id = post;

  -- Praise with a badge the catalogue holds, and a wish the wish book keeps once.
  INSERT INTO public.hr_ess_wall_posts (employee_id, kind, body, badge, about_employee_id) VALUES (hr, 'praise', 'Always helping the batch.', 'mentor', o);
  INSERT INTO public.hr_ess_wall_posts (employee_id, kind, body, occasion, about_employee_id) VALUES (hr, 'wish', 'Many happy returns!', 'birthday', o) RETURNING id INTO post;
  INSERT INTO public.hr_ess_wall_wishes (post_id, about_id, wisher_id, occasion, year) VALUES (post, o, hr, 'birthday', 2026);

  -- The mentions a post carries, and a report HR answers.
  INSERT INTO public.hr_ess_wall_mentions (post_id, mentioned_id, mentioned_by_id) VALUES (post, o, hr);
  INSERT INTO public.hr_ess_wall_reports (reporter_id, post_id, reason) VALUES (o, post, 'Not for the wall.');
  UPDATE public.hr_ess_wall_reports SET status = 'kept', resolved_by_user_id = u, resolved_by_name = 'Test HR', resolved_at = now() WHERE reporter_id = o;

  -- An announcement: published at once, its audience resolved, a read with an acknowledgement.
  INSERT INTO public.hr_ess_announcements (employee_id, title, body, needs_ack, closes_on, publish_at, published_at)
    VALUES (hr, 'Diwali holiday', 'The office is closed on 8 November.', true, DATE '2026-11-05', now(), now()) RETURNING id INTO post;
  SELECT audience, read_count, ack_count, pinned INTO r FROM public.hr_ess_announcements WHERE id = post;
  IF r.audience <> '{"all": true}'::jsonb OR r.read_count <> 0 OR r.ack_count <> 0 OR r.pinned THEN
    RAISE EXCEPTION 'announcement defaults: %, %, %, %', r.audience, r.read_count, r.ack_count, r.pinned;
  END IF;
  INSERT INTO public.hr_ess_announcement_audience (announcement_id, employee_id) VALUES (post, e), (post, o);
  INSERT INTO public.hr_ess_announcement_reads (announcement_id, employee_id, ack_at) VALUES (post, e, now());
  IF (SELECT count(*) FROM public.hr_ess_announcement_audience WHERE announcement_id = post) <> 2 THEN
    RAISE EXCEPTION 'the audience rows';
  END IF;

  -- A birthday opt-out, with its default.
  INSERT INTO public.hr_ess_celebration_optouts (employee_id) VALUES (e);
  IF NOT (SELECT hidden FROM public.hr_ess_celebration_optouts WHERE employee_id = e) THEN RAISE EXCEPTION 'opt-out default'; END IF;

  -- The employee's deletion takes every one of their rows with it.
  DELETE FROM public.hr_employees WHERE id = e;
  IF EXISTS (SELECT 1 FROM public.hr_ess_wall_posts WHERE employee_id = e) THEN RAISE EXCEPTION 'posts kept'; END IF;
  IF EXISTS (SELECT 1 FROM public.hr_ess_wall_reactions WHERE employee_id = e) THEN RAISE EXCEPTION 'reactions kept'; END IF;
  IF EXISTS (SELECT 1 FROM public.hr_ess_wall_poll_votes WHERE voter_employee_id = e) THEN RAISE EXCEPTION 'votes kept'; END IF;
  IF EXISTS (SELECT 1 FROM public.hr_ess_wall_wishes WHERE wisher_id = e) THEN RAISE EXCEPTION 'wishes kept'; END IF;
  IF EXISTS (SELECT 1 FROM public.hr_ess_celebration_optouts WHERE employee_id = e) THEN RAISE EXCEPTION 'the opt-out kept'; END IF;
  IF EXISTS (SELECT 1 FROM public.hr_ess_wall_comments WHERE employee_id = e) THEN RAISE EXCEPTION 'comments kept'; END IF;
END $check$;`;

/** The notification tables: defaults, the both-ways push CHECK, the task key, and the cascade. */
const NOTIFICATIONS = `DO $check$
DECLARE
  e uuid := gen_random_uuid();
  other uuid := gen_random_uuid();
  r record;
BEGIN
  INSERT INTO public.hr_employees (id) VALUES (e), (other);

  -- A device registers with its defaults; the same token then moves to another person in place.
  INSERT INTO public.hr_ess_push_devices (employee_id, token, device_label) VALUES (e, repeat('t', 32), 'Pixel 8');
  IF (SELECT platform FROM public.hr_ess_push_devices WHERE employee_id = e) <> 'android' THEN
    RAISE EXCEPTION 'device platform default';
  END IF;
  UPDATE public.hr_ess_push_devices SET employee_id = other WHERE employee_id = e;
  INSERT INTO public.hr_ess_push_devices (employee_id, token) VALUES (e, repeat('u', 32));

  -- A notification takes its defaults, and both directions of the pushed CHECK hold.
  INSERT INTO public.hr_ess_notifications (employee_id, category, title, body)
    VALUES (e, 'decisions', 'Request approved', 'Your CL on 20 Oct was approved.');
  SELECT read_at, pushed_at, push_mode, push_attempts INTO r FROM public.hr_ess_notifications WHERE employee_id = e;
  IF r.read_at IS NOT NULL OR r.pushed_at IS NOT NULL OR r.push_mode IS NOT NULL OR r.push_attempts <> 0 THEN
    RAISE EXCEPTION 'notification defaults';
  END IF;
  UPDATE public.hr_ess_notifications SET read_at = now(), pushed_at = now(), push_mode = 'skipped' WHERE employee_id = e;

  -- One notification per priority task, held by the unique index.
  INSERT INTO public.hr_ess_notifications (employee_id, category, title, body, data)
    VALUES (e, 'priority_tasks', 'Task', 'Do it.', '{"task_id": "7f000000-0000-4000-8000-000000000002"}'::jsonb);
  BEGIN
    INSERT INTO public.hr_ess_notifications (employee_id, category, title, body, data)
      VALUES (e, 'priority_tasks', 'Task', 'Do it.', '{"task_id": "7f000000-0000-4000-8000-000000000002"}'::jsonb);
    RAISE EXCEPTION 'a second task notification was accepted';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  -- Settings: nothing disabled by default, and an array of known categories stored.
  INSERT INTO public.hr_ess_notification_settings (employee_id) VALUES (e);
  IF (SELECT disabled_categories FROM public.hr_ess_notification_settings WHERE employee_id = e) <> '{}'::text[] THEN
    RAISE EXCEPTION 'settings default';
  END IF;
  UPDATE public.hr_ess_notification_settings SET disabled_categories = ARRAY['approvals'] WHERE employee_id = e;

  -- The employee's deletion takes their devices, notifications and settings with it.
  DELETE FROM public.hr_employees WHERE id = e;
  IF EXISTS (SELECT 1 FROM public.hr_ess_notifications WHERE employee_id = e) THEN RAISE EXCEPTION 'notifications kept'; END IF;
  IF EXISTS (SELECT 1 FROM public.hr_ess_notification_settings WHERE employee_id = e) THEN RAISE EXCEPTION 'settings kept'; END IF;
  IF EXISTS (SELECT 1 FROM public.hr_ess_push_devices WHERE employee_id = e) THEN RAISE EXCEPTION 'devices kept'; END IF;
END $check$;`;

/**
 * The Helpdesk's rows: a ticket takes its defaults and its HD- number from the sequence, the
 * thread takes comments and events, a claim stamps the assignee, a close takes a reason and a
 * rating, and the raiser's deletion takes the ticket and its thread with it.
 */
const HELPDESK_ROWS = `DO $check$
DECLARE
  e uuid := gen_random_uuid();
  other uuid := gen_random_uuid();
  ticket uuid;
  new_ref text;
  r record;
  threads integer;
BEGIN
  INSERT INTO public.hr_employees (id) VALUES (e), (other);

  -- A ticket takes its defaults (open, empty attachments, not anonymous, escalation 0) and its
  -- HD- number from the sequence.
  INSERT INTO public.hr_ess_helpdesk_tickets (created_by, category_id, priority, subject, body, first_response_due_at, resolution_due_at)
    VALUES (e, (SELECT id FROM public.hr_ess_helpdesk_categories WHERE slug = 'it_lab'), 'medium', 'The lab PCs will not start.', 'Six machines in Lab 2 stay on the boot screen.', now(), now())
    RETURNING id, ref INTO ticket, new_ref;
  SELECT status, attachments, anonymous, escalation_level INTO r
    FROM public.hr_ess_helpdesk_tickets WHERE id = ticket;
  IF r.status <> 'open' OR r.attachments <> '[]'::jsonb OR r.anonymous OR r.escalation_level <> 0 THEN
    RAISE EXCEPTION 'ticket defaults: %, %, %, %', r.status, r.attachments, r.anonymous, r.escalation_level;
  END IF;
  IF new_ref NOT SIMILAR TO 'HD-[0-9]{4,}' THEN RAISE EXCEPTION 'the ref: %', new_ref; END IF;

  -- The thread: the event rows the server writes and the comments people write.
  INSERT INTO public.hr_ess_helpdesk_messages (ticket_id, kind, event, details) VALUES (ticket, 'event', 'opened', '{}');
  INSERT INTO public.hr_ess_helpdesk_messages (ticket_id, employee_id, kind, body) VALUES (ticket, other, 'comment', 'Replacing the switch today.');
  SELECT count(*) INTO threads FROM public.hr_ess_helpdesk_messages WHERE ticket_id = ticket;
  IF threads <> 2 THEN RAISE EXCEPTION 'the thread rows'; END IF;

  -- A claim stamps the assignee, and the ticket moves to in progress.
  UPDATE public.hr_ess_helpdesk_tickets SET assignee_id = other, claimed_at = now(), status = 'in_progress' WHERE id = ticket;

  -- A close knows when, why and how the answer was.
  UPDATE public.hr_ess_helpdesk_tickets SET status = 'closed', closed_at = now(), closing_reason = 'Fixed in the end.', rating = 5 WHERE id = ticket;
  SELECT rating INTO r FROM public.hr_ess_helpdesk_tickets WHERE id = ticket;
  IF r.rating <> 5 THEN RAISE EXCEPTION 'the rating'; END IF;

  -- The raiser's deletion takes the ticket and its whole thread with it.
  DELETE FROM public.hr_employees WHERE id = e;
  IF EXISTS (SELECT 1 FROM public.hr_ess_helpdesk_tickets WHERE created_by = e) THEN RAISE EXCEPTION 'tickets kept'; END IF;
  IF EXISTS (SELECT 1 FROM public.hr_ess_helpdesk_messages WHERE ticket_id = ticket) THEN RAISE EXCEPTION 'messages kept'; END IF;
END $check$;`;

/**
 * The Documents phase's rows: a document takes its defaults and its review, an `others` upload
 * says what it is, a change request takes its defaults and its one-open-per-field rule, a bank
 * row carries its consent and saves in place, an assignment records who moved a ticket, and the
 * person's deletion takes the rows with it.
 */
const DOCUMENTS_ROWS = `DO $check$
DECLARE
  e uuid := gen_random_uuid();
  other uuid := gen_random_uuid();
  u uuid := gen_random_uuid();
  ticket uuid;
  r record;
BEGIN
  INSERT INTO public.hr_employees (id) VALUES (e), (other);
  INSERT INTO public.users (id) VALUES (u);

  -- A document takes its defaults (pending, nothing reviewed yet).
  INSERT INTO public.hr_ess_documents (employee_id, doc_type, file_name, storage_path, content_type, size_bytes)
    VALUES (e, 'resume', 'Resume.pdf', 'documents/' || e || '/resume.pdf', 'application/pdf', 400000);
  SELECT status, remark, verified_at, rejection_reason INTO r
    FROM public.hr_ess_documents WHERE employee_id = e;
  IF r.status <> 'pending' OR r.remark IS NOT NULL OR r.verified_at IS NOT NULL OR r.rejection_reason IS NOT NULL THEN
    RAISE EXCEPTION 'document defaults';
  END IF;

  -- An "others" upload says what it is; the review stamps verified, and a rejection says why
  -- and drops the verified time the earlier state held.
  INSERT INTO public.hr_ess_documents (employee_id, doc_type, file_name, storage_path, content_type, size_bytes, remark)
    VALUES (e, 'others', 'Sponsorship letter.pdf', 'documents/' || e || '/letter.pdf', 'application/pdf', 250000, 'The marathon sponsorship letter.');
  UPDATE public.hr_ess_documents SET status = 'verified', verified_by_user_id = u, verified_by_name = 'Test HR', verified_at = now()
    WHERE employee_id = e AND doc_type = 'others';
  UPDATE public.hr_ess_documents SET status = 'rejected', verified_by_user_id = u, verified_by_name = 'Test HR', rejection_reason = 'The scan is not readable.'
    WHERE employee_id = e AND doc_type = 'resume';
  SELECT verified_at INTO r FROM public.hr_ess_documents WHERE employee_id = e AND doc_type = 'resume';
  IF r.verified_at IS NOT NULL THEN RAISE EXCEPTION 'a rejection kept its verified time'; END IF;

  -- A change request takes its defaults, is decided, and makes room for the next ask on the field.
  INSERT INTO public.hr_ess_change_requests (employee_id, field, old_value, new_value, reason)
    VALUES (e, 'address', 'House 14, Sector 22', 'House 14, Sector 23', 'We moved next door.');
  SELECT status, decided_at INTO r FROM public.hr_ess_change_requests WHERE employee_id = e;
  IF r.status <> 'open' OR r.decided_at IS NOT NULL THEN RAISE EXCEPTION 'change request defaults'; END IF;
  UPDATE public.hr_ess_change_requests SET status = 'approved', decided_by_user_id = u, decided_by_name = 'Test HR',
      decided_at = now(), decision_note = 'Checked with the office.' WHERE employee_id = e;
  INSERT INTO public.hr_ess_change_requests (employee_id, field, new_value, reason)
    VALUES (e, 'address', 'House 14, Sector 24', 'They built the gate.');

  -- A bank row carries its consent, and a save updates it in place.
  INSERT INTO public.hr_ess_bank_details (employee_id, bank_name, branch_name, account_number, ifsc_code, consent_given_at, consent_name, updated_by_user_id, updated_by_name)
    VALUES (e, 'State Bank of India', 'Faridabad Sector 21', '1234567890', 'SBIN0001234', now(), 'Test Person', u, 'Test Person');
  UPDATE public.hr_ess_bank_details SET account_number = '1234567891' WHERE employee_id = e;
  SELECT account_number INTO r FROM public.hr_ess_bank_details WHERE employee_id = e;
  IF r.account_number <> '1234567891' THEN RAISE EXCEPTION 'the bank save'; END IF;

  -- An assignment records who the ticket went to, and who pointed it there.
  INSERT INTO public.hr_ess_helpdesk_tickets (created_by, category_id, priority, subject, body, first_response_due_at, resolution_due_at)
    VALUES (e, (SELECT id FROM public.hr_ess_helpdesk_categories WHERE slug = 'it_lab'), 'low', 'The library printer jams.', 'Every job takes two sheets at a time.', now(), now())
    RETURNING id INTO ticket;
  INSERT INTO public.hr_ess_helpdesk_assignments (ticket_id, to_employee_id, assigned_by_user_id, assigned_by_name)
    VALUES (ticket, other, u, 'Test HR');

  -- The person's deletion takes the documents, the requests, the bank row and the ticket's
  -- assignment history with it.
  DELETE FROM public.hr_employees WHERE id = e;
  IF EXISTS (SELECT 1 FROM public.hr_ess_documents WHERE employee_id = e) THEN RAISE EXCEPTION 'documents kept'; END IF;
  IF EXISTS (SELECT 1 FROM public.hr_ess_change_requests WHERE employee_id = e) THEN RAISE EXCEPTION 'change requests kept'; END IF;
  IF EXISTS (SELECT 1 FROM public.hr_ess_bank_details WHERE employee_id = e) THEN RAISE EXCEPTION 'bank details kept'; END IF;
  IF EXISTS (SELECT 1 FROM public.hr_ess_helpdesk_assignments WHERE ticket_id = ticket) THEN RAISE EXCEPTION 'assignments kept'; END IF;
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
    check('takes the notifications, their defaults and settings, and follows a deleted employee', () => runSql('the notification rows', NOTIFICATIONS));
    check("takes the Wall's rows, their defaults and counters, and follows a deleted employee", () => runSql('the Wall rows', WALL_ROWS));
    check("takes the Helpdesk's rows, their defaults and thread, and follows a deleted employee", () => runSql('the Helpdesk rows', HELPDESK_ROWS));
    check("takes the Documents' rows, their defaults and review, and follows a deleted employee", () => runSql('the Documents rows', DOCUMENTS_ROWS));

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
