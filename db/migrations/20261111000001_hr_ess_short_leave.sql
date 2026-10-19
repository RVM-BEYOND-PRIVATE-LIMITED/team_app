-- Team RVM (ESS): short leave (Phase 2D, task C3).
--
-- KP's decision (19 Oct 2026, docs/03-decisions.md): a short leave works by excusing the late it
-- covers. It is filed like the other attendance requests, with the minutes asked for; up to 180
-- minutes a person may ask for in a month (the limit is counted in minutes, not in requests --
-- hr_ess_request_limits already carries the row, seeded by 20261106000000). An approval writes
-- the day exactly as an excuse-late's does -- the late stops counting -- and HR's cancel
-- restores it the same way, so the short leave never invents a second kind of day.
--
-- Three touches, all on the ESS's own table and functions (ADR-0021), and this migration
-- supersedes the "short leave is Phase 2" note in 20261106000001's header:
--   1. the type CHECK admits 'short_leave';
--   2. the new minutes column, whole minutes 1 to 480 (the day has that many at most), and the
--      shape CHECK extended: a short leave carries minutes and nothing of the other types'
--      shape, and no other type carries minutes;
--   3. the decide and cancel functions re-created, the short-leave branch being the same write
--      the excuse-late branch makes (and refusing the same way when the day is not a late).
--
-- Safe to run twice: the CHECKs are dropped and re-added to the same definitions, the column is
-- added only when it is missing, and the functions are CREATE OR REPLACE.
--
-- Rollback: db/rollbacks/20261111000001_hr_ess_short_leave.sql

ALTER TABLE public.hr_ess_attendance_requests
  DROP CONSTRAINT IF EXISTS hr_ess_attendance_requests_type_check;
ALTER TABLE public.hr_ess_attendance_requests
  ADD CONSTRAINT hr_ess_attendance_requests_type_check
    CHECK (type IN ('on_duty', 'fix_a_day', 'excuse_late', 'short_leave'));

ALTER TABLE public.hr_ess_attendance_requests ADD COLUMN IF NOT EXISTS minutes integer;

ALTER TABLE public.hr_ess_attendance_requests
  DROP CONSTRAINT IF EXISTS hr_ess_attendance_requests_minutes_chk;
ALTER TABLE public.hr_ess_attendance_requests
  ADD CONSTRAINT hr_ess_attendance_requests_minutes_chk
    CHECK (minutes IS NULL OR minutes BETWEEN 1 AND 480);

ALTER TABLE public.hr_ess_attendance_requests
  DROP CONSTRAINT IF EXISTS hr_ess_attendance_requests_shape_chk;
ALTER TABLE public.hr_ess_attendance_requests
  ADD CONSTRAINT hr_ess_attendance_requests_shape_chk CHECK (
    (type = 'on_duty'        AND place IS NOT NULL AND fix_in IS NULL AND fix_out IS NULL AND minutes IS NULL)
    OR (type = 'fix_a_day'   AND place IS NULL AND (fix_in IS NOT NULL OR fix_out IS NOT NULL) AND minutes IS NULL)
    OR (type = 'excuse_late' AND place IS NULL AND fix_in IS NULL AND fix_out IS NULL AND minutes IS NULL)
    OR (type = 'short_leave' AND place IS NULL AND fix_in IS NULL AND fix_out IS NULL AND minutes IS NOT NULL)
  );

/* ── decide an attendance request (re-created: the short-leave branch is the excuse-late's) ── */
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

  -- A late, a fix or a short leave is about a day that has happened; on duty can be approved in
  -- advance. Rejecting is always possible: only an approval writes anything.
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

  -- A short leave is decided exactly as an excuse-late is: the late it covers stops counting
  -- (KP, 19 Oct). A day that is not a late arrival is refused, as an excuse's is.
  IF r.type IN ('excuse_late', 'short_leave') THEN
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

/* ── cancel (re-created: a short leave is restored exactly as an excuse-late is) ── */
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

  IF r.type IN ('excuse_late', 'short_leave') THEN
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

/* ── function access: service role only, as the request functions' own migration keeps them ── */
REVOKE EXECUTE ON FUNCTION public.hr_ess_decide_attendance_request(uuid, uuid, uuid, text, boolean, text, timestamptz, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.hr_ess_cancel_attendance_request(uuid, uuid, uuid, text, text, timestamptz) FROM PUBLIC;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE EXECUTE ON FUNCTION public.hr_ess_decide_attendance_request(uuid, uuid, uuid, text, boolean, text, timestamptz, integer) FROM anon;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_cancel_attendance_request(uuid, uuid, uuid, text, text, timestamptz) FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE EXECUTE ON FUNCTION public.hr_ess_decide_attendance_request(uuid, uuid, uuid, text, boolean, text, timestamptz, integer) FROM authenticated;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_cancel_attendance_request(uuid, uuid, uuid, text, text, timestamptz) FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT EXECUTE ON FUNCTION public.hr_ess_decide_attendance_request(uuid, uuid, uuid, text, boolean, text, timestamptz, integer) TO service_role;
    GRANT EXECUTE ON FUNCTION public.hr_ess_cancel_attendance_request(uuid, uuid, uuid, text, text, timestamptz) TO service_role;
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';
