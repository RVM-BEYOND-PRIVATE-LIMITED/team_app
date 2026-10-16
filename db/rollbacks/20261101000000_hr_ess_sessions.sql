-- Rollback of db/migrations/20261101000000_hr_ess_sessions.sql: the session functions, then the
-- table. Touches nothing else. Safe to run twice.
--
-- Every kept sign-in in the app ends with it. Access tokens the ESS minted stay good on the
-- Scheduler until their hour is out; on the ESS they and every refresh answer 503
-- MODULE_NOT_INSTALLED, which the app does not sign out on, so tell staff to sign out of the app
-- and in again once the code that needs this table is gone too.

DROP FUNCTION IF EXISTS public.hr_ess_session_rotate(uuid, uuid, text, timestamptz, timestamptz);
DROP FUNCTION IF EXISTS public.hr_ess_session_revoke(uuid, text, timestamptz, uuid);
DROP TABLE IF EXISTS public.hr_ess_sessions;

NOTIFY pgrst, 'reload schema';
