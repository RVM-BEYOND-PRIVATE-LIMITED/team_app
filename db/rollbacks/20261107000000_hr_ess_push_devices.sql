-- Rollback for db/migrations/20261107000000_hr_ess_push_devices.sql: drops the one table it adds.
-- Nothing else changes; push stops for every phone until the migration is applied again. Safe to
-- run twice.

DROP TABLE IF EXISTS public.hr_ess_push_devices;

NOTIFY pgrst, 'reload schema';
