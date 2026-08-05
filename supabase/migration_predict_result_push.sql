-- Migration: post-match "your Predict result is in" push (Change 8)
--
-- Two additions that let the match-watcher send a next-day, opt-in push to users who predicted a match
-- but HAVEN'T opened their result yet:
--
--   1. predict_result_seen — a server-visible "this user viewed this match's result" mark. Until now
--      "seen" was LOCAL-ONLY on device (PredictionStore.seenResultFixtureIDs), so the watcher had no way
--      to skip people who already looked. The app writes one row when the result screen renders; the
--      watcher left-anti-joins it so a viewer is never pushed. Insert-only (once seen, always seen).
--
--   2. notification_preferences.predict_results — the standalone opt-in toggle for this push. OPT-IN
--      (default false), NOT folded into the match-updates bundle ("match ended" and "how YOUR prediction
--      did" are different events). Offered after the user's first submitted prediction.
--
-- Run in the Supabase SQL editor BEFORE the app build that upserts these + the watcher pass deploy —
-- else they reference objects that don't exist. Idempotent.

-- 1. Seen mark (client-written, per-user RLS — the team_alert_preferences idiom; watcher reads it).
create table if not exists public.predict_result_seen (
  user_id  uuid not null references auth.users(id) on delete cascade,   -- account-delete cascades
  event_id text not null,                                               -- ESPN event id (watcher keys on this)
  seen_at  timestamptz default now(),
  primary key (user_id, event_id)                                       -- backs the app's insert-if-absent
);

alter table public.predict_result_seen enable row level security;

-- Insert-only for the owner; no update/delete (a result can't become un-seen). Select granted so the
-- client CAN read its own marks, though today it relies on the local set.
create policy "Users read own result-seen marks"
  on public.predict_result_seen for select using (auth.uid() = user_id);
create policy "Users insert own result-seen marks"
  on public.predict_result_seen for insert with check (auth.uid() = user_id);

-- Grants (42501 gotcha — RLS is not privilege). Client: authenticated only, never anon.
grant select, insert on public.predict_result_seen to authenticated;
-- Worker: the watcher reads it as service_role to drop already-viewed users. Bypassing RLS is NOT
-- table privilege, so this explicit grant is required.
grant select on public.predict_result_seen to service_role;

-- The watcher also reads WHO predicted a match from predict_submission_marks (created in
-- migration_predict_community.sql) as service_role — ensure the grant exists (idempotent).
grant select on public.predict_submission_marks to service_role;

-- Speeds the watcher's "who predicted these events" query (event_id=in.(…prior-day finals…)).
create index if not exists predict_submission_marks_event_idx
  on public.predict_submission_marks (event_id);
create index if not exists predict_result_seen_event_idx
  on public.predict_result_seen (event_id);

-- 2. The opt-in toggle column (default false — mirrors migration_notif_opt_in for a Tier-2 push).
-- No new grant: service_role already has select on notification_preferences (schema.sql).
alter table public.notification_preferences
  add column if not exists predict_results boolean not null default false;
