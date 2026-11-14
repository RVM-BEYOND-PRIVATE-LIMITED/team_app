-- Team RVM (ESS): one live Team-app sign-in per person (issue #59 item 10, with Scheduler_Backend #175).
--
-- A new reason a sign-in ends: 'superseded', the person signed in on another phone. While the Scheduler's
-- switch team_security is open for the person, a new sign-in ends their other live sign-ins with it, so the
-- old phone is signed out at its next request and its next refresh says why.
--
--   * the CHECK on hr_ess_sessions.revoked_reason gains 'superseded';
--   * hr_ess_session_revoke accepts it (the body is otherwise the one in 20261101000000).
--
-- Additive: nothing ends with this reason until the switch is opened. Numbered after the Scheduler's latest
-- migration (20261231000016). Safe to run twice.
--
-- Rollback: db/rollbacks/20261231000017_hr_ess_session_superseded.sql

ALTER TABLE public.hr_ess_sessions DROP CONSTRAINT IF EXISTS hr_ess_sessions_revoked_reason_check;
ALTER TABLE public.hr_ess_sessions ADD CONSTRAINT hr_ess_sessions_revoked_reason_check CHECK (revoked_reason IN
  ('rotated', 'signed_out', 'reuse', 'password_changed', 'login_off', 'left', 'unlinked', 'expired', 'superseded'));

CREATE OR REPLACE FUNCTION public.hr_ess_session_revoke(
  p_family_id   uuid,
  p_reason      text,
  p_now         timestamptz,
  p_employee_id uuid DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count integer;
BEGIN
  IF p_reason IS NULL OR p_reason NOT IN ('signed_out', 'reuse', 'password_changed', 'login_off', 'left', 'unlinked', 'expired', 'superseded') THEN
    RAISE EXCEPTION 'hr_ess_session_revoke: % is not a reason to end a sign-in', coalesce(p_reason, 'NULL');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('hr_ess_sessions:' || p_family_id::text, 0));

  UPDATE public.hr_ess_sessions s
     SET revoked_at = p_now, revoked_reason = p_reason
   WHERE s.family_id = p_family_id
     AND s.revoked_at IS NULL
     AND (p_employee_id IS NULL OR s.employee_id = p_employee_id);
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END $$;

REVOKE EXECUTE ON FUNCTION public.hr_ess_session_revoke(uuid, text, timestamptz, uuid) FROM PUBLIC;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE EXECUTE ON FUNCTION public.hr_ess_session_revoke(uuid, text, timestamptz, uuid) FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE EXECUTE ON FUNCTION public.hr_ess_session_revoke(uuid, text, timestamptz, uuid) FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT EXECUTE ON FUNCTION public.hr_ess_session_revoke(uuid, text, timestamptz, uuid) TO service_role;
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
