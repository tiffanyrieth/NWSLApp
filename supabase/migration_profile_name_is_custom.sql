-- Migration: profiles.name_is_custom (display-name confirmation flag)
--
-- Adds the column that distinguishes a CONFIRMED display name from a merely-present one
-- (e.g. an Apple-supplied name). The Fan Zone gate (`AuthStore.hasChosenName`) requires it
-- to be true before a name reaches a public leaderboard, so an unconfirmed Apple name can't
-- auto-pass the gate. Idempotent — safe to run on an existing project.
--
-- NO BACKFILL (deliberate): the column defaults false for every existing row, so each current
-- tester confirms their name once at their next ranked action (a single prefilled tap). This
-- gives the clean guarantee "no name reaches a leaderboard unconfirmed, full stop" and avoids
-- marking an existing *unconfirmed* Apple name as chosen — the exact case this flag prevents.

alter table public.profiles
  add column if not exists name_is_custom boolean not null default false;
