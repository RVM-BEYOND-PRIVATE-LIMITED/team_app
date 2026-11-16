-- Team RVM (ESS): push reliability (team_app #92 and #95, enhancements of #59).
--
--   hr_ess_notifications.dedupe_key   #95: an optional key per writer. With it, a writer that retries (a timeout, a
--                                      second process, a re-run job) cannot notify the same person twice: the
--                                      database refuses the second row (unique per person and key) and the store
--                                      answers "already there". Rows without a key are exactly as before.
--   hr_ess_worker_runs                 #92: one row per push loop ('push_minute', 'push_urgent'): when it last
--                                      started and finished, whether that run went through, its counts, how many
--                                      runs and failures. A loop that stopped shows as a stale finished_at.
--
-- Safe to run twice.
--
-- Rollback: db/rollbacks/20261231100000_hr_ess_push_reliability.sql

SET lock_timeout = '3s';

ALTER TABLE public.hr_ess_notifications
  ADD COLUMN IF NOT EXISTS dedupe_key text;
ALTER TABLE public.hr_ess_notifications
  DROP CONSTRAINT IF EXISTS hr_ess_notifications_dedupe_key_chk;
ALTER TABLE public.hr_ess_notifications
  ADD CONSTRAINT hr_ess_notifications_dedupe_key_chk CHECK (dedupe_key IS NULL OR char_length(dedupe_key) BETWEEN 3 AND 200);
CREATE UNIQUE INDEX IF NOT EXISTS hr_ess_notifications_dedupe_uq
  ON public.hr_ess_notifications (employee_id, dedupe_key) WHERE dedupe_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.hr_ess_worker_runs (
  worker           text PRIMARY KEY
    CONSTRAINT hr_ess_worker_runs_worker_chk CHECK (worker ~ '^[a-z][a-z0-9_]{2,40}$'),
  last_started_at  timestamptz,
  last_finished_at timestamptz,
  last_ok          boolean,
  last_counts      jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(last_counts) = 'object'),
  runs             bigint NOT NULL DEFAULT 0,
  failures         bigint NOT NULL DEFAULT 0,
  updated_at       timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.hr_ess_worker_runs ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON TABLE public.hr_ess_worker_runs FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON TABLE public.hr_ess_worker_runs FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.hr_ess_worker_runs TO service_role;
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
