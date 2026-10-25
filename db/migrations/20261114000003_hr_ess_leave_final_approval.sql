-- Team RVM (ESS): a faculty member's leave needs a final round after their manager.
--
-- RVM, 26 Oct 2026: "For faculty even though their manager approve leaves it has to go through
-- one more round of approvals only for faculties either HR or superadmin or CEO to get the
-- leave approved." Super admins and the CEO may approve any leave, as before.
--
-- The request stays `pending` through both rounds. `stage` says who must act next:
--   manager  the reporting line may decide (and, for a faculty member, only advance it)
--   final    only HR, the CEO or a super admin may decide; their approval writes the days
-- A non-faculty request has requires_final_approval = false, so the manager's approval is final
-- as it always was. HR, the CEO and a super admin still decide anything at either stage.
--
-- `manager_remark` is the manager's word carried to the employee and the final approver; the
-- final approver's own remark stays in decision_note.
--
-- New columns only (ADR-0021). Safe to run twice.

ALTER TABLE public.hr_ess_leave_requests
  ADD COLUMN IF NOT EXISTS requires_final_approval boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS stage                  text NOT NULL DEFAULT 'manager',
  ADD COLUMN IF NOT EXISTS manager_approved_by_employee_id uuid REFERENCES public.hr_employees(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS manager_approved_by_name text,
  ADD COLUMN IF NOT EXISTS manager_remark         text,
  ADD COLUMN IF NOT EXISTS manager_approved_at    timestamptz;

DO $$
BEGIN
  ALTER TABLE public.hr_ess_leave_requests
    ADD CONSTRAINT hr_ess_leave_requests_stage_chk
    CHECK (stage IN ('manager', 'final'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$
BEGIN
  ALTER TABLE public.hr_ess_leave_requests
    ADD CONSTRAINT hr_ess_leave_requests_manager_remark_chk
    CHECK (manager_remark IS NULL OR length(btrim(manager_remark)) BETWEEN 1 AND 1000);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- A final-stage request always waits on somebody: keep the two facts together.
DO $$
BEGIN
  ALTER TABLE public.hr_ess_leave_requests
    ADD CONSTRAINT hr_ess_leave_requests_final_stage_chk
    CHECK (NOT requires_final_approval OR stage IN ('manager', 'final'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS hr_ess_leave_requests_stage_idx
  ON public.hr_ess_leave_requests (stage, status) WHERE status = 'pending';

-- The manager's advance is its own history action, distinct from the final approval.
ALTER TABLE public.hr_ess_leave_request_history
  DROP CONSTRAINT IF EXISTS hr_ess_leave_request_history_action_check;
ALTER TABLE public.hr_ess_leave_request_history
  ADD CONSTRAINT hr_ess_leave_request_history_action_check
  CHECK (action IN ('filed', 'manager_approved', 'approved', 'rejected', 'withdrawn', 'cancelled'));

NOTIFY pgrst, 'reload schema';
