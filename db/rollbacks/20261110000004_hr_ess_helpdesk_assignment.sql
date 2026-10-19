-- Team RVM (ESS): undo the Helpdesk assignment (db/migrations/20261110000004_hr_ess_helpdesk_assignment.sql).
-- Safe to run twice: everything is IF EXISTS.

DROP TABLE IF EXISTS public.hr_ess_helpdesk_assignments;

-- Only while the table is there: a rollback run after 20261109000001 has already dropped it
-- (the pair is rolled back in reverse order, twice), as the Helpdesk's categories rollback does.
DO $check$
BEGIN
  IF to_regclass('public.hr_ess_helpdesk_tickets') IS NOT NULL THEN
    ALTER TABLE public.hr_ess_helpdesk_tickets DROP COLUMN IF EXISTS assigned_by_employee_id;
    ALTER TABLE public.hr_ess_helpdesk_tickets DROP COLUMN IF EXISTS assigned_by_name;
    ALTER TABLE public.hr_ess_helpdesk_tickets DROP COLUMN IF EXISTS assigned_at;
  END IF;
END
$check$;

NOTIFY pgrst, 'reload schema';
