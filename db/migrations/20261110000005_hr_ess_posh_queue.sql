-- Team RVM (ESS): POSH routes to the Internal Committee (Phase 2C, KP 6).
--
-- Phase 2B routed POSH complaints to HR because the Scheduler's roles list holds no Internal
-- Committee role (both flagged for KP). The decided version (KP, 19 Oct 2026) routes them to the
-- committee, named `internal_committee` in the ESS's own policy: when RVM appoints the committee
-- and its logins carry that role, the queue fills of itself. Until then it stays EMPTY, which is
-- the point: a POSH complaint must not sit in a queue of people who are not the committee.
--
-- The one non-additive touch of Phase 2C, and it is on an hr_ess_* table only (ADR-0021): the
-- queue-roles CHECK is widened to admit the new name, and the seeded `posh` row's queue_roles is
-- moved. Nothing outside hr_ess_helpdesk_categories changes.
--
-- Safe to run twice: the re-run drops and re-adds the same CHECK and rewrites the same row.
--
-- Rollback: db/rollbacks/20261110000005_hr_ess_posh_queue.sql

ALTER TABLE public.hr_ess_helpdesk_categories
  DROP CONSTRAINT IF EXISTS hr_ess_helpdesk_categories_roles_chk;
ALTER TABLE public.hr_ess_helpdesk_categories
  ADD CONSTRAINT hr_ess_helpdesk_categories_roles_chk CHECK (queue_roles <@ ARRAY[
    'ceo', 'super_admin', 'hoo', 'hod', 'hod_placement', 'admin_manager', 'admin',
    'accounts_admin', 'hr', 'hr_executive', 'faculty', 'internal_committee'
  ]::text[]);

-- The seeded POSH row moves to the committee. ON CONFLICT DO NOTHING (20261109000001) will not
-- overwrite it, so this is the UPDATE.
UPDATE public.hr_ess_helpdesk_categories
  SET queue_roles = ARRAY['internal_committee'], updated_at = now()
  WHERE slug = 'posh';

NOTIFY pgrst, 'reload schema';
