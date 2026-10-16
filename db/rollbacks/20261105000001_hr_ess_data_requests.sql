-- Rollback for db/migrations/20261105000001_hr_ess_data_requests.sql: drops the one table it
-- adds, with its indexes and its trigger, then the trigger's function. Nothing the Scheduler owns
-- is touched. Safe to run twice.
--
-- This deletes every request to correct or delete data, open or closed. Export it first if it may
-- be needed.

DROP TABLE IF EXISTS public.hr_ess_data_requests;
DROP FUNCTION IF EXISTS public.hr_ess_data_requests_open_limit();

NOTIFY pgrst, 'reload schema';
