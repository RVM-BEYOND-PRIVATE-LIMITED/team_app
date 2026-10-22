-- Team RVM (ESS): work from home for selected employees (KP, 22 Oct 2026).
--
-- WFH is a LEAVE request type ('wfh'), one whole day per request, in the same family, Inbox,
-- chain, decide, withdraw and cancel as CL and LWP. There is no generic request-limit row for it:
-- the per-employee allowance set here IS the limit.
--
--   hr_ess_wfh_allowances   one row per employee HR has selected. is_enabled false switches the
--                           type off for them without losing the agreed limit; monthly_limit_days
--                           is 1 to 31; note is HR's own reminder, up to 300 characters.
--
-- The day itself is written only through the Scheduler's hr_attendance_apply_override, exactly as
-- leave is (ADR-0020): status present, no leave_type, the note 'Work from home: <reason>', the
-- times the day already records kept, and day_before kept for HR's cancel to restore. The
-- Scheduler's tables are not altered (ADR-0018, ADR-0021).
--
-- The decide function is re-created with the WFH branch. On an approval it re-reads the allowance
-- FOR SHARE (so HR cannot disable it between the check and the write), counts the employee's
-- OTHER approved WFH days in the same month, and refuses with outcome wfh_not_allowed or
-- wfh_limit before writing anything. The cancel function needs no change: WFH stores day_before
-- exactly as CL/LWP do, so the existing restore already puts the day back.
--
-- Safe to run twice: the table, its policy/grant block and the CHECK swap are idempotent, and the
-- function is CREATE OR REPLACE.
--
-- Rollback: db/rollbacks/20261113000001_hr_ess_wfh_allowances.sql

CREATE TABLE IF NOT EXISTS public.hr_ess_wfh_allowances (
  employee_id        uuid PRIMARY KEY REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  is_enabled         boolean NOT NULL DEFAULT true,
  monthly_limit_days integer NOT NULL CHECK (monthly_limit_days BETWEEN 1 AND 31),
  note               text CHECK (note IS NULL OR length(btrim(note)) BETWEEN 1 AND 300),
  set_by_user_id     uuid REFERENCES public.users(id) ON DELETE SET NULL,
  set_by_name        text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.hr_ess_wfh_allowances ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON TABLE public.hr_ess_wfh_allowances FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON TABLE public.hr_ess_wfh_allowances FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT SELECT, INSERT, UPDATE ON TABLE public.hr_ess_wfh_allowances TO service_role;
  END IF;
END
$$;

-- WFH is a leave type now: the request table's own CHECK admits it.
ALTER TABLE public.hr_ess_leave_requests
  DROP CONSTRAINT IF EXISTS hr_ess_leave_requests_type_check;
ALTER TABLE public.hr_ess_leave_requests
  ADD CONSTRAINT hr_ess_leave_requests_type_check
    CHECK (type IN ('cl', 'lwp', 'wfh'));

-- There is no generic limit row for WFH: its per-employee allowance is the limit. Migration 6
-- seeded a `wfh` row when the type was switched off; it would only mislead HR's limits screen.
DELETE FROM public.hr_ess_request_limits WHERE type = 'wfh';

/* ── decide a leave request (re-created: the WFH branch writes present, not leave) ── */
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
  v_allowance  hr_ess_wfh_allowances;
  v_branch     uuid;
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

  -- WFH: the allowance is the limit. Re-read it under an exclusive row lock, count the month's
  -- OTHER approved WFH days, and refuse before touching the official day. The request stays
  -- pending. The lock is exclusive on purpose: two approvals for one employee must not both count
  -- the same "other approved" set and both pass; the second waits, sees the first, and refuses.
  IF r.type = 'wfh' THEN
    SELECT * INTO v_allowance FROM hr_ess_wfh_allowances
     WHERE employee_id = r.employee_id
     FOR UPDATE;
    IF NOT FOUND OR NOT v_allowance.is_enabled THEN
      RETURN jsonb_build_object('outcome', 'wfh_not_allowed');
    END IF;
    SELECT count(*) INTO v_taken FROM hr_ess_leave_requests
     WHERE employee_id = r.employee_id AND type = 'wfh' AND status IN ('approved', 'pending')
       AND id <> r.id
       AND day BETWEEN date_trunc('month', r.day::timestamp)::date
                   AND (date_trunc('month', r.day::timestamp) + interval '1 month')::date - 1;
    IF v_taken >= v_allowance.monthly_limit_days THEN
      RETURN jsonb_build_object('outcome', 'wfh_limit');
    END IF;
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

  IF r.type = 'wfh' THEN
    -- Present, with the WFH note; the times the day already records stay, as leave keeps them.
    SELECT branch_id INTO v_branch FROM hr_employees WHERE id = r.employee_id;
    PERFORM hr_attendance_apply_override(
      r.employee_id, r.day, COALESCE(v_day.branch_id, v_branch), 'present', NULL,
      v_day.first_in, v_day.last_out, v_day.worked_minutes,
      'Work from home: ' || r.reason, p_decider_user_id, p_decider_name);
  ELSE
    -- Leave may be recorded ahead (the controller's own rule): a future day is accepted for leave
    -- and nothing else. Whatever times the day records are kept (the controller's own merge).
    PERFORM hr_attendance_apply_override(
      r.employee_id, r.day, v_day.branch_id, 'leave', r.type,
      v_day.first_in, v_day.last_out, v_day.worked_minutes,
      r.reason, p_decider_user_id, p_decider_name);
  END IF;

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

/* ── function access: service role only, as migration 10 keeps it ── */
REVOKE EXECUTE ON FUNCTION public.hr_ess_decide_leave_request(uuid, uuid, uuid, text, boolean, text, timestamptz) FROM PUBLIC;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE EXECUTE ON FUNCTION public.hr_ess_decide_leave_request(uuid, uuid, uuid, text, boolean, text, timestamptz) FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE EXECUTE ON FUNCTION public.hr_ess_decide_leave_request(uuid, uuid, uuid, text, boolean, text, timestamptz) FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT EXECUTE ON FUNCTION public.hr_ess_decide_leave_request(uuid, uuid, uuid, text, boolean, text, timestamptz) TO service_role;
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';
