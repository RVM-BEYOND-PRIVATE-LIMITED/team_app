-- Team RVM (ESS): undo the urgent notification lane
-- (db/migrations/20261211000001_hr_ess_notification_priority.sql).
-- Safe to run twice. Only while the table is there: a rollback run after 20261107000001 has
-- already dropped it.

DO $check$
BEGIN
  IF to_regclass('public.hr_ess_notifications') IS NOT NULL THEN
    DROP INDEX IF EXISTS public.hr_ess_notifications_urgent_idx;
    ALTER TABLE public.hr_ess_notifications
      DROP CONSTRAINT IF EXISTS hr_ess_notifications_urgent_category_chk;
    ALTER TABLE public.hr_ess_notifications
      DROP CONSTRAINT IF EXISTS hr_ess_notifications_priority_chk;
    ALTER TABLE public.hr_ess_notifications
      DROP COLUMN IF EXISTS priority;
  END IF;
END
$check$;

NOTIFY pgrst, 'reload schema';
