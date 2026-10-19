-- Team RVM (ESS): undo the POSH queue move (db/migrations/20261110000005_hr_ess_posh_queue.sql).
-- Safe to run twice.

-- Only while the table is there: a rollback run after 20261109000001 has already dropped it
-- (the pair is rolled back in reverse order, twice), as the Helpdesk's categories rollback does.
DO $check$
BEGIN
  IF to_regclass('public.hr_ess_helpdesk_categories') IS NOT NULL THEN
    ALTER TABLE public.hr_ess_helpdesk_categories
      DROP CONSTRAINT IF EXISTS hr_ess_helpdesk_categories_roles_chk;

    -- The narrow CHECK refuses the committee's name, so the row goes back first.
    UPDATE public.hr_ess_helpdesk_categories
      SET queue_roles = ARRAY['hr'], updated_at = now()
      WHERE slug = 'posh';

    ALTER TABLE public.hr_ess_helpdesk_categories
      ADD CONSTRAINT hr_ess_helpdesk_categories_roles_chk CHECK (queue_roles <@ ARRAY[
        'ceo', 'super_admin', 'hoo', 'hod', 'hod_placement', 'admin_manager', 'admin',
        'accounts_admin', 'hr', 'hr_executive', 'faculty'
      ]::text[]);
  END IF;
END
$check$;

NOTIFY pgrst, 'reload schema';
