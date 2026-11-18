-- Team RVM (ESS): undo the social module's notification categories
-- (db/migrations/20261231100001_hr_ess_notification_categories_4.sql), back to 20261211000002's list.
-- Safe to run twice. A row already queued under 'shoots' or 'social' must be removed first, or the CHECK refuses:
--   DELETE FROM public.hr_ess_notifications WHERE category IN ('shoots', 'social');

DO $check$
BEGIN
  IF to_regclass('public.hr_ess_notifications') IS NOT NULL THEN
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
  END IF;
  IF to_regclass('public.hr_ess_notification_settings') IS NOT NULL THEN
    UPDATE public.hr_ess_notification_settings
       SET disabled_categories = array_remove(array_remove(disabled_categories, 'shoots'), 'social')
     WHERE disabled_categories && ARRAY['shoots', 'social']::text[];
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
  END IF;
END
$check$;

NOTIFY pgrst, 'reload schema';
