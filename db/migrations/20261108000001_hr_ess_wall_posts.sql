-- Team RVM (ESS): the Wall's feed — posts, praise, polls, reactions and comments (tasks F1-F4, F6).
--
-- The Wall is every staff member writing to everybody (the organisation wall), or to their own
-- branch's wall. Four kinds of thing appear in one feed, so they share one table and one set of
-- comment and reaction rules:
--   post        text, up to five photos or PDFs, @mentions, editable for 15 minutes, deletable
--               by its author. Announcements are NOT here (hr_ess_announcements, migration 3):
--               they have an audience, acknowledge counts and a closing date of their own.
--   praise      an RVM badge, a reason of up to 280 characters, an optional photo. The badge
--               catalogue is fixed in code (src/policy/wall.js, KP 19 Oct): a post cannot carry
--               a badge outside it.
--   wish        a one-tap birthday or anniversary wish, addressed to one person (F6); the
--               hr_ess_wall_wishes row makes one wish per person per occasion per year.
--   poll        a question with two to ten options, single or multiple choice, optionally
--               anonymous, closing on a date. The options are hr_ess_wall_poll_options' rows;
--               the votes are hr_ess_wall_poll_votes'; both are written only while the poll is
--               open and, once somebody has voted, the option set is frozen (F4).
--
-- Hiding (F7): HR hides a post with a reason, and a hidden post keeps its row — the moderation
-- trail (hr_ess_audit, 'wall.post.hidden') says what was hidden and why, and the report queue
-- (hr_ess_wall_reports) still has something to point at. A deleted post is gone for everybody
-- except the author's own history: the row is kept, deleted_at is set, the body is blanked and
-- the counters cleared, so an author's deletion does not quietly rewrite a moderation record or
-- strand its comments. Every read of the feed filters `deleted_at IS NULL`.
--
-- The counts (reactions and comments) live on the row so the feed is one query, never a count
-- per row. They are maintained by the routes, best effort: hr_ess_wall_reactions and
-- hr_ess_wall_comments are the truth, and a count that has drifted is corrected the next time
-- somebody reacts or comments.
--
-- New tables only (ADR-0021): nothing the Scheduler owns is altered, and the students' notices
-- are not touched (F5: "the students' notices stay as they are"). Safe to run twice. Row-level
-- security is on with no policy, so only the service role (the ESS) can read or write.
--
-- Rollback: db/rollbacks/20261108000001_hr_ess_wall_posts.sql

CREATE TABLE IF NOT EXISTS public.hr_ess_wall_posts (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id       uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  kind              text NOT NULL DEFAULT 'post'
                      CHECK (kind IN ('post', 'praise', 'wish', 'poll')),
  -- The wall it stands on: the organisation's, or one branch's. A branch post names its branch.
  scope             text NOT NULL DEFAULT 'org' CHECK (scope IN ('org', 'branch')),
  branch_id         uuid REFERENCES public.hr_branches(id) ON DELETE SET NULL,
  body              text NOT NULL CHECK (length(btrim(body)) BETWEEN 1 AND 2000),
  -- Up to five files: [{ path, name }] as the app reads them back, with signed links made on
  -- every read. The bytes live in the ESS's own bucket ('ESS'), never here.
  attachments       jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(attachments) = 'array'),
  mentions          uuid[] NOT NULL DEFAULT '{}',
  -- The praise badge, out of the fixed catalogue in src/policy/wall.js. NULL for every other kind.
  badge             text,
  -- The wish's occasion, and the post a wish or a praise is about. A wish must name somebody.
  occasion          text CHECK (occasion IS NULL OR occasion IN ('birthday', 'anniversary')),
  about_employee_id uuid REFERENCES public.hr_employees(id) ON DELETE SET NULL,
  -- The poll's own shape. options_locked_at is set as the first vote goes in (F4), and
  -- poll_closed_at when its author closes it early (its closing day still says when it was due).
  poll_multiple     boolean NOT NULL DEFAULT false,
  poll_anonymous    boolean NOT NULL DEFAULT false,
  poll_closes_on    date,
  options_locked_at timestamptz,
  poll_closed_at    timestamptz,
  reaction_counts   jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(reaction_counts) = 'object'),
  comment_count     integer NOT NULL DEFAULT 0 CHECK (comment_count >= 0),
  edited_at         timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  -- F7: HR hides a post with a reason. A hidden post keeps its row and its comments.
  hidden_at         timestamptz,
  hidden_by_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  hidden_by_name    text,
  hide_reason       text CHECK (hide_reason IS NULL OR length(btrim(hide_reason)) BETWEEN 3 AND 200),
  -- F1: the author's own deletion. The row stays (the trail and the comments point at it); the
  -- body and attachments are blanked when it is set, so nothing deleted is still readable.
  deleted_at        timestamptz,
  -- A branch post names its branch and an organisation post does not; a hidden post names its
  -- hider and the reason; a praise or a poll has what only it needs.
  CONSTRAINT hr_ess_wall_posts_scope_chk CHECK (
    (scope = 'org' AND branch_id IS NULL) OR (scope = 'branch' AND branch_id IS NOT NULL)
  ),
  CONSTRAINT hr_ess_wall_posts_hidden_chk CHECK (
    (hidden_at IS NULL AND hidden_by_name IS NULL AND hide_reason IS NULL)
    OR (hidden_at IS NOT NULL AND hidden_by_name IS NOT NULL AND hide_reason IS NOT NULL)
  ),
  CONSTRAINT hr_ess_wall_posts_shape_chk CHECK (
    (kind = 'post'   AND badge IS NULL AND occasion IS NULL AND about_employee_id IS NULL
                     AND poll_closes_on IS NULL)
    OR (kind = 'praise' AND badge IS NOT NULL AND occasion IS NULL AND about_employee_id IS NOT NULL)
    OR (kind = 'wish'   AND badge IS NULL AND occasion IS NOT NULL AND about_employee_id IS NOT NULL)
    OR (kind = 'poll'   AND badge IS NULL AND occasion IS NULL AND about_employee_id IS NULL
                        AND poll_closes_on IS NOT NULL)
  ),
  -- Praise is about somebody else; a wish is about somebody else whatever the occasion.
  CONSTRAINT hr_ess_wall_posts_about_chk CHECK (about_employee_id IS NULL OR about_employee_id <> employee_id),
  -- A wish's body is the wish itself; keep it short, as a one-tap wish is.
  CONSTRAINT hr_ess_wall_posts_wish_body_chk CHECK (kind <> 'wish' OR length(btrim(body)) BETWEEN 1 AND 200),
  -- A praise reason is up to 280 characters (F3).
  CONSTRAINT hr_ess_wall_posts_praise_body_chk CHECK (kind <> 'praise' OR length(btrim(body)) BETWEEN 3 AND 280)
);

-- The feed: everything not deleted, newest first, either the organisation's or one branch's.
CREATE INDEX IF NOT EXISTS hr_ess_wall_posts_feed_idx
  ON public.hr_ess_wall_posts (created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS hr_ess_wall_posts_branch_feed_idx
  ON public.hr_ess_wall_posts (branch_id, created_at DESC) WHERE deleted_at IS NULL;
-- The profile view and the celebration feed look a person up by who they are about (F3, F6).
CREATE INDEX IF NOT EXISTS hr_ess_wall_posts_about_idx
  ON public.hr_ess_wall_posts (about_employee_id, created_at DESC) WHERE deleted_at IS NULL;
-- The poll that closes tonight is found by its closing day (the job, src/jobs/wall.js).
CREATE INDEX IF NOT EXISTS hr_ess_wall_posts_poll_closing_idx
  ON public.hr_ess_wall_posts (poll_closes_on)
  WHERE kind = 'poll' AND deleted_at IS NULL AND hidden_at IS NULL;
-- One person's own posts, for their own history and the edit window's lookup.
CREATE INDEX IF NOT EXISTS hr_ess_wall_posts_author_idx
  ON public.hr_ess_wall_posts (employee_id, created_at DESC);

-- One row per comment or reply. ONE level of replies (F2): a reply points at a comment, and a
-- reply never carries replies of its own (the CHECK on the parent's parent is the route's).
CREATE TABLE IF NOT EXISTS public.hr_ess_wall_comments (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id           uuid NOT NULL REFERENCES public.hr_ess_wall_posts(id) ON DELETE CASCADE,
  employee_id       uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  parent_id         uuid REFERENCES public.hr_ess_wall_comments(id) ON DELETE CASCADE,
  body              text NOT NULL CHECK (length(btrim(body)) BETWEEN 1 AND 1000),
  mentions          uuid[] NOT NULL DEFAULT '{}',
  reaction_counts   jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(reaction_counts) = 'object'),
  reply_count       integer NOT NULL DEFAULT 0 CHECK (reply_count >= 0),
  edited_at         timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  hidden_at         timestamptz,
  hidden_by_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  hidden_by_name    text,
  hide_reason       text CHECK (hide_reason IS NULL OR length(btrim(hide_reason)) BETWEEN 3 AND 200),
  deleted_at        timestamptz,
  CONSTRAINT hr_ess_wall_comments_hidden_chk CHECK (
    (hidden_at IS NULL AND hidden_by_name IS NULL AND hide_reason IS NULL)
    OR (hidden_at IS NOT NULL AND hidden_by_name IS NOT NULL AND hide_reason IS NOT NULL)
  )
);

-- A post's comments and replies, oldest first, as a thread is read.
CREATE INDEX IF NOT EXISTS hr_ess_wall_comments_post_idx
  ON public.hr_ess_wall_comments (post_id, created_at);
-- A comment's replies.
CREATE INDEX IF NOT EXISTS hr_ess_wall_comments_parent_idx
  ON public.hr_ess_wall_comments (parent_id, created_at) WHERE parent_id IS NOT NULL;

-- Poll options, one row each, in the order the poll shows them. Written while the poll is open
-- and untouched after the first vote; the unique key is what freezes them (F4: "options locked
-- after the first vote" is the route's check, and this is the backstop for two requests at once).
CREATE TABLE IF NOT EXISTS public.hr_ess_wall_poll_options (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id     uuid NOT NULL REFERENCES public.hr_ess_wall_posts(id) ON DELETE CASCADE,
  option_key  text NOT NULL CHECK (option_key ~ '^[a-z0-9][a-z0-9_-]{0,29}$'),
  label       text NOT NULL CHECK (length(btrim(label)) BETWEEN 1 AND 120),
  position    integer NOT NULL CHECK (position >= 0 AND position < 10),
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS hr_ess_wall_poll_options_post_key
  ON public.hr_ess_wall_poll_options (post_id, option_key);
CREATE UNIQUE INDEX IF NOT EXISTS hr_ess_wall_poll_options_post_position
  ON public.hr_ess_wall_poll_options (post_id, position);

-- One vote per person per option. A multiple-choice poll is several rows; a single-choice poll is
-- one, which the route enforces. voter_employee_id is never returned for an anonymous poll (F4:
-- nobody, HR included, can see who voted what) — the route decides that, and this row is why it
-- can: the vote is recorded, the name is never read out.
CREATE TABLE IF NOT EXISTS public.hr_ess_wall_poll_votes (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id            uuid NOT NULL REFERENCES public.hr_ess_wall_posts(id) ON DELETE CASCADE,
  option_id          uuid NOT NULL REFERENCES public.hr_ess_wall_poll_options(id) ON DELETE CASCADE,
  voter_employee_id  uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  voted_at           timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS hr_ess_wall_poll_votes_option_key
  ON public.hr_ess_wall_poll_votes (option_id, voter_employee_id);
CREATE INDEX IF NOT EXISTS hr_ess_wall_poll_votes_voter_idx
  ON public.hr_ess_wall_poll_votes (post_id, voter_employee_id);

-- One reaction per person per post or per comment (F2), whatever the reaction. The two partial
-- unique indexes are what "one per person" means when a row belongs to a post or to a comment.
CREATE TABLE IF NOT EXISTS public.hr_ess_wall_reactions (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id           uuid REFERENCES public.hr_ess_wall_posts(id) ON DELETE CASCADE,
  comment_id        uuid REFERENCES public.hr_ess_wall_comments(id) ON DELETE CASCADE,
  employee_id       uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  reaction          text NOT NULL CHECK (reaction IN ('like', 'love', 'laugh', 'clap', 'insightful', 'curious')),
  created_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT hr_ess_wall_reactions_target_chk CHECK ((post_id IS NULL) <> (comment_id IS NULL))
);

CREATE UNIQUE INDEX IF NOT EXISTS hr_ess_wall_reactions_post_key
  ON public.hr_ess_wall_reactions (post_id, employee_id) WHERE post_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS hr_ess_wall_reactions_comment_key
  ON public.hr_ess_wall_reactions (comment_id, employee_id) WHERE comment_id IS NOT NULL;
-- "Who reacted": the people behind one reaction, in the order they tapped it.
CREATE INDEX IF NOT EXISTS hr_ess_wall_reactions_reaction_idx
  ON public.hr_ess_wall_reactions (post_id, reaction, created_at);

-- Every @mention a post or a comment carries, one row each, so the notification is written once
-- and a mention can be looked up without reading the text (F1, F2, D6).
CREATE TABLE IF NOT EXISTS public.hr_ess_wall_mentions (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id           uuid REFERENCES public.hr_ess_wall_posts(id) ON DELETE CASCADE,
  comment_id        uuid REFERENCES public.hr_ess_wall_comments(id) ON DELETE CASCADE,
  mentioned_id      uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  mentioned_by_id   uuid REFERENCES public.hr_employees(id) ON DELETE SET NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT hr_ess_wall_mentions_target_chk CHECK ((post_id IS NULL) <> (comment_id IS NULL))
);

CREATE UNIQUE INDEX IF NOT EXISTS hr_ess_wall_mentions_post_key
  ON public.hr_ess_wall_mentions (post_id, mentioned_id) WHERE post_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS hr_ess_wall_mentions_comment_key
  ON public.hr_ess_wall_mentions (comment_id, mentioned_id) WHERE comment_id IS NOT NULL;

-- F6: the wish book. One wish per person per occasion per year, so a birthday does not gather
-- four hundred of them, and the day's cards can show who has wished already. A wish's post is
-- hidden for everybody once its supposed giver asks (application-level; the row stays here).
CREATE TABLE IF NOT EXISTS public.hr_ess_wall_wishes (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id    uuid NOT NULL REFERENCES public.hr_ess_wall_posts(id) ON DELETE CASCADE,
  about_id   uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  wisher_id  uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  occasion   text NOT NULL CHECK (occasion IN ('birthday', 'anniversary')),
  year       integer NOT NULL CHECK (year BETWEEN 2020 AND 2100),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT hr_ess_wall_wishes_self_chk CHECK (wisher_id <> about_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS hr_ess_wall_wishes_key
  ON public.hr_ess_wall_wishes (about_id, wisher_id, occasion, year);
CREATE INDEX IF NOT EXISTS hr_ess_wall_wishes_about_idx
  ON public.hr_ess_wall_wishes (about_id, created_at DESC);

ALTER TABLE public.hr_ess_wall_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hr_ess_wall_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hr_ess_wall_poll_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hr_ess_wall_poll_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hr_ess_wall_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hr_ess_wall_mentions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hr_ess_wall_wishes ENABLE ROW LEVEL SECURITY;

-- Row-level security with no policy keeps the API roles out of every row, but not out of
-- statements it does not cover, such as TRUNCATE. So they hold no privilege on the tables at all,
-- as on hr_ess_sessions; only the service role keeps what the ESS uses.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON TABLE public.hr_ess_wall_posts FROM anon;
    REVOKE ALL ON TABLE public.hr_ess_wall_comments FROM anon;
    REVOKE ALL ON TABLE public.hr_ess_wall_poll_options FROM anon;
    REVOKE ALL ON TABLE public.hr_ess_wall_poll_votes FROM anon;
    REVOKE ALL ON TABLE public.hr_ess_wall_reactions FROM anon;
    REVOKE ALL ON TABLE public.hr_ess_wall_mentions FROM anon;
    REVOKE ALL ON TABLE public.hr_ess_wall_wishes FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON TABLE public.hr_ess_wall_posts FROM authenticated;
    REVOKE ALL ON TABLE public.hr_ess_wall_comments FROM authenticated;
    REVOKE ALL ON TABLE public.hr_ess_wall_poll_options FROM authenticated;
    REVOKE ALL ON TABLE public.hr_ess_wall_poll_votes FROM authenticated;
    REVOKE ALL ON TABLE public.hr_ess_wall_reactions FROM authenticated;
    REVOKE ALL ON TABLE public.hr_ess_wall_mentions FROM authenticated;
    REVOKE ALL ON TABLE public.hr_ess_wall_wishes FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.hr_ess_wall_posts TO service_role;
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.hr_ess_wall_comments TO service_role;
    GRANT SELECT, INSERT, UPDATE ON TABLE public.hr_ess_wall_poll_options TO service_role;
    -- A vote is withdrawn by deleting its row (the app's own tap again).
    GRANT SELECT, INSERT, DELETE ON TABLE public.hr_ess_wall_poll_votes TO service_role;
    -- A reaction is removed by deleting its row; a changed reaction updates it.
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.hr_ess_wall_reactions TO service_role;
    GRANT SELECT, INSERT, DELETE ON TABLE public.hr_ess_wall_mentions TO service_role;
    GRANT SELECT, INSERT ON TABLE public.hr_ess_wall_wishes TO service_role;
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';
