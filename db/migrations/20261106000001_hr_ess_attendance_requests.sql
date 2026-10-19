-- Team RVM (ESS): the employee's attendance requests (tasks C1, C3).
--
-- One row per request an employee files from Home or a day in the calendar: on duty, fix a day,
-- or excuse a late. Work from home is not offered (KP, 16 Oct); a request for it is refused
-- before it reaches this table. Short leave is Phase 2 and has no row here yet.
--
-- The lifecycle and who may move it (docs/06-backend-phases.md, Phase 1C):
--   filed -> pending. The employee may withdraw it while pending (status withdrawn).
--   An approval or rejection is written by hr_ess_decide_attendance_request
--   (db/migrations/20261106000004_hr_ess_request_functions.sql), which locks the row, re-checks
--   it and writes the official day through the Scheduler's hr_attendance_apply_override (or
--   excuses the late), in one transaction. A second decision finds the row decided and is
--   refused (409), whatever two approvers do at the same moment.
--   After an approval, only HR cancels (status cancelled), restoring the day it wrote: the day
--   row as it was before the approval is kept in day_before, NULL meaning there was no row.
--
-- The Scheduler's tables are not altered (ADR-0018, ADR-0021): this table is the ESS's own, and
-- the day is written only through the Scheduler's override function (ADR-0020). The one-CL rule
-- stays where it lives, the Scheduler's own unique index on hr_staff_attendance; the decision
-- function checks it first and the index is the backstop.
--
-- The CHECKs repeat what the ESS validates, as a backstop: the shape of each type, the decision
-- fields matching the status, and the reason's length. "Safe to run twice" holds here too.
--
-- Rollback: db/rollbacks/20261106000001_hr_ess_attendance_requests.sql

CREATE TABLE IF NOT EXISTS public.hr_ess_attendance_requests (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id            uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  type                   text NOT NULL CHECK (type IN ('on_duty', 'fix_a_day', 'excuse_late')),
  status                 text NOT NULL DEFAULT 'pending'
                           CHECK (status IN ('pending', 'approved', 'rejected', 'withdrawn', 'cancelled')),
  day                    date NOT NULL,
  reason                 text NOT NULL CHECK (length(btrim(reason)) BETWEEN 5 AND 1000),
  -- on_duty only: where the duty is ("College drive, Pune"). The morning job writes it as the
  -- day's note: 'On duty: <place>'.
  place                  text CHECK (place IS NULL OR length(btrim(place)) BETWEEN 1 AND 120),
  -- fix_a_day: the corrected times of day, IST wall clock. At least one; the other comes from
  -- the day row as it stands. A time is stored as `time`, as the shift times are.
  fix_in                 time,
  fix_out                time,
  -- The hr_staff_attendance row as it was before the approval wrote it (NULL: there was none),
  -- and when that write happened. HR's cancel restores it.
  day_before             jsonb,
  day_written_at         timestamptz,
  -- Whose decision it was. The user id is NULL for an approver who signed in with an attendance
  -- login; the name is always recorded. approval_note is the approver's comment (a rejection
  -- always carries one).
  decided_by_employee_id uuid REFERENCES public.hr_employees(id) ON DELETE SET NULL,
  decided_by_user_id     uuid REFERENCES public.users(id) ON DELETE SET NULL,
  decided_by_name        text,
  decided_at             timestamptz,
  decision_note          text CHECK (decision_note IS NULL OR length(btrim(decision_note)) BETWEEN 1 AND 1000),
  -- HR's cancel of an approved request, with the reason it gives.
  cancelled_by_user_id   uuid REFERENCES public.users(id) ON DELETE SET NULL,
  cancelled_by_name      text,
  cancelled_at           timestamptz,
  cancel_reason          text CHECK (cancel_reason IS NULL OR length(btrim(cancel_reason)) BETWEEN 1 AND 200),
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  -- Each type carries exactly what it needs and nothing of the others' shape.
  CONSTRAINT hr_ess_attendance_requests_shape_chk CHECK (
    (type = 'on_duty'      AND place IS NOT NULL AND fix_in IS NULL AND fix_out IS NULL)
    OR (type = 'fix_a_day'  AND place IS NULL AND (fix_in IS NOT NULL OR fix_out IS NOT NULL))
    OR (type = 'excuse_late' AND place IS NULL AND fix_in IS NULL AND fix_out IS NULL)
  ),
  -- A decided request carries its decision; a pending or withdrawn one carries none. A cancelled
  -- one was approved first, so it carries both.
  CONSTRAINT hr_ess_attendance_requests_decision_chk CHECK (
    (status = 'pending'   AND decided_at IS NULL     AND cancelled_at IS NULL)
    OR (status = 'withdrawn' AND decided_at IS NULL  AND cancelled_at IS NULL)
    OR (status IN ('approved', 'rejected') AND decided_at IS NOT NULL AND cancelled_at IS NULL)
    OR (status = 'cancelled' AND decided_at IS NOT NULL AND cancelled_at IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS hr_ess_attendance_requests_person_idx
  ON public.hr_ess_attendance_requests (employee_id, created_at DESC);
-- The approvals Inbox reads one status at a time across everybody.
CREATE INDEX IF NOT EXISTS hr_ess_attendance_requests_status_idx
  ON public.hr_ess_attendance_requests (status, day);
-- The morning job looks up approved on_duty requests by their day.
CREATE INDEX IF NOT EXISTS hr_ess_attendance_requests_on_duty_idx
  ON public.hr_ess_attendance_requests (day) WHERE type = 'on_duty' AND status = 'approved';

-- Every request's own history, one row per move, written as the move happens: the trigger below
-- writes 'filed'; the decision, withdraw and cancel functions write the rest. Nothing deletes a
-- history row but the request's own deletion, by cascade.
CREATE TABLE IF NOT EXISTS public.hr_ess_attendance_request_history (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id        uuid NOT NULL REFERENCES public.hr_ess_attendance_requests(id) ON DELETE CASCADE,
  at                timestamptz NOT NULL DEFAULT now(),
  actor_employee_id uuid REFERENCES public.hr_employees(id) ON DELETE SET NULL,
  actor_user_id     uuid REFERENCES public.users(id) ON DELETE SET NULL,
  actor_name        text,
  action            text NOT NULL CHECK (action IN ('filed', 'approved', 'rejected', 'withdrawn', 'cancelled')),
  note              text,
  details           jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS hr_ess_attendance_request_history_request_idx
  ON public.hr_ess_attendance_request_history (request_id, at);

-- 'filed' is the one move the employee makes with a plain insert, so it is written by the
-- database: a request without its first history row is a request nobody can account for.
-- SECURITY INVOKER and a pinned search_path, as the other trigger functions here.
CREATE OR REPLACE FUNCTION public.hr_ess_attendance_requests_filed()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO hr_ess_attendance_request_history
    (request_id, at, actor_employee_id, actor_name, action, details)
  VALUES
    (NEW.id, NEW.created_at, NEW.employee_id,
     (SELECT full_name FROM hr_employees WHERE id = NEW.employee_id),
     'filed', jsonb_build_object('type', NEW.type, 'day', NEW.day));
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS hr_ess_attendance_requests_filed_trg ON public.hr_ess_attendance_requests;
CREATE TRIGGER hr_ess_attendance_requests_filed_trg
  AFTER INSERT ON public.hr_ess_attendance_requests
  FOR EACH ROW EXECUTE FUNCTION public.hr_ess_attendance_requests_filed();

ALTER TABLE public.hr_ess_attendance_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hr_ess_attendance_request_history ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON TABLE public.hr_ess_attendance_requests FROM anon;
    REVOKE ALL ON TABLE public.hr_ess_attendance_request_history FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON TABLE public.hr_ess_attendance_requests FROM authenticated;
    REVOKE ALL ON TABLE public.hr_ess_attendance_request_history FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT SELECT, INSERT, UPDATE ON TABLE public.hr_ess_attendance_requests TO service_role;
    GRANT SELECT, INSERT ON TABLE public.hr_ess_attendance_request_history TO service_role;
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';
