-- Team RVM (ESS): profile-change requests (Phase 2C, E3 as the brief's change-of-record flow).
--
-- A person asks for their date of birth, address or legal name to be corrected; HR answers it.
-- The request keeps what the person says the record shows (old_value) and what it should show
-- (new_value), so the decision is one screen even when HR does not have the file open.
--
-- The ESS records the DECISION only (KP, 19 Oct 2026): it never writes hr_employees, because the
-- Scheduler's HR record stays the system of record (ADR-0003) and the ESS writes its own tables
-- (ADR-0021). HR applies the approved change in the Scheduler by hand; the request row is the
-- paper trail.
--
-- One open request per field per person: a second ask for the same field while one waits is
-- refused by the partial unique index (hr_ess_change_requests_open_field_key), so HR's queue
-- cannot fill with duplicates of one ask. An answered request makes room for the next.
--
-- New table only (ADR-0021). Safe to run twice. Row-level security is on with no policy, so
-- only the service role (the ESS) can read or write.
--
-- Rollback: db/rollbacks/20261110000002_hr_ess_change_requests.sql

CREATE TABLE IF NOT EXISTS public.hr_ess_change_requests (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id     uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  -- The field asked about. `legal_name` is the name on the certificates; the others are the
  -- personal-details fields E9 already holds.
  field           text NOT NULL,
  -- What the person says the record shows now (null: "I do not know what it says").
  old_value       text CHECK (old_value IS NULL OR length(btrim(old_value)) BETWEEN 1 AND 500),
  new_value       text NOT NULL CHECK (length(btrim(new_value)) BETWEEN 1 AND 500),
  -- Why it is wrong, in the person's words; the employee's own, always.
  reason          text NOT NULL CHECK (length(btrim(reason)) BETWEEN 5 AND 1000),
  status          text NOT NULL DEFAULT 'open',
  decided_by_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  decided_by_name text,
  decided_at      timestamptz,
  decision_note   text CHECK (decision_note IS NULL OR length(btrim(decision_note)) BETWEEN 1 AND 1000),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT hr_ess_change_requests_field_chk CHECK (field IN ('date_of_birth', 'address', 'legal_name')),
  CONSTRAINT hr_ess_change_requests_status_chk CHECK (status IN ('open', 'approved', 'rejected')),
  CONSTRAINT hr_ess_change_requests_decided_chk CHECK (
    (status = 'open') = (decided_at IS NULL)
  )
);

-- One open ask per field per person.
CREATE UNIQUE INDEX IF NOT EXISTS hr_ess_change_requests_open_field_key
  ON public.hr_ess_change_requests (employee_id, field)
  WHERE status = 'open';
-- HR's queue, and the person's own list.
CREATE INDEX IF NOT EXISTS hr_ess_change_requests_employee_idx
  ON public.hr_ess_change_requests (employee_id, created_at DESC);

ALTER TABLE public.hr_ess_change_requests ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON TABLE public.hr_ess_change_requests FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON TABLE public.hr_ess_change_requests FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT SELECT, INSERT, UPDATE ON TABLE public.hr_ess_change_requests TO service_role;
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';
