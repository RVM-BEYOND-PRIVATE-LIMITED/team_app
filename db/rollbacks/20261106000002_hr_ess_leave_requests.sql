-- Rollback for db/migrations/20261106000002_hr_ess_leave_requests.sql: drops the leave-request
-- table and its history, with the trigger and the trigger's function. Nothing the Scheduler owns
-- is touched. Safe to run twice.
--
-- This deletes every leave request and its history. An approved request that wrote a day leaves
-- that day as it is: cancelling it would need the day_before rows, which go with this table.

DROP TRIGGER IF EXISTS hr_ess_leave_requests_filed_trg ON public.hr_ess_leave_requests;
DROP FUNCTION IF EXISTS public.hr_ess_leave_requests_filed();
DROP TABLE IF EXISTS public.hr_ess_leave_request_history;
DROP TABLE IF EXISTS public.hr_ess_leave_requests;

NOTIFY pgrst, 'reload schema';
