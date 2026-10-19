-- Team RVM (ESS): staff announcements, their audience and their read state (task F5).
--
-- An announcement is HR's (or the CEO's, or a super admin's; decision 8) — never a Wall post with
-- extras bolted on, because almost everything about it differs:
--   * it has an audience (by branch, department, role or named people, or everybody);
--   * it may be scheduled: it is written with a publish_at in the future and appears when the
--     job (src/jobs/wall.js) publishes it, so publish_at is the one time that matters;
--   * it may ask to be acknowledged, and then carries a closing date;
--   * its sender reads read and acknowledgement counts, and HR may pin up to three.
-- Student notices are the Scheduler's own tables and are not touched (F5). Nothing here writes
-- them, reads them, or shares an id with them.
--
-- The audience is one jsonb object, resolved by the route (src/policy/wall.js audienceMatches):
--   { "all": true } or { "branch_ids": [...], "department_ids": [...], "roles": [...],
--     "employee_ids": [...] }. Any present list is an OR of the people it names; nothing present
-- means everybody. Roles are the Scheduler's `users.role` values, as decision 8's audience means
-- them. The audience is fixed once the rows in hr_ess_announcement_audience are written, so a new
-- branch or a role change never silently reaches somebody new, and does never lose its rows.
--
-- hr_ess_announcement_audience is filled when the announcement is published: one row per person
-- the audience resolved to at that moment. It is what the feed reads ("sent to me"), what the
-- read and acknowledgement counts count, and what the reminder job walks. Publishing to "all" is
-- one row per employee at that time — about 110 rows — which is what makes counts exact; a list
-- recomputed on every read could not say "who has not acknowledged yet".
--
-- hr_ess_announcement_reads is one row per person per announcement, written when they open it,
-- updated with the time they acknowledged it. An acknowledgement is a button the person presses;
-- nothing infers it from reading.
--
-- New tables only (ADR-0021). Safe to run twice. Row-level security is on with no policy, so only
-- the service role (the ESS) can read or write.
--
-- Rollback: db/rollbacks/20261108000003_hr_ess_announcements.sql

CREATE TABLE IF NOT EXISTS public.hr_ess_announcements (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id       uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  title             text NOT NULL CHECK (length(btrim(title)) BETWEEN 3 AND 200),
  body              text NOT NULL CHECK (length(btrim(body)) BETWEEN 3 AND 5000),
  -- Up to five files, as on the Wall: [{ path, name }], bytes in the ESS bucket.
  attachments       jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(attachments) = 'array'),
  audience          jsonb NOT NULL DEFAULT '{"all": true}'::jsonb
                      CHECK (jsonb_typeof(audience) = 'object'),
  -- Written as a draft (NULL) or published at once; a scheduled one carries its future time, and
  -- the row is invisible to its audience until the job has published it (published_at not null).
  publish_at        timestamptz,
  published_at      timestamptz,
  needs_ack         boolean NOT NULL DEFAULT false,
  closes_on         date,
  pinned            boolean NOT NULL DEFAULT false,
  -- The sender's counts, maintained as reads and acknowledgements arrive.
  read_count        integer NOT NULL DEFAULT 0 CHECK (read_count >= 0),
  ack_count         integer NOT NULL DEFAULT 0 CHECK (ack_count >= 0),
  -- The last time the reminder job wrote to those who have not acknowledged (best effort).
  reminded_at       timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  edited_at         timestamptz,
  -- F7's moderation applies to the Wall's posts; an announcement is HR's own, so it is only ever
  -- taken down by the person who wrote it (deleted_at) — the row stays for the counts' record.
  deleted_at        timestamptz,
  -- An acknowledgement needs a closing date, and a close needs an acknowledgement.
  CONSTRAINT hr_ess_announcements_ack_chk CHECK (needs_ack = (closes_on IS NOT NULL)),
  -- A published announcement has a publish time and no draft state; a draft has neither.
  CONSTRAINT hr_ess_announcements_published_chk CHECK (
    published_at IS NULL OR (publish_at IS NOT NULL AND publish_at <= published_at)
  )
);

-- The feed: published, not deleted, newest first; pinned first is the route's ordering.
CREATE INDEX IF NOT EXISTS hr_ess_announcements_feed_idx
  ON public.hr_ess_announcements (published_at DESC) WHERE deleted_at IS NULL AND published_at IS NOT NULL;
-- The job's queue: scheduled, not yet published, oldest first.
CREATE INDEX IF NOT EXISTS hr_ess_announcements_due_idx
  ON public.hr_ess_announcements (publish_at)
  WHERE published_at IS NULL AND deleted_at IS NULL;
-- The reminder job's walk: announcements asking for an acknowledgement, whose close is near.
CREATE INDEX IF NOT EXISTS hr_ess_announcements_ack_idx
  ON public.hr_ess_announcements (closes_on)
  WHERE needs_ack AND deleted_at IS NULL AND published_at IS NOT NULL;
-- The sender's own list.
CREATE INDEX IF NOT EXISTS hr_ess_announcements_author_idx
  ON public.hr_ess_announcements (employee_id, created_at DESC);

-- Who an announcement reached, resolved when it was published. Keeping it as rows is what makes
-- the counts exact and the reminder honest: "sent to 40, read by 12, acknowledged by 7".
CREATE TABLE IF NOT EXISTS public.hr_ess_announcement_audience (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  announcement_id uuid NOT NULL REFERENCES public.hr_ess_announcements(id) ON DELETE CASCADE,
  employee_id     uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  added_at        timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS hr_ess_announcement_audience_key
  ON public.hr_ess_announcement_audience (announcement_id, employee_id);
CREATE INDEX IF NOT EXISTS hr_ess_announcement_audience_person_idx
  ON public.hr_ess_announcement_audience (employee_id);

-- Reads and acknowledgements: one row per person per announcement, read_at is the first open and
-- ack_at the moment the button was pressed.
CREATE TABLE IF NOT EXISTS public.hr_ess_announcement_reads (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  announcement_id uuid NOT NULL REFERENCES public.hr_ess_announcements(id) ON DELETE CASCADE,
  employee_id     uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  read_at         timestamptz NOT NULL DEFAULT now(),
  ack_at          timestamptz,
  CONSTRAINT hr_ess_announcement_reads_ack_chk CHECK (ack_at IS NULL OR ack_at >= read_at)
);

CREATE UNIQUE INDEX IF NOT EXISTS hr_ess_announcement_reads_key
  ON public.hr_ess_announcement_reads (announcement_id, employee_id);
CREATE INDEX IF NOT EXISTS hr_ess_announcement_reads_person_idx
  ON public.hr_ess_announcement_reads (employee_id);

ALTER TABLE public.hr_ess_announcements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hr_ess_announcement_audience ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hr_ess_announcement_reads ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON TABLE public.hr_ess_announcements FROM anon;
    REVOKE ALL ON TABLE public.hr_ess_announcement_audience FROM anon;
    REVOKE ALL ON TABLE public.hr_ess_announcement_reads FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON TABLE public.hr_ess_announcements FROM authenticated;
    REVOKE ALL ON TABLE public.hr_ess_announcement_audience FROM authenticated;
    REVOKE ALL ON TABLE public.hr_ess_announcement_reads FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT SELECT, INSERT, UPDATE ON TABLE public.hr_ess_announcements TO service_role;
    GRANT SELECT, INSERT, UPDATE ON TABLE public.hr_ess_announcement_audience TO service_role;
    GRANT SELECT, INSERT, UPDATE ON TABLE public.hr_ess_announcement_reads TO service_role;
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';
