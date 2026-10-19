-- Rollback for db/migrations/20261106000001_hr_ess_attendance_requests.sql: drops the request
-- table and its history, with the trigger and the trigger's function. Nothing the Scheduler owns
-- is touched. Safe to run twice.
--
-- This deletes every attendance request and its history. An approved request that wrote a day
-- leaves that day as it is: cancelling it would need the day_before rows, which go with this
-- table. Export the table first if that matters.

DROP TRIGGER IF EXISTS hr_ess_attendance_requests_filed_trg ON public.hr_ess_attendance_requests;
DROP FUNCTION IF EXISTS public.hr_ess_attendance_requests_filed();
DROP TABLE IF EXISTS public.hr_ess_attendance_request_history;
DROP TABLE IF EXISTS public.hr_ess_attendance_requests;

NOTIFY pgrst, 'reload schema';
