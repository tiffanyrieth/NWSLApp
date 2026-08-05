-- Migration: Superfan economy rebuild (2026-08-04) — per-channel ENGAGEMENT momentum.
--
-- The rebuilt economy (docs/fan-zone.md, SuperfanScoring.swift) splits each 0–25 channel into
-- 20 accuracy + 5 engagement. Engagement is a FORGIVING participation "momentum" (0–5) per channel —
-- reward showing up, never a reset-on-miss penalty. These are raw inputs (source of truth); the score
-- stays derived in code, so the economy re-tunes without a further migration.
--
-- Replaces the single `trivia_streak` column (which drove the old Trivia-only streak bonus). We ADD the
-- four momentum columns and leave `trivia_streak` in place (now unused/deprecated) so a deployed app on
-- the old build keeps working during rollout; a later cleanup migration can drop it.
--
-- Run in the Supabase SQL editor. Idempotent.

alter table public.superfan_scores
  add column if not exists predict_momentum int not null default 0,
  add column if not exists bracket_momentum int not null default 0,
  add column if not exists khg_momentum     int not null default 0,
  add column if not exists trivia_momentum  int not null default 0;

-- (Grants/RLS are inherited from the base table — superfan_scores is world-readable, user-writes-own;
--  no new policy needed for added columns.)
