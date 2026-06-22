-- NWSLApp — Bracket Battle v2 migration: Manual/Auto mode, qualifying pools, stat backing
--
-- Run ONCE in the Supabase SQL editor, AFTER migration_bracket_v2.sql (vote_count +
-- creative-edition library + service_role grants). This migration takes Bracket from the
-- fully-auto 64-only engine to the operator-controlled, large-pool (96–256) game:
--   1. bracket_config           — global Worker settings + the Manual/Auto switch + the
--                                 manual_action queue (the operator controls the live game
--                                 with a single value change here; no deploy, no app push).
--   2. bracket_stats_editions   — the stat-edition library (Best Forward/GK/Mid/Defender,
--                                 Ironwoman…), mirroring the creative-edition library; the
--                                 Worker seeds the pool live from ESPN by `seeding_stat`.
--   3. bracket_user_edition_stats — per-edition accuracy backing for the Leaderboard's
--                                 "Your Stats" tab, written by the service-role tally.
--   4. bracket_editions columns — mode + pool/round/order/timestamps for the new structure.
-- Idempotent: `add column if not exists` / `create table if not exists` / `on conflict do
-- nothing` are all safe to re-run.

-- ── 1. Global Worker config + the Manual/Auto switch ─────────────────────────
-- One row per setting (key → jsonb value). The Worker reads this on EVERY poll cycle.
-- mode = "manual" | "auto"; in manual mode the Worker acts only on `manual_action`
-- (advance_round | close_edition | start_edition | pause | resume), then clears it. Flip
-- to fully-automatic with ONE update — no deploy, no app change:
--     update public.bracket_config set value = '"auto"', updated_at = now() where key = 'mode';
create table if not exists public.bracket_config (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz default now()
);

-- Seed defaults (do nothing if a key already exists, so re-running never resets live state).
insert into public.bracket_config (key, value) values
  ('mode', '"manual"'),                  -- launch in Manual; flip to "auto" when ready
  ('season', '"2026"'),                  -- gates "no theme repeats per season"
  ('default_pool_size', '128'),          -- target pool for generated editions
  ('early_round_days', '2'),             -- qualifying + first 2 main rounds: 2-day windows
  ('late_round_days', '3'),              -- Round of 16 onward: 3-day windows
  ('break_days', '10'),                  -- gap between editions (auto mode)
  ('manual_action', 'null'),             -- the operator's pending one-shot action (or null)
  ('theme_rotation', '"alternate"'),     -- "alternate" (stats↔creative) | "sequential"
  ('used_themes_this_season', '[]')      -- ids consumed this season (rotation skip-list)
on conflict (key) do nothing;

alter table public.bracket_config enable row level security;
-- World-readable so the app can show e.g. the mode; writes are service-role only (the
-- operator's SQL/loader or the Worker). RLS does not imply privilege (the 42501 gotcha).
create policy "Anyone can read bracket config"
  on public.bracket_config for select using (true);
grant select on public.bracket_config to anon, authenticated;
grant select, insert, update, delete on public.bracket_config to service_role;

-- ── 2. Stats-edition library (Worker seeds the pool live from ESPN) ──────────
-- The twin of bracket_creative_editions for STAT editions. Creative editions carry their
-- full player roster as JSON (the content lines matter); stat editions carry only the
-- RECIPE — which position to pull and which stat to seed by — and the Worker builds the
-- pool from ESPN at generation time. Adding a new stat edition is a pure DATA insert.
create table if not exists public.bracket_stats_editions (
  id text primary key,                   -- e.g. 'best-goalkeeper-2026'
  theme_label text not null,             -- tracked-caps eyebrow, "BEST GOALKEEPER"
  title text not null,                   -- "Best Goalkeeper · 2026"
  description text not null,             -- the intro blurb (warm, fan voice)
  position_filter text,                  -- 'F' | 'M' | 'D' | 'G' | null (all positions)
  seeding_stat text not null,            -- 'goals_assists' | 'save_pct' | 'minutes' | …
  status text not null default 'ready',  -- 'ready' | 'used'
  season int not null,                   -- gates "no repeats per season"
  created_at timestamptz default now()
);

alter table public.bracket_stats_editions enable row level security;
create policy "Anyone can read stats editions"
  on public.bracket_stats_editions for select using (true);
grant select on public.bracket_stats_editions to anon, authenticated;
grant select, insert, update, delete on public.bracket_stats_editions to service_role;

-- ── 3. Per-edition user stats (backs the Leaderboard "Your Stats" tab) ───────
-- Written by the service-role tally at each round close (alongside bracket_scores). This
-- must exist BEFORE the first live edition — accuracy can't be recomputed once a round's
-- votes/matchups age out, so we accumulate it as rounds resolve. The app derives lifetime
-- totals + best edition client-side from the row set; per-edition accuracy = correct/total.
-- World-readable (the Rankings tab shows every player's accuracy %, same as bracket_scores
-- exposes points + display_name); writes are service-role only.
create table if not exists public.bracket_user_edition_stats (
  user_id uuid references auth.users(id) on delete cascade,
  edition_id text references public.bracket_editions(id) on delete cascade,
  correct_picks int not null default 0,  -- cumulative correct picks this edition
  total_picks int not null default 0,    -- cumulative submitted picks scored this edition
  best_round int,                        -- round int (BracketRound rawValue) of best accuracy
  best_round_correct int,                -- correct picks in that round (for an honest %)
  best_round_total int,                  -- picks in that round
  updated_at timestamptz default now(),
  primary key (user_id, edition_id)
);
-- (Streak metrics for Your Stats are intentionally NOT stored yet — the exact definition
--  of "current/longest streak" is settled in the Leaderboard phase; add a column then.)

alter table public.bracket_user_edition_stats enable row level security;
create policy "Anyone can read bracket user stats"
  on public.bracket_user_edition_stats for select using (true);
grant select on public.bracket_user_edition_stats to anon, authenticated;
grant select, insert, update, delete on public.bracket_user_edition_stats to service_role;

-- ── 4. Edition metadata for the new structure ────────────────────────────────
-- mode is recorded per edition for history; bracket_config.mode is AUTHORITATIVE for the
-- Worker's behavior. pool_size/total_rounds/edition_order are set at generation;
-- started_at/completed_at frame the active window (completed_at set when the final resolves).
alter table public.bracket_editions
  add column if not exists mode text not null default 'manual',
  add column if not exists edition_order int,
  add column if not exists pool_size int,
  add column if not exists total_rounds int,
  add column if not exists started_at timestamptz,
  add column if not exists completed_at timestamptz;
