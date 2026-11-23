-- Team RVM (ESS): in-app feedback, a bug report or a suggestion about the Team app itself (#151).
--
-- Any signed-in employee sends one from the floating Feedback button, with either sign-in
-- (POST /api/ess/feedback). Only super admins read them (GET /api/ess/admin/feedback; the role
-- set is apps/ess-api/src/policy/feedback.js FEEDBACK_REVIEW_ROLES, exact role, nothing inherits
-- its way in). The person who sent one cannot read it back: there is no status and no reply yet.
--
-- With each item the app attaches where it was sent from and on what, so a bug report can be
-- acted on: the screen (the app's route), the app version and build, the platform, the OS
-- version and the device model. Every one of them is optional, because an old build or a web
-- build may not know them, and each is short text the ESS checks the length of.
--
-- A screenshot is optional: one PNG or JPEG of up to 2 MB, kept in the ESS's private bucket
-- under feedback/<employee_id>/<uuid>.<ext> (the bucket the documents use; KP, 19 Oct 2026). The
-- row keeps the path, the type and the size, all three or none (the CHECK below), and the path
-- never leaves the server: a super admin opens it through a 300-second signed link, and that
-- opening is audited (hr_ess_audit, feedback.screenshot_opened).
--
-- employee_id cascades like every per-employee HR table (20261015000004_hr_staff_attendance.sql:15):
-- when a record is deleted, that person's feedback goes with it. The bucket objects are left for
-- the cleanup the documents already need (docs/09-data-inventory.md, section 4).
--
-- A new table only (ADR-0021): nothing the Scheduler owns is altered. Safe to run twice.
-- Row-level security is on with no policy, so only the service role (the ESS) can read or write.
--
-- Rollback: db/rollbacks/20261231200000_hr_ess_feedback.sql

CREATE TABLE IF NOT EXISTS public.hr_ess_feedback (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id             uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  kind                    text NOT NULL CHECK (kind IN ('bug', 'suggestion', 'other')),
  message                 text NOT NULL CHECK (length(btrim(message)) BETWEEN 1 AND 2000),
  -- What the app attached (apps/ess-api/src/policy/feedback.js CONTEXT_FIELDS holds the same limits).
  screen                  text CHECK (screen IS NULL OR length(screen) BETWEEN 1 AND 200),
  app_version             text CHECK (app_version IS NULL OR length(app_version) BETWEEN 1 AND 40),
  build_number            text CHECK (build_number IS NULL OR length(build_number) BETWEEN 1 AND 20),
  platform                text CHECK (platform IS NULL OR length(platform) BETWEEN 1 AND 40),
  os_version              text CHECK (os_version IS NULL OR length(os_version) BETWEEN 1 AND 80),
  device_model            text CHECK (device_model IS NULL OR length(device_model) BETWEEN 1 AND 120),
  -- The screenshot: an ESS bucket path under feedback/, never a URL.
  screenshot_path         text CHECK (screenshot_path IS NULL OR screenshot_path LIKE 'feedback/%'),
  screenshot_content_type text CHECK (screenshot_content_type IS NULL OR screenshot_content_type IN ('image/png', 'image/jpeg')),
  screenshot_bytes        integer CHECK (screenshot_bytes IS NULL OR screenshot_bytes BETWEEN 1 AND 2097152),
  created_at              timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT hr_ess_feedback_screenshot_chk CHECK (
    (screenshot_path IS NULL AND screenshot_content_type IS NULL AND screenshot_bytes IS NULL)
    OR (screenshot_path IS NOT NULL AND screenshot_content_type IS NOT NULL AND screenshot_bytes IS NOT NULL)
  )
);

-- The super admins' list (newest first, optionally one kind), and the cascade from hr_employees.
CREATE INDEX IF NOT EXISTS idx_hr_ess_feedback_created
  ON public.hr_ess_feedback (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_hr_ess_feedback_kind_created
  ON public.hr_ess_feedback (kind, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_hr_ess_feedback_employee
  ON public.hr_ess_feedback (employee_id);

ALTER TABLE public.hr_ess_feedback ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON TABLE public.hr_ess_feedback FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON TABLE public.hr_ess_feedback FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT SELECT, INSERT ON TABLE public.hr_ess_feedback TO service_role;
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';
