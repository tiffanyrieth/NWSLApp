-- migration_account_deletion_cascade.sql
--
-- Adds ON DELETE CASCADE to every per-user foreign key that referenced
-- auth.users(id) WITHOUT it, so deleting an auth user (the account-deletion proxy
-- route's `DELETE /auth/v1/admin/users/{id}`) removes ALL of that user's rows in one
-- transaction instead of being blocked by a restrict FK.
--
-- Five tables lacked the cascade: profiles, follows, device_tokens,
-- notification_preferences, bracket_votes. (team_alert_preferences,
-- competition_follows, bracket_scores, prediction_scores, trivia_scores already had it.)
--
-- Idempotent-ish: re-running drops the constraint we just (re)created and re-adds it.
-- Constraint names are Postgres's defaults (`<table>_<column>_fkey`). Apply once in the
-- Supabase SQL editor; schema.sql is updated to match for fresh provisioning.

begin;

alter table public.profiles
  drop constraint profiles_id_fkey,
  add constraint profiles_id_fkey
    foreign key (id) references auth.users(id) on delete cascade;

alter table public.follows
  drop constraint follows_user_id_fkey,
  add constraint follows_user_id_fkey
    foreign key (user_id) references auth.users(id) on delete cascade;

alter table public.device_tokens
  drop constraint device_tokens_user_id_fkey,
  add constraint device_tokens_user_id_fkey
    foreign key (user_id) references auth.users(id) on delete cascade;

alter table public.notification_preferences
  drop constraint notification_preferences_user_id_fkey,
  add constraint notification_preferences_user_id_fkey
    foreign key (user_id) references auth.users(id) on delete cascade;

alter table public.bracket_votes
  drop constraint bracket_votes_user_id_fkey,
  add constraint bracket_votes_user_id_fkey
    foreign key (user_id) references auth.users(id) on delete cascade;

commit;
