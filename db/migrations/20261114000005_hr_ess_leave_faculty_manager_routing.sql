-- Team RVM (ESS): only faculty take the Admin Manager route. Everybody else's leave is a
-- single approval by their reporting manager. Faculty leave then goes to the centre's Level 2
-- approver (Faridabad/Lucknow: Bhupender; Pune/Ahmedabad: Vishal), with a superadmin fallback.
--
-- RVM, 27 Oct 2026.
--
-- Additive and safe to run twice.

/* ══════════════ 1. LEVEL 2 AND SINGLE-APPROVER COLUMNS ══════════════ */

ALTER TABLE public.hr_ess_leave_requests
  ADD COLUMN IF NOT EXISTS final_approver_employee_id uuid REFERENCES public.hr_employees(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS final_approver_name text;

CREATE INDEX IF NOT EXISTS hr_ess_leave_final_approver_idx
  ON public.hr_ess_leave_requests (final_approver_employee_id, status, stage);

/* ══════════════ 2. THE CENTRE LEVEL 2 APPROVER ══════════════ */

CREATE TABLE IF NOT EXISTS public.hr_ess_leave_final_approvers (
  branch_id             uuid PRIMARY KEY REFERENCES public.hr_branches(id) ON DELETE CASCADE,
  employee_id           uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  configured_by_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  configured_by_name    text,
  updated_at            timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.hr_ess_leave_final_approvers ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON TABLE public.hr_ess_leave_final_approvers FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON TABLE public.hr_ess_leave_final_approvers FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.hr_ess_leave_final_approvers TO service_role;
  END IF;
END $$;

-- KP, 27 Oct 2026: Bhupender for Faridabad and Lucknow; Vishal for Pune and Ahmedabad.
-- Match on the employee code first, then the exact name, so a renamed login still maps.
WITH mapping(branch_name, employee_code, full_name) AS (
  VALUES
    ('Faridabad', 'RVM/F/43', 'Bhupender Singh'),
    ('Lucknow',   'RVM/F/43', 'Bhupender Singh'),
    ('Pune',      'RVM/F/29', 'Vishal Narwat'),
    ('Ahmedabad', 'RVM/F/29', 'Vishal Narwat')
)
INSERT INTO public.hr_ess_leave_final_approvers (branch_id, employee_id, configured_by_name)
SELECT b.id, e.id, 'Automatic — centre Level 2'
  FROM mapping m
  JOIN public.hr_branches b ON b.name = m.branch_name
  JOIN public.hr_employees e
    ON e.is_archived = false
   AND (e.employee_code = m.employee_code OR lower(e.full_name) = lower(m.full_name))
ON CONFLICT (branch_id) DO NOTHING;

/* ══════════════ 3. ROUTING ══════════════ */

DROP TRIGGER IF EXISTS hr_ess_leave_route_trg ON public.hr_ess_leave_requests;
DROP FUNCTION IF EXISTS public.hr_ess_leave_route(uuid);

CREATE OR REPLACE FUNCTION public.hr_ess_leave_route(p_employee_id uuid)
RETURNS TABLE (
  admin_manager_employee_id uuid,
  admin_manager_name text,
  stage text,
  is_teaching boolean,
  final_approver_employee_id uuid,
  final_approver_name text
)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_employee public.hr_employees%ROWTYPE;
  v_teaching boolean := false;
  v_faculty boolean := false;
  v_selected uuid;
  v_name text;
  v_manager uuid;
  v_manager_name text;
  v_count integer;
  v_admin uuid;
  v_admin_name text;
  v_final uuid;
  v_final_name text;
BEGIN
  SELECT * INTO v_employee FROM public.hr_employees WHERE id = p_employee_id;
  IF NOT FOUND THEN
    RETURN QUERY SELECT NULL::uuid, NULL::text, 'final'::text, false, NULL::uuid, NULL::text;
    RETURN;
  END IF;

  -- `is_teaching` drives the class-coverage dialog. Only a faculty member takes the Admin
  -- Manager route; an HOD is "other" for approval and uses their reporting manager.
  SELECT EXISTS (
    SELECT 1 FROM public.users u
     WHERE u.id = v_employee.user_id AND u.role IN ('faculty', 'hod')
  ) OR (
    v_employee.email IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.faculty f WHERE lower(f.email) = lower(v_employee.email)
    )
  ) INTO v_teaching;

  SELECT EXISTS (
    SELECT 1 FROM public.users u
     WHERE u.id = v_employee.user_id AND u.role IN ('faculty', 'hod')
  ) OR (
    v_employee.email IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.faculty f WHERE lower(f.email) = lower(v_employee.email)
    )
  ) INTO v_faculty;

  -- The centre's Level 2 approver, where KP has named one. A branch with no mapping falls
  -- back to the superadmin in the application.
  SELECT f.employee_id, e.full_name
    INTO v_final, v_final_name
    FROM public.hr_ess_leave_final_approvers f
    JOIN public.hr_employees e ON e.id = f.employee_id AND e.is_archived = false
   WHERE f.branch_id = v_employee.branch_id
   LIMIT 1;

  -- Everybody except faculty: one approval by the reporting manager. If the manager is
  -- missing, archived or the person themselves, the request falls back to the superadmin.
  IF NOT v_faculty THEN
    SELECT e.manager_id, m.full_name
      INTO v_manager, v_manager_name
      FROM public.hr_employees e
      JOIN public.hr_employees m ON m.id = e.manager_id AND m.is_archived = false
     WHERE e.id = p_employee_id
       AND e.manager_id <> p_employee_id;
    RETURN QUERY SELECT
      NULL::uuid, NULL::text, 'final'::text, false, v_manager, v_manager_name;
    RETURN;
  END IF;

  -- The branch's explicit Admin Manager choice, if that person is still active and linked.
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
    RETURN QUERY SELECT v_selected, v_name, 'manager'::text, true, v_final, v_final_name;
    RETURN;
  END IF;

  SELECT count(*), (array_agg(e.id ORDER BY e.id))[1]
    INTO v_count, v_admin
    FROM public.hr_employees e
    JOIN public.users u ON u.id = e.user_id AND u.role = 'admin_manager'
   WHERE e.branch_id = v_employee.branch_id
     AND e.is_archived = false
     AND e.id <> p_employee_id;

  IF v_count = 1 THEN
    SELECT e.full_name INTO v_admin_name FROM public.hr_employees e WHERE e.id = v_admin;
    RETURN QUERY SELECT v_admin, v_admin_name, 'manager'::text, true, v_final, v_final_name;
  ELSIF v_count > 1 THEN
    RETURN QUERY SELECT NULL::uuid, NULL::text, 'manager'::text, true, v_final, v_final_name;
  ELSE
    -- No Admin Manager: HR is the first-stage bypass; with no HR, the centre Level 2
    -- approver takes it directly.
    IF EXISTS (
      SELECT 1 FROM public.hr_employees h
      JOIN public.users u ON u.id = h.user_id AND u.role = 'hr'
      WHERE h.is_archived = false
    ) THEN
      RETURN QUERY SELECT NULL::uuid, NULL::text, 'manager'::text, true, v_final, v_final_name;
    ELSE
      RETURN QUERY SELECT NULL::uuid, NULL::text, 'final'::text, true, v_final, v_final_name;
    END IF;
  END IF;
END $$;

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
  NEW.final_approver_employee_id := r.final_approver_employee_id;
  NEW.final_approver_name := r.final_approver_name;
  NEW.stage := r.stage;
  RETURN NEW;
END $$;

CREATE TRIGGER hr_ess_leave_route_trg
  BEFORE INSERT ON public.hr_ess_leave_requests
  FOR EACH ROW EXECUTE FUNCTION public.hr_ess_leave_route_trigger();

-- Existing pending requests move to the new rule. A faculty request already at 'final' has
-- had its Admin Manager round and stays there; everybody else is final immediately.
WITH routed AS (
  SELECT l.id, r.*
    FROM public.hr_ess_leave_requests l
    CROSS JOIN LATERAL public.hr_ess_leave_route(l.employee_id) r
   WHERE l.status = 'pending'
)
UPDATE public.hr_ess_leave_requests l
   SET requires_final_approval = true,
       admin_manager_employee_id = routed.admin_manager_employee_id,
       admin_manager_name = routed.admin_manager_name,
       is_teaching = COALESCE(routed.is_teaching, false),
       final_approver_employee_id = routed.final_approver_employee_id,
       final_approver_name = routed.final_approver_name,
       stage = CASE WHEN l.stage = 'final' THEN 'final' ELSE routed.stage END,
       updated_at = now()
  FROM routed
 WHERE l.id = routed.id;

NOTIFY pgrst, 'reload schema';
