-- Migration: notification_preferences.live_activities_enabled (V2 Live Activity opt-out)
--
-- Adds the per-user toggle that lets someone keep V1 push notifications while turning OFF the V2 Live
-- Activity (lock-screen / Dynamic Island live-score card). It's an OPT-OUT: default true, so existing
-- users and new installs keep the feature. The match-watcher reads this alongside
-- team_alert_preferences.alerts_enabled when deciding whether to push-to-start an Activity for a match
-- (startTokensForTeams) — a signed-in user with match alerts on but this OFF gets no Live Activity.
-- Idempotent. RUN THIS BEFORE the build-22 app (which upserts this column) is archived, and before the
-- watcher's startTokensForTeams filter deploys — else those reference a column that doesn't exist.
--
-- No new grant needed: service_role already has `select` on notification_preferences (schema.sql).

alter table public.notification_preferences
  add column if not exists live_activities_enabled boolean not null default true;
