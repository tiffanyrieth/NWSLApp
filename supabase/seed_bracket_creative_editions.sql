-- NWSLApp — Bracket Battle creative-edition LIBRARY seed (launch set).
--
-- Run ONCE in the Supabase SQL editor, AFTER migration_bracket_qualifying.sql (which
-- drops the old per-player `entries` column). Creative editions are now THEME-ONLY: the
-- Worker pulls the whole-league pool from ESPN automatically (all positions, seeded by
-- the same heuristic as stats editions), so a creative edition is just a label + title +
-- description. The matchup cards show name/jersey/team; the theme is the context.
--
-- These are the app's own editorial themes (no per-player claims), so the launch set is
-- authored here as data — no content research needed to go live. The Worker rotates
-- creative ↔ stats, picking the next `ready` row. `on conflict do nothing` → re-running
-- never re-arms an edition the Worker has already used.
--
-- Recommended FIRST drop: "Who Would Win a Stare-Down?" — fun, personality-driven, and
-- now launchable with zero curation. To add a one-off theme later, use
-- scripts/load_creative_edition.mjs (the only manual input is the theme).

insert into public.bracket_creative_editions
  (id, theme_label, title, description, status, season)
values
  ('who-wins-a-stare-down-2026', 'STARE-DOWN', 'Who Would Win a Stare-Down? · 2026',
   'No ball, no whistle — just two players locked in until someone blinks. The whole league, one bracket. You''re not picking who you like — you''re predicting who the crowd thinks never breaks.',
   'ready', 2026),

  ('best-celebration-2026', 'BEST CELEBRATION', 'Best Goal Celebration · 2026',
   'Forget the goals — we''re here for what happens after. Every celebration in the league, one bracket. Vote who the crowd sends through.',
   'ready', 2026),

  ('best-walkout-vibes-2026', 'WALKOUT VIBES', 'Best Walkout Energy · 2026',
   'Tunnel to pitch — who brings it? The whole league, drawn into one bracket. Predict who the crowd crowns.',
   'ready', 2026),

  ('most-likely-to-coach-2026', 'FUTURE COACH', 'Most Likely to Coach in 10 Years · 2026',
   'The tacticians, the organizers, the ones already running the back line. One bracket, the whole league — who does the crowd see on the sideline someday?',
   'ready', 2026)
on conflict (id) do nothing;
