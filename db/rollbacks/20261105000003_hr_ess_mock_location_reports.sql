-- Rollback for db/migrations/20261105000003_hr_ess_mock_location_reports.sql: drops the one
-- table it adds, with its indexes. Nothing the Scheduler owns is touched. Safe to run twice.
--
-- This deletes every mocked-location report. Export them first if they may be needed.

DROP TABLE IF EXISTS public.hr_ess_mock_location_reports;

NOTIFY pgrst, 'reload schema';
