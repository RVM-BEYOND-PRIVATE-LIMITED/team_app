-- Team RVM (ESS): a record of the HR actions that reach into somebody else's data.
--
-- Wave 2 (KP, 16 Oct 2026). Four actions leave a row here:
--   devices.reset             HR's bulk phone reset (task B8)
--   data_request.resolved     HR closing a request to correct or delete somebody's data (task A8)
--   personal_details.read     HR opening somebody's personal details (task E9). This is the DPDP
--                             question "who looked at whose personal data", which nothing in the
--                             Scheduler records.
--   personal_details.updated  HR changing somebody's personal details (task E9); details names
--                             the fields that changed, never their values.
--
-- Append-only by use: the ESS inserts rows and never updates or deletes them, and no endpoint
-- reads them yet. `details` carries ids, counts and reasons, never the personal data itself, so
-- the record does not become a second copy of what it protects.
--
-- The actor is kept by id and by name, as the Scheduler's audit_events keeps it
-- (20261016000000_audit_events.sql:76-78): the ids are foreign keys that go null when their row
-- goes, and the name stays. target_employee_id has no foreign key on purpose, like
-- audit_events.entity_id (20261016000000_audit_events.sql:93), so the trail of a person's record
-- outlives the record. A request to delete somebody's data, once done, is proved here.
--
-- A new table only (ADR-0021): nothing the Scheduler owns is altered. Safe to run twice.
-- Row-level security is on with no policy, so only the service role (the ESS) can read or write.
--
-- Rollback: db/rollbacks/20261105000000_hr_ess_audit.sql

CREATE TABLE IF NOT EXISTS public.hr_ess_audit (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  at                 timestamptz NOT NULL DEFAULT now(),
  actor_user_id      uuid REFERENCES public.users(id) ON DELETE SET NULL,
  actor_employee_id  uuid REFERENCES public.hr_employees(id) ON DELETE SET NULL,
  actor_name         text NOT NULL,
  action             text NOT NULL CHECK (action ~ '^[a-z_]+(\.[a-z_]+)+$'),
  target_employee_id uuid,
  details            jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(details) = 'object')
);

CREATE INDEX IF NOT EXISTS idx_hr_ess_audit_at
  ON public.hr_ess_audit (at DESC);
CREATE INDEX IF NOT EXISTS idx_hr_ess_audit_target
  ON public.hr_ess_audit (target_employee_id, at DESC) WHERE target_employee_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_hr_ess_audit_actor
  ON public.hr_ess_audit (actor_employee_id, at DESC);

ALTER TABLE public.hr_ess_audit ENABLE ROW LEVEL SECURITY;

-- PostgREST caches the schema; tell it about the new table now rather than at its next reload.
-- Row-level security with no policy keeps the API roles out of every row, but not out of
-- statements it does not cover, such as TRUNCATE. So they hold no privilege on the table at
-- all, as on hr_ess_sessions; only the service role keeps what the ESS uses. The ESS never
-- deletes a row: KP does, by hand (ADR-0015).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON TABLE public.hr_ess_audit FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON TABLE public.hr_ess_audit FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT SELECT, INSERT ON TABLE public.hr_ess_audit TO service_role;
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';
