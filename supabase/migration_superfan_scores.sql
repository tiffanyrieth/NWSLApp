-- ═══════════════════════════════════════════════════════════════════════════
-- Superfan Zone — per-season cross-game total + tier/percentile (Fan Zone v2, Priority #3)
-- ═══════════════════════════════════════════════════════════════════════════
-- One row per (user, season): the fan's combined Superfan total this season plus how many of the four
-- games they've played (the ≥2-game qualification for the percentile/tier). World-readable (the tier
-- system is a rank across all qualifying fans, computed client-side with a count query — no Postgres
-- function). Season-scoped: each NWSL season is its own row, never combined across years.
--
-- Idempotent: safe to re-run. Model = prediction_scores (schema.sql).

create table if not exists public.superfan_scores (
  user_id uuid references auth.users(id) on delete cascade,
  season text not null default '2026',
  total int not null default 0,
  games_played int not null default 0,   -- the ≥2 qualifier for the percentile/tier
  display_name text,
  updated_at timestamptz default now(),
  primary key (user_id, season)           -- backs the upsert onConflict
);

alter table public.superfan_scores enable row level security;

-- Public reads (the tier percentile is a rank across all fans, browsable). Each user writes only their own row.
drop policy if exists "Anyone can read superfan scores" on public.superfan_scores;
create policy "Anyone can read superfan scores"
  on public.superfan_scores for select using (true);
drop policy if exists "Users insert own superfan score" on public.superfan_scores;
create policy "Users insert own superfan score"
  on public.superfan_scores for insert with check (auth.uid() = user_id);
drop policy if exists "Users update own superfan score" on public.superfan_scores;
create policy "Users update own superfan score"
  on public.superfan_scores for update using (auth.uid() = user_id);

-- Grants (the 42501 gotcha — RLS does not imply privilege). Read: anon + authed (the rank is public);
-- write: authenticated-only (the user's own row). No service_role: the app reads/writes directly, no proxy path.
grant select on public.superfan_scores to anon, authenticated;
grant select, insert, update on public.superfan_scores to authenticated;
