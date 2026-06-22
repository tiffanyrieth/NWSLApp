-- NWSLApp — Bracket Battle v2 migration (0.3.9)
--
-- Run ONCE in the Supabase SQL editor, AFTER schema.sql's bracket_* section already
-- exists (it does — the v1 tables were applied earlier). This migration takes Bracket
-- from the hand-seeded test scaffold to the real, Worker-driven v2 game:
--   1. adds the community vote count to matchups (shown in the "See stats" reveal),
--   2. adds the owner-curated CREATIVE EDITION library the Worker rotates from,
--   3. drops the old 16-player test edition (the Worker generates real ones now).
-- Idempotent-ish: `add column if not exists` / `create table if not exists` are safe to
-- re-run; the delete only removes the named test edition.

-- ── 1. Vote count on matchups ────────────────────────────────────────────────
-- Written by the service-role tally at round close; null until then. The app shows
-- "N fans voted" in the results donut.
alter table public.bracket_matchups
  add column if not exists vote_count int;

-- ── 2. Creative-edition library (owner-curated; the Worker rotates from this) ──
-- Stats-seeded editions are generated live from ESPN by the Worker and need no
-- storage. CREATIVE editions (best goal celebration, walkout song, staring contest…)
-- are owner-curated: researched + vetted on Claude Max, handed to Code, loaded here as
-- data. The Worker picks the next `ready` row when it's time for a creative edition and
-- flips it to `used` — adding a future edition is a pure DATA insert, never an app push.
--
-- `entries` is a JSON array; each entry = one bracket contender with its verified
-- content line + source. The bracket structure (seeding/byes/matchups) is built by the
-- Worker from this list — the JSON only carries WHO is in and WHAT they're known for.
-- See Reference/Bracket Battle/creative-edition-template.json for the exact shape and
-- scripts/load_creative_edition.mjs to turn a vetted JSON file into the INSERT below.
create table if not exists public.bracket_creative_editions (
  id text primary key,                 -- e.g. 'best-goal-celebration-2026'
  theme_label text not null,           -- tracked-caps eyebrow, "BEST CELEBRATION"
  title text not null,                 -- "Best Goal Celebration · 2026"
  description text not null,           -- the intro blurb (warm, fan voice)
  status text not null default 'ready',-- 'ready' | 'used'
  season int not null,                 -- gates "no repeats per season"
  entries jsonb not null,              -- [{ player_id, player_name, jersey_number,
                                       --    team_abbreviation, seed, content, source }, …]
  created_at timestamptz default now()
);

alter table public.bracket_creative_editions enable row level security;

-- World-readable (same as the other bracket content); writes are service-role only
-- (the Worker / the owner's load script with the service-role key) — no authenticated
-- insert/update policy, so RLS blocks app writes.
drop policy if exists "Anyone can read creative editions" on public.bracket_creative_editions;
create policy "Anyone can read creative editions"
  on public.bracket_creative_editions for select using (true);

-- Grants (the 42501 gotcha — RLS does not imply privilege). Read to anon+authenticated;
-- the service role bypasses RLS for writes and needs no grant.
grant select on public.bracket_creative_editions to anon, authenticated;

-- ── 2b. Grants for the Worker (service_role) ─────────────────────────────────
-- The proxy Worker writes editions/matchups/scores with the service-role key. RLS
-- BYPASS is not the same as a table GRANT (the 42501 gotcha — see
-- project memory supabase_rls_needs_grants): service_role still needs explicit table
-- privileges. (The original schema granted only anon/authenticated.)
grant select, insert, update, delete on
  public.bracket_editions,
  public.bracket_entrants,
  public.bracket_matchups,
  public.bracket_votes,
  public.bracket_scores,
  public.bracket_creative_editions
to service_role;

-- ── 3. Drop the v1 hand-seeded test edition ──────────────────────────────────
-- The Worker generates real editions now; the 16-player "Top Forward" scaffold goes.
-- Cascades to its entrants / matchups / votes.
delete from public.bracket_editions where id = 'top-forward-2026';
