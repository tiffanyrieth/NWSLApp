-- NWSLApp — Supabase schema (per-user backend, 0.2.x)
--
-- The source of truth for the Supabase Postgres schema behind Sign in with Apple
-- + follow sync. Run in the Supabase SQL editor on a fresh project to reproduce
-- the backend. Idempotent-ish: `create table` will error if the tables already
-- exist (drop them first, or skip to the grants). No secrets live here — the
-- project URL + anon key are in the gitignored NWSLApp/Config/Secrets.swift.
--
-- Design notes:
--  * `profiles` extends Supabase's auth.users (1:1, same id).
--  * `follows` is one row per (user, club), keyed by ESPN team id (a string).
--  * RLS scopes every row to its owner (auth.uid()). RLS alone is NOT enough —
--    a role also needs table-level GRANTs or queries fail with 42501
--    "permission denied for table". We grant to `authenticated` only; `anon`
--    stays locked out (these are private per-user tables).

-- ── Tables ───────────────────────────────────────────────────────────────────

-- User profiles (extends Supabase auth.users)
create table public.profiles (
  id uuid references auth.users(id) primary key,
  display_name text,
  created_at timestamptz default now()
);

-- Followed teams (one row per user per club)
create table public.follows (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users(id) not null,
  team_id text not null,            -- ESPN team id (string)
  created_at timestamptz default now(),
  unique(user_id, team_id)          -- backs the app's upsert onConflict
);

-- ── Row-Level Security ───────────────────────────────────────────────────────

alter table public.profiles enable row level security;
alter table public.follows  enable row level security;

create policy "Users can read own profile"
  on public.profiles for select using (auth.uid() = id);
create policy "Users can update own profile"
  on public.profiles for update using (auth.uid() = id);
create policy "Users can insert own profile"
  on public.profiles for insert with check (auth.uid() = id);

create policy "Users can read own follows"
  on public.follows for select using (auth.uid() = user_id);
create policy "Users can insert own follows"
  on public.follows for insert with check (auth.uid() = user_id);
create policy "Users can delete own follows"
  on public.follows for delete using (auth.uid() = user_id);

-- ── Table-level grants (REQUIRED — RLS does not imply privilege) ──────────────
-- Without these, a signed-in user's queries fail with 42501 and follow sync
-- silently no-ops. Grant to `authenticated` only, never `anon`.

grant select, insert, update, delete on public.follows  to authenticated;
grant select, insert, update          on public.profiles to authenticated;
