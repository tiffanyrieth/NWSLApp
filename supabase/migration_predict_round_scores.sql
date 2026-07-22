-- Predict the XI — per-ROUND (soccer-week) leaderboard rows (2026-07-23).
--
-- WHY: the comp arena needs TWO clocks (owner design ruling — Overwatch model): this-round rank AND
-- season rank. The season clock existed (`prediction_scores`, one row per user/team/season); the round
-- clock did not — per-fixture points lived only in the device's PredictionStore, so "how did I rank in
-- Sunday's Spirit round" was unbuildable server-side. This table is that round clock: one row per
-- (user, team, season, week), points = the sum of that soccer week's scored fixtures for that club
-- (a two-game week sums both — owner rule). Boards are PER-CLUB (fans of one club share the same
-- fixtures that week, so the comparison is fair).
--
-- `week` is the CALENDAR-derived soccer-week ordinal (FanZoneCadence.soccerWeek, Week 1 = the week of
-- the season opener). Deliberately calendar-based, not fixture-counted: it's a primary key, and a
-- postponed match must never renumber every later week under already-banked rows. Weeks with no NWSL
-- fixtures simply have no rows (the app shows Predict's paused state instead of a phantom round).
--
-- RETENTION (owner rule): current + previous completed round only — the daily cron prunes rows whose
-- updated_at is older than ~4 weeks (see migration_retention_cron.sql); the season table keeps the
-- running totals forever. Size while live: users × followed-clubs × 2 weeks ⇒ trivially passes 1k/100k.
--
-- Idempotent-ish: `create table if not exists` is safe to re-run (skip to grants if it exists).

create table if not exists public.predict_round_scores (
  user_id uuid references auth.users(id) on delete cascade not null default auth.uid(),
  team_abbreviation text not null,
  season text not null default '2026',
  week int not null,
  display_name text,
  points int not null default 0,
  updated_at timestamptz default now(),
  primary key (user_id, team_abbreviation, season, week)   -- backs the app's upsert onConflict
);

alter table public.predict_round_scores enable row level security;

-- Same visibility contract as prediction_scores: standings are browsable signed-out;
-- each user writes only their own rows.
create policy "Anyone can read predict round scores"
  on public.predict_round_scores for select using (true);
create policy "Users insert own predict round score"
  on public.predict_round_scores for insert with check (auth.uid() = user_id);
create policy "Users update own predict round score"
  on public.predict_round_scores for update using (auth.uid() = user_id);

-- Grants (the 42501 gotcha — RLS does not imply privilege). Read: anon + authed;
-- write: authenticated-only (own rows).
grant select on public.predict_round_scores to anon, authenticated;
grant insert, update on public.predict_round_scores to authenticated;
