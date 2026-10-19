-- Team RVM (ESS): bank details (Phase 2C, KP 3).
--
-- A person keeps their own salary account here, once, with the consent the entry needs: the
-- person types their own name into consent_name and the save stamps consent_given_at, so the
-- row carries the proof it was entered knowingly, by them. One row per person (its primary key);
-- a save updates it in place, and nothing is ever deleted by the app.
--
-- The number is masked to everybody but its owner: HR's read answers the last four digits only,
-- and every HR read is audited (routes/bankDetails.js, lib/audit.js recordBefore). No list
-- response ever carries a bank row at all.
--
-- The checks are the RBI's own shapes: an IFSC is four letters, a zero, six more; the account
-- number is the digits Indian banks issue. The IFSC is stored upper-cased by the route.
--
-- New table only (ADR-0021). Safe to run twice. Row-level security is on with no policy, so
-- only the service role (the ESS) can read or write.
--
-- Rollback: db/rollbacks/20261110000003_hr_ess_bank_details.sql

CREATE TABLE IF NOT EXISTS public.hr_ess_bank_details (
  employee_id     uuid PRIMARY KEY REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  bank_name       text NOT NULL CHECK (length(btrim(bank_name)) BETWEEN 2 AND 120),
  branch_name     text CHECK (branch_name IS NULL OR length(btrim(branch_name)) BETWEEN 2 AND 120),
  account_number  text NOT NULL CHECK (account_number ~ '^[0-9]{8,18}$'),
  ifsc_code       text NOT NULL CHECK (ifsc_code ~ '^[A-Z]{4}0[A-Z0-9]{6}$'),
  upi_id          text CHECK (upi_id IS NULL OR length(btrim(upi_id)) BETWEEN 3 AND 60),
  -- The consent the entry needs: the person's own typed name, and the moment they gave it.
  consent_given_at timestamptz NOT NULL,
  consent_name    text NOT NULL CHECK (length(btrim(consent_name)) BETWEEN 1 AND 120),
  updated_by_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  updated_by_name text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.hr_ess_bank_details ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON TABLE public.hr_ess_bank_details FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON TABLE public.hr_ess_bank_details FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT SELECT, INSERT, UPDATE ON TABLE public.hr_ess_bank_details TO service_role;
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';
