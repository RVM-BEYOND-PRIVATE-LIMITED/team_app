-- Team RVM (ESS): undo the short-leave types (db/migrations/20261111000001_hr_ess_short_leave.sql).
-- Safe to run twice.
--
-- The CHECKs go back to the three-type shapes of 20261106000001, the minutes column goes away,
-- and the decide and cancel functions are re-created as 20261106000004 first wrote them. Nothing
-- the Scheduler owns is touched.

DO $check$
BEGIN
  IF to_regclass('public.hr_ess_attendance_requests') IS NOT NULL THEN
    -- The narrow CHECK refuses a short leave, so none may exist. This deletes nothing: export or
    -- cancel the rows by hand first.
    IF EXISTS (SELECT 1 FROM public.hr_ess_attendance_requests WHERE type = 'short_leave') THEN
      RAISE EXCEPTION 'hr_ess_attendance_requests still holds short-leave rows; export or cancel them before rolling back';
    END IF;

    ALTER TABLE public.hr_ess_attendance_requests
      DROP CONSTRAINT IF EXISTS hr_ess_attendance_requests_shape_chk;
    ALTER TABLE public.hr_ess_attendance_requests
      ADD CONSTRAINT hr_ess_attendance_requests_shape_chk CHECK (
        (type = 'on_duty'      AND place IS NOT NULL AND fix_in IS NULL AND fix_out IS NULL)
        OR (type = 'fix_a_day'  AND place IS NULL AND (fix_in IS NOT NULL OR fix_out IS NOT NULL))
        OR (type = 'excuse_late' AND place IS NULL AND fix_in IS NULL AND fix_out IS NULL)
      );

    ALTER TABLE public.hr_ess_attendance_requests
      DROP CONSTRAINT IF EXISTS hr_ess_attendance_requests_minutes_chk;
    ALTER TABLE public.hr_ess_attendance_requests DROP COLUMN IF EXISTS minutes;

    ALTER TABLE public.hr_ess_attendance_requests
      DROP CONSTRAINT IF EXISTS hr_ess_attendance_requests_type_check;
    ALTER TABLE public.hr_ess_attendance_requests
      ADD CONSTRAINT hr_ess_attendance_requests_type_check
        CHECK (type IN ('on_duty', 'fix_a_day', 'excuse_late'));
  END IF;
END
$check$;

/* ── the two functions as 20261106000004 first wrote them ── */
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
  r             record;
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

  v_boundary := date_trunc('month', v_today::timestamp)::date;
  IF r.day < v_boundary THEN
    IF r.day < (date_trunc('month', v_today::timestamp) - interval '1 month')::date THEN
      RETURN jsonb_build_object('outcome', 'too_old');
    END IF;
    IF extract(day FROM v_today) > 5 THEN
      RETURN jsonb_build_object('outcome', 'cutoff');
    END IF;
  END IF;

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
    v_status := CASE WHEN v_worked >= p_half_day_minutes THEN 'present' ELSE 'half_day' END;
    PERFORM hr_attendance_apply_override(
      r.employee_id, r.day, v_day.branch_id, v_status, NULL, v_in, v_out, v_worked,
      'Fix a day: ' || r.reason, p_decider_user_id, p_decider_name);
    v_written := true;
    v_day_before := CASE WHEN v_had THEN to_jsonb(v_day) END;

  ELSE -- on_duty
    IF r.day <= v_today THEN
      SELECT * INTO v_day FROM hr_staff_attendance
       WHERE employee_id = r.employee_id AND day = r.day
       FOR UPDATE;
      v_had := FOUND;
      SELECT branch_id INTO v_branch FROM hr_employees WHERE id = r.employee_id;
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
  r record;
  v_restored boolean := false;
BEGIN
  SELECT * INTO r FROM hr_ess_attendance_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('outcome', 'not_found'); END IF;
  IF r.status <> 'approved' THEN
    RETURN jsonb_build_object('outcome', 'not_approved', 'request', to_jsonb(r));
  END IF;

  IF r.type = 'excuse_late' THEN
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
    DELETE FROM hr_staff_attendance WHERE employee_id = r.employee_id AND day = r.day;
    v_restored := true;
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

NOTIFY pgrst, 'reload schema';
