-- Team RVM (ESS): the Wall's notification categories reach the two CHECKs (task F8, D8).
--
-- Phase 1D built the notification tables with Phase 1's three categories, and left the comment
-- "the Wall's categories extend the CHECK then"
-- (db/migrations/20261107000001_hr_ess_notifications.sql:8-10). This migration is that "then":
-- six more values on hr_ess_notifications.category and on
-- hr_ess_notification_settings.disabled_categories, so the Wall can write its own notifications
-- and a person can turn them off one by one:
--   mentions         somebody @mentioned me in a post or a comment
--   replies          somebody replied to my comment
--   praise           somebody praised me
--   announcements    an announcement reached me
--   acknowledgements an announcement asks me to acknowledge it, and the reminder when I have not
--   polls            a poll I voted in has closed
--
-- Only CHECKs change: no column, no index, no row is touched, and nothing outside the ESS's own
-- two tables (ADR-0021). Both directions are re-added, so the two tables keep disagreeing about
-- nothing, and a re-run drops and re-adds the same two constraints.
--
-- Until this is applied, the Wall's endpoints still work: an announcement publishes and a mention
-- notifies nobody, each write logged as a failed notification (the same "best effort" as D6), and
-- the app's settings screen still reads and writes the Phase 1 categories.
--
-- Rollback: db/rollbacks/20261108000004_hr_ess_notification_categories.sql

ALTER TABLE public.hr_ess_notifications
  DROP CONSTRAINT IF EXISTS hr_ess_notifications_category_check;
ALTER TABLE public.hr_ess_notifications
  ADD CONSTRAINT hr_ess_notifications_category_check CHECK (category IN (
    'approvals', 'decisions', 'priority_tasks',
    'mentions', 'replies', 'praise', 'announcements', 'acknowledgements', 'polls'
  ));

ALTER TABLE public.hr_ess_notification_settings
  DROP CONSTRAINT IF EXISTS hr_ess_notification_settings_disabled_categories_check;
ALTER TABLE public.hr_ess_notification_settings
  ADD CONSTRAINT hr_ess_notification_settings_disabled_categories_check CHECK (
    disabled_categories <@ ARRAY[
      'approvals', 'decisions', 'priority_tasks',
      'mentions', 'replies', 'praise', 'announcements', 'acknowledgements', 'polls'
    ]::text[]
  );

NOTIFY pgrst, 'reload schema';
