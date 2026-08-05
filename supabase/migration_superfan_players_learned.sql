-- Migration: Superfan "Players Learned" collection (2026-08-05) — durable server mirror.
--
-- The collection of KHG players you've gotten to know this season (the anchor of the rebuilt Superfan).
-- Kept device-local (PlayersLearnedStore) for the live read; this table makes it survive a REINSTALL and
-- sync across devices. Cheap + bounded (~10–30 rows/user/season): id, name, team, best score.
--
-- Written on KHG finish (idempotent upsert, keeping the BEST score); read + merged into the local cache
-- when the Superfan detail opens. Same storage discipline as the rest of Superfan.
--
-- Run in the Supabase SQL editor. Idempotent. (Pairs with migration_superfan_scores_v3.sql this ship.)

create table if not exists public.superfan_players_learned (
  user_id      uuid    not null references auth.users(id) on delete cascade,   -- account-delete cascades
  season       int     not null,
  athlete_id   text    not null,
  player_name  text    not null,
  team_abbr    text    not null,
  best_correct int     not null default 0,
  out_of       int     not null default 0,
  learned_at   timestamptz default now(),
  primary key (user_id, season, athlete_id)                                    -- backs the best-score upsert
);

alter table public.superfan_players_learned enable row level security;

-- World-readable (a collection is not private), user writes only their own rows — the same idiom as
-- superfan_scores. A replay only RAISES best_correct (enforced app-side + the on-conflict upsert).
create policy "Anyone reads players-learned"
  on public.superfan_players_learned for select using (true);
create policy "Users insert own players-learned"
  on public.superfan_players_learned for insert with check (auth.uid() = user_id);
create policy "Users update own players-learned"
  on public.superfan_players_learned for update using (auth.uid() = user_id);

-- Grants (42501 gotcha — RLS is not privilege). Client reads/writes its own; no service_role needed.
grant select on public.superfan_players_learned to anon, authenticated;
grant select, insert, update on public.superfan_players_learned to authenticated;
