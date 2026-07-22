-- Fan Zone retention — pg_cron pruning (2026-07-23).
--
-- OWNER RULE: quiz/round data lives for the CURRENT + PREVIOUS round only; older detail is pruned.
-- The app can't render anything older by design (stores keep two rounds; landing pages show "this
-- round" + "last round"), so the database holding more is storage with no reader — and quiz_answers
-- was the one table flagged unbounded in docs/stress-testing.md (~85 MB/season at 1k engaged users).
--
-- WHY pg_cron (inside Supabase, free tier) and not a Worker: Cloudflare requests are the metered
-- resource (100k/day cap), Supabase API calls are unlimited but a cron INSIDE Postgres uses neither.
-- WHY age-based (not round-key math): a 2-week round means current+previous spans ≤ 4 weeks of
-- writes; a fixed age window implements the rule within a few days' slack, with no round-arithmetic
-- duplicated into SQL (the anchor lives in the app + proxy; SQL never needs to know it) and full
-- robustness to key-format changes (it also silently clears the legacy day-keyed Trivia editions).
--
-- NOT covered here, by design:
--   • bracket_votes — pruned by the engine AT EDITION CLOSE (bracket-engine.ts pruneOldEditionVotes);
--     an edition's lifetime isn't calendar-shaped, so age is the wrong knife there.
--   • prediction_scores / bracket_scores / *_stats / fanzone_progress — the RECORD BOOK: one tiny
--     row per user, kept forever (season totals, stamped final ranks, restore summaries).
--
-- Idempotent: unschedule-if-exists before each schedule, so re-running replaces rather than stacks.

create extension if not exists pg_cron;

-- quiz_answers (Trivia + Know Her Game per-question answers): rounds are 2 weeks; current + previous
-- ≤ 28 days of life, 35 gives margin for a late player reviewing "last round" on its final day.
select cron.unschedule('prune_quiz_answers')
where exists (select 1 from cron.job where jobname = 'prune_quiz_answers');
select cron.schedule(
  'prune_quiz_answers',
  '17 6 * * *',   -- daily, 06:17 UTC (off the hour to avoid thundering-herd defaults)
  $$delete from public.quiz_answers where created_at < now() - interval '35 days'$$
);

-- predict_round_scores (per-soccer-week round boards): a week's rows stop updating once its fixtures
-- are scored; 28 days retains the current + previous round comfortably (the boards only ever show
-- those), then the rows age out. Season standings live in prediction_scores, untouched.
select cron.unschedule('prune_predict_round_scores')
where exists (select 1 from cron.job where jobname = 'prune_predict_round_scores');
select cron.schedule(
  'prune_predict_round_scores',
  '23 6 * * *',
  $$delete from public.predict_round_scores where updated_at < now() - interval '28 days'$$
);
