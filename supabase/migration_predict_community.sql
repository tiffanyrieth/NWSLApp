-- Predict the XI — community pick aggregate (2026-07-28, results-redesign handoff Part 4a.4).
--
-- WHAT IT IS: how many of a club's predictors picked each player for a given match. It powers the
-- share bars, the "biggest hit / biggest miss" standout cards, the consensus XI, and the post-close
-- contrarian panel on the locked-wait screen.
--
-- ⚠️ THE CONSTRAINT THAT SHAPES ALL OF THIS: individual lineups are LOCAL-ONLY and stay that way
-- (docs/fan-zone.md §3 — "Predict lineups (the 11 picks) | PredictionStore | never uploaded").
-- Uploading everyone's XI would also be exactly the per-user-per-round growth the storage budget
-- can't absorb (docs/stress-testing.md). So we store COUNTS, never lineups:
--   predict_pick_counts is bounded by SQUAD SIZE × SLOTS × MATCHES — roughly 150 rows per match,
--   ~27k rows per season, IDENTICAL whether 100 people play or 100,000.
--
-- ⚠️ WHY AN RPC AND NOT A CLIENT WRITE. The design handoff specified a bare counter table with no
-- user_id, incremented by the app "idempotently per prediction". That cannot work:
--   (a) with no user column, RLS has nothing to constrain — `with check (auth.uid() = user_id)` is
--       the entire write-authorization model everywhere else in this schema, so any signed-in user
--       could inflate any player's count arbitrarily;
--   (b) "idempotent per prediction" with no server-side key can only be a LOCAL flag, which fails on
--       reinstall and on a write that succeeds but whose response is lost.
-- Every other aggregate in this database (analytics_counters, bracket splits, quiz distributions) is
-- written by a SECURITY DEFINER function for the same reason. So: predict_submission_marks holds one
-- (user_id, event_id) row as the dedupe key — and NOTHING else, so no lineup is reconstructable from
-- it — and predict_record_picks refuses to count a second time for the same pair.
--
-- ⚠️ READS ARE NOT GRANTED TO CLIENTS. The percentages must stay unreadable until submissions close
-- at kickoff − 2h; if they were queryable while picking, users would copy the consensus and flatten
-- the very distribution the feature depends on. Postgres cannot enforce that gate — it has no idea
-- when kickoff is. So predict_pick_distribution is service_role-only and is reached through the
-- proxy's GET /predict/community, which knows kickoff from its cached ESPN data and fails CLOSED.
--
-- THREAT MODEL: a modified client can report picks it did not make. That is already true of this
-- game — Predict scores are computed on-device and self-reported (see schema.sql's note on
-- prediction_scores). The property that matters is the one the mark enforces: one submission per
-- user per match, no matter how many times the call is retried.
--
-- Run in the Supabase SQL editor. Idempotent (create if not exists / or replace).

-- ── Tables ────────────────────────────────────────────────────────────────────

-- The aggregate itself. NO user_id, by design and permanently.
-- `slot` is retained (not just player) because the consensus XI is "the most-picked player PER SLOT";
-- the set-wise share a player owns is the SUM across her slots, which matches how scoring treats a
-- hit (a pick counts if she started anywhere).
create table if not exists public.predict_pick_counts (
  season            text not null default '2026',
  week              int  not null,               -- FanZoneCadence.soccerWeek of the kickoff
  event_id          text not null,               -- ESPN event id
  team_abbreviation text not null,               -- the club whose XI was predicted
  player_id         text not null,               -- ESPN athlete id
  slot              int  not null,               -- Formation slot index 0…10
  count             int  not null default 0,
  updated_at        timestamptz default now(),
  primary key (season, week, event_id, team_abbreviation, player_id, slot)
);

-- The percentage DENOMINATOR: how many complete XIs were submitted for this match.
--
-- `closes_at` is the LATE-WRITE GUARD and is writable only by service_role (see
-- predict_set_close below). Counters are pre-summed, so unlike raw rows they cannot be
-- retro-filtered to a cutoff — a submission that lands after the real lineup is public would
-- sit in the aggregate permanently. The honest client already refuses to submit past the
-- deadline, but that is a client-side gate; this column is the server-side one. It is written
-- by the PROXY (which derives kickoff − 2h from ESPN) precisely so a client cannot forge it —
-- a client-supplied deadline would be worth nothing, and a client-supplied timestamp column on
-- a raw-rows design has exactly the same flaw.
create table if not exists public.predict_match_submissions (
  season            text not null default '2026',
  week              int  not null,
  event_id          text not null,
  team_abbreviation text not null,
  submissions       int  not null default 0,
  closes_at         timestamptz,           -- proxy-written; null until first looked up
  updated_at        timestamptz default now(),
  primary key (season, week, event_id, team_abbreviation)
);

-- Additive for re-runs against an earlier version of this migration.
alter table public.predict_match_submissions add column if not exists closes_at timestamptz;

-- The dedupe key, and ONLY the dedupe key. Deliberately stores no picks: knowing that a user
-- submitted for a match reveals nothing about who she picked.
create table if not exists public.predict_submission_marks (
  user_id    uuid not null references auth.users(id) on delete cascade,
  event_id   text not null,
  created_at timestamptz default now(),
  primary key (user_id, event_id)
);

-- RLS on with NO client policies on any of the three — anon/authenticated can neither read nor write
-- them directly. The two SECURITY DEFINER functions below are the only paths in and out.
alter table public.predict_pick_counts        enable row level security;
alter table public.predict_match_submissions  enable row level security;
alter table public.predict_submission_marks   enable row level security;

-- ── Write path (called by the APP as the signed-in user, on submit) ───────────

-- Returns true if this call counted, false if the user had already submitted for this match.
-- The mark insert is the gate: everything after it runs at most once per (user, event), so a retry,
-- a fast double-tap, or a reinstall-and-resubmit is a no-op rather than a double-count.
create or replace function public.predict_record_picks(
  p_season text, p_week int, p_event_id text, p_team text, p_picks jsonb
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rows  int;
  v_close timestamptz;
begin
  if auth.uid() is null then
    raise exception 'predict_record_picks requires an authenticated caller';
  end if;

  -- Late-write guard. Once the proxy has stamped the real close time for this match, refuse any
  -- submission after it: the lineup may already be public, and a pre-summed counter can never be
  -- filtered back. Null (nobody has opened the community view for this match yet) falls through to
  -- the client-side deadline gate in PredictionStore.submit.
  select closes_at into v_close from public.predict_match_submissions
   where season = p_season and week = p_week
     and event_id = p_event_id and team_abbreviation = p_team;
  if v_close is not null and now() >= v_close then
    return false;
  end if;

  -- Shape guards. A prediction is only submittable at 11 filled slots, so anything else is a
  -- malformed or hostile call — refuse it rather than record a distorted aggregate. Distinct slots
  -- also guarantee the (player_id, slot) pairs below are unique, which ON CONFLICT DO UPDATE
  -- requires (it errors if one statement touches the same row twice).
  if jsonb_typeof(p_picks) <> 'array' or jsonb_array_length(p_picks) <> 11 then
    raise exception 'predict_record_picks expects exactly 11 picks';
  end if;
  if (select count(distinct (e->>'slot')) from jsonb_array_elements(p_picks) e) <> 11 then
    raise exception 'predict_record_picks expects 11 distinct slots';
  end if;

  insert into public.predict_submission_marks (user_id, event_id)
  values (auth.uid(), p_event_id)
  on conflict (user_id, event_id) do nothing;

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    return false;                                -- already counted — idempotent no-op
  end if;

  insert into public.predict_pick_counts
    (season, week, event_id, team_abbreviation, player_id, slot, count)
  select p_season, p_week, p_event_id, p_team, (e->>'player_id'), (e->>'slot')::int, 1
  from jsonb_array_elements(p_picks) e
  on conflict (season, week, event_id, team_abbreviation, player_id, slot)
  do update set count = public.predict_pick_counts.count + 1, updated_at = now();

  insert into public.predict_match_submissions
    (season, week, event_id, team_abbreviation, submissions)
  values (p_season, p_week, p_event_id, p_team, 1)
  on conflict (season, week, event_id, team_abbreviation)
  do update set submissions = public.predict_match_submissions.submissions + 1, updated_at = now();

  return true;
end;
$$;

revoke all on function public.predict_record_picks(text, int, text, text, jsonb) from public, anon;
grant execute on function public.predict_record_picks(text, int, text, text, jsonb) to authenticated;

-- ── Close-time stamp (called by the PROXY as service_role) ───────────────────

-- Records the authoritative kickoff − 2h for a match, derived proxy-side from ESPN. Write-once in
-- effect: `coalesce` keeps the first value, so a later call cannot move a deadline that submissions
-- have already been judged against.
create or replace function public.predict_set_close(
  p_season text, p_week int, p_event_id text, p_team text, p_closes_at timestamptz
) returns void
language sql
security definer
set search_path = public
as $$
  insert into public.predict_match_submissions
    (season, week, event_id, team_abbreviation, submissions, closes_at)
  values (p_season, p_week, p_event_id, p_team, 0, p_closes_at)
  on conflict (season, week, event_id, team_abbreviation)
  do update set closes_at = coalesce(public.predict_match_submissions.closes_at, excluded.closes_at);
$$;

revoke all on function public.predict_set_close(text, int, text, text, timestamptz) from public, anon, authenticated;
grant execute on function public.predict_set_close(text, int, text, text, timestamptz) to service_role;

-- ── Read path (called by the PROXY as service_role, after the close) ──────────

-- Split into two functions on purpose. The pre-close "sealed" state needs ONLY the denominator
-- ("312 of 340 fans have locked in"), so it calls the count function and cannot leak per-player data
-- even if the proxy's gate were mis-coded. Defence in depth for a rule the whole feature rests on.
create or replace function public.predict_submission_count(
  p_season text, p_week int, p_event_id text, p_team text
) returns int
language sql
security definer
set search_path = public
as $$
  select coalesce((
    select submissions from public.predict_match_submissions
    where season = p_season and week = p_week
      and event_id = p_event_id and team_abbreviation = p_team), 0);
$$;

create or replace function public.predict_pick_distribution(
  p_season text, p_week int, p_event_id text, p_team text
) returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'submissions', public.predict_submission_count(p_season, p_week, p_event_id, p_team),
    'picks', coalesce((
      select jsonb_agg(jsonb_build_object('playerId', player_id, 'slot', slot, 'count', count))
      from public.predict_pick_counts
      where season = p_season and week = p_week
        and event_id = p_event_id and team_abbreviation = p_team), '[]'::jsonb)
  );
$$;

revoke all on function public.predict_submission_count(text, int, text, text) from public, anon, authenticated;
revoke all on function public.predict_pick_distribution(text, int, text, text) from public, anon, authenticated;
grant execute on function public.predict_submission_count(text, int, text, text) to service_role;
grant execute on function public.predict_pick_distribution(text, int, text, text) to service_role;

-- ── Verifying this migration ─────────────────────────────────────────────────
-- Idempotency is the claim worth testing. As a signed-in user, call predict_record_picks TWICE with
-- the same event id and confirm it returns true then false, and that the counts moved exactly once:
--   select public.predict_record_picks('2026', 21, 'TEST-1', 'WAS',
--     '[{"player_id":"p1","slot":0},{"player_id":"p2","slot":1},{"player_id":"p3","slot":2},
--       {"player_id":"p4","slot":3},{"player_id":"p5","slot":4},{"player_id":"p6","slot":5},
--       {"player_id":"p7","slot":6},{"player_id":"p8","slot":7},{"player_id":"p9","slot":8},
--       {"player_id":"p10","slot":9},{"player_id":"p11","slot":10}]'::jsonb);
--   select * from public.predict_match_submissions where event_id = 'TEST-1';   -- submissions = 1
--   delete from public.predict_pick_counts       where event_id = 'TEST-1';
--   delete from public.predict_match_submissions where event_id = 'TEST-1';
--   delete from public.predict_submission_marks  where event_id = 'TEST-1';
