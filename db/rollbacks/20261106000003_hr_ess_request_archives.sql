-- Rollback for db/migrations/20261106000003_hr_ess_request_archives.sql: drops the one table it
-- adds. Nothing else changes: an archived request is still a request. Safe to run twice.

DROP TABLE IF EXISTS public.hr_ess_request_archives;

NOTIFY pgrst, 'reload schema';
