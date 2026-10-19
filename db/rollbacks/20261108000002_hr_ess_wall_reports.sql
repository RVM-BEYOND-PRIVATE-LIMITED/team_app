-- Rollback of db/migrations/20261108000002_hr_ess_wall_reports.sql.
--
-- Drops the report queue and the celebration opt-out table. hr_ess_wall_reports' rows are HR's
-- record of what was reported and how it was answered; dropping it discards that record, so run
-- this only to take the Wall out, with 20261108000001 first (its post and comment tables are
-- what these rows point at).
--
-- Safe to run twice.

DROP TABLE IF EXISTS public.hr_ess_wall_reports;
DROP TABLE IF EXISTS public.hr_ess_celebration_optouts;

NOTIFY pgrst, 'reload schema';
