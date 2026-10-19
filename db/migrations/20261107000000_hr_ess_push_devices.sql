-- Team RVM (ESS): the phones that receive push (task D5).
--
-- One row per FCM registration token: the Android app registers its token after sign-in, and
-- registers it again on every launch (the token can be rotated by Firebase). The same token
-- belongs to one install, so registering a token that is already held moves it to the caller and
-- clears any revocation — the phone is now this person's. A sign-out revokes it (revoked_at), and
-- the worker never sends to a revoked row.
--
-- Tokens are the app's, not the Scheduler's: this table is the ESS's own (ADR-0021), with
-- row-level security on and no policy, so only the service role reads it. Nothing deletes a row
-- through the API; the employee's deletion cascades it.
--
-- Rollback: db/rollbacks/20261107000000_hr_ess_push_devices.sql

CREATE TABLE IF NOT EXISTS public.hr_ess_push_devices (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id  uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  -- FCM registration tokens are long; control characters are never part of one.
  token        text NOT NULL CHECK (length(token) BETWEEN 20 AND 4096 AND token !~ '[[:cntrl:]]'),
  platform     text NOT NULL DEFAULT 'android' CHECK (platform IN ('android')),
  device_label text CHECK (device_label IS NULL OR length(device_label) BETWEEN 1 AND 80),
  install_id   text CHECK (install_id IS NULL OR length(install_id) BETWEEN 1 AND 128),
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  revoked_at   timestamptz
);

-- One install, one row: a token registers to one person at a time.
CREATE UNIQUE INDEX IF NOT EXISTS hr_ess_push_devices_token_key
  ON public.hr_ess_push_devices (token);
CREATE INDEX IF NOT EXISTS hr_ess_push_devices_employee_idx
  ON public.hr_ess_push_devices (employee_id) WHERE revoked_at IS NULL;

ALTER TABLE public.hr_ess_push_devices ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON TABLE public.hr_ess_push_devices FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON TABLE public.hr_ess_push_devices FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT SELECT, INSERT, UPDATE ON TABLE public.hr_ess_push_devices TO service_role;
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';
