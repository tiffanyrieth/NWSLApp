-- Predict the XI: per-match graded results — the reinstall-durability table (2026-08-10).
--
-- WHY: predict.v2.predictions / predict.v2.scores were UserDefaults-only (the 2026-08-03
-- Category-3 "fine to lose" ruling, docs/data-sync.md). A real reinstall then proved the cost:
-- the owner lost her Recent Results + round board, and the board rendering (gated on local
-- state) erased her from her own leaderboard. Owner decision 2026-08-10: graded results are
-- server-durable. ~26 rows/user/season at ~300B — trivial against the 500MB budget at 1k users.
--
-- ⚠️ WRITES HAPPEN ONLY POST-GRADING (match final, lineups long public), so this table cannot
-- leak pre-deadline picks — the predict_record_picks consensus protection is untouched, and the
-- "lineups are never uploaded" rule narrows to "never uploaded BEFORE the deadline".
-- The submitted XI (formation/slots/scoreline guess) IS stored here because the restore path
-- must re-render predicted-vs-actual on the result detail screen.
--
-- ⚠️ NOT MONOTONIC, unlike prediction_scores/predict_round_scores: a regrade (suspended-match
-- self-heal) legitimately REWRITES a row, so the app uses a plain upsert on the PK — do not
-- "fix" this with a GREATEST merge.

create table if not exists public.predict_match_results (
  user_id uuid references auth.users(id) on delete cascade not null default auth.uid(),
  event_id text not null,
  team_abbreviation text not null,
  season text not null default '2026',
  week int,                                  -- FanZoneCadence soccerWeek (null: pre-round-clock grades)
  -- the grade (facts only; the total is derived client-side from PredictionScore's weights,
  -- so a future re-weighting never strands stored totals)
  correct_players int not null default 0,
  correct_positions int not null default 0,
  formation_correct boolean not null default false,
  exact_scoreline boolean not null default false,
  result_correct boolean not null default false,
  perfect_xi boolean not null default false,
  graded_home_score int,                     -- the regrade-staleness stamp (nullable: legacy grades)
  graded_away_score int,
  -- the submitted XI (restores predicted-vs-actual on the result detail)
  formation text not null,
  slots jsonb not null,                      -- {"0": "athleteID", ...} — STRING keys (JSON has no int keys)
  home_score_guess int not null default 0,
  away_score_guess int not null default 0,
  graded_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, event_id, team_abbreviation)
);

alter table public.predict_match_results enable row level security;

-- OWN-ROW ONLY (like predict_season_bests, NOT like the world-readable board tables): the XI +
-- breakdown are personal history; no surface renders another user's row. No display_name column
-- at all — this table is immune to the name-clobber class by construction.
drop policy if exists "Users read own predict results" on public.predict_match_results;
create policy "Users read own predict results"
  on public.predict_match_results for select using (auth.uid() = user_id);
drop policy if exists "Users insert own predict results" on public.predict_match_results;
create policy "Users insert own predict results"
  on public.predict_match_results for insert with check (auth.uid() = user_id);
drop policy if exists "Users update own predict results" on public.predict_match_results;
create policy "Users update own predict results"
  on public.predict_match_results for update using (auth.uid() = user_id);

-- The 42501 gotcha: RLS is not privilege. No anon grant (own-row, signed-in only); no
-- service_role grant (no Worker touches this table).
grant select, insert, update on public.predict_match_results to authenticated;

-- Retention: the current season restores all season; last season's rows age out on a fixed
-- clock (~13 months, so a season row never dies mid-season). Age-based like every other
-- Predict sweep — no season-anchor math in SQL.
select cron.unschedule('prune_predict_match_results')
where exists (select 1 from cron.job where jobname = 'prune_predict_match_results');
select cron.schedule('prune_predict_match_results', '30 4 * * *',
  $$delete from public.predict_match_results where graded_at < now() - interval '400 days'$$);
