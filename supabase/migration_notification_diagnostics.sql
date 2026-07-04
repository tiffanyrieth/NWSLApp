-- notification_diagnostics — a device-keyed, append-only breadcrumb log of the notification
-- TOKEN-REGISTRATION chain, so a failed registration is diagnosable after the fact instead of
-- silent. Each row is one step ("permission", "register-called", "didRegister", "device-upsert",
-- "push-to-start-rx", …) with a status (ok/skip/fail) + detail. Query after a live game:
--
--   select created_at, step, status, detail from public.notification_diagnostics
--   where device_id = '<uuid>' order by created_at;
--
-- DISPOSABLE DEBUG SCAFFOLDING: this table + the app-side NotifTrace writer exist to pinpoint the
-- current "empty device_tokens" break. Once the pipeline is proven solid it can be dropped
-- (drop table public.notification_diagnostics; and remove the NotifTrace call sites). Not permanent
-- plumbing.
--
-- The app buffers breadcrumbs on-device (keyed by the Keychain-stable device_id) and flushes them
-- ONLY when a Supabase session exists, stamping user_id = the signed-in user. So every insert is
-- authenticated (auth.uid() = user_id) — pre-sign-in steps are captured locally and uploaded with
-- their real timestamps once signed in. No anon writes.

create table if not exists public.notification_diagnostics (
  id         uuid default gen_random_uuid() primary key,
  user_id    uuid references auth.users(id) on delete cascade not null,
  device_id  text not null,          -- Keychain-stable per-device UUID (DeviceIdentity.swift)
  step       text not null,          -- e.g. "launch", "register-called", "didRegister", "device-upsert", "push-to-start-rx"
  status     text not null,          -- "ok" | "skip" | "fail"
  detail     text,                   -- freeform (token prefix, error code, authorizationStatus, etc. — NO full token)
  app_build  text,                   -- "0.4.3 (24)"
  os         text,                   -- "iOS 26.4.1"
  occurred_at timestamptz not null,  -- when the step happened on-device (may predate the flush)
  created_at  timestamptz not null default now()
);

create index if not exists notification_diagnostics_device_time
  on public.notification_diagnostics (device_id, occurred_at);
create index if not exists notification_diagnostics_user_time
  on public.notification_diagnostics (user_id, occurred_at);

-- RLS: a signed-in user may only append rows for themselves (append-only log — no read/update/delete
-- for the client; the owner reads via the SQL editor as postgres/service_role, which bypasses RLS).
alter table public.notification_diagnostics enable row level security;

create policy "Users can insert own diagnostics"
  on public.notification_diagnostics for insert with check (auth.uid() = user_id);

-- GRANT is required IN ADDITION to RLS (bypassing RLS is not table privilege). Insert only for the
-- app; service_role can read for post-game queries.
grant insert on public.notification_diagnostics to authenticated;
grant select on public.notification_diagnostics to service_role;
