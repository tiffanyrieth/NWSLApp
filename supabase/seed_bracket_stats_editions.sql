-- NWSLApp — Bracket Battle stats-edition LIBRARY seed (launch set).
--
-- Run ONCE in the Supabase SQL editor, AFTER migration_bracket_qualifying.sql (which
-- creates bracket_stats_editions). These are RECIPES, not rosters — each says which
-- position to pull and which stat to seed by; the Worker builds the live player pool
-- from ESPN at generation time. No per-player curation needed, so the full launch set
-- is authored here as data (the creative editions, which DO need researched content,
-- are loaded separately via scripts/load_creative_edition.mjs).
--
-- `on conflict (id) do nothing` → re-running never resets an edition the Worker has
-- already consumed (status flips 'ready' → 'used' when generated). To re-arm a theme for
-- a new season, insert a new row with a new id/season (or update status back to 'ready').
--
-- seeding_stat is descriptive today (the engine seeds by roster-depth as a visibility
-- proxy); it becomes the live ranking key when exact-stat seeding ships (see the bracket
-- plan's researched recipe). position_filter: F | M | D | G | null (all positions).

insert into public.bracket_stats_editions
  (id, theme_label, title, description, position_filter, seeding_stat, status, season)
values
  ('best-forward-2026', 'BEST FORWARD', 'Best Forward · 2026',
   'Goals, assists, the ones who make defenders sweat. Every forward in the league, one bracket — you predict who the crowd sends through.',
   'F', 'goals_assists', 'ready', 2026),

  ('best-goalkeeper-2026', 'BEST GOALKEEPER', 'Best Goalkeeper · 2026',
   'The last line. Shot-stoppers, sweeper-keepers, the ones who win you points nobody notices. The whole league''s keepers — call who advances.',
   'G', 'save_pct', 'ready', 2026),

  ('midfield-engine-2026', 'MIDFIELD ENGINE', 'Midfield Engine · 2026',
   'The ones who run the game — chances created, tackles won, 90 minutes box to box. Every midfielder, drawn into one bracket.',
   'M', 'chances_tackles', 'ready', 2026),

  ('best-defender-2026', 'BEST DEFENDER', 'Best Defender · 2026',
   'The wall. Tackles, interceptions, the last-ditch block that saves the match. The league''s defenders, one bracket — read the room.',
   'D', 'tackles_interceptions', 'ready', 2026),

  ('ironwoman-2026', 'IRONWOMAN', 'Ironwoman · 2026',
   'Who never comes off? Seeded by minutes played — the ones who answer the bell every single week. All positions, one bracket.',
   null, 'minutes', 'ready', 2026)
on conflict (id) do nothing;
