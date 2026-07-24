-- ═══════════════════════════════════════════════════════════════════════════
-- Season history — the Superfan permanent record book (Fan Zone Competitive Redesign, PR3)
-- ═══════════════════════════════════════════════════════════════════════════
-- One row per (user, season_year): the fan's PEAK Superfan tier/score that season plus the final score at
-- season close. Superfan scores reset each NWSL season (superfan_scores is season-scoped); this is the
-- durable record that survives the reset, so the Superfan detail screen's "Season History" can show a
-- fan's arc across years. Tiny — one small row per user per season.
--
-- The app maintains the CURRENT season's row live (peak_score is monotonic via GREATEST; final_score
-- tracks the latest), so the record book is always current without a separate rollover job. World-readable
-- (a public record, like superfan_scores); each user writes only their own row. No service_role — the app
-- reads/writes directly. Idempotent: safe to re-run.

create table if not exists public.season_history (
  user_id uuid references auth.users(id) on delete cascade,
  season_year int not null,
  peak_tier text,                          -- tier at the peak score (fan/rising/allStar/mvp)
  peak_score int not null default 0,       -- highest 0–100 Superfan score reached that season (monotonic)
  final_score int not null default 0,      -- the latest score (== peak until it drops back)
  updated_at timestamptz default now(),
  primary key (user_id, season_year)       -- backs the upsert onConflict
);

alter table public.season_history enable row level security;

drop policy if exists "Anyone can read season history" on public.season_history;
create policy "Anyone can read season history"
  on public.season_history for select using (true);
drop policy if exists "Users insert own season history" on public.season_history;
create policy "Users insert own season history"
  on public.season_history for insert with check (auth.uid() = user_id);
drop policy if exists "Users update own season history" on public.season_history;
create policy "Users update own season history"
  on public.season_history for update using (auth.uid() = user_id);

-- Grants (the 42501 gotcha — RLS ≠ privilege). Read: anon + authed (public record); write: authed-only.
grant select on public.season_history to anon, authenticated;
grant select, insert, update on public.season_history to authenticated;
