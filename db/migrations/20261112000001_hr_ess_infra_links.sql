-- Team RVM (ESS): the infra register link (Phase 2D, task G6; KP, 22 Oct 2026).
--
-- A lab or facility helpdesk ticket also gets one summary row in the Admin Manager's own
-- register, infra_tickets (supabase/migrations/20260804000003:113-130). The register has no
-- thread and no in-progress state, so the helpdesk stays the system of record and the register
-- gets the summary the Admin Manager audits. This table is the link between the two, kept on the
-- ESS side so no Scheduler schema changes (ADR-0018, ADR-0021):
--
--   linked   the register row exists; infra_ticket_id is its id
--   skipped  the mirror could not be made (for example the branch has no location of the same
--            name); reason says why and the hourly job retries it
--
-- The link is never deleted by hand: it cascades with its helpdesk ticket, and the register row
-- (a Scheduler table) is not foreign-keyed so the trail outlives it exactly as hr_ess_audit's does.
--
-- Safe to run twice. Rollback: db/rollbacks/20261112000001_hr_ess_infra_links.sql

CREATE TABLE IF NOT EXISTS public.hr_ess_infra_links (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id       uuid NOT NULL UNIQUE REFERENCES public.hr_ess_helpdesk_tickets(id) ON DELETE CASCADE,
  infra_ticket_id uuid UNIQUE,
  state           text NOT NULL CHECK (state IN ('linked', 'skipped')),
  reason          text,
  last_synced_at  timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  CHECK (
    (state = 'linked' AND infra_ticket_id IS NOT NULL)
    OR (state = 'skipped' AND infra_ticket_id IS NULL)
  ),
  CHECK (reason IS NULL OR length(btrim(reason)) BETWEEN 1 AND 300)
);

CREATE INDEX IF NOT EXISTS hr_ess_infra_links_infra_idx
  ON public.hr_ess_infra_links (infra_ticket_id)
  WHERE infra_ticket_id IS NOT NULL;

ALTER TABLE public.hr_ess_infra_links ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON TABLE public.hr_ess_infra_links FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON TABLE public.hr_ess_infra_links FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.hr_ess_infra_links TO service_role;
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';
