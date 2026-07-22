-- Bracket Battle — final rank + field size on the per-edition record book (2026-07-23).
--
-- WHY: "Your Stats" showed a past edition's points/accuracy/streaks but not where you FINISHED —
-- the number that makes history competitive ("Finished #12 of 340"). The engine now stamps both at
-- edition close (bracket-engine.ts `stampFinalRanks`: bracket_scores ranked points-desc, ties to the
-- earlier updated_at) right before older editions' per-user votes are pruned (owner retention rule:
-- ballot boxes live for the active + previous edition; the record book — scores/stats/rank — forever).
--
-- Nullable on purpose: NULL = "closed before rank-stamping existed" (or a still-active edition); the
-- app renders those rows without the rank line rather than inventing one.
--
-- Idempotent: add column if not exists.

alter table public.bracket_user_edition_stats
  add column if not exists final_rank int,
  add column if not exists field_size int;

-- The stats table is already world-readable (standings model) and service-role-writable
-- (migration_bracket_qualifying.sql). But the retention prune introduces a NEW operation: the engine
-- now DELETEs old editions' bracket_votes as service_role. The grants gotcha (CLAUDE.md): the grant
-- must match the OPERATION — a select-only table strands the prune with a silent 42501. Explicit
-- grant, idempotent to re-run:
grant select, delete on public.bracket_votes to service_role;
