-- Team RVM (ESS): undo push reliability (db/migrations/20261231100000_hr_ess_push_reliability.sql).
-- Safe to run twice. The notification column only while the table is there: a rollback run after
-- 20261107000001 has already dropped it.

DROP TABLE IF EXISTS public.hr_ess_worker_runs;

DO $check$
BEGIN
  IF to_regclass('public.hr_ess_notifications') IS NOT NULL THEN
    DROP INDEX IF EXISTS public.hr_ess_notifications_dedupe_uq;
    ALTER TABLE public.hr_ess_notifications
      DROP CONSTRAINT IF EXISTS hr_ess_notifications_dedupe_key_chk;
    ALTER TABLE public.hr_ess_notifications
      DROP COLUMN IF EXISTS dedupe_key;
  END IF;
END
$check$;

NOTIFY pgrst, 'reload schema';
