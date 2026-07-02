-- Migration: quiz_answers + aggregate functions (quiz community results)
--
-- Backs the NYT-style "how everyone did" screen shared by NWSL Trivia + Know Her Game
-- (docs/know-her-game.md §11/§11b) — the leaderboard REPLACEMENT for the quiz-style games.
-- Trivia today is local + a single trivia_scores.best_streak scalar; NO per-question data
-- exists, so this is fully net-new. Run once in the Supabase SQL editor on the live project.
-- Idempotent-ish: `create table` errors if it already exists (skip to the grants); the
-- functions use `create or replace`.
--
-- COST-SAFE (the Swifties-tour lesson): raw answers are OWNER-ONLY (RLS). Only AGGREGATE
-- distributions leave the server — via the SECURITY DEFINER functions below, called by the
-- proxy as service_role and served from its EDGE CACHE (never per-view live aggregation, never
-- KV writes — the free tier's scarce limit is 1,000 KV writes/day).

create table if not exists public.quiz_answers (
  user_id uuid references auth.users(id) on delete cascade not null default auth.uid(),
  game text not null,                    -- 'trivia' | 'knowher'
  edition_key text not null,             -- 'YYYY-MM-DD' (Trivia) | '{weekKey}-{team}-{athleteId}' (Know Her)
  question_id text not null,
  selected_index int not null,
  is_correct boolean not null,
  season text not null default '2026',
  created_at timestamptz default now(),
  primary key (user_id, game, edition_key, question_id)  -- idempotent upsert; replay can't inflate
);

alter table public.quiz_answers enable row level security;

-- Owner-only (no cross-user select — unlike the world-readable *_scores standings tables).
create policy "Users read own quiz answers"
  on public.quiz_answers for select using (auth.uid() = user_id);
create policy "Users insert own quiz answers"
  on public.quiz_answers for insert with check (auth.uid() = user_id);
create policy "Users update own quiz answers"
  on public.quiz_answers for update using (auth.uid() = user_id);

-- Grants (the 42501 gotcha — RLS does not imply privilege). authenticated writes its own rows;
-- service_role (proxy aggregation) needs the explicit grant even though it bypasses RLS.
grant select, insert, update on public.quiz_answers to authenticated;
grant select on public.quiz_answers to service_role;

-- ── Aggregate functions (SECURITY DEFINER — return ONLY distributions) ────────────────────
create or replace function public.quiz_distribution(p_game text, p_edition_key text)
returns table (question_id text, selected_index int, is_correct boolean, cnt bigint)
language sql
security definer
set search_path = public
as $$
  select question_id, selected_index, is_correct, count(*)::bigint
  from public.quiz_answers
  where game = p_game and edition_key = p_edition_key
  group by question_id, selected_index, is_correct;
$$;

create or replace function public.quiz_summary(p_game text, p_edition_key text)
returns table (responders bigint, avg_correct numeric)
language sql
security definer
set search_path = public
as $$
  select count(distinct user_id)::bigint,
         (count(*) filter (where is_correct))::numeric / nullif(count(distinct user_id), 0)
  from public.quiz_answers
  where game = p_game and edition_key = p_edition_key;
$$;

grant execute on function public.quiz_distribution(text, text) to service_role;
grant execute on function public.quiz_summary(text, text)      to service_role;
