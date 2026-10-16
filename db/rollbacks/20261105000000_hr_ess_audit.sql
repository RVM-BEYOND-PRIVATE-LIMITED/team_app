-- Rollback for db/migrations/20261105000000_hr_ess_audit.sql: drops the one table it adds, with
-- its indexes. Nothing the Scheduler owns is touched. Safe to run twice.
--
-- This deletes the record of every HR phone reset, data-request resolution and personal-details
-- read. Export it first if it may be needed.

DROP TABLE IF EXISTS public.hr_ess_audit;

NOTIFY pgrst, 'reload schema';
