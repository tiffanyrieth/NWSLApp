-- Predict the XI — season high-water marks (2026-07-28, results-redesign handoff Part 4a.5).
--
-- The superlative slot's top rungs ("Your best match of the season", "Your best round of the
-- season") compare against the user's own season history. Those thresholds CANNOT be derived from
-- predict_round_scores, which pg_cron prunes at 28 days — so they are carried here as monotonic
-- marks instead. Record book: one tiny row per user per season, never pruned.
--
-- ⚠️ BOTH MARKS COUNT STARTERS, NOT POINTS. Handoff §4.3 is explicit: the superlative ladder reads
-- starters-called only, never points. "8 of 11" is the sentence a fan says out loud; points are the
-- accounting underneath it.
--
-- ⚠️ WHY ITS OWN TABLE and not columns on prediction_scores: that row is keyed
-- (user_id, team_abbreviation, season) — PER CLUB — but a ROUND total aggregates across every club
-- the user follows (handoff §2.5: "Points aggregate… Ranks do not"). A cross-club number cannot live
-- on a per-club row. Keyed (user_id, season) here, so it holds either shape.
--
-- ⚠️ WHY SECURITY INVOKER: the merge must be atomic (a read-then-write from the client races itself
-- across two devices — docs/roadmap.md already flags that exact bug against upsertScore), but it must
-- NOT bypass RLS. Invoker keeps auth.uid() as the caller and leaves the policies in force, so a user
-- can only ever raise their OWN row, while GREATEST guarantees a stale or wiped device can never
-- lower a mark (logic gate #5, the same monotonic stance as SuperfanCounts.merged).
--
-- Run in the Supabase SQL editor. Idempotent (create if not exists / or replace).

create table if not exists public.predict_season_bests (
  user_id             uuid references auth.users(id) on delete cascade not null default auth.uid(),
  season              text not null default '2026',
  best_match_starters int  not null default 0,   -- most correct starters in a single match
  best_round_starters int  not null default 0,   -- most correct starters across one soccer week
  updated_at          timestamptz not null default now(),
  primary key (user_id, season)
);

alter table public.predict_season_bests enable row level security;

-- Own-row only. Unlike the leaderboard tables there is no public read: a personal best is not a
-- ranked, comparable number, so nothing outside the user's own app needs it.
-- ⚠️ `create policy` has NO `if not exists` in Postgres, so a bare create makes the whole file
-- non-idempotent — re-running it aborts with 42710 and every statement AFTER the failure (here, the
-- grants and the merge function) silently never applies. Drop-then-create, matching
-- migration_superfan_scores.sql. (Learned the hard way on 2026-07-28: this file's header claimed
-- idempotency it didn't have, and a re-run to pick up the revoke below failed on the first policy.)
drop policy if exists "Users read own predict bests" on public.predict_season_bests;
create policy "Users read own predict bests"
  on public.predict_season_bests for select using (auth.uid() = user_id);
drop policy if exists "Users insert own predict bests" on public.predict_season_bests;
create policy "Users insert own predict bests"
  on public.predict_season_bests for insert with check (auth.uid() = user_id);
drop policy if exists "Users update own predict bests" on public.predict_season_bests;
create policy "Users update own predict bests"
  on public.predict_season_bests for update using (auth.uid() = user_id);

-- The standing grant rule: RLS is not privilege (a missing grant 42501s a signed-in query).
grant select, insert, update on public.predict_season_bests to authenticated;

-- Atomic monotonic merge, one round trip. Passing 0 (or null) for either mark leaves it untouched.
create or replace function public.predict_merge_bests(
  p_season text, p_match int, p_round int
) returns void
language sql
security invoker
set search_path = public
as $$
  insert into public.predict_season_bests
    (user_id, season, best_match_starters, best_round_starters, updated_at)
  values (auth.uid(), p_season, greatest(coalesce(p_match, 0), 0), greatest(coalesce(p_round, 0), 0), now())
  on conflict (user_id, season) do update set
    best_match_starters = greatest(public.predict_season_bests.best_match_starters,
                                   excluded.best_match_starters),
    best_round_starters = greatest(public.predict_season_bests.best_round_starters,
                                   excluded.best_round_starters),
    updated_at = now();
$$;

-- ⚠️ REVOKE FIRST. Postgres grants EXECUTE on a new function to PUBLIC by default, so a bare
-- `grant … to authenticated` leaves anon able to call it too. Today that's harmless — this function
-- is SECURITY INVOKER, so anon is stopped at the table grant and RLS anyway (verified 2026-07-28:
-- an anon call fails with "permission denied for table predict_season_bests", not a write). But it
-- is the standing grant rule's exact blind spot: the day someone changes this to SECURITY DEFINER
-- for an atomicity reason, that default PUBLIC grant silently becomes a live unauthenticated write
-- path. Revoke explicitly so the function's reach never depends on what body it happens to have.
revoke all on function public.predict_merge_bests(text, int, int) from public, anon;
grant execute on function public.predict_merge_bests(text, int, int) to authenticated;

-- ⚠️ ORDERING RULE FOR CALLERS: evaluate the superlative ladder BEFORE merging this match's result.
-- Merging first makes every match its own "season best" and the praise becomes worthless — which is
-- precisely what handoff §3.2 says the ladder's floor exists to prevent.
