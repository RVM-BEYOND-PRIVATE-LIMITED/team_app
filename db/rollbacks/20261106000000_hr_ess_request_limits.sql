-- Rollback for db/migrations/20261106000000_hr_ess_request_limits.sql: drops the one table it
-- adds. Nothing the Scheduler owns is touched. Safe to run twice.
--
-- This deletes the numbers HR has set; they come back at their seeded values when the migration
-- is applied again.

DROP TABLE IF EXISTS public.hr_ess_request_limits;

NOTIFY pgrst, 'reload schema';
