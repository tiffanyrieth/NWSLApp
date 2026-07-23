-- migration_seed_grants.sql — TEMPORARY service_role grants for the pre-launch seed population.
--
-- ⚠️ TEMP (2026-07-22). WHAT: lets the service-role key write the Fan Zone score tables.
--    WHY: `nwslapp-proxy/scripts/seed_test_fans.mjs` populates them so the crowd-shaped surfaces
--    (leaderboards, community splits, Superfan tier) can be designed against before launch.
--    WHEN REMOVED: after `--purge`, by running the REVOKE block at the bottom of this file.
--
-- These tables are written by the APP as the signed-in user (RLS: auth.uid() = user_id), so they
-- were only ever granted to `authenticated`. No Worker had touched them — hence no service_role
-- grant, hence 42501 on the first seed write. This is the documented gotcha: RLS BYPASS IS NOT A
-- TABLE PRIVILEGE (CLAUDE.md; project memory supabase_rls_needs_grants). The same omission has now
-- bitten on profiles (SIWA), device_tokens (watcher prune) and here.
--
-- Scope is deliberately minimal: SELECT/INSERT/UPDATE only. No DELETE — teardown works by deleting
-- the auth.users rows and letting `on delete cascade` do it, so the seeder never needs to delete
-- from these tables directly, and the key stays unable to wipe a real user's scores.

grant select, insert, update on
  public.prediction_scores,
  public.predict_round_scores,
  public.superfan_scores
to service_role;

-- quiz_answers already has SELECT (the community-results RPCs read it); seeding needs to write too.
grant insert, update on public.quiz_answers to service_role;


-- ── TEARDOWN — run this AFTER `node scripts/seed_test_fans.mjs --purge` ──────────────────────
-- Returns the service-role key to exactly the reach it had before seeding. Safe to run even if the
-- grants were never applied. Kept commented so this file stays a valid forward migration.
--
-- revoke insert, update on public.quiz_answers from service_role;
-- revoke select, insert, update on
--   public.prediction_scores,
--   public.predict_round_scores,
--   public.superfan_scores
-- from service_role;
