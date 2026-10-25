-- Rollback: 20261114000001_hr_ess_leave_ranges.sql
--
-- Removes the range/half-day columns and puts the single-day decision, cancel and history
-- functions back. The Scheduler's own changes (the CL trigger and the recompute tweak) roll
-- back with Scheduler_Backend 20261114000001_hr_leave_ranges.sql.

DROP FUNCTION IF EXISTS public.hr_ess_leave_working_days(uuid, date, date);
DROP FUNCTION IF EXISTS public.hr_ess_leave_cl_units(uuid, date);
DROP FUNCTION IF EXISTS public.hr_ess_leave_cl_limit();

/* ── the single-day decision again ── */
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

/* ── the single-day cancel again ── */
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

/* ── the history trigger without the new fields ── */
CREATE OR REPLACE FUNCTION public.hr_ess_leave_requests_filed()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO hr_ess_leave_request_history
    (request_id, at, actor_employee_id, actor_name, action, details)
  VALUES
    (NEW.id, NEW.created_at, NEW.employee_id,
     (SELECT full_name FROM hr_employees WHERE id = NEW.employee_id),
     'filed', jsonb_build_object('type', NEW.type, 'day', NEW.day));
  RETURN NEW;
END $$;

ALTER TABLE public.hr_ess_leave_requests
  DROP CONSTRAINT IF EXISTS hr_ess_leave_requests_range_chk,
  DROP CONSTRAINT IF EXISTS hr_ess_leave_requests_portion_chk,
  DROP CONSTRAINT IF EXISTS hr_ess_leave_requests_half_day_chk,
  DROP CONSTRAINT IF EXISTS hr_ess_leave_requests_count_chk;

ALTER TABLE public.hr_ess_leave_requests
  DROP COLUMN IF EXISTS end_day,
  DROP COLUMN IF EXISTS portion,
  DROP COLUMN IF EXISTS day_count,
  DROP COLUMN IF EXISTS working_days,
  DROP COLUMN IF EXISTS days_before;

NOTIFY pgrst, 'reload schema';
