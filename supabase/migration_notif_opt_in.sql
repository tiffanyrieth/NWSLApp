-- Migration: notification_preferences → pure opt-in defaults
--
-- The app is moving to a pure opt-in notification model: every toggle defaults OFF and nothing is
-- auto-enabled (no dark-pattern default-ons; discovery is via the Teams coaching note + the gear icon).
-- This makes the schema's column defaults match — they're mostly cosmetic (the app upserts whole rows and
-- the watcher gates Tier-2 on `<col>=eq.true`), but honest defaults prevent a stray row from being "on".
--
-- The one behavioral line is the `live_activities_enabled` reset: the prior migration added that column
-- `default true`, which grandfathered EVERY existing row into V2 Live Activities. Since it's now a Tier-2
-- opt-in (sign-in-gated, default off), reset existing rows to false so opt-in means opt-in. (Other toggles'
-- existing values are left alone — test users keep their explicit V1 choices.)
-- Idempotent. Run BEFORE archiving the build with the opt-in app + before the watcher's opt-in gate deploys.

alter table public.notification_preferences alter column day_before              set default false;
alter table public.notification_preferences alter column lineup_posted           set default false;
alter table public.notification_preferences alter column kickoff                 set default false;
alter table public.notification_preferences alter column goals                   set default false;
alter table public.notification_preferences alter column halftime                set default false;
alter table public.notification_preferences alter column full_time               set default false;
alter table public.notification_preferences alter column substitutions           set default false;
alter table public.notification_preferences alter column fan_zone_rounds         set default false;
alter table public.notification_preferences alter column player_spotlight        set default false;
alter table public.notification_preferences alter column live_activities_enabled set default false;

-- Un-grandfather the V2 Live Activity opt-in (was default-true).
update public.notification_preferences set live_activities_enabled = false;
