-- Rollback: 20261114000004_hr_ess_leave_admin_manager_flow.sql
--
-- Removes everything this migration introduced: the Admin Manager approver table and the choices
-- seeded into it, the six request columns with their index and CHECK, and the routing and
-- decision functions it created. No earlier migration defined hr_ess_leave_route,
-- hr_ess_leave_route_trigger, hr_ess_leave_admin_decide or hr_ess_leave_stage, so they are
-- dropped rather than restored. Safe to run twice, and after the leave tables themselves have
-- been turned back.

DO $routing$
BEGIN
  IF to_regclass('public.hr_ess_leave_requests') IS NOT NULL THEN
    EXECUTE 'DROP TRIGGER IF EXISTS hr_ess_leave_route_trg ON public.hr_ess_leave_requests';
  END IF;
END
$routing$;

DROP FUNCTION IF EXISTS public.hr_ess_leave_admin_decide(uuid, uuid, uuid, text, boolean, text, uuid, text, text, timestamptz);
DROP FUNCTION IF EXISTS public.hr_ess_leave_stage(uuid);
DROP FUNCTION IF EXISTS public.hr_ess_leave_route_trigger();
DROP FUNCTION IF EXISTS public.hr_ess_leave_route(uuid);

DROP TABLE IF EXISTS public.hr_ess_leave_approvers;
DROP INDEX IF EXISTS public.hr_ess_leave_admin_manager_idx;

DO $columns$
BEGIN
  IF to_regclass('public.hr_ess_leave_requests') IS NOT NULL THEN
    ALTER TABLE public.hr_ess_leave_requests
      DROP CONSTRAINT IF EXISTS hr_ess_leave_class_timing_chk,
      DROP COLUMN IF EXISTS admin_manager_employee_id,
      DROP COLUMN IF EXISTS admin_manager_name,
      DROP COLUMN IF EXISTS is_teaching,
      DROP COLUMN IF EXISTS substitute_faculty_id,
      DROP COLUMN IF EXISTS substitute_faculty_name,
      DROP COLUMN IF EXISTS class_timing;
  END IF;
END
$columns$;

NOTIFY pgrst, 'reload schema';
