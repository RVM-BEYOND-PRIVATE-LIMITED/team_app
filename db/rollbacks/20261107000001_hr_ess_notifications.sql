-- Rollback for db/migrations/20261107000001_hr_ess_notifications.sql: drops the notification and
-- settings tables it adds. Nothing else changes; the Inbox starts empty when they are created
-- again. Safe to run twice.

DROP TABLE IF EXISTS public.hr_ess_notification_settings;
DROP TABLE IF EXISTS public.hr_ess_notifications;

NOTIFY pgrst, 'reload schema';
