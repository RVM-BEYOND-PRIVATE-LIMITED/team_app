-- Team RVM (ESS): undo the documents notification category (db/migrations/20261110000006_hr_ess_notification_documents.sql).
-- Safe to run twice.

-- Only while the tables are there: a rollback run after 20261107000001 has already dropped them
-- (the pair is rolled back in reverse order, twice), as the Helpdesk's categories rollback does.
DO $check$
BEGIN
  IF to_regclass('public.hr_ess_notifications') IS NOT NULL THEN
    ALTER TABLE public.hr_ess_notifications
      DROP CONSTRAINT IF EXISTS hr_ess_notifications_category_check;
    ALTER TABLE public.hr_ess_notifications
      ADD CONSTRAINT hr_ess_notifications_category_check CHECK (category IN (
        'approvals', 'decisions', 'priority_tasks',
        'mentions', 'replies', 'praise', 'announcements', 'acknowledgements', 'polls',
        'helpdesk'
      ));
  END IF;
  IF to_regclass('public.hr_ess_notification_settings') IS NOT NULL THEN
    ALTER TABLE public.hr_ess_notification_settings
      DROP CONSTRAINT IF EXISTS hr_ess_notification_settings_disabled_categories_check;
    ALTER TABLE public.hr_ess_notification_settings
      ADD CONSTRAINT hr_ess_notification_settings_disabled_categories_check CHECK (
        disabled_categories <@ ARRAY[
          'approvals', 'decisions', 'priority_tasks',
          'mentions', 'replies', 'praise', 'announcements', 'acknowledgements', 'polls',
          'helpdesk'
        ]::text[]
      );
  END IF;
END
$check$;

NOTIFY pgrst, 'reload schema';
