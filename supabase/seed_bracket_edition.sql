-- NWSLApp — Bracket Battle seed: one real "Top Forward" edition (0.3.9)
--
-- Run AFTER schema.sql (the bracket_* tables must exist), in the Supabase SQL
-- editor (it runs as the service role, which is allowed to write these global
-- tables — RLS blocks authenticated/anon from inserting editions/matchups).
--
-- This is the TEMP one-time stand-in for the deferred proxy edition-generator
-- (ESPN rosters+stats → 64 seeded + Haiku creative themes). It seeds a real,
-- playable 16-forward "Round of 16" edition so the live vote pipeline works
-- end-to-end now; the Worker will later generate full 64-pools and rotate them.
--
-- entrant_id here is a synthetic "tf{seed}" — the generator will use real ESPN
-- athlete ids. Votes reference entrant_id, so it's self-consistent within the
-- edition. Re-running: delete the edition first (cascades to entrants/matchups):
--   delete from public.bracket_editions where id = 'top-forward-2026';

-- ── Edition ──────────────────────────────────────────────────────────────────
insert into public.bracket_editions
  (id, theme_label, title, emoji, type, current_round, round_opened_at, round_closes_at, is_active, fan_count)
values
  ('top-forward-2026', 'TOP FORWARD', 'Best Forward · 2026', '⚽', 'statsSeeded',
   16, now(), now() + interval '2 days', true, 0);

-- ── Entrants (seed order, strongest first) ───────────────────────────────────
insert into public.bracket_entrants (edition_id, entrant_id, seed, player_name, jersey_number, team_abbreviation) values
  ('top-forward-2026', 'tf1',  1,  'Rodman',   2,  'WAS'),
  ('top-forward-2026', 'tf2',  2,  'Banda',    9,  'ORL'),
  ('top-forward-2026', 'tf3',  3,  'Chawinga', 17, 'KC'),
  ('top-forward-2026', 'tf4',  4,  'Swanson',  7,  'CHI'),
  ('top-forward-2026', 'tf5',  5,  'Marta',    10, 'ORL'),
  ('top-forward-2026', 'tf6',  6,  'Hatch',    11, 'WAS'),
  ('top-forward-2026', 'tf7',  7,  'Macario',  28, 'SD'),
  ('top-forward-2026', 'tf8',  8,  'Shaw',     12, 'NJ'),
  ('top-forward-2026', 'tf9',  9,  'Thompson', 7,  'LA'),
  ('top-forward-2026', 'tf10', 10, 'Sanchez',  8,  'NC'),
  ('top-forward-2026', 'tf11', 11, 'Wilson',   19, 'POR'),
  ('top-forward-2026', 'tf12', 12, 'Moultrie', 13, 'POR'),
  ('top-forward-2026', 'tf13', 13, 'Bethune',  6,  'KC'),
  ('top-forward-2026', 'tf14', 14, 'LaBonta',  15, 'KC'),
  ('top-forward-2026', 'tf15', 15, 'Fox',      3,  'NC'),
  ('top-forward-2026', 'tf16', 16, 'Bugg',     14, 'DEN');

-- ── Round of 16 matchups (1v16, 2v15, … 8v9; +12 pts each) ───────────────────
insert into public.bracket_matchups (id, edition_id, round, slot, entrant_a_id, entrant_b_id, points) values
  ('top-forward-2026-r16-s0', 'top-forward-2026', 16, 0, 'tf1', 'tf16', 12),
  ('top-forward-2026-r16-s1', 'top-forward-2026', 16, 1, 'tf2', 'tf15', 12),
  ('top-forward-2026-r16-s2', 'top-forward-2026', 16, 2, 'tf3', 'tf14', 12),
  ('top-forward-2026-r16-s3', 'top-forward-2026', 16, 3, 'tf4', 'tf13', 12),
  ('top-forward-2026-r16-s4', 'top-forward-2026', 16, 4, 'tf5', 'tf12', 12),
  ('top-forward-2026-r16-s5', 'top-forward-2026', 16, 5, 'tf6', 'tf11', 12),
  ('top-forward-2026-r16-s6', 'top-forward-2026', 16, 6, 'tf7', 'tf10', 12),
  ('top-forward-2026-r16-s7', 'top-forward-2026', 16, 7, 'tf8', 'tf9',  12);

-- After voting closes, the tally step (deferred Worker / manual) resolves each
-- matchup and advances the round, e.g.:
--   update public.bracket_matchups set community_winner_id='tf1', split_a_percent=78
--     where id='top-forward-2026-r16-s0';
--   update public.bracket_editions set current_round=8 where id='top-forward-2026';
--   -- then insert the Quarterfinal matchups from the winners, and upsert
--   -- public.bracket_scores per user from their votes × resolved winners.
