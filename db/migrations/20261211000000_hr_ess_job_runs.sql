-- Team RVM (ESS): the job run record (team_app #49, F-51).
--
-- Every deploy restarts the ESS process, and each job runs once at boot as well as on its timer
-- (src/server.js). For the hourly jobs that is harmless, because their work is idempotent; for the
-- weekly missing-documents reminder (src/jobs/documents.js) it meant the whole staff was told
-- again after every deploy. A row here is the claim: the first process to insert (job, period_key)
-- does the work, and every process started later in the same period finds the row and skips it.
--
-- period_key is the period the work belongs to, in IST (India time, UTC+5:30, as src/jobs/
-- runRecord.js builds it): the ISO week ('2026-W42') for the weekly reminder, the day
-- ('2026-10-16') for a job that runs daily. The pair is the primary key, so the database itself
-- refuses the second claim however many processes race for it.
--
-- status is running while the work is in flight and done when it finished. When every reminder
-- of a run failed (nothing was sent), the job deletes its claim so the next start in the same
-- period can try again (src/jobs/documents.js); a run that sent anything keeps its row.
--
-- Safe to run twice.
--
-- Rollback: db/rollbacks/20261211000000_hr_ess_job_runs.sql

CREATE TABLE IF NOT EXISTS public.hr_ess_job_runs (
  job         text NOT NULL,
  -- The period the job's work belongs to, in IST: 'YYYY-Www' (ISO week) or 'YYYY-MM-DD' (day).
  period_key  text NOT NULL,
  started_at  timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  status      text NOT NULL DEFAULT 'running'
    CONSTRAINT hr_ess_job_runs_status_chk CHECK (status IN ('running', 'done', 'failed')),
  -- One run per job per period: the claim the restarted process loses the race for.
  PRIMARY KEY (job, period_key)
);

ALTER TABLE public.hr_ess_job_runs ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON TABLE public.hr_ess_job_runs FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON TABLE public.hr_ess_job_runs FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.hr_ess_job_runs TO service_role;
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';
