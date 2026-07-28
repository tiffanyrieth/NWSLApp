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
--   • bracket_votes — pruned by the engine AT NEXT EDITION START (bracket-engine.ts
--     pruneCompletedEditionVotes, via writeEdition), so a finished edition stays fully browsable
--     round-by-round through the between-editions review window; an edition's lifetime isn't
--     calendar-shaped, so age is the wrong knife there.
--   • prediction_scores / bracket_scores / *_stats / fanzone_progress / predict_season_bests — the
--     RECORD BOOK: one tiny row per user, kept forever (season totals, stamped final ranks, restore
--     summaries, personal bests). predict_season_bests in particular MUST outlive the 28-day windows
--     below: it exists precisely because the superlative ladder's thresholds cannot be derived from
--     pruned round data (migration_predict_season_bests.sql).
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

-- Predict community pick aggregate (migration_predict_community.sql). The results screen renders
-- only the current + previous soccer week, so once a match leaves that window nothing can read its
-- distribution — 28 days matches predict_round_scores so the Predict tables age out together.
-- These three are the ONLY growth this feature adds; predict_pick_counts is already flat in user
-- count (squad × slots × matches), so the sweep exists mainly for predict_submission_marks, which
-- is the one per-user-per-match row.
select cron.unschedule('prune_predict_pick_counts')
where exists (select 1 from cron.job where jobname = 'prune_predict_pick_counts');
select cron.schedule(
  'prune_predict_pick_counts',
  '29 6 * * *',
  $$delete from public.predict_pick_counts where updated_at < now() - interval '28 days'$$
);

select cron.unschedule('prune_predict_match_submissions')
where exists (select 1 from cron.job where jobname = 'prune_predict_match_submissions');
select cron.schedule(
  'prune_predict_match_submissions',
  '31 6 * * *',
  $$delete from public.predict_match_submissions where updated_at < now() - interval '28 days'$$
);

-- The dedupe marks. Safe to drop on the same schedule: submit is one-way and the deadline gates the
-- action, so a mark has no reader once its match is weeks past — there is nothing left to dedupe.
select cron.unschedule('prune_predict_submission_marks')
where exists (select 1 from cron.job where jobname = 'prune_predict_submission_marks');
select cron.schedule(
  'prune_predict_submission_marks',
  '33 6 * * *',
  $$delete from public.predict_submission_marks where created_at < now() - interval '28 days'$$
);
