-- Team RVM (ESS): the approval escalations (Phase 2D, task D4).
--
-- Decision 1's chain decides a request through the reporting line: the manager, then upward, with
-- HR as the fallback when nobody is recorded. When a level cannot decide it that day -- the same
-- person who asked, somebody no longer on strength, somebody on leave that day -- it is stepped
-- over, and when a request waits past the escalation window (src/jobs/approvals.js, hourly; the
-- window is a policy constant there, proposed two IST days for KP to confirm) the job tells the
-- next level and records the move here.
--
-- One row per level told: the family and the request it is about -- no foreign key on the
-- request, so the trail outlives it exactly as hr_ess_audit's does -- who it came from, who it
-- went to, and the reason the levels below were stepped over. The ESS reads it to build the
-- chain view and to know where the next escalation goes; nothing updates or deletes a row but
-- the people behind it.
--
-- The notification the job sends reuses the `approvals` category (the CHECK in
-- 20261110000006 already holds it), so no notification change rides along here.
--
-- Safe to run twice.
--
-- Rollback: db/rollbacks/20261111000002_hr_ess_approval_escalations.sql

CREATE TABLE IF NOT EXISTS public.hr_ess_approval_escalations (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  family           text NOT NULL CHECK (family IN ('attendance', 'leave')),
  -- The request the trail is about, by family; no foreign key, so the trail outlives it.
  request_id       uuid NOT NULL,
  -- The level the move came from (NULL when the row's writer has since gone) and the one told.
  from_employee_id uuid REFERENCES public.hr_employees(id) ON DELETE SET NULL,
  to_employee_id   uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  -- Why this level was told: how long it has waited, and who was stepped over.
  reason           text NOT NULL CHECK (length(btrim(reason)) BETWEEN 3 AND 200),
  escalated_at     timestamptz NOT NULL DEFAULT now(),
  -- One telling per level per request: the job may be restarted mid-walk, and the second run
  -- finds the row and moves on.
  CONSTRAINT hr_ess_approval_escalations_family_request_id_to_employee_id_key
    UNIQUE (family, request_id, to_employee_id)
);

CREATE INDEX IF NOT EXISTS hr_ess_approval_escalations_request_idx
  ON public.hr_ess_approval_escalations (family, request_id, escalated_at);

ALTER TABLE public.hr_ess_approval_escalations ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON TABLE public.hr_ess_approval_escalations FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON TABLE public.hr_ess_approval_escalations FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT SELECT, INSERT ON TABLE public.hr_ess_approval_escalations TO service_role;
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';
