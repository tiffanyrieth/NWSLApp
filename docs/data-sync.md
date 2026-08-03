# Data Sync Directions — the audit (2026-08-03)

_Which direction every piece of per-user data syncs, and WHY. This is the reference the next
"restore X on reinstall" idea gets checked against — the reinstall-restore idea recurred ~7 times
because no such document existed. Read alongside `docs/stress-testing.md` (the 1k/100k lens decides
what is cheap enough to store server-side) and CLAUDE.md's restore line (2026-08-03: detailed
PREFERENCES may restore, the generic "who do I follow" may not)._

## The three categories (owner's model)

1. **UP-ONLY — device is truth.** Supabase needs a current copy to *act* (the watcher must know who
   to push to), but nothing ever flows back down. Re-picking costs the user seconds; hidden restored
   state costs debugging sessions.
2. **BOTH WAYS — server is durable truth.** Things the user **EARNED**. Half a season of Predict or
   Superfan progress must survive a broken phone — "start from zero again" is the worst feeling an
   end user can have, and the acceptance bar is: **a user who replaces their phone never starts over
   in the Fan Zone.**
3. **LOCAL-ONLY — deliberately not stored.** Per-round micro-detail that would cost real database
   per user, where the server keeps only the cheap rollup the leaderboards need. Cost-driven, and
   fine to lose.

The hybrid is deliberate: category 1 keeps sign-in from ever rewriting what's on screen; category 2
keeps earned progress immortal; category 3 keeps the database from growing with usage detail.

## Category 1 — UP-ONLY (device is truth)

| Data | Table | Up path | Verified |
|---|---|---|---|
| Club follows | `follows` | `FollowSyncCoordinator.resolveFollowOps` — adds always, deletes only once `hasOnboarded` | ✅ upward-only since 2026-07-23 |
| NT follows | `competition_follows` | same coordinator | ✅ |
| Per-team alert bells | `team_alert_preferences` | `TeamAlertSyncCoordinator` reconcile (push + prune to the device's set) | ✅ **upward-only since 2026-08-03** — restore branch deleted; prune gated on `hasOnboarded` and skips a bell currently ON |
| NT alert bells | `competition_alert_preferences` | same | ✅ same |
| APNs token | `device_tokens` | `DeviceTokenService` upsert on `(user_id, device_id)` | ✅ per-device by definition — a new phone is a NEW device row, nothing to restore |
| Live Activity tokens | `live_activity_start_tokens`, `live_activities` | `LiveActivityManager` | ✅ per-device, operational |
| Quiz answer picks | `quiz_answers` | written on submit (Trivia/KHG view models) | ✅ write-only aggregate — feeds `/quiz-results` community splits; 35d pg_cron retention |
| Predict pick aggregate | `predict_pick_counts` + `predict_match_submissions` + `predict_submission_marks` | `PredictCommunityService` (counts only, idempotent mark) | ✅ write-only aggregate; 28d retention |
| Anonymous usage | `analytics_counters` | `/analytics` batch | ✅ no user id at all |

**Why nothing here restores down:** the server copy exists so the *watcher* and *community stats*
can act, not as a backup of the user's choices. A reinstall is a clean slate (owner, 2026-08-01);
not re-selecting a team is a real signal.

## Category 2 — BOTH WAYS (server is durable truth; must survive a new phone)

| Data | Table | Up | Down | Merge discipline |
|---|---|---|---|---|
| Alert types (9 toggles) | `notification_preferences` | `NotificationSyncCoordinator` push | `decideRestore` at sign-in, on a device with NO local choices | restored VERBATIM (a type deliberately off stays off), and lands INERT — the UI disables the section until a bell is on |
| Identity / display name | `profiles` | upsert on change | `AuthStore.hydrateProfile()` at sign-in AND restore | `name_is_custom` guard — a custom name is never clobbered by Apple's |
| Trivia rollups (lifetime, season, round streak, round gate) | `fanzone_progress` | `ProgressSyncCoordinator` on completions | **same coordinator at sign-in** → `TriviaStore.restoreProgress` | monotonic (max per counter) |
| KHG rollups (points, editions, week streak, played-week gate) | `fanzone_progress` | same | same → `KnowHerGameStore` restore | monotonic + `restoredBaseline` (prevents double-count when local play and restore overlap) |
| Superfan counts (per-game correct/attempted) | `superfan_scores` | `SuperfanService` GREATEST merge | server-merged counts adopted + cached (`SuperfanCountsCache`) | per-counter max, both directions |
| Season archive | `season_history` | `SuperfanService` at rollover | read for "past seasons" | append-only |
| Predict season board row | `prediction_scores` | `PredictLeaderboardService` — client max-merge points/matches | boards read server rows (the "You" row is server truth) | max-merge; avg derived from merged pair |
| Predict banked rounds | `predict_round_scores` | server-side `GREATEST` upsert | round boards read server | ✅ atomic — not read-then-write |
| Predict season bests | `predict_season_bests` | `predict_merge_bests` RPC (server-side GREATEST) | season card standing | ✅ atomic |
| Bracket points | `bracket_scores` | **app never writes** — the Worker tally computes from `bracket_votes` (service-role) | app reads boards + own row | server-authoritative by construction |
| Bracket per-edition stats | `bracket_user_edition_stats` | Worker at edition close | Superfan detail reads | server-authoritative |
| Achievements | `user_achievements` | `AchievementService.award` (`ignoreDuplicates`) | `earned()` read on Superfan detail | insert-once; re-detection can't duplicate |

**The replaced-phone walk-through (the acceptance bar, traced):** sign in on the new phone →
`hydrateProfile` brings the display name back → `ProgressSyncCoordinator` restores Trivia + KHG
rollups *automatically at sign-in* → Predict/Bracket boards show the server "You" row on first open →
Superfan counts GREATEST-merge **at sign-in** (`ProgressSyncCoordinator.mergeSuperfan`, 2026-08-03 — it
used to wait for a visit to Superfan detail, so Home and the Game Center submit understated until then)
→ achievements read back on the detail screen. **No earned number is lost, and none of it waits for the
user to go looking.**

## Category 3 — LOCAL-ONLY (deliberate, cost-driven)

| Data | Where | Why it doesn't sync |
|---|---|---|
| Predict per-match score breakdowns (`predict.v2.scores`) | UserDefaults | per-match detail × every user = real DB growth; the board totals + banked rounds survive server-side |
| Predict rank movement snapshots/deltas, seen-results | UserDefaults | presentation memory ("↑2 since last match"), meaningless on a new device |
| Trivia per-round picks | UserDefaults | retention is current + previous round ONLY by owner rule — the server keeps the rollups |
| KHG per-edition score detail | UserDefaults | rollups restore via `fanzone_progress`; the per-question detail is replay UI |
| Bracket picks by round / submitted rounds | UserDefaults | the VOTE is in `bracket_votes` server-side the moment it's cast; local copy is the picker UI |
| Fan Zone "seen" dots, feed prefs, chip state | UserDefaults | pure presentation |
| Caches (images, headshots, roster, Superfan merged-counts cache) | Caches/UserDefaults | re-derivable |
| Onboarding + sentinel flags | UserDefaults | device-scoped by definition |

**The cost rule that draws this line:** the server stores what leaderboards and restore need
(one row per user per season — flat, cheap, passes 1k/100k trivially) and never per-round detail
(grows with usage forever). `quiz_answers` is the deliberate exception — kept 35 days for community
splits, then pruned by pg_cron.

## Gaps found (2026-08-03 audit)

1. **✅ FIXED 2026-08-03 — the bell restore-down is gone.** `TeamAlertSyncCoordinator` no longer pulls
   `team_alert_preferences` down onto an empty device. Alert TYPES deliberately still restore (owner:
   preferences may, choices may not) — see the category-2 note below.
2. **✅ FIXED 2026-08-03 — Superfan now merges at sign-in.** `ProgressSyncCoordinator.mergeSuperfan`
   runs the GREATEST merge on every sign-in, deliberately OUTSIDE the `fanzone_progress` guard (a
   Predict/Bracket-only player has no progress row but can have a rich `superfan_scores` row). Gated
   on `counts != .zero` so a never-played user writes nothing.
3. **🟡 The Predict dual-source disagreement** (roadmap, 2026-08-01 sweep 3e): `standing.rank` and
   the fetched board rows disagreed on a real device ("#70 of 72" vs a rung at #89, on a team never
   predicted). Both are category-2 server reads, so this is a consistency bug between two server
   paths, not a sync-direction gap — but it lives in this table's territory. Fix the data first.
4. **✅ RESOLVED 2026-08-03 — `trivia_scores` retired.** `supabase/migration_drop_trivia_scores.sql`
   archives the rows (streaks there counted DAYS, not rounds — never read them back) then drops the
   table. Owner runs the SQL.
5. **🟢 GC leaderboards on a fresh device** submit LOCAL totals which start low; Game Center keeps
   the best submitted score, so the board never regresses — but verify the three boards are
   configured "best score" in App Store Connect (they are per the checklist) before trusting this.

_Verified against code on 2026-08-03: every path named above was read, not assumed. Update this
document when any sync path changes — it exists so direction decisions stop being re-litigated._
