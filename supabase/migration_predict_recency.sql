-- Migration: Predict SEASON leaderboard — recency-to-remain (replaces the 3-match ranking gate)
--
-- Owner ruling 2026-08-04: the "predict 3 matches before you're ranked" gate leaned too competitive /
-- gamer for a low-entry women's-soccer fandom app (it put a barrier at the front door for every new
-- fan). Replace it: you rank on the season board from your VERY FIRST prediction (zero entry barrier —
-- newcomers show up right away), and only DROP OFF the board after long inactivity. This kills the
-- "someone plays once, gets lucky, and their name sits at the top for six months" ghost problem without
-- gating entry. Invisible to anyone who plays even occasionally.
--
-- Mechanism: a `last_scored_at` stamp on prediction_scores, bumped whenever a NEW match is banked (the
-- `matches` count goes up). The season-board queries then filter to rows active within the recency
-- window (~3 months app-side — break-tolerant for World Cup / international windows). The app's upsert
-- doesn't send this column; a trigger owns it, so no client change is needed.
--
-- Run in the Supabase SQL editor. Idempotent.

alter table public.prediction_scores
  add column if not exists last_scored_at timestamptz not null default now();
-- (add-column-with-default backfills existing rows to now(): everyone currently on the board starts
--  "active" and only fades if they go quiet for the window from here — nobody drops off immediately.)

-- Bump last_scored_at only when the row banks a genuinely new match (matches increases). A plain
-- app-open re-push (same matches) leaves it untouched, so it tracks "last actually played", not
-- "last opened the app". Fires on the upsert's ON CONFLICT DO UPDATE path.
create or replace function public.bump_prediction_last_scored()
returns trigger
language plpgsql
as $$
begin
  if new.matches > old.matches then
    new.last_scored_at = now();
  end if;
  return new;
end;
$$;

drop trigger if exists prediction_scores_last_scored on public.prediction_scores;
create trigger prediction_scores_last_scored
  before update on public.prediction_scores
  for each row execute function public.bump_prediction_last_scored();

-- Season board queries filter (team, season, last_scored_at) — index it so the recency filter + the
-- avg-ordered read + the rank COUNT don't scan the table at scale.
create index if not exists prediction_scores_recent_idx
  on public.prediction_scores (team_abbreviation, season, last_scored_at);
