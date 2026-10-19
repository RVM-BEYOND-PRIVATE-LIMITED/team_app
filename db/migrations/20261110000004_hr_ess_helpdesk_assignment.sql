-- Team RVM (ESS): Helpdesk assignment and reassignment (Phase 2C, KP 5).
--
-- Phase 2B left a claim as the only way a ticket got an assignee (decision 7 open). This is the
-- decided version (KP, 19 Oct 2026): the team may ASSIGN a live ticket to a named handler, and
-- reassign it, and the record says who pointed it there.
--
--   assigned_by_employee_id, assigned_by_name, assigned_at   who assigned it, and when; additive
--                                                            columns on the ticket, so nothing
--                                                            Phase 2B wrote changes shape;
--   hr_ess_helpdesk_assignments                              the history: one row per assignment,
--                                                            so a reassign does not overwrite
--                                                            who had it first.
--
-- The route sets claimed_at with the assignee (the claim stamp the lifecycle's state CHECK
-- hr_ess_helpdesk_tickets_state_chk asks for), so the CHECK keeps holding whatever it held.
--
-- Additive only (ADR-0021): a new table and three columns on an hr_ess_* table. Safe to run
-- twice. Row-level security is on with no policy, so only the service role (the ESS) can read or
-- write.
--
-- Rollback: db/rollbacks/20261110000004_hr_ess_helpdesk_assignment.sql

ALTER TABLE public.hr_ess_helpdesk_tickets
  ADD COLUMN IF NOT EXISTS assigned_by_employee_id uuid REFERENCES public.hr_employees(id) ON DELETE SET NULL;
ALTER TABLE public.hr_ess_helpdesk_tickets
  ADD COLUMN IF NOT EXISTS assigned_by_name text;
ALTER TABLE public.hr_ess_helpdesk_tickets
  ADD COLUMN IF NOT EXISTS assigned_at timestamptz;

CREATE TABLE IF NOT EXISTS public.hr_ess_helpdesk_assignments (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id        uuid NOT NULL REFERENCES public.hr_ess_helpdesk_tickets(id) ON DELETE CASCADE,
  -- Who had it before, null for a first assignment; the ticket it went to.
  from_employee_id uuid REFERENCES public.hr_employees(id) ON DELETE SET NULL,
  to_employee_id   uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE SET NULL,
  assigned_by_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  assigned_by_name text,
  -- Why it moved on, when a reassign says so.
  note             text CHECK (note IS NULL OR length(btrim(note)) BETWEEN 1 AND 500),
  created_at       timestamptz NOT NULL DEFAULT now()
);

-- The history, oldest first.
CREATE INDEX IF NOT EXISTS hr_ess_helpdesk_assignments_ticket_idx
  ON public.hr_ess_helpdesk_assignments (ticket_id, created_at);

ALTER TABLE public.hr_ess_helpdesk_assignments ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON TABLE public.hr_ess_helpdesk_assignments FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON TABLE public.hr_ess_helpdesk_assignments FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT SELECT, INSERT ON TABLE public.hr_ess_helpdesk_assignments TO service_role;
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';
