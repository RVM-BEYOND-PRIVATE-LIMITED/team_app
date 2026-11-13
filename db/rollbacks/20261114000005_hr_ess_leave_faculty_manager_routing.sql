-- Rollback: 20261114000005_hr_ess_leave_faculty_manager_routing.sql
--
-- Puts the Admin Manager routing back exactly as 20261114000004 wrote it: the four-column
-- hr_ess_leave_route (copied from 20261114000004_hr_ess_leave_admin_manager_flow.sql), its
-- trigger function and the BEFORE INSERT trigger. Drops the centre Level 2 approver table and
-- the final-approver columns/index this migration added; the mapping rows go with the table.
-- Safe to run twice, and after the leave tables themselves have been turned back.

DROP TABLE IF EXISTS public.hr_ess_leave_final_approvers;
DROP INDEX IF EXISTS public.hr_ess_leave_final_approver_idx;

DO $columns$
BEGIN
  IF to_regclass('public.hr_ess_leave_requests') IS NOT NULL THEN
    ALTER TABLE public.hr_ess_leave_requests
      DROP COLUMN IF EXISTS final_approver_employee_id,
      DROP COLUMN IF EXISTS final_approver_name;
  END IF;
END
$columns$;

DO $routing$
BEGIN
  IF to_regclass('public.hr_ess_leave_requests') IS NOT NULL THEN
    EXECUTE 'DROP TRIGGER IF EXISTS hr_ess_leave_route_trg ON public.hr_ess_leave_requests';
  END IF;
END
$routing$;

DROP FUNCTION IF EXISTS public.hr_ess_leave_route(uuid);

-- Copied from 20261114000004_hr_ess_leave_admin_manager_flow.sql.
CREATE OR REPLACE FUNCTION public.hr_ess_leave_route(p_employee_id uuid)
RETURNS TABLE (
  admin_manager_employee_id uuid,
  admin_manager_name text,
  stage text,
  is_teaching boolean
)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_employee public.hr_employees%ROWTYPE;
  v_selected uuid;
  v_name text;
  v_manager uuid;
  v_manager_name text;
  v_count integer;
  v_teaching boolean := false;
BEGIN
  SELECT * INTO v_employee FROM public.hr_employees WHERE id = p_employee_id;
  IF NOT FOUND THEN
    RETURN QUERY SELECT NULL::uuid, NULL::text, 'final'::text, false;
    RETURN;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.users u
     WHERE u.id = v_employee.user_id AND u.role IN ('faculty', 'hod')
  ) OR (
    v_employee.email IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.faculty f WHERE lower(f.email) = lower(v_employee.email)
    )
  ) INTO v_teaching;

  -- The branch's explicit choice, if that person is still an active linked Admin Manager.
  SELECT a.employee_id INTO v_selected
    FROM public.hr_ess_leave_approvers a
    JOIN public.hr_employees e ON e.id = a.employee_id
    JOIN public.users u ON u.id = e.user_id AND u.role = 'admin_manager'
   WHERE a.branch_id = v_employee.branch_id
     AND e.is_archived = false
     AND e.id <> p_employee_id
   LIMIT 1;

  IF v_selected IS NOT NULL THEN
    SELECT e.full_name INTO v_name FROM public.hr_employees e WHERE e.id = v_selected;
    RETURN QUERY SELECT v_selected, v_name, 'manager'::text, v_teaching;
    RETURN;
  END IF;

  -- No usable choice. One other Admin Manager in the branch is the natural default; several
  -- means any of them may act until the super admin picks one.
  SELECT count(*), (array_agg(e.id ORDER BY e.id))[1]
    INTO v_count, v_manager
    FROM public.hr_employees e
    JOIN public.users u ON u.id = e.user_id AND u.role = 'admin_manager'
   WHERE e.branch_id = v_employee.branch_id
     AND e.is_archived = false
     AND e.id <> p_employee_id;

  IF v_count = 1 THEN
    SELECT e.full_name INTO v_manager_name FROM public.hr_employees e WHERE e.id = v_manager;
    RETURN QUERY SELECT v_manager, v_manager_name, 'manager'::text, v_teaching;
  ELSIF v_count > 1 THEN
    RETURN QUERY SELECT NULL::uuid, NULL::text, 'manager'::text, v_teaching;
  ELSE
    -- No Admin Manager at the branch: HR is the bypass at the first stage. If there is no
    -- active HR employee either, the super admin is the only remaining entity.
    IF EXISTS (
      SELECT 1 FROM public.hr_employees h
      JOIN public.users u ON u.id = h.user_id AND u.role = 'hr'
      WHERE h.is_archived = false
    ) THEN
      RETURN QUERY SELECT NULL::uuid, NULL::text, 'manager'::text, v_teaching;
    ELSE
      RETURN QUERY SELECT NULL::uuid, NULL::text, 'final'::text, v_teaching;
    END IF;
  END IF;
END $$;

-- Copied from 20261114000004_hr_ess_leave_admin_manager_flow.sql.
CREATE OR REPLACE FUNCTION public.hr_ess_leave_route_trigger()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  r record;
BEGIN
  SELECT * INTO r FROM public.hr_ess_leave_route(NEW.employee_id);
  NEW.requires_final_approval := true;
  NEW.admin_manager_employee_id := r.admin_manager_employee_id;
  NEW.admin_manager_name := r.admin_manager_name;
  NEW.is_teaching := COALESCE(r.is_teaching, false);
  NEW.stage := r.stage;
  RETURN NEW;
END $$;

DO $trigger$
BEGIN
  IF to_regclass('public.hr_ess_leave_requests') IS NOT NULL THEN
    EXECUTE $trg$
CREATE TRIGGER hr_ess_leave_route_trg
  BEFORE INSERT ON public.hr_ess_leave_requests
  FOR EACH ROW EXECUTE FUNCTION public.hr_ess_leave_route_trigger()
$trg$;
  END IF;
END
$trigger$;

NOTIFY pgrst, 'reload schema';
