-- Anonymous Level-3 usage analytics: daily rollup counters (2026-07-16 design, built 2026-07-17).
--
-- One row per (day, event, param) with an additive count. The PROXY is the only writer
-- (service_role via the increment_counters RPC); clients never touch this table — the app
-- batches anonymous counts per session and POSTs them to the proxy's /analytics route.
-- NO identifiers anywhere: no user_id, no device_id, no session_id, no IP, no timestamp
-- finer than a day. App Store label: Data Not Linked to You (Usage Data / Diagnostics).
--
-- Events (whitelisted proxy-side): session_start (param = app version), session_os
-- (param = iOS major.minor), tab_opened (home/schedule/standings/teams/feed),
-- fanzone_game_opened (predict/bracket/trivia/knowher), feed_item_tapped (no param),
-- feed_chip_tapped (all/reporters/players/clubs).
--
-- Run in the Supabase SQL editor. Idempotent (create if not exists / or replace).

create table if not exists public.analytics_counters (
  day   date   not null default current_date,
  event text   not null,
  param text   not null default '',      -- '' for paramless events; NOT NULL so the PK dedupes
  count bigint not null default 0,
  primary key (day, event, param)
);

-- RLS on with NO client policies: anon/authenticated cannot read or write this table at all.
-- The proxy's SECURITY DEFINER function below is the only write path; the owner reads via the
-- Supabase dashboard (which uses the service role).
alter table public.analytics_counters enable row level security;

-- Atomic set-based increment: one call folds a whole batch, adding to existing counts.
-- SECURITY DEFINER so it bypasses RLS; execute granted to service_role ONLY (the standing
-- grant rule: bypassing RLS is not table privilege — and here even authenticated gets nothing).
create or replace function public.increment_counters(p_events jsonb)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.analytics_counters (day, event, param, count)
  select current_date, (e->>'event'), coalesce(e->>'param', ''), (e->>'n')::bigint
  from jsonb_array_elements(p_events) e
  on conflict (day, event, param) do update
    set count = public.analytics_counters.count + excluded.count;
$$;

revoke all on function public.increment_counters(jsonb) from public, anon, authenticated;
grant execute on function public.increment_counters(jsonb) to service_role;

-- Owner's starter queries (run in the dashboard):
--   Build distribution (who's on what version):
--     select day, param as version, count from analytics_counters
--       where event = 'session_start' order by day desc, count desc;
--   Tab popularity, last 30 days:
--     select param as tab, sum(count) from analytics_counters
--       where event = 'tab_opened' and day > current_date - 30 group by param order by 2 desc;
--   Fan Zone game opens, last 30 days:
--     select param as game, sum(count) from analytics_counters
--       where event = 'fanzone_game_opened' and day > current_date - 30 group by param order by 2 desc;
