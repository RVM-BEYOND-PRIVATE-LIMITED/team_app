-- Team RVM (ESS): the employee's leave requests (tasks C2, C4).
--
-- One row per request: casual leave (one a month, the Scheduler's own rule) or leave without pay
-- (no limit set yet, still open). Leave can be recorded AHEAD -- a planned CL -- so a future day
-- is accepted, as the Scheduler's own override accepts one for leave only. A HALF-day leave is
-- not offered in this phase: the day model marks a whole day leave, and a half day needs a rule
-- change in the Scheduler's own day (see docs/06-backend-phases.md, Phase 1C).
--
-- The lifecycle is the attendance requests' (hr_ess_attendance_requests), by the same functions
-- and with the same day_before for HR's cancel:
--   hr_ess_decide_leave_request and hr_ess_cancel_leave_request, in
--   db/migrations/20261106000004_hr_ess_request_functions.sql. The CL rule is the Scheduler's
--   own unique index on hr_staff_attendance (one CL a month); the decision function checks it
--   first and the index is the backstop, answered as 409 CL_LIMIT.
--
-- The Scheduler's tables are not altered (ADR-0018, ADR-0021): this table is the ESS's own, and
-- the day is written only through the Scheduler's override function (ADR-0020).
--
-- Rollback: db/rollbacks/20261106000002_hr_ess_leave_requests.sql

CREATE TABLE IF NOT EXISTS public.hr_ess_leave_requests (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id            uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  type                   text NOT NULL CHECK (type IN ('cl', 'lwp')),
  status                 text NOT NULL DEFAULT 'pending'
                           CHECK (status IN ('pending', 'approved', 'rejected', 'withdrawn', 'cancelled')),
  day                    date NOT NULL,
  reason                 text NOT NULL CHECK (length(btrim(reason)) BETWEEN 5 AND 1000),
  day_before             jsonb,
  day_written_at         timestamptz,
  decided_by_employee_id uuid REFERENCES public.hr_employees(id) ON DELETE SET NULL,
  decided_by_user_id     uuid REFERENCES public.users(id) ON DELETE SET NULL,
  decided_by_name        text,
  decided_at             timestamptz,
  decision_note          text CHECK (decision_note IS NULL OR length(btrim(decision_note)) BETWEEN 1 AND 1000),
  cancelled_by_user_id   uuid REFERENCES public.users(id) ON DELETE SET NULL,
  cancelled_by_name      text,
  cancelled_at           timestamptz,
  cancel_reason          text CHECK (cancel_reason IS NULL OR length(btrim(cancel_reason)) BETWEEN 1 AND 200),
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT hr_ess_leave_requests_decision_chk CHECK (
    (status = 'pending'   AND decided_at IS NULL     AND cancelled_at IS NULL)
    OR (status = 'withdrawn' AND decided_at IS NULL  AND cancelled_at IS NULL)
    OR (status IN ('approved', 'rejected') AND decided_at IS NOT NULL AND cancelled_at IS NULL)
    OR (status = 'cancelled' AND decided_at IS NOT NULL AND cancelled_at IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS hr_ess_leave_requests_person_idx
  ON public.hr_ess_leave_requests (employee_id, created_at DESC);
CREATE INDEX IF NOT EXISTS hr_ess_leave_requests_status_idx
  ON public.hr_ess_leave_requests (status, day);
-- "Who else is off that day" reads approved and pending leave requests by day.
CREATE INDEX IF NOT EXISTS hr_ess_leave_requests_day_idx
  ON public.hr_ess_leave_requests (day) WHERE status IN ('pending', 'approved');

CREATE TABLE IF NOT EXISTS public.hr_ess_leave_request_history (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id        uuid NOT NULL REFERENCES public.hr_ess_leave_requests(id) ON DELETE CASCADE,
  at                timestamptz NOT NULL DEFAULT now(),
  actor_employee_id uuid REFERENCES public.hr_employees(id) ON DELETE SET NULL,
  actor_user_id     uuid REFERENCES public.users(id) ON DELETE SET NULL,
  actor_name        text,
  action            text NOT NULL CHECK (action IN ('filed', 'approved', 'rejected', 'withdrawn', 'cancelled')),
  note              text,
  details           jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS hr_ess_leave_request_history_request_idx
  ON public.hr_ess_leave_request_history (request_id, at);

-- 'filed', as for attendance requests.
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

DROP TRIGGER IF EXISTS hr_ess_leave_requests_filed_trg ON public.hr_ess_leave_requests;
CREATE TRIGGER hr_ess_leave_requests_filed_trg
  AFTER INSERT ON public.hr_ess_leave_requests
  FOR EACH ROW EXECUTE FUNCTION public.hr_ess_leave_requests_filed();

ALTER TABLE public.hr_ess_leave_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hr_ess_leave_request_history ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON TABLE public.hr_ess_leave_requests FROM anon;
    REVOKE ALL ON TABLE public.hr_ess_leave_request_history FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON TABLE public.hr_ess_leave_requests FROM authenticated;
    REVOKE ALL ON TABLE public.hr_ess_leave_request_history FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT SELECT, INSERT, UPDATE ON TABLE public.hr_ess_leave_requests TO service_role;
    GRANT SELECT, INSERT ON TABLE public.hr_ess_leave_request_history TO service_role;
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';
