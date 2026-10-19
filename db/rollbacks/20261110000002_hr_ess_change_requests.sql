-- Team RVM (ESS): undo the profile-change requests (db/migrations/20261110000002_hr_ess_change_requests.sql).
-- Safe to run twice: everything is IF EXISTS.

DROP TABLE IF EXISTS public.hr_ess_change_requests;

NOTIFY pgrst, 'reload schema';
