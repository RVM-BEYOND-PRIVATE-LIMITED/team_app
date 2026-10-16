-- Team RVM (ESS): an employee's personal details, kept by the employee.
--
-- Task E9. hr_employees has no date of birth, blood group, address or emergency contact
-- (20260826000001_hrms_tables.sql:82-131, and no later migration adds one), and the Scheduler's
-- tables are not altered (ADR-0018, ADR-0021), so they live here, one row per employee, keyed to
-- hr_employees.id. The ESS never writes hr_employees.
--
-- The employee reads all of theirs from the app (Me) and changes only the blood group and the
-- emergency contact: a date of birth or an address changes through HR (the brief: sensitive edits
-- need HR's approval). HR, HR Executive and super admins (apps/ess-api/src/policy/hrAccess.js
-- HR_RECORD_ROLES: the Scheduler's HR_ROLES, config/hrPolicy.js:25-30, without the CEO) read and
-- change anybody else's, and each such read and change is recorded in hr_ess_audit. Nobody else
-- reads them, managers included.
--
-- The CHECKs repeat what the ESS validates, as a backstop. The one rule a CHECK cannot hold is the
-- upper bound on the date of birth (16 years before today, IST), because it moves with the date;
-- the ESS checks that one.
--
-- A new table only (ADR-0021): nothing the Scheduler owns is altered. Safe to run twice.
-- Row-level security is on with no policy, so only the service role (the ESS) can read or write.
--
-- Rollback: db/rollbacks/20261105000002_hr_ess_personal_details.sql

CREATE TABLE IF NOT EXISTS public.hr_ess_personal_details (
  employee_id        uuid PRIMARY KEY REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  date_of_birth      date CHECK (date_of_birth IS NULL OR date_of_birth >= DATE '1940-01-01'),
  blood_group        text CHECK (blood_group IS NULL OR blood_group IN ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-')),
  address_line1      text CHECK (address_line1 IS NULL OR length(address_line1) BETWEEN 1 AND 200),
  address_line2      text CHECK (address_line2 IS NULL OR length(address_line2) BETWEEN 1 AND 200),
  city               text CHECK (city IS NULL OR length(city) BETWEEN 1 AND 80),
  state              text CHECK (state IS NULL OR length(state) BETWEEN 1 AND 80),
  -- An Indian PIN code: six digits, never starting with 0.
  pincode            text CHECK (pincode IS NULL OR pincode ~ '^[1-9][0-9]{5}$'),
  emergency_name     text CHECK (emergency_name IS NULL OR length(emergency_name) BETWEEN 1 AND 100),
  emergency_relation text CHECK (emergency_relation IS NULL OR length(emergency_relation) BETWEEN 1 AND 50),
  -- A 10-digit Indian mobile, stored without +91 or a leading 0.
  emergency_phone    text CHECK (emergency_phone IS NULL OR emergency_phone ~ '^[6-9][0-9]{9}$'),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  updated_by_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  updated_by_name    text,
  -- A name with no number reaches nobody, and a relation needs somebody to be related to.
  CONSTRAINT hr_ess_personal_details_emergency_chk CHECK (
    (emergency_name IS NULL) = (emergency_phone IS NULL)
    AND (emergency_relation IS NULL OR emergency_name IS NOT NULL)
  )
);

ALTER TABLE public.hr_ess_personal_details ENABLE ROW LEVEL SECURITY;

NOTIFY pgrst, 'reload schema';
