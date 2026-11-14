-- Team RVM (ESS): undo the 'superseded' reason (db/migrations/20261231000017_hr_ess_session_superseded.sql).
-- A sign-in already ended as superseded reads as signed out afterwards. Safe to run twice.

DO $rollback$
BEGIN
  IF to_regclass('public.hr_ess_sessions') IS NOT NULL THEN
    UPDATE public.hr_ess_sessions SET revoked_reason = 'signed_out' WHERE revoked_reason = 'superseded';
    ALTER TABLE public.hr_ess_sessions DROP CONSTRAINT IF EXISTS hr_ess_sessions_revoked_reason_check;
    ALTER TABLE public.hr_ess_sessions ADD CONSTRAINT hr_ess_sessions_revoked_reason_check CHECK (revoked_reason IN
      ('rotated', 'signed_out', 'reuse', 'password_changed', 'login_off', 'left', 'unlinked', 'expired'));
  END IF;
  IF to_regprocedure('public.hr_ess_session_revoke(uuid, text, timestamptz, uuid)') IS NOT NULL THEN
    EXECUTE $fn$
      CREATE OR REPLACE FUNCTION public.hr_ess_session_revoke(
        p_family_id   uuid,
        p_reason      text,
        p_now         timestamptz,
        p_employee_id uuid DEFAULT NULL
      )
      RETURNS integer
      LANGUAGE plpgsql
      SET search_path = public, pg_temp
      AS $body$
      DECLARE
        v_count integer;
      BEGIN
        IF p_reason IS NULL OR p_reason NOT IN ('signed_out', 'reuse', 'password_changed', 'login_off', 'left', 'unlinked', 'expired') THEN
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
      END $body$;
    $fn$;
  END IF;
END $rollback$;

NOTIFY pgrst, 'reload schema';
