-- Team RVM (ESS): undo the job run record (db/migrations/20261211000000_hr_ess_job_runs.sql).
-- Safe to run twice. Nothing outside the ESS's own table is touched.

DROP TABLE IF EXISTS public.hr_ess_job_runs;

NOTIFY pgrst, 'reload schema';
