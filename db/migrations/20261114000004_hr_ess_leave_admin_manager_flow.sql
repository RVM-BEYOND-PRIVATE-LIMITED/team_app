-- Team RVM (ESS): leave approval moves from the reporting line to the branch Admin Manager,
-- then to a super admin.
--
-- RVM, 27 Oct 2026: HODs are not the attendance/leave approvers. Every leave request goes to
-- the Admin Manager of the employee's branch. Where a branch has more than one Admin Manager,
-- a super admin chooses the one in the HRMS Leaves tab (hr_ess_leave_approvers). The Admin
-- Manager records the substitute faculty and class timing for a teaching employee, then the
-- request moves to the super admin for final approval.
--
-- `stage = 'manager'` is retained as the Admin Manager stage so existing rows and constraints
-- stay compatible; 'final' is the super-admin stage. `manager_approved_*` now means the Admin
-- Manager's approval; the history action remains `manager_approved` and is labelled accordingly.
--
-- Additive and safe to run twice.

/* ══════════════ 1. REQUEST COLUMNS ══════════════ */

ALTER TABLE public.hr_ess_leave_requests
  ADD COLUMN IF NOT EXISTS admin_manager_employee_id uuid REFERENCES public.hr_employees(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS admin_manager_name text,
  ADD COLUMN IF NOT EXISTS is_teaching boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS substitute_faculty_id uuid REFERENCES public.faculty(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS substitute_faculty_name text,
  ADD COLUMN IF NOT EXISTS class_timing text;

DO $$
BEGIN
  ALTER TABLE public.hr_ess_leave_requests
    ADD CONSTRAINT hr_ess_leave_class_timing_chk
    CHECK (class_timing IS NULL OR length(btrim(class_timing)) BETWEEN 1 AND 200);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS hr_ess_leave_admin_manager_idx
  ON public.hr_ess_leave_requests (admin_manager_employee_id, status, stage);

/* ══════════════ 2. THE BRANCH'S CHOSEN ADMIN MANAGER ══════════════ */

CREATE TABLE IF NOT EXISTS public.hr_ess_leave_approvers (
  branch_id          uuid PRIMARY KEY REFERENCES public.hr_branches(id) ON DELETE CASCADE,
  employee_id        uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  configured_by_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  configured_by_name text,
  updated_at         timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.hr_ess_leave_approvers ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON TABLE public.hr_ess_leave_approvers FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON TABLE public.hr_ess_leave_approvers FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.hr_ess_leave_approvers TO service_role;
  END IF;
END $$;

-- Where a branch has exactly one linked, active Admin Manager, use that person at once. A
-- branch with several has no default; the super admin chooses, and until then any of them may
-- act. A branch with none uses HR as the first-stage bypass; only where there is no HR either
-- does it go straight to the super admin.
INSERT INTO public.hr_ess_leave_approvers (branch_id, employee_id, configured_by_name)
SELECT e.branch_id, min(e.id), 'Automatic — sole Admin Manager'
  FROM public.hr_employees e
  JOIN public.users u ON u.id = e.user_id AND u.role = 'admin_manager'
 WHERE e.branch_id IS NOT NULL
   AND e.is_archived = false
 GROUP BY e.branch_id
HAVING count(*) = 1
ON CONFLICT (branch_id) DO NOTHING;

/* ══════════════ 3. ROUTING ══════════════ */

-- The routing answer for one employee. Used by the BEFORE INSERT trigger and the backfill.
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
  SELECT count(*), min(e.id)
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

DROP TRIGGER IF EXISTS hr_ess_leave_route_trg ON public.hr_ess_leave_requests;
CREATE TRIGGER hr_ess_leave_route_trg
  BEFORE INSERT ON public.hr_ess_leave_requests
  FOR EACH ROW EXECUTE FUNCTION public.hr_ess_leave_route_trigger();

-- Existing pending requests move with the new rule. A request already at 'final' has already
-- had its first approval and stays there; only the not-yet-approved ones are re-routed.
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
       stage = CASE WHEN l.stage = 'final' THEN 'final' ELSE routed.stage END,
       updated_at = now()
  FROM routed
 WHERE l.id = routed.id;

/* ══════════════ 4. THE ADMIN MANAGER'S DECISION ══════════════ */

-- Approval at the Admin Manager stage does NOT write the leave days. It records the coverage
-- and moves the request to `final`; only the super admin's final approval writes the days.
CREATE OR REPLACE FUNCTION public.hr_ess_leave_admin_decide(
  p_request_id              uuid,
  p_decider_employee_id     uuid,
  p_decider_user_id         uuid,
  p_decider_name            text,
  p_approve                 boolean,
  p_note                    text,
  p_substitute_faculty_id   uuid,
  p_substitute_faculty_name text,
  p_class_timing            text,
  p_now                     timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  r public.hr_ess_leave_requests%ROWTYPE;
  v_branch uuid;
  v_ok boolean := false;
BEGIN
  SELECT * INTO r FROM public.hr_ess_leave_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('outcome', 'not_found'); END IF;
  IF r.status <> 'pending' OR r.stage <> 'manager' THEN
    RETURN jsonb_build_object('outcome', 'not_pending');
  END IF;

  SELECT branch_id INTO v_branch FROM public.hr_employees WHERE id = r.employee_id;

  IF r.admin_manager_employee_id IS NOT NULL THEN
    v_ok := (r.admin_manager_employee_id = p_decider_employee_id);
  ELSE
    SELECT EXISTS (
      SELECT 1 FROM public.hr_employees e
       JOIN public.users u ON u.id = e.user_id AND u.role = 'admin_manager'
       WHERE e.id = p_decider_employee_id
         AND e.branch_id = v_branch
         AND e.is_archived = false
         AND e.id <> r.employee_id
    ) OR EXISTS (
      SELECT 1 FROM public.hr_employees e
       JOIN public.users u ON u.id = e.user_id AND u.role = 'hr'
       WHERE e.id = p_decider_employee_id
         AND e.is_archived = false
         AND NOT EXISTS (
           SELECT 1 FROM public.hr_employees a
            JOIN public.users au ON au.id = a.user_id AND au.role = 'admin_manager'
            WHERE a.branch_id = v_branch AND a.is_archived = false AND a.id <> r.employee_id
         )
    ) INTO v_ok;
  END IF;

  IF NOT v_ok THEN
    RETURN jsonb_build_object('outcome', 'not_authorized');
  END IF;

  IF NOT p_approve THEN
    IF p_note IS NULL OR length(btrim(p_note)) < 3 THEN
      RETURN jsonb_build_object('outcome', 'note_required');
    END IF;
    UPDATE public.hr_ess_leave_requests
       SET status = 'rejected',
           decided_by_employee_id = p_decider_employee_id,
           decided_by_user_id = p_decider_user_id,
           decided_by_name = p_decider_name,
           decided_at = p_now,
           decision_note = btrim(p_note),
           manager_approved_by_employee_id = p_decider_employee_id,
           manager_approved_by_name = p_decider_name,
           manager_remark = btrim(p_note),
           manager_approved_at = p_now,
           updated_at = p_now
     WHERE id = r.id
     RETURNING * INTO r;
    INSERT INTO public.hr_ess_leave_request_history
      (request_id, at, actor_employee_id, actor_user_id, actor_name, action, note, details)
    VALUES
      (r.id, p_now, p_decider_employee_id, p_decider_user_id, p_decider_name, 'rejected', btrim(p_note),
       jsonb_build_object('type', r.type, 'day', r.day, 'stage', 'admin_manager'));
    RETURN jsonb_build_object('outcome', 'rejected', 'request', to_jsonb(r));
  END IF;

  IF r.is_teaching AND (
       p_substitute_faculty_id IS NULL
       OR p_class_timing IS NULL OR length(btrim(p_class_timing)) = 0
     ) THEN
    RETURN jsonb_build_object('outcome', 'coverage_required');
  END IF;

  UPDATE public.hr_ess_leave_requests
     SET stage = 'final',
         manager_approved_by_employee_id = p_decider_employee_id,
         manager_approved_by_name = p_decider_name,
         manager_remark = NULLIF(btrim(p_note), ''),
         manager_approved_at = p_now,
         substitute_faculty_id = p_substitute_faculty_id,
         substitute_faculty_name = NULLIF(btrim(p_substitute_faculty_name), ''),
         class_timing = NULLIF(btrim(p_class_timing), ''),
         updated_at = p_now
   WHERE id = r.id
   RETURNING * INTO r;

  INSERT INTO public.hr_ess_leave_request_history
    (request_id, at, actor_employee_id, actor_user_id, actor_name, action, note, details)
  VALUES
    (r.id, p_now, p_decider_employee_id, p_decider_user_id, p_decider_name, 'manager_approved',
     NULLIF(btrim(p_note), ''),
     jsonb_build_object(
       'type', r.type, 'day', r.day, 'end_day', r.end_day,
       'portion', r.portion, 'day_count', r.day_count,
       'stage', 'final', 'substitute_faculty_id', p_substitute_faculty_id,
       'substitute_faculty_name', r.substitute_faculty_name, 'class_timing', r.class_timing
     ));

  RETURN jsonb_build_object('outcome', 'advanced', 'request', to_jsonb(r), 'stage', 'final');
END $$;

/* Keep the final decision on the final stage. The existing function is reused for the actual
 * day write; this guard is repeated in both backends. */
CREATE OR REPLACE FUNCTION public.hr_ess_leave_stage(p_request_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$ SELECT stage FROM public.hr_ess_leave_requests WHERE id = p_request_id $$;

NOTIFY pgrst, 'reload schema';
