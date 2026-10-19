-- Rollback of db/migrations/20261108000004_hr_ess_notification_categories.sql.
--
-- Puts the two CHECKs back to Phase 1D's three categories (the exact constraint text of
-- db/migrations/20261107000001_hr_ess_notifications.sql:24 and :54). Nothing else is touched.
--
-- It fails if any row still holds one of the Wall's six categories, which is the database saying
-- "delete those notifications first": dropping them is a person's data, so this file does not do
-- it by itself. Either wait for those rows to age out, or, once KP agrees, run
--   DELETE FROM public.hr_ess_notifications WHERE category IN
--     ('mentions', 'replies', 'praise', 'announcements', 'acknowledgements', 'polls');
--   DELETE FROM public.hr_ess_notification_settings WHERE disabled_categories && ARRAY[
--     'mentions', 'replies', 'praise', 'announcements', 'acknowledgements', 'polls']::text[];
-- and then run this. Safe to re-run once the rows are gone.

-- Only while the tables are there: a rollback run after 20261107000001 has already dropped them
-- (the pair is rolled back in reverse order, twice).
DO $check$
BEGIN
  IF to_regclass('public.hr_ess_notifications') IS NOT NULL THEN
    ALTER TABLE public.hr_ess_notifications
      DROP CONSTRAINT IF EXISTS hr_ess_notifications_category_check;
    ALTER TABLE public.hr_ess_notifications
      ADD CONSTRAINT hr_ess_notifications_category_check
      CHECK (category IN ('approvals', 'decisions', 'priority_tasks'));
  END IF;
  IF to_regclass('public.hr_ess_notification_settings') IS NOT NULL THEN
    ALTER TABLE public.hr_ess_notification_settings
      DROP CONSTRAINT IF EXISTS hr_ess_notification_settings_disabled_categories_check;
    ALTER TABLE public.hr_ess_notification_settings
      ADD CONSTRAINT hr_ess_notification_settings_disabled_categories_check
      CHECK (disabled_categories <@ ARRAY['approvals', 'decisions', 'priority_tasks']::text[]);
  END IF;
END
$check$;

NOTIFY pgrst, 'reload schema';
