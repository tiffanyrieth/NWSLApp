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


-- ═════════════════════════════════════════════════════════════════════════════
-- Notifications — Tier 2 / server push (0.4.x)
-- ═════════════════════════════════════════════════════════════════════════════
--
-- Two tables back live match-event push. The app keeps them in sync per signed-in
-- user (RLS-scoped, like `follows`); the match-watcher Worker reads them with the
-- SERVICE-ROLE key (which bypasses RLS) to fan a goal out to every follower of a
-- team — a cross-user read no single user is allowed to do, by design.
--
--  * `device_tokens` — the APNs tokens for a user's devices (one row per device).
--    A user can have several (phone + iPad); a token can move between users (a
--    shared device), so the natural key is (user_id, token). The Worker selects
--    `token` for the matching followers.
--  * `notification_preferences` — the 9 toggles from the Profile screen, mirrored
--    server-side so the Worker can honor "goals: off" without asking the device.
--    1:1 with the user (like `profiles`), so user_id is the primary key.

-- APNs device tokens (one row per user per device)
create table public.device_tokens (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users(id) not null,
  token text not null,                 -- APNs device token (hex string)
  platform text not null default 'ios',
  updated_at timestamptz default now(),
  unique(user_id, token)               -- backs the app's upsert onConflict
);

-- Notification preferences (1:1 with the user; the 9 Profile toggles)
create table public.notification_preferences (
  user_id uuid references auth.users(id) primary key,
  day_before       boolean not null default true,
  lineup_posted    boolean not null default true,
  kickoff          boolean not null default true,
  goals            boolean not null default true,
  halftime         boolean not null default false,
  full_time        boolean not null default true,
  substitutions    boolean not null default false,
  fan_zone_rounds  boolean not null default true,
  player_spotlight boolean not null default true,
  updated_at timestamptz default now()
);

alter table public.device_tokens            enable row level security;
alter table public.notification_preferences enable row level security;

create policy "Users can read own device tokens"
  on public.device_tokens for select using (auth.uid() = user_id);
create policy "Users can insert own device tokens"
  on public.device_tokens for insert with check (auth.uid() = user_id);
create policy "Users can update own device tokens"
  on public.device_tokens for update using (auth.uid() = user_id);
create policy "Users can delete own device tokens"
  on public.device_tokens for delete using (auth.uid() = user_id);

create policy "Users can read own notification prefs"
  on public.notification_preferences for select using (auth.uid() = user_id);
create policy "Users can insert own notification prefs"
  on public.notification_preferences for insert with check (auth.uid() = user_id);
create policy "Users can update own notification prefs"
  on public.notification_preferences for update using (auth.uid() = user_id);

-- Grants (the 42501 gotcha again — RLS does not imply privilege).
grant select, insert, update, delete on public.device_tokens            to authenticated;
grant select, insert, update          on public.notification_preferences to authenticated;


-- ═════════════════════════════════════════════════════════════════════════════
-- Bracket Battle — community-voting tournament (Fan Zone game 2, 0.3.9)
-- ═════════════════════════════════════════════════════════════════════════════
--
-- The "guess what the community votes" game. A themed edition seeds a large player
-- pool into a bracket; each round, every signed-in user votes who advances, and the
-- community majority decides. Unlike `follows`/`device_tokens` (private per-user),
-- the EDITION + MATCHUPS + final SCORES are GLOBAL — everyone votes the same bracket
-- and sees the same standings — so they are world-READABLE (anon + authenticated;
-- you can read the rules + fill a bracket signed-out, the Apple sheet only appears
-- at submit). Only `bracket_votes` is RLS owner-scoped: you write your OWN picks.
--
-- Cross-user work (resolving a round's community winner from all votes, and writing
-- each user's score) is done by a SERVICE-ROLE job — the proxy match-watcher-style
-- Worker that generates editions + advances/tallies rounds (deferred; seeded by SQL
-- for now). The service role bypasses RLS, so no user can read others' raw votes —
-- they only see the resolved winner + split on the matchup, and the public scores.

-- Edition (global; one row is `is_active` at a time during the season)
create table public.bracket_editions (
  id text primary key,
  theme_label text not null,            -- tracked-caps eyebrow, "TOP FORWARD"
  title text not null,                  -- "Best Forward · 2026"
  emoji text not null,
  type text not null,                   -- 'statsSeeded' | 'creative'
  current_round int not null,           -- BracketRound rawValue (entrant count of round)
  round_opened_at timestamptz,
  round_closes_at timestamptz,
  is_active boolean not null default true,
  fan_count int not null default 0,
  created_at timestamptz default now()
);

-- Entrants in an edition's pool (seed order)
create table public.bracket_entrants (
  edition_id text references public.bracket_editions(id) on delete cascade,
  entrant_id text not null,             -- ESPN athlete id
  seed int not null,
  player_name text not null,
  jersey_number int,
  team_abbreviation text not null,
  primary key (edition_id, entrant_id)
);

-- Matchups per round. `community_winner_id` + `split_a_percent` are null until the
-- round closes and the service-role tally resolves them. `points` is the round's
-- per-correct-pick value (denormalized so scoring is a trivial sum).
create table public.bracket_matchups (
  id text primary key,                  -- "{edition}-r{round}-s{slot}"
  edition_id text references public.bracket_editions(id) on delete cascade,
  round int not null,
  slot int not null,
  entrant_a_id text not null,
  entrant_b_id text not null,
  points int not null,
  community_winner_id text,
  split_a_percent int,
  created_at timestamptz default now()
);

-- One vote per user per matchup (the chosen entrant). Owner-scoped.
create table public.bracket_votes (
  user_id uuid references auth.users(id) not null default auth.uid(),
  matchup_id text references public.bracket_matchups(id) on delete cascade,
  edition_id text not null,
  round int not null,
  entrant_id text not null,
  created_at timestamptz default now(),
  primary key (user_id, matchup_id)     -- backs the app's upsert onConflict
);

-- Per-user per-edition banked points — the leaderboard source. Written by the
-- service-role tally job (so it's a cross-user-readable standings table); the app
-- only reads it and splices its own live total in client-side.
create table public.bracket_scores (
  user_id uuid references auth.users(id) on delete cascade,
  edition_id text references public.bracket_editions(id) on delete cascade,
  display_name text,
  points int not null default 0,
  updated_at timestamptz default now(),
  primary key (user_id, edition_id)
);

-- ── Row-Level Security ───────────────────────────────────────────────────────

alter table public.bracket_editions enable row level security;
alter table public.bracket_entrants enable row level security;
alter table public.bracket_matchups enable row level security;
alter table public.bracket_votes    enable row level security;
alter table public.bracket_scores   enable row level security;

-- Public reads (the bracket is global; browse it signed-out). Writes to these
-- tables are service-role only (no authenticated insert/update policy → blocked).
create policy "Anyone can read bracket editions" on public.bracket_editions for select using (true);
create policy "Anyone can read bracket entrants" on public.bracket_entrants for select using (true);
create policy "Anyone can read bracket matchups" on public.bracket_matchups for select using (true);
create policy "Anyone can read bracket scores"   on public.bracket_scores   for select using (true);

-- Votes: each user reads/writes only their own picks.
create policy "Users read own bracket votes"
  on public.bracket_votes for select using (auth.uid() = user_id);
create policy "Users insert own bracket votes"
  on public.bracket_votes for insert with check (auth.uid() = user_id);
create policy "Users update own bracket votes"
  on public.bracket_votes for update using (auth.uid() = user_id);

-- ── Grants (the 42501 gotcha — RLS does not imply privilege) ──────────────────
-- Read tables go to anon + authenticated (signed-out browsing); votes are
-- authenticated-only. Service-role (generation/tally) bypasses RLS + needs no grant.
grant select on public.bracket_editions to anon, authenticated;
grant select on public.bracket_entrants to anon, authenticated;
grant select on public.bracket_matchups to anon, authenticated;
grant select on public.bracket_scores   to anon, authenticated;
grant select, insert, update on public.bracket_votes to authenticated;
