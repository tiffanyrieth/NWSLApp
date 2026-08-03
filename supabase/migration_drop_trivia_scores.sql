-- Retire the orphaned `trivia_scores` table (2026-08-03).
--
-- WHY. This backed the league-wide "best streak" leaderboard, which was DELETED in the biweekly
-- Trivia rebuild (app PR #167, 2026-07-22) along with `TriviaLeaderboardService`. The Swift code went;
-- the table did not. Nothing in the app, the proxy or the watcher has read or written it since —
-- confirmed by a full-repo sweep on 2026-08-03. Found by the sync-direction audit (`docs/data-sync.md`).
--
-- ⚠️ WHY THE CLEANUP WAS MISSED, worth remembering: removing a reader is a code change that shows up
-- in a PR diff; dropping a table is a separate step run by hand in the Supabase console, so it lives
-- OUTSIDE the diff and rides along with nothing. Every schema change in this repo is a manual .sql
-- file — when a feature dies, its table needs its own deliberate follow-up or it simply persists.
--
-- ARCHIVE FIRST, then drop. The rows are stale by definition — pre-rebuild a "streak" counted
-- consecutive DAYS, post-rebuild it counts consecutive ROUNDS, so the stored integers no longer mean
-- what the column name says and must never be read back into the new model. But the drop is one-way,
-- these are real user rows, and the copy costs nothing. Delete the archive whenever you like.
--
-- Run in the Supabase SQL editor. Idempotent: safe to re-run.

begin;

-- 1. Snapshot whatever is there (no-op if the table is already gone).
create table if not exists public.trivia_scores_archive_2026_08 as
  select * from public.trivia_scores;

comment on table public.trivia_scores_archive_2026_08 is
  'Frozen copy of trivia_scores, retired 2026-08-03. Streak values here count DAYS (pre-2026-07-22 '
  'Trivia rebuild), NOT rounds — do not read them back into the biweekly-round model. Safe to drop.';

-- The archive is owner-only: no RLS policies, no grants. Nothing should query it from the app.
revoke all on public.trivia_scores_archive_2026_08 from anon, authenticated;

-- 2. Drop the live table. Policies + grants go with it; `cascade` clears the FK to auth.users
--    that migration_account_deletion_cascade.sql added.
drop table if exists public.trivia_scores cascade;

commit;

-- Verify (expect: 0 rows for the first, 1 for the second):
--   select count(*) from information_schema.tables
--     where table_schema = 'public' and table_name = 'trivia_scores';
--   select count(*) from information_schema.tables
--     where table_schema = 'public' and table_name = 'trivia_scores_archive_2026_08';
