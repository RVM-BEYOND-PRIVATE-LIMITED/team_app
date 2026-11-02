-- Team RVM (ESS): faculty final approval goes to the HOO.
--
-- RVM, Nov 2026: Vishal Narwat (super admin) for Pune/Ahmedabad, Bhupender Singh
-- for Faridabad/Lucknow. Non-faculty stays a single approval by the reporting
-- manager. Additive and safe to run twice.

CREATE TABLE IF NOT EXISTS public.hr_ess_leave_final_approvers (
  branch_id             uuid PRIMARY KEY REFERENCES public.hr_branches(id) ON DELETE CASCADE,
  employee_id           uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  configured_by_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  configured_by_name    text,
  updated_at            timestamptz NOT NULL DEFAULT now()
);

-- Re-assert the HOO mapping (match code first, then name, case-insensitive).
WITH mapping(branch_name, employee_code, full_name) AS (
  VALUES
    ('Faridabad', 'RVM/F/43', 'Bhupender Singh'),
    ('Lucknow',   'RVM/F/43', 'Bhupender Singh'),
    ('Pune',      'RVM/F/29', 'Vishal Narwat'),
    ('Ahmedabad', 'RVM/F/29', 'Vishal Narwat')
), resolved AS (
  SELECT b.id AS branch_id, e.id AS employee_id
    FROM mapping m
    JOIN public.hr_branches b ON b.name = m.branch_name
    JOIN public.hr_employees e
      ON e.is_archived = false
     AND (e.employee_code = m.employee_code OR lower(e.full_name) = lower(m.full_name))
)
INSERT INTO public.hr_ess_leave_final_approvers (branch_id, employee_id, configured_by_name)
SELECT branch_id, employee_id, 'HOO final — Nov 2026'
  FROM resolved
ON CONFLICT (branch_id) DO UPDATE
  SET employee_id = EXCLUDED.employee_id,
      configured_by_name = EXCLUDED.configured_by_name,
      updated_at = now();

-- Backfill pending faculty requests waiting at final with no named HOO.
WITH routed AS (
  SELECT l.id, r.final_approver_employee_id, r.final_approver_name
    FROM public.hr_ess_leave_requests l
    CROSS JOIN LATERAL public.hr_ess_leave_route(l.employee_id) r
   WHERE l.status = 'pending'
     AND l.stage = 'final'
     AND l.final_approver_employee_id IS NULL
     AND r.final_approver_employee_id IS NOT NULL
)
UPDATE public.hr_ess_leave_requests l
   SET final_approver_employee_id = routed.final_approver_employee_id,
       final_approver_name = routed.final_approver_name,
       updated_at = now()
  FROM routed
 WHERE l.id = routed.id;

NOTIFY pgrst, 'reload schema';
