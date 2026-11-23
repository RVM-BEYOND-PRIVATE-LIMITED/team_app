-- Rollback for db/migrations/20261231200000_hr_ess_feedback.sql: drops the one table it adds,
-- with its indexes. Nothing the Scheduler owns is touched. Safe to run twice.
--
-- This deletes every feedback item. Export it first if it may be needed. The screenshots stay in
-- the ESS bucket under feedback/ until they are removed by hand.

DROP TABLE IF EXISTS public.hr_ess_feedback;

NOTIFY pgrst, 'reload schema';
