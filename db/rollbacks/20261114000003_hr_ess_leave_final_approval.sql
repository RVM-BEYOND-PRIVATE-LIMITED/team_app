-- Rollback: 20261114000003_hr_ess_leave_final_approval.sql
--
-- Removes the final-round columns and puts the history action list back. Requests already at
-- the final stage keep their `pending` status; without `stage` they simply behave as their
-- manager's approval would have. Run 20261114000002 before this if WFH's cancel must be undone.

DROP INDEX IF EXISTS public.hr_ess_leave_requests_stage_idx;

-- Safe to run twice, including after the leave tables themselves have been rolled back.
DO $restore$
BEGIN
  IF to_regclass('public.hr_ess_leave_request_history') IS NOT NULL THEN
    ALTER TABLE public.hr_ess_leave_request_history
      DROP CONSTRAINT IF EXISTS hr_ess_leave_request_history_action_check;
    ALTER TABLE public.hr_ess_leave_request_history
      ADD CONSTRAINT hr_ess_leave_request_history_action_check
      CHECK (action IN ('filed', 'approved', 'rejected', 'withdrawn', 'cancelled'));
  END IF;

  IF to_regclass('public.hr_ess_leave_requests') IS NOT NULL THEN
    ALTER TABLE public.hr_ess_leave_requests
      DROP CONSTRAINT IF EXISTS hr_ess_leave_requests_stage_chk,
      DROP CONSTRAINT IF EXISTS hr_ess_leave_requests_manager_remark_chk,
      DROP CONSTRAINT IF EXISTS hr_ess_leave_requests_final_stage_chk;

    ALTER TABLE public.hr_ess_leave_requests
      DROP COLUMN IF EXISTS requires_final_approval,
      DROP COLUMN IF EXISTS stage,
      DROP COLUMN IF EXISTS manager_approved_by_employee_id,
      DROP COLUMN IF EXISTS manager_approved_by_name,
      DROP COLUMN IF EXISTS manager_remark,
      DROP COLUMN IF EXISTS manager_approved_at;
  END IF;
END
$restore$;

NOTIFY pgrst, 'reload schema';
