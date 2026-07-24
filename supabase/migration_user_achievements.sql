-- ═══════════════════════════════════════════════════════════════════════════
-- Achievements — the Superfan "Your Best Moments" (Fan Zone Competitive Redesign, PR4)
-- ═══════════════════════════════════════════════════════════════════════════
-- One row per (user, achievement, season) earned across the four Fan Zone games. Detected CLIENT-SIDE at
-- game completion (this app has no Supabase Edge Functions — the deliberate minimal-dependency stance) and
-- upserted here; the UNIQUE (user_id, achievement_key, season_year) makes a re-award a no-op, so the same
-- game commit firing detection twice can never duplicate a badge (the achievement twin of the score
-- idempotency rule). `metadata` (jsonb) carries the flavor detail for the card ("10/10 on Sandy MacIver",
-- "3 upsets in Round 4"). Season-scoped: an achievement can be re-earned in a new season.
--
-- World-readable (a badge is public, like the leaderboards + display names); each user writes only their
-- own rows. No service_role — the app writes/reads directly. Idempotent: safe to re-run.

create table if not exists public.user_achievements (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users(id) on delete cascade,
  achievement_key text not null,
  earned_at timestamptz default now(),
  metadata jsonb,
  season_year int not null,
  unique (user_id, achievement_key, season_year)   -- award idempotency
);

create index if not exists user_achievements_user_idx on public.user_achievements (user_id, season_year);

alter table public.user_achievements enable row level security;

drop policy if exists "Anyone can read achievements" on public.user_achievements;
create policy "Anyone can read achievements"
  on public.user_achievements for select using (true);
drop policy if exists "Users insert own achievements" on public.user_achievements;
create policy "Users insert own achievements"
  on public.user_achievements for insert with check (auth.uid() = user_id);

-- Grants (the 42501 gotcha — RLS ≠ privilege). Read: anon + authed (public badges); write: authed-only.
-- No UPDATE/DELETE: an earned achievement is permanent (the on-conflict-do-nothing award never updates).
grant select on public.user_achievements to anon, authenticated;
grant select, insert on public.user_achievements to authenticated;
