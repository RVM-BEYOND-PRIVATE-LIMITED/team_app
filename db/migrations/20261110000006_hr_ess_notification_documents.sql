-- Team RVM (ESS): the documents reminder's own notification category (Phase 2C).
--
-- The same move as the Wall's six and the Helpdesk's one: one more value on
-- hr_ess_notifications.category and on hr_ess_notification_settings.disabled_categories, so the
-- weekly missing-documents job (src/jobs/documents.js) can write its reminder and a person can
-- turn it off.
--
--   documents   a document HR has looked at (verified or turned away), or the weekly reminder
--               that mandatory documents of mine are missing
--
-- Only CHECKs change: no column, no index, no row is touched (ADR-0021). Both directions are
-- re-added, so a re-run drops and re-adds the same two constraints.
--
-- Rollback: db/rollbacks/20261110000006_hr_ess_notification_documents.sql

ALTER TABLE public.hr_ess_notifications
  DROP CONSTRAINT IF EXISTS hr_ess_notifications_category_check;
ALTER TABLE public.hr_ess_notifications
  ADD CONSTRAINT hr_ess_notifications_category_check CHECK (category IN (
    'approvals', 'decisions', 'priority_tasks',
    'mentions', 'replies', 'praise', 'announcements', 'acknowledgements', 'polls',
    'helpdesk',
    'documents'
  ));

ALTER TABLE public.hr_ess_notification_settings
  DROP CONSTRAINT IF EXISTS hr_ess_notification_settings_disabled_categories_check;
ALTER TABLE public.hr_ess_notification_settings
  ADD CONSTRAINT hr_ess_notification_settings_disabled_categories_check CHECK (
    disabled_categories <@ ARRAY[
      'approvals', 'decisions', 'priority_tasks',
      'mentions', 'replies', 'praise', 'announcements', 'acknowledgements', 'polls',
      'helpdesk',
      'documents'
    ]::text[]
  );

NOTIFY pgrst, 'reload schema';
