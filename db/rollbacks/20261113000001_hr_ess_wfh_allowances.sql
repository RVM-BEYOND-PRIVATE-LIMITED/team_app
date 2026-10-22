-- Rollback for db/migrations/20261113000001_hr_ess_wfh_allowances.sql.
--
-- Restores the leave decide function to the version migration 10 wrote (no WFH branch), removes
-- any WFH leave requests so the narrower type CHECK can be put back, restores the CHECK to
-- cl/lwp, and drops the allowance table. Safe to run twice.

DROP TABLE IF EXISTS public.hr_ess_wfh_allowances;

-- A WFH request cannot survive the narrower type CHECK, so the rows go with the type. Guarded so
-- the rollback can be run again after the leave table itself has been rolled back.
DO $wfh$
BEGIN
  IF to_regclass('public.hr_ess_leave_requests') IS NOT NULL THEN
    DELETE FROM public.hr_ess_leave_requests WHERE type = 'wfh';

    ALTER TABLE public.hr_ess_leave_requests
      DROP CONSTRAINT IF EXISTS hr_ess_leave_requests_type_check;
    ALTER TABLE public.hr_ess_leave_requests
      ADD CONSTRAINT hr_ess_leave_requests_type_check
        CHECK (type IN ('cl', 'lwp'));
  END IF;
END
$wfh$;

-- Migration 6 seeded a switched-off wfh limit row; put it back for a rollback that keeps the
-- limits table.
DO $seed$
BEGIN
  IF to_regclass('public.hr_ess_request_limits') IS NOT NULL THEN
    INSERT INTO public.hr_ess_request_limits (type, limit_count, limit_minutes)
      VALUES ('wfh', 0, NULL)
      ON CONFLICT (type) DO NOTHING;
  END IF;
END
$seed$;

DO $restore$
BEGIN
  IF to_regclass('public.hr_ess_leave_requests') IS NOT NULL THEN
    EXECUTE $fn$
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
    $fn$;
  END IF;
END
$restore$;

NOTIFY pgrst, 'reload schema';
