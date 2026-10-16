-- Team RVM (ESS): an employee's request to correct or delete their data, and HR's answer.
--
-- Task A8 (the brief's "Request correction or deletion of my data", in Me). The employee raises
-- it from the app with either sign-in; HR, HR Executive and super admins
-- (apps/ess-api/src/policy/hrAccess.js HR_RECORD_ROLES: the Scheduler's HR_ROLES,
-- config/hrPolicy.js:25-30, without the CEO) see the open ones and close each as done or
-- rejected, with a note. Nobody closes their own (the ESS answers 409 OWN_REQUEST).
--
-- A row is either open, with nothing about its resolution filled in, or closed, with when and
-- by whom: the CHECK below holds the two shapes, so a half-closed request cannot exist.
--
-- employee_id cascades like every per-employee HR table (20261015000004_hr_staff_attendance.sql:15).
-- When a request to delete somebody's data ends with their record deleted, these rows go with it,
-- and the proof that it was handled stays in hr_ess_audit, which has no foreign key to the record.
-- The resolver is kept by id and by name, the HRMS convention (20260826000001_hrms_tables.sql:8-12).
--
-- A new table only (ADR-0021): nothing the Scheduler owns is altered. Safe to run twice.
-- Row-level security is on with no policy, so only the service role (the ESS) can read or write.
--
-- Rollback: db/rollbacks/20261105000001_hr_ess_data_requests.sql

CREATE TABLE IF NOT EXISTS public.hr_ess_data_requests (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id         uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  kind                text NOT NULL CHECK (kind IN ('correct', 'delete')),
  details             text NOT NULL CHECK (length(btrim(details)) BETWEEN 1 AND 2000),
  status              text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'done', 'rejected')),
  created_at          timestamptz NOT NULL DEFAULT now(),
  resolved_at         timestamptz,
  resolved_by_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  resolved_by_name    text,
  resolution_note     text CHECK (resolution_note IS NULL OR length(resolution_note) BETWEEN 1 AND 1000),
  CONSTRAINT hr_ess_data_requests_resolution_chk CHECK (
    (status = 'open' AND resolved_at IS NULL AND resolved_by_user_id IS NULL
      AND resolved_by_name IS NULL AND resolution_note IS NULL)
    OR (status <> 'open' AND resolved_at IS NOT NULL AND resolved_by_name IS NOT NULL)
  )
);

-- HR's queue (open, oldest first) and each person's own list (newest first).
CREATE INDEX IF NOT EXISTS idx_hr_ess_data_requests_status_created
  ON public.hr_ess_data_requests (status, created_at);
CREATE INDEX IF NOT EXISTS idx_hr_ess_data_requests_employee_created
  ON public.hr_ess_data_requests (employee_id, created_at DESC);

ALTER TABLE public.hr_ess_data_requests ENABLE ROW LEVEL SECURITY;

NOTIFY pgrst, 'reload schema';
