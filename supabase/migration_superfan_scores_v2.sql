-- ═══════════════════════════════════════════════════════════════════════════
-- Superfan Zone v2 — the 0–100 accuracy economy (Fan Zone Competitive Redesign, PR1)
-- ═══════════════════════════════════════════════════════════════════════════
-- Redefines `superfan_scores.total` from an opaque additive sum (trivia correct + predict points +
-- bracket points + know-her points, all in mismatched units) to a NORMALIZED 0–100 score: each of the
-- four games contributes accuracy × 25. See docs/fan-zone.md §Scoring.
--
-- Why per-game COUNT columns and not just the accuracy: accuracy legitimately moves DOWN (a bad game
-- lowers it), so the old `max(total)` monotonic clamp is wrong for it. Instead we persist the raw
-- correct/attempted COUNTS per game — those only ever GROW — and derive accuracy = correct/attempted and
-- contribution = accuracy × 25 in code. `GREATEST`-merging the counts on write makes the score
-- reinstall-safe (a wiped device can't lower the server) WITHOUT freezing an accuracy that should fall.
-- It also means Trivia/KHG season accuracy survives the `quiz_answers` 35-day prune (those rows age out;
-- these running totals don't).
--
-- Idempotent: `add column if not exists` throughout. Preserves the existing RLS + grants (user writes
-- own row, world-readable — no service_role; the app reads/writes directly). Model = migration_superfan_scores.sql.

alter table public.superfan_scores
  -- Per-game monotonic counts (the source of truth; accuracy + contribution are derived in code).
  add column if not exists predict_correct  int not null default 0,   -- Σ correct XI player slots
  add column if not exists predict_total    int not null default 0,   -- Σ 11 × scored matches
  add column if not exists bracket_correct  int not null default 0,   -- Σ correct picks across editions
  add column if not exists bracket_total    int not null default 0,   -- Σ edition-structure matchups (tallied rounds; missed = zeros)
  add column if not exists khg_correct      int not null default 0,   -- Σ correct Know Her Game answers
  add column if not exists khg_total        int not null default 0,   -- Σ attempted Know Her Game questions
  add column if not exists trivia_correct   int not null default 0,   -- Σ correct Trivia answers
  add column if not exists trivia_total     int not null default 0,   -- Σ attempted Trivia answers
  add column if not exists trivia_streak    int not null default 0,   -- consecutive Trivia rounds (for the +1/round, cap +10 bonus)
  -- The absolute tier (Fan/Rising/All-Star/MVP) persisted for read convenience + the carousel card.
  -- Source of truth is still `total`'s band; this is a denormalized cache the recalc writes.
  add column if not exists tier text;

-- NOTE: `total` is REUSED as the 0–100 score (no rename — keeps the existing upsert/onConflict + reads
-- working). `games_played` is unchanged (still the ≥1 "has this game contributed" count for gates).
-- Existing rows keep their old additive `total` until the app next recalculates them (the counts start
-- at 0 and are back-filled from local state on the next sync), so a stale big number can briefly show;
-- the first Superfan-screen open per user overwrites it with the real 0–100 value.
