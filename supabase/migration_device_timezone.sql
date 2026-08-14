-- Migration: per-user local-time for the "Predict results" push (kill the midnight-in-Sydney bug)
--
-- The Predict-results push fired once daily at 14:00 UTC — which is MIDNIGHT in Sydney. NWSL is a
-- worldwide sport (the #1 women's league; fans follow international stars from everywhere), so a fixed
-- UTC hour is the wrong local time for someone. To fire at each fan's own ~10am the watcher needs their
-- timezone, which was stored NOWHERE. Two additions:
--
--   1. device_tokens.timezone — the device's IANA id (e.g. "America/New_York"), written by the app at
--      token registration and refreshed whenever it changes (DST / travel). NULL for un-migrated app
--      builds, which the watcher treats as the legacy 14:00-UTC send — so the rollout is deploy-order-safe.
--
--   2. predict_result_notified — a server-owned "we pushed this user for this fixture" ledger. The old
--      idempotency was a single per-FIXTURE KV marker ("fixture done"), which breaks once the send fans
--      out across 24 hourly local-morning waves (the first wave would strand every later timezone). A
--      per-(event,user) ledger lets each wave send only to not-yet-notified users at their local 10am.
--
-- Run in the Supabase SQL editor BEFORE the watcher deploy that reads these — else it references objects
-- that don't exist. Idempotent.

-- 1. Per-device IANA timezone. Nullable → legacy rows fall back to the 14:00-UTC send in the watcher.
alter table public.device_tokens
  add column if not exists timezone text;
-- No new grant: service_role already has `select` on device_tokens (schema.sql), which covers a new
-- column; `authenticated` already has insert/update for the app's own upsert.

-- 2. Per-user idempotency ledger for the localized push. SERVER-OWNED: the client never reads or writes
-- it (unlike predict_result_seen, which is client-written). RLS on + zero policy = the client sees
-- nothing, which is correct; only the watcher (service_role) touches it.
create table if not exists public.predict_result_notified (
  event_id    text not null,                                             -- ESPN event id
  user_id     uuid not null references auth.users(id) on delete cascade, -- account-delete cascades
  notified_at timestamptz default now(),
  primary key (event_id, user_id)                                        -- backs on-conflict-do-nothing
);

alter table public.predict_result_notified enable row level security;   -- no policy: client has no access

-- Grants (42501 gotcha — RLS is not privilege). Watcher-only: it SELECTs to subtract already-notified
-- users from the funnel and INSERTs to mark them after a send. No authenticated grant (no client access).
grant select, insert on public.predict_result_notified to service_role;

-- Speeds the watcher's per-fixture "who have we already notified" subtraction (event_id=eq.<id>).
create index if not exists predict_result_notified_event_idx
  on public.predict_result_notified (event_id);

-- Retention: a fixture leaves the ~2-day scoreboard window and is never re-processed, so its notified
-- rows have no reader after that. Prune on the same pg_cron schedule as the other Predict dedupe marks
-- (migration_retention_cron.sql) so the ledger stays bounded. Idempotent (unschedule-if-exists).
create extension if not exists pg_cron;
select cron.unschedule('prune_predict_result_notified')
where exists (select 1 from cron.job where jobname = 'prune_predict_result_notified');
select cron.schedule(
  'prune_predict_result_notified',
  '35 6 * * *',   -- daily, 06:35 UTC (off the hour; distinct minute from the sibling prunes)
  $$delete from public.predict_result_notified where notified_at < now() - interval '28 days'$$
);
