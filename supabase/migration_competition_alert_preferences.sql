-- Migration: competition_alert_preferences (national-team match alerts)
--
-- The national-team twin of team_alert_preferences — WHICH national teams buzz your phone on match
-- day (🔔), keyed by the SAME follow_key as competition_follows ("nt:USA"). Closes the national-team
-- alert pipeline (app writes here, the match-watcher reads it as service_role when it polls the
-- national-team ESPN feeds and fans a NT event out by FIFA code). Run once in the Supabase SQL editor.
--
-- WHY a separate table (not team_alert_preferences): that table is keyed by ESPN CLUB id and joined by
-- the watcher against the NWSL scoreboard; a FIFA-code row there would muddy those club follower
-- lookups (the competition_follows schema comment warns of exactly this).

create table if not exists public.competition_alert_preferences (
  user_id uuid references auth.users(id) on delete cascade not null,
  follow_key text not null,              -- "nt:USA" (matches competition_follows.follow_key)
  alerts_enabled boolean not null default false,
  updated_at timestamptz default now(),
  primary key (user_id, follow_key)
);

alter table public.competition_alert_preferences enable row level security;

create policy "Users read own competition alert prefs"
  on public.competition_alert_preferences for select using (auth.uid() = user_id);
create policy "Users insert own competition alert prefs"
  on public.competition_alert_preferences for insert with check (auth.uid() = user_id);
create policy "Users update own competition alert prefs"
  on public.competition_alert_preferences for update using (auth.uid() = user_id);
create policy "Users delete own competition alert prefs"
  on public.competition_alert_preferences for delete using (auth.uid() = user_id);

-- Grants (the 42501 gotcha — RLS does not imply privilege). authenticated writes its own rows; the
-- match-watcher reads as service_role even though it bypasses RLS.
grant select, insert, update, delete on public.competition_alert_preferences to authenticated;
grant select on public.competition_alert_preferences to service_role;
