-- Team RVM: staying signed in (task A3; KP, 16 Oct 2026).
--
-- The app trades a fresh Scheduler sign-in for a refresh token, and the ESS mints one-hour access
-- tokens from it in the Scheduler's own two formats (ADR-0006), signed with the shared JWT_SECRET.
-- This table is the ESS's record of those kept sign-ins.
--
--   * ONE ROW PER REFRESH TOKEN. Every refresh retires the row it was given ('rotated') and adds
--     the next one in the same family, so a family is one sign-in and a row is one turn of it. A
--     family's id is its first row's id.
--   * The refresh token is never stored, only its hash (refresh_hash): HMAC-SHA256 under a key
--     derived from JWT_SECRET, so rotating that secret still ends every sign-in, kept ones too.
--   * signed_in_at is the iat of the Scheduler token that was traded in. Every token the ESS mints
--     carries it as its own iat (apps/ess-api/src/lib/accessTokens.js), so the Scheduler's 15-minute
--     password window and its sessions_valid_from cut-off go on working unchanged.
--   * A sign-in lasts 90 days from its last refresh (expires_at moves on at every turn), and ends at
--     once on sign-out, on a refresh token presented twice ('reuse'), on a password change, when HR
--     switches the attendance login off, and when the person leaves.
--   * ONE TRADE PER SIGN-IN. A Scheduler token can be traded once: a second trade of the same token
--     (the same person, kind and signed_in_at) breaks hr_ess_sessions_sign_in_key, and the ESS
--     answers 409. Otherwise anybody holding a copy of a fresh token could start a 90-day sign-in of
--     their own beside the app's.
--   * A PORTAL PASSWORD CHANGE ENDS THE SIGN-IN, however the Scheduler made it. Only two of its five
--     password writes stamp users.password_changed_at (profileController.js:271-274,
--     authSecurityController.js:176-179); updateUser, resetPassword and changeOwnPassword
--     (userController.js:1022-1031, 1231-1236, 1313-1318) write password_hash alone. So a portal
--     sign-in also keeps password_fingerprint, a SHA-256 of users.password_hash taken by the trigger
--     below as the row goes in, and every refresh asks hr_ess_session_password_current whether it
--     still matches. The hash and its fingerprint never leave the database.
--
-- New table and functions only. Nothing the Scheduler owns is altered (ADR-0018, ADR-0021): the two
-- foreign keys live on this table and point at hr_employees and users. Row-level security is on
-- with no policy, and the API roles get no grants, so only the service role reaches it. Safe to run
-- twice.
--
-- Rollback: db/rollbacks/20261101000000_hr_ess_sessions.sql

CREATE TABLE IF NOT EXISTS public.hr_ess_sessions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id       uuid NOT NULL,
  -- Leaving the HR record or the login behind removes its sign-ins with it.
  employee_id     uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  login_kind      text NOT NULL CHECK (login_kind IN ('portal', 'attendance')),
  user_id         uuid REFERENCES public.users(id) ON DELETE CASCADE,
  -- The branch the person signed in at, which the Scheduler signs into its token unchecked and the
  -- ESS carries into every token it mints (portal only).
  location_name   text,
  -- How the attendance sign-in was earned: a code or the password (attendance only).
  method          text CHECK (method IN ('otp', 'pw')),
  signed_in_at    timestamptz NOT NULL,
  install_id      text NOT NULL,
  device_label    text,
  refresh_hash    text NOT NULL UNIQUE,
  -- Portal only: SHA-256 (hex) of users.password_hash when the sign-in was kept. Set by
  -- hr_ess_sessions_bind_password on a family's first row, and copied by hr_ess_session_rotate,
  -- so every turn of the sign-in is held to the password it was kept with. Never read by the ESS.
  password_fingerprint text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  last_used_at    timestamptz NOT NULL DEFAULT now(),
  expires_at      timestamptz NOT NULL,
  replaced_by     uuid,
  revoked_at      timestamptz,
  revoked_reason  text CHECK (revoked_reason IN
                    ('rotated', 'signed_out', 'reuse', 'password_changed', 'login_off', 'left', 'unlinked', 'expired')),

  -- A portal sign-in names its account and has no method; an attendance one the other way round.
  CONSTRAINT hr_ess_sessions_kind_fields CHECK (
    (login_kind = 'portal' AND user_id IS NOT NULL AND method IS NULL)
    OR (login_kind = 'attendance' AND user_id IS NULL AND method IS NOT NULL AND location_name IS NULL)),
  CONSTRAINT hr_ess_sessions_revoked_with_reason CHECK ((revoked_at IS NULL) = (revoked_reason IS NULL)),
  -- The app's own random install id, and its own name for the phone.
  CONSTRAINT hr_ess_sessions_install_id CHECK (install_id ~ '^[A-Za-z0-9._-]{16,128}$'),
  CONSTRAINT hr_ess_sessions_device_label CHECK (char_length(device_label) <= 80),
  CONSTRAINT hr_ess_sessions_refresh_hash CHECK (refresh_hash ~ '^[0-9a-f]{64}$'),
  CONSTRAINT hr_ess_sessions_password_fingerprint CHECK (
    password_fingerprint IS NULL OR (password_fingerprint ~ '^[0-9a-f]{64}$' AND login_kind = 'portal')),
  CONSTRAINT hr_ess_sessions_lifetime CHECK (expires_at > created_at)
);

COMMENT ON TABLE public.hr_ess_sessions IS
  'Team RVM kept sign-ins (task A3): one row per refresh token, a family per sign-in. Written only by '
  'the ESS, through hr_ess_session_rotate and hr_ess_session_revoke once a row is live.';

-- The family's history, for whoever looks into a sign-in by hand.
CREATE INDEX IF NOT EXISTS hr_ess_sessions_family_idx ON public.hr_ess_sessions (family_id);

-- One live row per family: rotation retires the old row before it adds the next, so a family can
-- never fork into two working refresh tokens. Also the ESS's lookup on every request made with a
-- token it minted.
CREATE UNIQUE INDEX IF NOT EXISTS hr_ess_sessions_live_family_key
  ON public.hr_ess_sessions (family_id) WHERE revoked_at IS NULL;

-- "My sign-ins".
CREATE INDEX IF NOT EXISTS hr_ess_sessions_live_employee_idx
  ON public.hr_ess_sessions (employee_id) WHERE revoked_at IS NULL;

-- One trade per Scheduler sign-in, ended or not. A family's first row (id = family_id) carries the
-- traded token's iat as signed_in_at, in whole seconds, and a person has one login of each kind
-- (hr_employees.user_id is unique), so (employee, kind, iat) names that token's sign-in. Two
-- genuine sign-ins of one login in the same second collide too; the second one signs in again.
CREATE UNIQUE INDEX IF NOT EXISTS hr_ess_sessions_sign_in_key
  ON public.hr_ess_sessions (employee_id, login_kind, signed_in_at) WHERE id = family_id;

ALTER TABLE public.hr_ess_sessions ENABLE ROW LEVEL SECURITY;


/*
 * The password fingerprint: SHA-256 of the stored hash, so it says only "the same hash or not".
 * bcrypt's salt stays in the hash, which never leaves users, so the fingerprint cannot be used to
 * test a guessed password.
 */
CREATE OR REPLACE FUNCTION public.hr_ess_password_fingerprint(p_password_hash text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT encode(sha256(convert_to(p_password_hash, 'UTF8')), 'hex');
$$;

/*
 * A family's first portal row takes the fingerprint of the account's password as it goes in,
 * whatever the insert said, so the ESS never handles the hash or the fingerprint. Later rows are
 * written by hr_ess_session_rotate, which copies the one before.
 */
CREATE OR REPLACE FUNCTION public.hr_ess_sessions_bind_password()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.login_kind = 'portal' AND NEW.id = NEW.family_id THEN
    NEW.password_fingerprint := (
      SELECT public.hr_ess_password_fingerprint(u.password_hash) FROM public.users u WHERE u.id = NEW.user_id);
  END IF;
  RETURN NEW;
END $$;

-- CREATE OR REPLACE TRIGGER needs Postgres 14 or later; Supabase runs 15 and up.
CREATE OR REPLACE TRIGGER hr_ess_sessions_bind_password
  BEFORE INSERT ON public.hr_ess_sessions
  FOR EACH ROW EXECUTE FUNCTION public.hr_ess_sessions_bind_password();

/*
 * Is a portal sign-in's password still the one it was kept with? true or false; NULL when the row
 * is not a portal sign-in or its account is gone. The ESS asks at every refresh and ends the
 * sign-in on anything but true.
 */
CREATE OR REPLACE FUNCTION public.hr_ess_session_password_current(p_session_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT coalesce(s.password_fingerprint = public.hr_ess_password_fingerprint(u.password_hash), false)
    FROM public.hr_ess_sessions s
    JOIN public.users u ON u.id = s.user_id
   WHERE s.id = p_session_id AND s.login_kind = 'portal';
$$;


/*
 * Every write to a live row goes through one of these two functions. Each takes a per-family
 * advisory lock first, so a refresh and a sign-out, or a refresh and the detection of a reused
 * token, cannot cross: whichever comes second sees what the first did. Without it, a sign-out that
 * ran while a refresh was adding the next row could miss that row, and the "ended" sign-in would
 * go on.
 *
 * Times come from the ESS's clock (p_now), as the Scheduler's own writes take theirs from its
 * server, so the 60-second retry window and the 90 days are measured on one clock.
 *
 * SECURITY INVOKER (the default), with EXECUTE for service_role only (below), like the
 * Scheduler's own functions (20261020000000_hr_attendance_punch.sql:343-366).
 */

/*
 * Retire a live row and add the next one in its family, in one transaction. Answers the new row's
 * id, family and expiry, or no row at all when the old one was no longer live: another refresh
 * with the same token got there first, or the family has just ended. Either way nothing changes.
 */
CREATE OR REPLACE FUNCTION public.hr_ess_session_rotate(
  p_session_id   uuid,
  p_new_id       uuid,
  p_refresh_hash text,
  p_now          timestamptz,
  p_expires_at   timestamptz
)
RETURNS TABLE (new_session_id uuid, session_family_id uuid, new_expires_at timestamptz)
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_family uuid;
  v_old    public.hr_ess_sessions;
BEGIN
  SELECT s.family_id INTO v_family FROM public.hr_ess_sessions s WHERE s.id = p_session_id;
  IF NOT FOUND THEN
    RETURN;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('hr_ess_sessions:' || v_family::text, 0));

  UPDATE public.hr_ess_sessions s
     SET revoked_at = p_now, revoked_reason = 'rotated', replaced_by = p_new_id, last_used_at = p_now
   WHERE s.id = p_session_id AND s.revoked_at IS NULL AND s.expires_at > p_now
  RETURNING s.* INTO v_old;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  RETURN QUERY
    INSERT INTO public.hr_ess_sessions AS n
      (id, family_id, employee_id, login_kind, user_id, location_name, method, signed_in_at,
       install_id, device_label, refresh_hash, password_fingerprint, created_at, last_used_at, expires_at)
    VALUES
      (p_new_id, v_old.family_id, v_old.employee_id, v_old.login_kind, v_old.user_id, v_old.location_name,
       v_old.method, v_old.signed_in_at, v_old.install_id, v_old.device_label, p_refresh_hash,
       v_old.password_fingerprint, p_now, p_now, p_expires_at)
    RETURNING n.id, n.family_id, n.expires_at;
END $$;

/*
 * End a family: its live row is revoked with the reason. With p_employee_id, only a family of that
 * employee, so "end one of my sign-ins" cannot reach anybody else's. Answers how many rows ended,
 * 0 or 1. 'rotated' is not a way to end a sign-in, so it is refused.
 */
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
END $$;


/*
 * Access. Postgres grants EXECUTE on a new function to PUBLIC, and Supabase grants the API roles
 * (anon, authenticated) every privilege on new tables and functions in public, so without this
 * the public key could call both through PostgREST and see the table in its listing. The DO block
 * keeps the file runnable where those roles do not exist (a plain local Postgres).
 */
REVOKE EXECUTE ON FUNCTION public.hr_ess_session_rotate(uuid, uuid, text, timestamptz, timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.hr_ess_session_revoke(uuid, text, timestamptz, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.hr_ess_session_password_current(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.hr_ess_password_fingerprint(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.hr_ess_sessions_bind_password() FROM PUBLIC;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON TABLE public.hr_ess_sessions FROM anon;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_session_rotate(uuid, uuid, text, timestamptz, timestamptz) FROM anon;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_session_revoke(uuid, text, timestamptz, uuid) FROM anon;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_session_password_current(uuid) FROM anon;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_password_fingerprint(text) FROM anon;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_sessions_bind_password() FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON TABLE public.hr_ess_sessions FROM authenticated;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_session_rotate(uuid, uuid, text, timestamptz, timestamptz) FROM authenticated;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_session_revoke(uuid, text, timestamptz, uuid) FROM authenticated;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_session_password_current(uuid) FROM authenticated;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_password_fingerprint(text) FROM authenticated;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_sessions_bind_password() FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    -- UPDATE because the functions run as their caller. The ESS never deletes a row: KP does,
    -- by hand, when old ones are to go (ADR-0015).
    GRANT SELECT, INSERT, UPDATE ON TABLE public.hr_ess_sessions TO service_role;
    GRANT EXECUTE ON FUNCTION public.hr_ess_session_rotate(uuid, uuid, text, timestamptz, timestamptz) TO service_role;
    GRANT EXECUTE ON FUNCTION public.hr_ess_session_revoke(uuid, text, timestamptz, uuid) TO service_role;
    GRANT EXECUTE ON FUNCTION public.hr_ess_session_password_current(uuid) TO service_role;
    -- Called as the service role by the check above and by the trigger on the ESS's inserts.
    GRANT EXECUTE ON FUNCTION public.hr_ess_password_fingerprint(text) TO service_role;
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
