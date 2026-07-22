-- Fan Zone progress restore — the per-user, per-season SUMMARY row (2026-07-23).
--
-- WHY: "sign in restores your follows" was removed (16 clubs, seconds to re-pick) — what a fan
-- would actually mourn on a replaced/reinstalled phone is GAME progress: streaks, season points,
-- lifetime accuracy. Those lived only in UserDefaults; the server had every leaderboard total but
-- nothing ever read back DOWN. This table is the read-back: one tiny row per (user, season) that
-- the app upserts after each quiz completion and folds back into the local stores at sign-in
-- (monotonic max-merge — a stale server row can never LOWER a fresher local count, the same clamp
-- philosophy as superfan_scores).
--
-- Deliberately a SUMMARY, not history: raw `quiz_answers` are pruned to the current+previous round
-- (owner retention rule), so restore must never depend on them. ~150 bytes/row ⇒ ~20 MB at 100k
-- users — passes the 1k/100k stress tests by construction (stress-testing.md §7 entry).
--
-- Predict + Bracket need no columns here: `prediction_scores` and `bracket_user_edition_stats`
-- already hold their per-user numbers server-side and are read back by the boards.
--
-- Idempotent-ish: `create table if not exists` is safe to re-run (skip to grants if it exists).

create table if not exists public.fanzone_progress (
  user_id uuid references auth.users(id) on delete cascade not null default auth.uid(),
  season text not null default '2026',

  -- NWSL Trivia (biweekly rounds)
  trivia_lifetime_correct  int not null default 0,
  trivia_lifetime_answered int not null default 0,
  trivia_best_streak       int not null default 0,
  trivia_season_correct    int not null default 0,
  trivia_round_streak      int not null default 0,
  trivia_last_round        int not null default 0,   -- round ordinal of the latest completion

  -- Know Her Game (biweekly editions)
  khg_season_points        int not null default 0,
  khg_editions_played      int not null default 0,
  khg_week_streak          int not null default 0,
  khg_best_week_streak     int not null default 0,
  khg_last_week            text,                     -- ISO weekKey of the latest completion

  updated_at timestamptz default now(),
  primary key (user_id, season)                      -- backs the app's upsert onConflict
);

alter table public.fanzone_progress enable row level security;

-- Owner-only in BOTH directions: progress is personal, never browsed cross-user
-- (leaderboards have their own world-readable tables).
create policy "Users read own fanzone progress"
  on public.fanzone_progress for select using (auth.uid() = user_id);
create policy "Users insert own fanzone progress"
  on public.fanzone_progress for insert with check (auth.uid() = user_id);
create policy "Users update own fanzone progress"
  on public.fanzone_progress for update using (auth.uid() = user_id);

-- Grants (the 42501 gotcha — RLS does not imply privilege). App-only table: no anon read
-- (progress is meaningless signed out), no service_role (no Worker touches it).
grant select, insert, update on public.fanzone_progress to authenticated;
