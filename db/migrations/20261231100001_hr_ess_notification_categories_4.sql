-- Team RVM (ESS): the social module's notification categories (team_app #129).
--
-- The Scheduler's social module (Scheduler_Backend #180) writes its notices into this queue through its relay
-- (sm_relay_due): a shoot booked, moved or coming up tomorrow or in an hour lands under 'shoots'; a card allotted to an
-- editor, a stuck card, a Done card with no post date and a clash under 'social'. Until now the queue's CHECK refused both,
-- so those notices waited in sm_outbox with the error and never reached a phone.
--
--   shoots   a shoot I am tagged on: booked, moved, the day before, the hour before
--   social   the social media team's work: a card allotted to me, a stuck card, the kitty, a clash
--
-- Neither is urgent (20261211000001 keeps 'urgent' for the two CRM categories), so both wait for the quiet hours like
-- every other category. Only CHECKs change: no column, no index, no row is touched (ADR-0021). Both directions are
-- re-added, so a re-run drops and re-adds the same two constraints.
--
-- Rollback: db/rollbacks/20261231100001_hr_ess_notification_categories_4.sql

ALTER TABLE public.hr_ess_notifications
  DROP CONSTRAINT IF EXISTS hr_ess_notifications_category_check;
ALTER TABLE public.hr_ess_notifications
  ADD CONSTRAINT hr_ess_notifications_category_check CHECK (category IN (
    'approvals', 'decisions', 'priority_tasks',
    'mentions', 'replies', 'praise', 'announcements', 'acknowledgements', 'polls',
    'helpdesk',
    'documents',
    'crm_callback', 'crm_call', 'crm_lead_assigned', 'crm_followup', 'crm_alert',
    'shoots', 'social'
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
      'crm_callback', 'crm_call', 'crm_lead_assigned', 'crm_followup', 'crm_alert',
      'shoots', 'social'
    ]::text[]
  );

NOTIFY pgrst, 'reload schema';
