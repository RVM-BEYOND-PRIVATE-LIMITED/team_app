-- Rollback for db/migrations/20261115000001_hr_ess_profile_and_experience.sql.
--
-- Drops the two issue #31 tables. Their rows go with them; nothing in the Scheduler is touched.
-- Safe to run twice.

DROP FUNCTION IF EXISTS public.hr_ess_replace_work_experience(uuid, jsonb);
DROP TABLE IF EXISTS public.hr_ess_work_experience;
DROP TABLE IF EXISTS public.hr_ess_profile_details;

NOTIFY pgrst, 'reload schema';
