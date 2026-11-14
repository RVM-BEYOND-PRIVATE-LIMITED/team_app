-- Team RVM (ESS): the CRM's notification categories (team_app #59, TA-P-01).
--
-- The same move as the Wall's six, the Helpdesk's one and the documents reminder: values on
-- hr_ess_notifications.category and on hr_ess_notification_settings.disabled_categories, so the
-- CRM can write its notifications and a person can turn them off.
--
--   crm_callback        a callback the sales team promised
--   crm_call            a call placed from the web
--   crm_lead_assigned   a lead assigned to me
--   crm_followup        a follow-up due
--   crm_alert           a sales alert
--
-- The first two are the urgent ones: 20261211000001 lets only these two carry priority 'urgent'.
-- Only CHECKs change: no column, no index, no row is touched (ADR-0021). Both directions are
-- re-added, so a re-run drops and re-adds the same two constraints.
--
-- Rollback: db/rollbacks/20261211000002_hr_ess_notification_categories_3.sql

ALTER TABLE public.hr_ess_notifications
  DROP CONSTRAINT IF EXISTS hr_ess_notifications_category_check;
ALTER TABLE public.hr_ess_notifications
  ADD CONSTRAINT hr_ess_notifications_category_check CHECK (category IN (
    'approvals', 'decisions', 'priority_tasks',
    'mentions', 'replies', 'praise', 'announcements', 'acknowledgements', 'polls',
    'helpdesk',
    'documents',
    'crm_callback', 'crm_call', 'crm_lead_assigned', 'crm_followup', 'crm_alert'
  ));

ALTER TABLE public.hr_ess_notification_settings
  DROP CONSTRAINT IF EXISTS hr_ess_notification_settings_disabled_categories_check;
ALTER TABLE public.hr_ess_notification_settings
  ADD CONSTRAINT hr_ess_notification_settings_disabled_categories_check CHECK (
    disabled_categories <@ ARRAY[
      'approvals', 'decisions', 'priority_tasks',
      'mentions', 'replies', 'praise', 'announcements', 'acknowledgements', 'polls',
      'helpdesk',
      'documents',
      'crm_callback', 'crm_call', 'crm_lead_assigned', 'crm_followup', 'crm_alert'
    ]::text[]
  );

NOTIFY pgrst, 'reload schema';
