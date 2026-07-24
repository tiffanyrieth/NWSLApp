-- ═══════════════════════════════════════════════════════════════════════════
-- Predict the XI — rank the leaderboard by AVERAGE points per scored match
-- (Fan Zone comp-arena, Batch 3, 2026-07-24)
-- ═══════════════════════════════════════════════════════════════════════════
-- The old board ranked by cumulative `points`, which inflates to four digits by
-- mid-season and can't be compared across players who've played a different number
-- of matches (500 pts over 20 matches is WORSE than 400 over 6). We now rank by the
-- average, which stays in the 0–88 per-match range forever. Same principle as a
-- batting average.
--
-- Two additive columns (the app writes all three: points, matches, avg_points):
--   • matches     — how many of the user's predictions for this (team, season) have
--                   been SCORED. The client already tracks this locally
--                   (PredictionStore.scoredMatchCount) but never persisted it server-side.
--   • avg_points  — points / matches, stored (not computed) so PostgREST can ORDER BY it
--                   and the rank COUNT (avg_points > mine) works with no rows transferred,
--                   exactly like the old points-based rank. 0 when matches = 0.
--
-- Idempotent + additive: existing rows default to matches=0 / avg_points=0 and rank
-- last until their owner's next client sync writes the real values. (Pre-launch the
-- only rows are seed + test data; the seeder now writes all three — see
-- nwslapp-proxy/scripts/seed_test_fans.mjs.)

alter table public.prediction_scores
  add column if not exists matches integer not null default 0;
alter table public.prediction_scores
  add column if not exists avg_points double precision not null default 0;

-- Backs both the ORDER BY avg_points desc (top-N board) and the rank COUNT
-- (avg_points > x), team+season scoped.
create index if not exists prediction_scores_avg_idx
  on public.prediction_scores (team_abbreviation, season, avg_points desc);

-- No new grants/RLS needed: the columns live on an already-granted, already-RLS'd
-- table (writes stay owner-scoped by the existing "Users update own prediction score"
-- policy; reads stay public). The `matches`/`avg_points` values are written by the
-- same owner-scoped upsert as `points`.
