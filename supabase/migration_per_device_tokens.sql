-- Per-device token keying — fixes token ACCUMULATION (the V2 Live Activity "zombie token" bug).
--
-- Was: device_tokens UNIQUE(user_id, token) + live_activity_start_tokens PK(user_id, token). Every APNs
-- token rotation (reinstall / device restore / iOS update) produced a NEW row and never removed the old
-- one, so the watcher fanned pushes out to a pile of dead tokens — which is why the Live Activity
-- push-to-start "delivered" (200) to zombies but never rendered on the current device.
--
-- Now key on (user_id, device_id): each physical device keeps exactly ONE current token
-- (replace-on-rotation), while the SAME user on two devices keeps two rows (iPhone + iPad both get
-- pushes). `device_id` is the app's Keychain-stable per-device UUID (DeviceIdentity.swift — survives
-- reinstall, so a reinstall reuses the same id and replaces the token in place).
--
-- Existing rows have no device_id; tokens auto re-register on the next app launch, so wiping is clean.
-- The watcher (service_role) additionally self-prunes any token APNs rejects (410 Unregistered / 400
-- BadDeviceToken) — see nwslapp-match-watcher supabase.ts pruneDeadTokens.
--
-- GRANTS (re-asserted below, idempotent): device-verify on build 22 surfaced two grant gaps the live
-- DB never had, distinct from the constraint swap — `authenticated` was missing DELETE on device_tokens
-- (app removeToken → 42501 permission denied) and `service_role` was missing DELETE (watcher pruneDeadTokens
-- couldn't prune). Re-granting is harmless if already present, so this migration is self-contained.

-- device_tokens: PK stays `id`; swap the (user_id, token) UNIQUE for (user_id, device_id).
alter table public.device_tokens add column if not exists device_id text;
delete from public.device_tokens;
alter table public.device_tokens drop constraint if exists device_tokens_user_id_token_key;
alter table public.device_tokens drop constraint if exists device_tokens_user_device_key;  -- idempotent re-run
alter table public.device_tokens alter column device_id set not null;
alter table public.device_tokens add constraint device_tokens_user_device_key unique (user_id, device_id);

-- live_activity_start_tokens: swap the composite PK (user_id, token) -> (user_id, device_id).
alter table public.live_activity_start_tokens add column if not exists device_id text;
delete from public.live_activity_start_tokens;
alter table public.live_activity_start_tokens drop constraint if exists live_activity_start_tokens_pkey;
alter table public.live_activity_start_tokens alter column device_id set not null;
alter table public.live_activity_start_tokens add primary key (user_id, device_id);

-- Grant corrections (idempotent — re-assert the intended grants; see the GRANTS note above).
grant select, insert, update, delete on public.device_tokens              to authenticated; -- app removeToken
grant select, delete                 on public.device_tokens              to service_role;  -- watcher pruneDeadTokens
grant select, insert, update, delete on public.live_activity_start_tokens to authenticated;
grant select, insert, update, delete on public.live_activity_start_tokens to service_role;
