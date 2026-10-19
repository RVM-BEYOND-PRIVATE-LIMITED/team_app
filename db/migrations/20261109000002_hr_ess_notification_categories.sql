-- Team RVM (ESS): the Helpdesk's notification category reaches the two CHECKs (Phase 2B, G2).
--
-- The same move as the Wall's six (db/migrations/20261108000004_hr_ess_notification_categories.sql):
-- one more value on hr_ess_notifications.category and on
-- hr_ess_notification_settings.disabled_categories, so the Helpdesk can write its own
-- notifications -- a raise telling the team, a reply telling the raiser, and G3's escalations --
-- and a person can turn them off.
--
--   helpdesk   a ticket of mine moved, or one of my team's arrived or is overdue
--
-- Only CHECKs change: no column, no index, no row is touched, and nothing outside the ESS's own
-- two tables (ADR-0021). Both directions are re-added, so the two tables keep disagreeing about
-- nothing, and a re-run drops and re-adds the same two constraints.
--
-- Until this is applied, the Helpdesk's endpoints still work: a ticket is raised and nobody is
-- told, each write logged as a failed notification (the same "best effort" as D6).
--
-- Rollback: db/rollbacks/20261109000002_hr_ess_notification_categories.sql

ALTER TABLE public.hr_ess_notifications
  DROP CONSTRAINT IF EXISTS hr_ess_notifications_category_check;
ALTER TABLE public.hr_ess_notifications
  ADD CONSTRAINT hr_ess_notifications_category_check CHECK (category IN (
    'approvals', 'decisions', 'priority_tasks',
    'mentions', 'replies', 'praise', 'announcements', 'acknowledgements', 'polls',
    'helpdesk'
  ));

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

NOTIFY pgrst, 'reload schema';
