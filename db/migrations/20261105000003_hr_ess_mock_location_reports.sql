-- Team RVM (ESS): the punches the app refused because the phone's location was mocked.
--
-- Task B14, decision 6 (KP, 16 Oct 2026): a mocked location is refused on the phone, and the
-- attempt is reported to HR. The Scheduler's punch API cannot take a mock flag without a change
-- (ADR-0018), so the app sends the report here instead of the punch. Only punches for now: whether
-- mocked location pings are reported too is still open, so `kind` allows 'punch' alone.
--
-- HR, the CEO and super admins read them, the Scheduler's ATTENDANCE_OVERRIDE_ROLES
-- (config/hrPolicy.js:68-72): the people who see location data today.
--
-- The coordinates are the mocked ones, kept because where somebody pretended to be is part of the
-- report. The server's clock (reported_at) is the record; the phone's (client_at) is kept beside it
-- and never trusted, as on a punch (20261020000000_hr_attendance_punch.sql:106-108). The two
-- coordinates are both present or both absent, as on a branch (20261020000000:50-55).
--
-- A new table only (ADR-0021): nothing the Scheduler owns is altered. Safe to run twice.
-- Row-level security is on with no policy, so only the service role (the ESS) can read or write.
--
-- Rollback: db/rollbacks/20261105000003_hr_ess_mock_location_reports.sql

CREATE TABLE IF NOT EXISTS public.hr_ess_mock_location_reports (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  reported_at timestamptz NOT NULL DEFAULT now(),
  client_at   timestamptz,
  kind        text NOT NULL CHECK (kind IN ('punch')),
  latitude    double precision CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
  longitude   double precision CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),
  accuracy_m  double precision CHECK (accuracy_m IS NULL OR accuracy_m >= 0),
  provider    text CHECK (provider IS NULL OR length(provider) BETWEEN 1 AND 80),
  app_version text CHECK (app_version IS NULL OR length(app_version) BETWEEN 1 AND 40),
  install_id  text CHECK (install_id IS NULL OR length(install_id) BETWEEN 1 AND 128),
  CONSTRAINT hr_ess_mock_location_reports_latlng_chk CHECK ((latitude IS NULL) = (longitude IS NULL))
);

-- HR's list by date, and one person's reports.
CREATE INDEX IF NOT EXISTS idx_hr_ess_mock_location_reports_reported
  ON public.hr_ess_mock_location_reports (reported_at DESC);
CREATE INDEX IF NOT EXISTS idx_hr_ess_mock_location_reports_employee
  ON public.hr_ess_mock_location_reports (employee_id, reported_at DESC);

ALTER TABLE public.hr_ess_mock_location_reports ENABLE ROW LEVEL SECURITY;

NOTIFY pgrst, 'reload schema';
