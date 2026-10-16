-- Rollback for db/migrations/20261105000002_hr_ess_personal_details.sql: drops the one table it
-- adds. Nothing the Scheduler owns is touched. Safe to run twice.
--
-- This deletes every employee's personal details. Export them first if they may be needed.

DROP TABLE IF EXISTS public.hr_ess_personal_details;

NOTIFY pgrst, 'reload schema';
