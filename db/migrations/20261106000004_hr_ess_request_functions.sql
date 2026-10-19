-- Team RVM (ESS): the request decisions, withdrawals and cancels, and the morning job's own
-- function (tasks C7, C8, C9, C3).
--
-- One database function per request family, which the ESS calls through PostgREST. Each locks
-- the request row, re-checks everything the ESS checked (a second decision on the same request
-- is refused whatever two approvers do at the same moment), writes the official day through the
-- Scheduler's hr_attendance_apply_override (or excuses the late in place, as HR's own
-- excuse-late does), and writes the request's status and history -- all in one transaction.
--
-- The Scheduler's function is NOT safe to call blind: its SQL has no day or status guard (the
-- six-status list and 'future only for leave' live in its controller, attendanceAdminController
-- .js:15,57-60), so every guard the controller applies is re-implemented here, plus the ESS's
-- own reach-back and cut-off. What the controller does AFTER the RPC -- ensureSnapshot and
-- hr_attendance_recompute -- the ESS's Node code does after this function returns (routes/),
-- because both are separate calls in the Scheduler too (attendanceAdminController.js:124-126).
--
-- The outcomes the ESS maps to refusals (routes/decide):
--   not_found        no such request (or, for a withdraw, not the caller's: never leaked)
--   not_pending      already decided, withdrawn or cancelled
--   not_approved     a cancel of something that is not approved
--   note_required    a rejection with no reason (the route refuses this too)
--   too_old          a day before last month: outside the reach-back window
--   cutoff           last month's request acted on after the 5th (the default while decision 6
--                    is open: last month stays open while the IST day of month is 5 or less)
--   future           fix_a_day or excuse_late for a day that has not happened
--   not_late         an excuse of a day that is not a late arrival (the Scheduler's NOT_LATE)
--   times_incomplete the fix would still leave the day without an in or out time
--   day_off          a fix_a_day on a day recorded as leave, a week off or a holiday
--   cl_limit         a second CL in one month (the Scheduler's own rule)
--
-- New functions only (ADR-0021): nothing the Scheduler owns is altered. Safe to run twice.
-- Service role only, as every function here (REVOKE ... FROM PUBLIC, GRANT to service_role).
--
-- Rollback: db/rollbacks/20261106000004_hr_ess_request_functions.sql

/* ── decide an attendance request (on_duty, fix_a_day, excuse_late) ── */
CREATE OR REPLACE FUNCTION public.hr_ess_decide_attendance_request(
  p_request_id           uuid,
  p_decider_employee_id  uuid,
  p_decider_user_id      uuid,
  p_decider_name         text,
  p_approve              boolean,
  p_note                 text,
  p_now                  timestamptz,
  p_half_day_minutes     integer
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  r             hr_ess_attendance_requests;
  v_today       date := (p_now AT TIME ZONE 'Asia/Kolkata')::date;
  v_boundary    date;
  v_day         hr_staff_attendance;
  v_had         boolean;
  v_written     boolean := false;
  v_day_before  jsonb;
  v_in          timestamptz;
  v_out         timestamptz;
  v_worked      integer;
  v_status      text;
  v_branch      uuid;
  v_action      text;
BEGIN
  SELECT * INTO r FROM hr_ess_attendance_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('outcome', 'not_found'); END IF;
  IF r.status <> 'pending' THEN
    RETURN jsonb_build_object('outcome', 'not_pending', 'request', to_jsonb(r));
  END IF;

  -- The reach-back window and the cut-off, re-checked (C12). Last month stays open while the
  -- IST day of month is 5 or less; the same rule is in src/policy/requests.js (PAYROLL_CUTOFF_DAY).
  v_boundary := date_trunc('month', v_today::timestamp)::date;
  IF r.day < v_boundary THEN
    IF r.day < (date_trunc('month', v_today::timestamp) - interval '1 month')::date THEN
      RETURN jsonb_build_object('outcome', 'too_old');
    END IF;
    IF extract(day FROM v_today) > 5 THEN
      RETURN jsonb_build_object('outcome', 'cutoff');
    END IF;
  END IF;

  -- A late or a fix is about a day that has happened; on duty can be approved in advance.
  -- Rejecting is always possible: only an approval writes anything.
  IF p_approve AND r.type <> 'on_duty' AND r.day > v_today THEN
    RETURN jsonb_build_object('outcome', 'future');
  END IF;

  IF NOT p_approve THEN
    IF p_note IS NULL OR length(btrim(p_note)) < 3 THEN
      RETURN jsonb_build_object('outcome', 'note_required');
    END IF;
    UPDATE hr_ess_attendance_requests
       SET status = 'rejected', decided_by_employee_id = p_decider_employee_id,
           decided_by_user_id = p_decider_user_id, decided_by_name = p_decider_name,
           decided_at = p_now, decision_note = btrim(p_note), updated_at = p_now
     WHERE id = r.id
     RETURNING * INTO r;
    INSERT INTO hr_ess_attendance_request_history
      (request_id, at, actor_employee_id, actor_user_id, actor_name, action, note, details)
    VALUES
      (r.id, p_now, p_decider_employee_id, p_decider_user_id, p_decider_name, 'rejected', btrim(p_note),
       jsonb_build_object('type', r.type, 'day', r.day));
    RETURN jsonb_build_object('outcome', 'rejected', 'request', to_jsonb(r));
  END IF;

  IF r.type = 'excuse_late' THEN
    SELECT * INTO v_day FROM hr_staff_attendance
     WHERE employee_id = r.employee_id AND day = r.day
     FOR UPDATE;
    IF NOT FOUND OR (v_day.late_minutes IS NULL AND NOT v_day.late_excused) THEN
      RETURN jsonb_build_object('outcome', 'not_late');
    END IF;
    -- The same fields HR's own excuse-late writes (attendanceAdminController.js:158-164): the
    -- late is still shown, it stops counting. The approver's note wins over the request's reason.
    UPDATE hr_staff_attendance
       SET late_excused = true,
           late_excused_by_name = p_decider_name,
           late_excused_reason = COALESCE(NULLIF(btrim(p_note), ''), r.reason),
           late_excused_at = p_now,
           updated_at = p_now
     WHERE id = v_day.id;
    v_written := true;
    v_day_before := to_jsonb(v_day);

  ELSIF r.type = 'fix_a_day' THEN
    SELECT * INTO v_day FROM hr_staff_attendance
     WHERE employee_id = r.employee_id AND day = r.day
     FOR UPDATE;
    v_had := FOUND;
    IF v_had AND v_day.status IN ('leave', 'week_off', 'holiday') THEN
      RETURN jsonb_build_object('outcome', 'day_off');
    END IF;
    -- A named time wins; a blank one keeps what the day already records -- the controller's own
    -- merge (attendanceAdminController.js:85-96), which is what lets a fix correct one side only.
    v_in := CASE WHEN r.fix_in IS NOT NULL
                 THEN (r.day + r.fix_in) AT TIME ZONE 'Asia/Kolkata'
                 ELSE v_day.first_in END;
    v_out := CASE WHEN r.fix_out IS NOT NULL
                  THEN (r.day + r.fix_out) AT TIME ZONE 'Asia/Kolkata'
                  ELSE v_day.last_out END;
    IF v_in IS NULL OR v_out IS NULL OR v_out <= v_in THEN
      RETURN jsonb_build_object('outcome', 'times_incomplete');
    END IF;
    v_worked := floor(extract(epoch FROM (v_out - v_in)) / 60)::integer;
    -- The day is judged by its times: a fixed day under the half-day threshold stays a half day,
    -- one over it is a present day. Late, early and the month's count are hr_attendance_recompute's
    -- job, which the route runs right after this function, as the Scheduler's controller does.
    v_status := CASE WHEN v_worked >= p_half_day_minutes THEN 'present' ELSE 'half_day' END;
    PERFORM hr_attendance_apply_override(
      r.employee_id, r.day, v_day.branch_id, v_status, NULL, v_in, v_out, v_worked,
      'Fix a day: ' || r.reason, p_decider_user_id, p_decider_name);
    v_written := true;
    v_day_before := CASE WHEN v_had THEN to_jsonb(v_day) END;

  ELSE -- on_duty
    IF r.day <= v_today THEN
      -- Approved on the day or later: write it now. A future day is left to the morning job
      -- (hr_ess_on_duty_apply), because an override would lock a day that has not happened.
      SELECT * INTO v_day FROM hr_staff_attendance
       WHERE employee_id = r.employee_id AND day = r.day
       FOR UPDATE;
      v_had := FOUND;
      SELECT branch_id INTO v_branch FROM hr_employees WHERE id = r.employee_id;
      -- The times the day already records are kept: the override names none (the controller's
      -- own merge, attendanceAdminController.js:85-96).
      PERFORM hr_attendance_apply_override(
        r.employee_id, r.day, COALESCE(v_day.branch_id, v_branch), 'present', NULL,
        v_day.first_in, v_day.last_out, v_day.worked_minutes,
        'On duty: ' || r.place, p_decider_user_id, p_decider_name);
      v_written := true;
      v_day_before := CASE WHEN v_had THEN to_jsonb(v_day) END;
    END IF;
  END IF;

  v_action := 'approved';
  UPDATE hr_ess_attendance_requests
     SET status = 'approved', decided_by_employee_id = p_decider_employee_id,
         decided_by_user_id = p_decider_user_id, decided_by_name = p_decider_name,
         decided_at = p_now, decision_note = NULLIF(btrim(p_note), ''),
         day_before = CASE WHEN v_written THEN v_day_before ELSE day_before END,
         day_written_at = CASE WHEN v_written THEN p_now ELSE day_written_at END,
         updated_at = p_now
   WHERE id = r.id
   RETURNING * INTO r;
  INSERT INTO hr_ess_attendance_request_history
    (request_id, at, actor_employee_id, actor_user_id, actor_name, action, note, details)
  VALUES
    (r.id, p_now, p_decider_employee_id, p_decider_user_id, p_decider_name, v_action,
     NULLIF(btrim(p_note), ''),
     jsonb_build_object('type', r.type, 'day', r.day, 'day_written', v_written));
  RETURN jsonb_build_object('outcome', 'approved', 'request', to_jsonb(r), 'day_written', v_written);
END $$;

/* ── decide a leave request (cl, lwp) ── */
CREATE OR REPLACE FUNCTION public.hr_ess_decide_leave_request(
  p_request_id           uuid,
  p_decider_employee_id  uuid,
  p_decider_user_id      uuid,
  p_decider_name         text,
  p_approve              boolean,
  p_note                 text,
  p_now                  timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  r            hr_ess_leave_requests;
  v_today      date := (p_now AT TIME ZONE 'Asia/Kolkata')::date;
  v_boundary   date;
  v_day        hr_staff_attendance;
  v_had        boolean;
  v_taken      integer;
BEGIN
  SELECT * INTO r FROM hr_ess_leave_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('outcome', 'not_found'); END IF;
  IF r.status <> 'pending' THEN
    RETURN jsonb_build_object('outcome', 'not_pending', 'request', to_jsonb(r));
  END IF;

  v_boundary := date_trunc('month', v_today::timestamp)::date;
  IF r.day < v_boundary THEN
    IF r.day < (date_trunc('month', v_today::timestamp) - interval '1 month')::date THEN
      RETURN jsonb_build_object('outcome', 'too_old');
    END IF;
    IF extract(day FROM v_today) > 5 THEN
      RETURN jsonb_build_object('outcome', 'cutoff');
    END IF;
  END IF;

  IF NOT p_approve THEN
    IF p_note IS NULL OR length(btrim(p_note)) < 3 THEN
      RETURN jsonb_build_object('outcome', 'note_required');
    END IF;
    UPDATE hr_ess_leave_requests
       SET status = 'rejected', decided_by_employee_id = p_decider_employee_id,
           decided_by_user_id = p_decider_user_id, decided_by_name = p_decider_name,
           decided_at = p_now, decision_note = btrim(p_note), updated_at = p_now
     WHERE id = r.id
     RETURNING * INTO r;
    INSERT INTO hr_ess_leave_request_history
      (request_id, at, actor_employee_id, actor_user_id, actor_name, action, note, details)
    VALUES
      (r.id, p_now, p_decider_employee_id, p_decider_user_id, p_decider_name, 'rejected', btrim(p_note),
       jsonb_build_object('type', r.type, 'day', r.day));
    RETURN jsonb_build_object('outcome', 'rejected', 'request', to_jsonb(r));
  END IF;

  -- One CL a month, the Scheduler's own rule (its unique index is the backstop): whatever else
  -- wrote a CL that month counts, and the day being written itself does not.
  IF r.type = 'cl' THEN
    SELECT count(*) INTO v_taken FROM hr_staff_attendance
     WHERE employee_id = r.employee_id AND status = 'leave' AND leave_type = 'cl'
       AND day BETWEEN date_trunc('month', r.day::timestamp)::date
                   AND (date_trunc('month', r.day::timestamp) + interval '1 month')::date - 1
       AND day <> r.day;
    IF v_taken >= 1 THEN RETURN jsonb_build_object('outcome', 'cl_limit'); END IF;
  END IF;

  SELECT * INTO v_day FROM hr_staff_attendance
   WHERE employee_id = r.employee_id AND day = r.day
   FOR UPDATE;
  v_had := FOUND;
  -- Leave may be recorded ahead (the controller's own rule): a future day is accepted for leave
  -- and nothing else. Whatever times the day records are kept (the controller's own merge).
  PERFORM hr_attendance_apply_override(
    r.employee_id, r.day, v_day.branch_id, 'leave', r.type,
    v_day.first_in, v_day.last_out, v_day.worked_minutes,
    r.reason, p_decider_user_id, p_decider_name);

  UPDATE hr_ess_leave_requests
     SET status = 'approved', decided_by_employee_id = p_decider_employee_id,
         decided_by_user_id = p_decider_user_id, decided_by_name = p_decider_name,
         decided_at = p_now, decision_note = NULLIF(btrim(p_note), ''),
         day_before = CASE WHEN v_had THEN to_jsonb(v_day) END, day_written_at = p_now,
         updated_at = p_now
   WHERE id = r.id
   RETURNING * INTO r;
  INSERT INTO hr_ess_leave_request_history
    (request_id, at, actor_employee_id, actor_user_id, actor_name, action, note, details)
  VALUES
    (r.id, p_now, p_decider_employee_id, p_decider_user_id, p_decider_name, 'approved',
     NULLIF(btrim(p_note), ''),
     jsonb_build_object('type', r.type, 'day', r.day, 'day_written', true));
  RETURN jsonb_build_object('outcome', 'approved', 'request', to_jsonb(r), 'day_written', true);
END $$;

/* ── withdraw (while pending, by the employee themselves) ── */
CREATE OR REPLACE FUNCTION public.hr_ess_withdraw_attendance_request(
  p_request_id  uuid,
  p_employee_id uuid,
  p_now         timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  r hr_ess_attendance_requests;
BEGIN
  SELECT * INTO r FROM hr_ess_attendance_requests WHERE id = p_request_id FOR UPDATE;
  -- Somebody else's request is 'not_found': a withdraw never says whether it exists.
  IF NOT FOUND OR r.employee_id <> p_employee_id THEN
    RETURN jsonb_build_object('outcome', 'not_found');
  END IF;
  IF r.status <> 'pending' THEN
    RETURN jsonb_build_object('outcome', 'not_pending', 'request', to_jsonb(r));
  END IF;
  UPDATE hr_ess_attendance_requests
     SET status = 'withdrawn', updated_at = p_now
   WHERE id = r.id
   RETURNING * INTO r;
  INSERT INTO hr_ess_attendance_request_history
    (request_id, at, actor_employee_id, actor_name, action, details)
  VALUES
    (r.id, p_now, r.employee_id, (SELECT full_name FROM hr_employees WHERE id = r.employee_id),
     'withdrawn', jsonb_build_object('type', r.type, 'day', r.day));
  RETURN jsonb_build_object('outcome', 'withdrawn', 'request', to_jsonb(r));
END $$;

CREATE OR REPLACE FUNCTION public.hr_ess_withdraw_leave_request(
  p_request_id  uuid,
  p_employee_id uuid,
  p_now         timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  r hr_ess_leave_requests;
BEGIN
  SELECT * INTO r FROM hr_ess_leave_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND OR r.employee_id <> p_employee_id THEN
    RETURN jsonb_build_object('outcome', 'not_found');
  END IF;
  IF r.status <> 'pending' THEN
    RETURN jsonb_build_object('outcome', 'not_pending', 'request', to_jsonb(r));
  END IF;
  UPDATE hr_ess_leave_requests
     SET status = 'withdrawn', updated_at = p_now
   WHERE id = r.id
   RETURNING * INTO r;
  INSERT INTO hr_ess_leave_request_history
    (request_id, at, actor_employee_id, actor_name, action, details)
  VALUES
    (r.id, p_now, r.employee_id, (SELECT full_name FROM hr_employees WHERE id = r.employee_id),
     'withdrawn', jsonb_build_object('type', r.type, 'day', r.day));
  RETURN jsonb_build_object('outcome', 'withdrawn', 'request', to_jsonb(r));
END $$;

/* ── cancel (HR only, after an approval, restoring the day the approval wrote) ── */
CREATE OR REPLACE FUNCTION public.hr_ess_cancel_attendance_request(
  p_request_id  uuid,
  p_by_employee_id uuid,
  p_by_user_id  uuid,
  p_by_name     text,
  p_reason      text,
  p_now         timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  r hr_ess_attendance_requests;
  v_restored boolean := false;
BEGIN
  SELECT * INTO r FROM hr_ess_attendance_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('outcome', 'not_found'); END IF;
  IF r.status <> 'approved' THEN
    RETURN jsonb_build_object('outcome', 'not_approved', 'request', to_jsonb(r));
  END IF;

  IF r.type = 'excuse_late' THEN
    -- Undo the excuse: the four late_excused fields go back to what the day held before.
    IF r.day_before IS NOT NULL THEN
      UPDATE hr_staff_attendance
         SET late_excused = COALESCE((r.day_before ->> 'late_excused')::boolean, false),
             late_excused_by_name = r.day_before ->> 'late_excused_by_name',
             late_excused_reason = r.day_before ->> 'late_excused_reason',
             late_excused_at = (r.day_before ->> 'late_excused_at')::timestamptz,
             updated_at = p_now
       WHERE employee_id = r.employee_id AND day = r.day;
      v_restored := true;
    END IF;
  ELSIF r.day_before IS NULL THEN
    -- The approval created the day (there was no row); the cancel takes it away.
    DELETE FROM hr_staff_attendance WHERE employee_id = r.employee_id AND day = r.day;
    v_restored := true;
  ELSE
    -- Restore exactly the columns the override wrote, from the row as it was.
    UPDATE hr_staff_attendance
       SET status = r.day_before ->> 'status',
           leave_type = r.day_before ->> 'leave_type',
           note = r.day_before ->> 'note',
           source = r.day_before ->> 'source',
           first_in = (r.day_before ->> 'first_in')::timestamptz,
           last_out = (r.day_before ->> 'last_out')::timestamptz,
           worked_minutes = (r.day_before ->> 'worked_minutes')::integer,
           marked_by = (r.day_before ->> 'marked_by')::uuid,
           marked_by_name = r.day_before ->> 'marked_by_name',
           marked_at = (r.day_before ->> 'marked_at')::timestamptz,
           updated_at = p_now
     WHERE employee_id = r.employee_id AND day = r.day;
    v_restored := true;
  END IF;

  UPDATE hr_ess_attendance_requests
     SET status = 'cancelled', cancelled_by_user_id = p_by_user_id, cancelled_by_name = p_by_name,
         cancelled_at = p_now, cancel_reason = btrim(p_reason), updated_at = p_now
   WHERE id = r.id
   RETURNING * INTO r;
  INSERT INTO hr_ess_attendance_request_history
    (request_id, at, actor_employee_id, actor_user_id, actor_name, action, note, details)
  VALUES
    (r.id, p_now, p_by_employee_id, p_by_user_id, p_by_name, 'cancelled', btrim(p_reason),
     jsonb_build_object('type', r.type, 'day', r.day, 'day_restored', v_restored));
  RETURN jsonb_build_object('outcome', 'cancelled', 'request', to_jsonb(r), 'day_restored', v_restored);
END $$;

CREATE OR REPLACE FUNCTION public.hr_ess_cancel_leave_request(
  p_request_id  uuid,
  p_by_employee_id uuid,
  p_by_user_id  uuid,
  p_by_name     text,
  p_reason      text,
  p_now         timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  r hr_ess_leave_requests;
BEGIN
  SELECT * INTO r FROM hr_ess_leave_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('outcome', 'not_found'); END IF;
  IF r.status <> 'approved' THEN
    RETURN jsonb_build_object('outcome', 'not_approved', 'request', to_jsonb(r));
  END IF;

  IF r.day_before IS NULL THEN
    DELETE FROM hr_staff_attendance WHERE employee_id = r.employee_id AND day = r.day;
  ELSE
    UPDATE hr_staff_attendance
       SET status = r.day_before ->> 'status',
           leave_type = r.day_before ->> 'leave_type',
           note = r.day_before ->> 'note',
           source = r.day_before ->> 'source',
           first_in = (r.day_before ->> 'first_in')::timestamptz,
           last_out = (r.day_before ->> 'last_out')::timestamptz,
           worked_minutes = (r.day_before ->> 'worked_minutes')::integer,
           marked_by = (r.day_before ->> 'marked_by')::uuid,
           marked_by_name = r.day_before ->> 'marked_by_name',
           marked_at = (r.day_before ->> 'marked_at')::timestamptz,
           updated_at = p_now
     WHERE employee_id = r.employee_id AND day = r.day;
  END IF;

  UPDATE hr_ess_leave_requests
     SET status = 'cancelled', cancelled_by_user_id = p_by_user_id, cancelled_by_name = p_by_name,
         cancelled_at = p_now, cancel_reason = btrim(p_reason), updated_at = p_now
   WHERE id = r.id
   RETURNING * INTO r;
  INSERT INTO hr_ess_leave_request_history
    (request_id, at, actor_employee_id, actor_user_id, actor_name, action, note, details)
  VALUES
    (r.id, p_now, p_by_employee_id, p_by_user_id, p_by_name, 'cancelled', btrim(p_reason),
     jsonb_build_object('type', r.type, 'day', r.day, 'day_restored', true));
  RETURN jsonb_build_object('outcome', 'cancelled', 'request', to_jsonb(r), 'day_restored', true);
END $$;

/* ── the on-duty morning job (C3, C7) ── */
/*
 * Writes every approved on_duty request for p_day whose day has no row yet, as present, with the
 * place as the note -- through the Scheduler's override function, so the day is locked exactly as
 * HR's own override locks it. Runs from src/jobs/onDuty.js on boot and then hourly; safe to run
 * again (a written day means the request no longer matches) and one request's failure does not
 * stop the others (each runs in its own subtransaction). The route (jobs) logs the failures for
 * HR and runs hr_attendance_recompute for every employee a row was written for.
 *
 * A day that already has a row is left alone: the person may have punched, HR may have marked
 * it, or an earlier run may have written it.
 */
CREATE OR REPLACE FUNCTION public.hr_ess_on_duty_apply(
  p_day date,
  p_now timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  r           record;
  v_place     text;
  v_branch    uuid;
  v_applied   integer := 0;
  v_failed    jsonb := '[]'::jsonb;
  v_employees uuid[] := '{}';
BEGIN
  FOR r IN
    SELECT q.id, q.employee_id, q.day, q.place, q.decided_by_user_id, q.decided_by_name
      FROM hr_ess_attendance_requests q
     WHERE q.type = 'on_duty' AND q.status = 'approved' AND q.day = p_day
       AND NOT EXISTS (SELECT 1 FROM hr_staff_attendance a
                        WHERE a.employee_id = q.employee_id AND a.day = q.day)
     ORDER BY q.id
     FOR UPDATE OF q
  LOOP
    BEGIN
      SELECT branch_id INTO v_branch FROM hr_employees WHERE id = r.employee_id;
      PERFORM hr_attendance_apply_override(
        r.employee_id, r.day, v_branch, 'present', NULL, NULL, NULL, NULL,
        'On duty: ' || r.place, r.decided_by_user_id,
        COALESCE(r.decided_by_name, 'Team RVM (on duty)'));
      UPDATE hr_ess_attendance_requests
         SET day_before = NULL, day_written_at = p_now, updated_at = p_now
       WHERE id = r.id;
      v_applied := v_applied + 1;
      v_employees := v_employees || r.employee_id;
    EXCEPTION WHEN OTHERS THEN
      v_failed := v_failed || jsonb_build_object(
        'request_id', r.id, 'employee_id', r.employee_id, 'error', SQLERRM);
    END;
  END LOOP;
  RETURN jsonb_build_object('applied', v_applied, 'failed', v_failed, 'employees', to_jsonb(v_employees));
END $$;

/* ── function access: service role only, as every function here ── */
REVOKE EXECUTE ON FUNCTION public.hr_ess_decide_attendance_request(uuid, uuid, uuid, text, boolean, text, timestamptz, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.hr_ess_decide_leave_request(uuid, uuid, uuid, text, boolean, text, timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.hr_ess_withdraw_attendance_request(uuid, uuid, timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.hr_ess_withdraw_leave_request(uuid, uuid, timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.hr_ess_cancel_attendance_request(uuid, uuid, uuid, text, text, timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.hr_ess_cancel_leave_request(uuid, uuid, uuid, text, text, timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.hr_ess_on_duty_apply(date, timestamptz) FROM PUBLIC;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE EXECUTE ON FUNCTION public.hr_ess_decide_attendance_request(uuid, uuid, uuid, text, boolean, text, timestamptz, integer) FROM anon;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_decide_leave_request(uuid, uuid, uuid, text, boolean, text, timestamptz) FROM anon;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_withdraw_attendance_request(uuid, uuid, timestamptz) FROM anon;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_withdraw_leave_request(uuid, uuid, timestamptz) FROM anon;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_cancel_attendance_request(uuid, uuid, uuid, text, text, timestamptz) FROM anon;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_cancel_leave_request(uuid, uuid, uuid, text, text, timestamptz) FROM anon;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_on_duty_apply(date, timestamptz) FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE EXECUTE ON FUNCTION public.hr_ess_decide_attendance_request(uuid, uuid, uuid, text, boolean, text, timestamptz, integer) FROM authenticated;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_decide_leave_request(uuid, uuid, uuid, text, boolean, text, timestamptz) FROM authenticated;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_withdraw_attendance_request(uuid, uuid, timestamptz) FROM authenticated;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_withdraw_leave_request(uuid, uuid, timestamptz) FROM authenticated;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_cancel_attendance_request(uuid, uuid, uuid, text, text, timestamptz) FROM authenticated;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_cancel_leave_request(uuid, uuid, uuid, text, text, timestamptz) FROM authenticated;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_on_duty_apply(date, timestamptz) FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT EXECUTE ON FUNCTION public.hr_ess_decide_attendance_request(uuid, uuid, uuid, text, boolean, text, timestamptz, integer) TO service_role;
    GRANT EXECUTE ON FUNCTION public.hr_ess_decide_leave_request(uuid, uuid, uuid, text, boolean, text, timestamptz) TO service_role;
    GRANT EXECUTE ON FUNCTION public.hr_ess_withdraw_attendance_request(uuid, uuid, timestamptz) TO service_role;
    GRANT EXECUTE ON FUNCTION public.hr_ess_withdraw_leave_request(uuid, uuid, timestamptz) TO service_role;
    GRANT EXECUTE ON FUNCTION public.hr_ess_cancel_attendance_request(uuid, uuid, uuid, text, text, timestamptz) TO service_role;
    GRANT EXECUTE ON FUNCTION public.hr_ess_cancel_leave_request(uuid, uuid, uuid, text, text, timestamptz) TO service_role;
    GRANT EXECUTE ON FUNCTION public.hr_ess_on_duty_apply(date, timestamptz) TO service_role;
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
