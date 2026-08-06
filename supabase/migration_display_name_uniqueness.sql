-- ═══════════════════════════════════════════════════════════════════════════
-- Display-name uniqueness + profanity filter (pre-launch, 2026-08-06)
-- ═══════════════════════════════════════════════════════════════════════════
-- WHY: `profiles.display_name` was a plain nullable text with no unique constraint and no content
-- filter, so two accounts could hold the same leaderboard identity (audit: 10 collisions across ~120
-- seeded fans) and nothing stopped a profane or impersonating name. Owner decisions (2026-08-06):
--   • Uniqueness = GLOBAL, case-insensitive, first-come. Renaming frees your old name automatically.
--   • Filter = profanity/slurs only for v1. Enforced BOTH client-side (instant feedback) and here
--     (a trigger a direct Supabase call can't bypass).
--   • A rename AUTO-UPDATES the leaderboards — `set_display_name` cascades the new name onto every
--     denormalized copy in one atomic call (no rank reset, no lingering old name).
--
-- HOW IT FITS: names are still written from the client, but now through `set_display_name(new_name)`
-- (SECURITY DEFINER) instead of a raw upsert, so the profiles write + the board cascade are one unit.
-- `check_display_name(candidate)` is the advisory pre-check the UI calls (RLS blocks a client from
-- reading other users' profiles rows, so availability MUST be a definer RPC). The unique index is the
-- real race guard; the trigger is the real profanity guard.
--
-- Idempotent: safe to re-run (`if not exists`, `create or replace`, `drop … if exists`).
-- ⚠️ APPLY NOTE: the unique index at the bottom fails if two profiles share a name. This file first
-- de-dupes names that live in SEED accounts (@seed.nwslapp.test) so it applies cleanly today. A
-- collision between two REAL accounts fails LOUD → resolve it by hand (never auto-rename a real user).

-- ── 1. Blocked-name list (the single source of truth for the filter) ──────────
-- Curatable without a code deploy (add rows in the SQL editor). `exact` = block only when the whole
-- normalized name equals the pattern (so "ass" blocks the name "ass" but NOT "Cassie"); `substring` =
-- block anywhere in the name (reserve for unambiguous slurs that never sit inside an innocent name).
create table if not exists public.blocked_names (
  pattern    text primary key,                              -- stored already-normalized (lowercase, a-z0-9 only)
  match_type text not null default 'exact' check (match_type in ('exact','substring'))
);

alter table public.blocked_names enable row level security;
-- The list itself is not secret, but only the filter functions (SECURITY DEFINER) need to read it.
-- No public policy → clients can't enumerate it; the definer functions bypass RLS.
grant select on public.blocked_names to service_role;

-- Starter list — deliberately modest; owner curates. Unambiguous slurs/profanity go `substring`;
-- short words that appear inside ordinary names go `exact` (whole-name only).
insert into public.blocked_names (pattern, match_type) values
  ('fuck','substring'), ('shit','substring'), ('bitch','substring'), ('cunt','substring'),
  ('nigger','substring'), ('nigga','substring'), ('faggot','substring'), ('retard','substring'),
  ('rape','substring'), ('rapist','substring'), ('slut','substring'), ('whore','substring'),
  ('pedophile','substring'), ('pedo','substring'), ('molest','substring'), ('nazi','substring'),
  ('kkk','substring'), ('coon','exact'), ('spic','exact'), ('chink','substring'), ('kike','substring'),
  ('ass','exact'), ('asshole','substring'), ('dick','exact'), ('cock','exact'), ('pussy','substring'),
  ('cum','exact'), ('sex','exact'), ('porn','substring'), ('penis','substring'), ('vagina','substring')
on conflict (pattern) do nothing;

-- ── 2. The rejection function (used by the trigger AND both RPCs — one source of truth) ──
-- Returns null when OK, else a reason code ('too_short' | 'blocked'). Normalizes first: lowercase,
-- fold common leetspeak (4→a 3→e 1→i 0→o $→s !→i), strip everything but a-z0-9. This is what makes
-- "sh1t" and "f.u.c.k" resolve to the blocked forms.
create or replace function public.display_name_rejection(candidate text)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  trimmed text := left(trim(candidate), 20);   -- match the app's stored form (20-char cap)
  norm    text;
begin
  if char_length(trimmed) < 2 then
    return 'too_short';
  end if;
  norm := regexp_replace(translate(lower(trimmed), '4310$!', 'aeiosi'), '[^a-z0-9]', '', 'g');
  if char_length(norm) = 0 then
    return 'blocked';   -- a name that normalizes to nothing (all punctuation) isn't a usable identity
  end if;
  if exists (select 1 from public.blocked_names where match_type = 'exact'     and norm = pattern) then
    return 'blocked';
  end if;
  if exists (select 1 from public.blocked_names where match_type = 'substring' and norm like '%' || pattern || '%') then
    return 'blocked';
  end if;
  return null;
end;
$$;

-- ── 3. Trigger — the unbypassable profanity guard on the table itself ─────────
-- Fires for any write path (the RPC below, OR a client hitting profiles directly with the anon key).
-- Uniqueness is NOT enforced here — that's the unique index (§6).
create or replace function public.enforce_display_name()
returns trigger
language plpgsql
as $$
begin
  if new.display_name is not null and public.display_name_rejection(new.display_name) is not null then
    raise exception 'display name not allowed' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_display_name_guard on public.profiles;
create trigger profiles_display_name_guard
  before insert or update of display_name on public.profiles
  for each row execute function public.enforce_display_name();

-- ── 4. check_display_name — advisory pre-check the UI calls before submit ─────
-- SECURITY DEFINER so it can see OTHER users' names (RLS on profiles is auth.uid()=id). Returns
-- 'ok' | 'taken' | 'blocked' | 'too_short'. Excludes your own row so your current name reads free.
create or replace function public.check_display_name(candidate text)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  capped text := left(trim(candidate), 20);
  reason text := public.display_name_rejection(capped);
begin
  if reason is not null then
    return reason;
  end if;
  if exists (
    select 1 from public.profiles
    where lower(display_name) = lower(capped) and id <> auth.uid()
  ) then
    return 'taken';
  end if;
  return 'ok';
end;
$$;

grant execute on function public.check_display_name(text) to authenticated;

-- ── 5. set_display_name — the ONE write entrypoint (atomic profiles + board cascade) ──
-- SECURITY DEFINER: writes profiles (the unique index + trigger enforce), then cascades the new name
-- onto every denormalized leaderboard copy so a rename shows up on the boards immediately (definer
-- bypasses RLS on bracket_scores, which is otherwise service-role-write-only). Returns
-- 'ok' | 'taken' | 'blocked' | 'too_short' | 'not_signed_in'. All-or-nothing: a unique_violation
-- rolls the whole thing back and returns 'taken', so no partial cascade on a rejected name.
create or replace function public.set_display_name(new_name text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  uid    uuid := auth.uid();
  capped text := left(trim(new_name), 20);
  reason text;
begin
  if uid is null then
    return 'not_signed_in';
  end if;
  reason := public.display_name_rejection(capped);
  if reason is not null then
    return reason;
  end if;
  begin
    update public.profiles set display_name = capped, name_is_custom = true where id = uid;
    if not found then
      insert into public.profiles (id, display_name, name_is_custom) values (uid, capped, true);
    end if;
  exception when unique_violation then
    return 'taken';
  end;
  -- Cascade onto the denormalized copies (all keyed user_id). Bounded, indexed, rename is rare.
  update public.prediction_scores    set display_name = capped where user_id = uid;
  update public.predict_round_scores set display_name = capped where user_id = uid;
  update public.superfan_scores      set display_name = capped where user_id = uid;
  update public.bracket_scores       set display_name = capped where user_id = uid;
  return 'ok';
end;
$$;

grant execute on function public.set_display_name(text) to authenticated;

-- ── 6. De-dupe seed names, then the unique index (the real uniqueness guard) ──
-- Resolve case-insensitive duplicates that live ONLY in seed accounts, keeping the earliest and
-- suffixing the rest, so the index below applies today. Real-vs-real collisions are left untouched →
-- the index creation fails LOUD on them (intended: surface, don't auto-rename a real user).
with dupes as (
  select p.id,
         row_number() over (partition by lower(p.display_name) order by p.created_at, p.id) as rn
  from public.profiles p
  join auth.users u on u.id = p.id
  where p.display_name is not null
    and u.email like '%@seed.nwslapp.test'
)
update public.profiles p
set display_name = left(p.display_name, 16) || '_' || d.rn
from dupes d
where p.id = d.id and d.rn > 1;

-- Case-insensitive global uniqueness. NULL display_names stay allowed (unconfirmed profiles).
create unique index if not exists profiles_display_name_lower_idx
  on public.profiles (lower(display_name));
