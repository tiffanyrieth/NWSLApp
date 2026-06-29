-- Migration: Live Activity (V2) token storage
--
-- Two per-user tables the watcher reads (service-role) to drive Live Activities:
--   * live_activity_start_tokens — the per-DEVICE ActivityKit push-to-start token. The watcher
--     sends an `event:start` push here ~5 min before kickoff to remotely create the Activity
--     (iOS 17.2+). One row per (user, token); a user can have several devices.
--   * live_activities — the per-ACTIVITY update token, captured by the app once an Activity is
--     running, keyed by match. The watcher sends `event:update`/`event:end` here on goals/HT/FT.
--     One active Activity per (user, match); pruned by the app when the Activity ends.
--
-- RLS owner-scoped + `grant ... to authenticated` (the 42501 gotcha — RLS ≠ privilege). The watcher
-- uses the service-role key (bypasses RLS) for the cross-user fan-out. Idempotent-ish on a fresh project.

create table public.live_activity_start_tokens (
  user_id uuid references auth.users(id) on delete cascade not null,
  token text not null,                 -- ActivityKit push-to-start token (hex)
  updated_at timestamptz default now(),
  primary key (user_id, token)         -- backs the app's upsert onConflict
);

create table public.live_activities (
  user_id uuid references auth.users(id) on delete cascade not null,
  match_id text not null,              -- ESPN event id
  push_token text not null,            -- per-Activity ActivityKit update token
  updated_at timestamptz default now(),
  primary key (user_id, match_id)      -- backs the app's upsert onConflict
);

alter table public.live_activity_start_tokens enable row level security;
alter table public.live_activities          enable row level security;

create policy "Users read own start tokens"   on public.live_activity_start_tokens for select using (auth.uid() = user_id);
create policy "Users insert own start tokens"  on public.live_activity_start_tokens for insert with check (auth.uid() = user_id);
create policy "Users update own start tokens"  on public.live_activity_start_tokens for update using (auth.uid() = user_id);
create policy "Users delete own start tokens"  on public.live_activity_start_tokens for delete using (auth.uid() = user_id);

create policy "Users read own live activities"   on public.live_activities for select using (auth.uid() = user_id);
create policy "Users insert own live activities"  on public.live_activities for insert with check (auth.uid() = user_id);
create policy "Users update own live activities"  on public.live_activities for update using (auth.uid() = user_id);
create policy "Users delete own live activities"  on public.live_activities for delete using (auth.uid() = user_id);

grant select, insert, update, delete on public.live_activity_start_tokens to authenticated;
grant select, insert, update, delete on public.live_activities          to authenticated;
