-- Migration: profiles.apple_refresh_token (Sign in with Apple revocation)
--
-- Adds the column where the proxy stores the user's Apple `refresh_token`. App Store
-- guideline 5.1.1(v) requires REVOKING the SIWA credential on account deletion (not just
-- deleting our own data) — otherwise Apple keeps treating the user as linked and a
-- re-signup returns "existing user". The proxy exchanges Apple's authorizationCode for
-- this long-lived token at sign-in (POST /auth/apple-token-exchange) and reads it back at
-- account deletion to call Apple's /auth/revoke. Idempotent — safe to re-run.
--
-- NO BACKFILL (deliberate): existing testers have no stored token until their NEXT sign-in,
-- at which point the exchange runs and the token lands here. Until then, deletion works
-- exactly as today (Supabase cascade only) — the revoke step is simply skipped.

alter table public.profiles
  add column if not exists apple_refresh_token text;

-- Grant for the Worker (service_role). The proxy UPSERTS this column at sign-in and READS
-- it at deletion as service_role. service_role bypasses RLS but that is NOT a substitute
-- for table privilege, and this project's default privileges don't cover service_role (see
-- project memory supabase_rls_needs_grants / the live_activity + bracket_v2 migrations) —
-- without this grant the very first service_role read/write 42501s. Insert is included
-- because the proxy upserts (a sign-in/exchange race could otherwise hit a missing row).
grant select, insert, update on public.profiles to service_role;
