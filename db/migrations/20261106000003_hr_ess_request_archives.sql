-- Team RVM (ESS): the approver's "archive", for the Inbox (task D1).
--
-- Archiving clears a request from ONE approver's Inbox without deciding it: it stays pending, any
-- other approver still sees it, and the manager or HR still has to decide it. That is the shape
-- Keka's archive has, and it is the only shape that works when a request sits with a manager and
-- with HR at once: a single archived flag on the request would clear it for everybody.
--
-- One row per (request, approver). The row is never deleted through the API; archiving again is
-- the same as the first time (the unique key answers the second one as "already archived").
--
-- There is no foreign key to the request tables: a request id can be from either family, and a
-- foreign key cannot point at two tables. Requests are never deleted through the API (a request
-- ends as withdrawn or cancelled), and the employee's own deletion cascades this row away with
-- their record.
--
-- A new table only (ADR-0021). Safe to run twice. Row-level security on with no policy.
--
-- Rollback: db/rollbacks/20261106000003_hr_ess_request_archives.sql

CREATE TABLE IF NOT EXISTS public.hr_ess_request_archives (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  family       text NOT NULL CHECK (family IN ('attendance', 'leave')),
  request_id   uuid NOT NULL,
  employee_id  uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  archived_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (family, request_id, employee_id)
);

CREATE INDEX IF NOT EXISTS hr_ess_request_archives_employee_idx
  ON public.hr_ess_request_archives (employee_id);

ALTER TABLE public.hr_ess_request_archives ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON TABLE public.hr_ess_request_archives FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON TABLE public.hr_ess_request_archives FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT SELECT, INSERT ON TABLE public.hr_ess_request_archives TO service_role;
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';
