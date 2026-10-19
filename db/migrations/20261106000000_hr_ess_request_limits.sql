-- Team RVM (ESS): the monthly request limits, in a table HR can change.
--
-- Task C6. The numbers are KP's of 16 Oct 2026 (docs/03-decisions.md, "Request limits"): on duty
-- no limit; fix a day 3; excuse a late 3; short leave 180 minutes (Phase 2); CL 1; leave without
-- pay no limit set yet; work from home not offered, limit 0. `src/policy/requestLimits.js` holds
-- the types, their units and their phases; this table holds the numbers, so HR can change them
-- without a deploy (the brief: "Limit HR sets").
--
-- Seeded here and read through `GET /ess/hr/request-limits`; changed through
-- `PUT /ess/hr/request-limits/{type}`, which records the change in hr_ess_audit.
--
-- `limit_count` is a number of requests, `limit_minutes` a number of minutes; exactly one of the
-- two is set for a type, and NULL in that column means no limit. The seed writes DO NOTHING on a
-- second run, so re-running the file never puts back a number HR has changed.
--
-- A new table only (ADR-0021): nothing the Scheduler owns is altered. Safe to run twice.
-- Row-level security is on with no policy, so only the service role (the ESS) can read or write.
--
-- Rollback: db/rollbacks/20261106000000_hr_ess_request_limits.sql

CREATE TABLE IF NOT EXISTS public.hr_ess_request_limits (
  type               text PRIMARY KEY CHECK (type IN (
                       'on_duty', 'fix_a_day', 'excuse_late', 'short_leave',
                       'leave_cl', 'leave_lwp', 'wfh'
                     )),
  limit_count        integer CHECK (limit_count IS NULL OR limit_count >= 0),
  limit_minutes      integer CHECK (limit_minutes IS NULL OR limit_minutes >= 0),
  -- One unit per type: a minutes type keeps its number in limit_minutes and never in limit_count,
  -- a count type the other way round. NULL in the type's own column means no limit.
  CONSTRAINT hr_ess_request_limits_unit_chk CHECK (
    (type = 'short_leave' AND limit_count IS NULL)
    OR (type <> 'short_leave' AND limit_minutes IS NULL)
  ),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  updated_by_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  updated_by_name    text
);

INSERT INTO public.hr_ess_request_limits (type, limit_count, limit_minutes) VALUES
  ('on_duty',     NULL, NULL),
  ('fix_a_day',      3, NULL),
  ('excuse_late',    3, NULL),
  ('short_leave', NULL,  180),
  ('leave_cl',       1, NULL),
  ('leave_lwp',   NULL, NULL),
  ('wfh',            0, NULL)
ON CONFLICT (type) DO NOTHING;

ALTER TABLE public.hr_ess_request_limits ENABLE ROW LEVEL SECURITY;

-- Row-level security with no policy keeps the API roles out of every row, but not out of a
-- statement it does not cover, such as TRUNCATE. So they hold no privilege on the table at all;
-- only the service role keeps what the ESS uses.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON TABLE public.hr_ess_request_limits FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON TABLE public.hr_ess_request_limits FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT SELECT, INSERT, UPDATE ON TABLE public.hr_ess_request_limits TO service_role;
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';
