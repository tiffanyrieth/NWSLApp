# Notifications — the whole pipeline (V1 + V2), end to end

_The single "start here" walkthrough of how a notification gets from a match event to your phone — both the
**V1 rich push** (the interrupt: buzz + card) and the **V2 Live Activity** (the quiet glance). Traces every hop:
ESPN → proxy → watcher cron → detect → APNs (Queues / Broadcast Channels) → device → render. The deep dives
stay in `live-activity-v2.md` (V2 manual) and `push-fanout-scaling.md` (the fan-out architecture); this stitches
them into one flow. Point-in-time — **2026-07-12**; verify against code before relying on a specific line._

Two Cloudflare Workers + APNs + Supabase, spanning three repos: the app (`NWSLApp`), the watcher
(`~/Projects/nwslapp-match-watcher`), the proxy (`~/Projects/nwslapp-proxy`), plus the card renderer
(`nwslapp-card`, same repo as the watcher).

## The flow at a glance

```
match event (e.g. a goal on the pitch)
      │
      ▼
ESPN unofficial endpoints ───────────── source of truth, ~1 min behind live
      │   the WATCHER fetches this; the app's ESPNService is a SEPARATE path (in-app display only)
      ▼
nwslapp-proxy  (Cloudflare Worker) ───── pass-through cache · match-state-aware TTL · _cb upstream bust
      │   reached via a service binding (a public *.workers.dev fetch → CF error 1042)
      ▼
nwslapp-match-watcher  (Cloudflare Worker)
   cron  * * * * *   +   30s double-poll during live windows
   diff the scoreboard vs KV (MATCH_STATE, write-on-change)
   detectEvents → kickoff · goal · HT · FT · red card · VAR correction · lineup-posted
      │
      ├─ look up device_tokens + preferences (Supabase, service_role) · sign an ES256 .p8 APNs JWT
      │
      ├──▶ V1 buzz  +  LA push-to-start  ──▶ Cloudflare QUEUES  ──▶ APNs
      │       chunked tokens · apns-collapse-id · V1 card image from the nwslapp-card worker
      │
      └──▶ V2 in-match update  ──▶ APNs BROADCAST CHANNEL (one POST/event, Apple fans out) ──▶ APNs
      ▼
the phone
   · V1 rich push → NotificationServiceExtension renders the card (mutable-content: 1)
   · V2 → LiveActivityManager mirrors tokens → the widget renders from the content-state
   · tap → AppDelegate → PushBridge → deep-link → Match Detail
```

A visual version of this diagram is published as an Artifact (see the bottom of this file / ask Claude for the link).

## 1. The two tiers & the opt-in model

Everything is **opt-in** — nothing auto-enables at onboarding or launch (owner rule, no dark patterns).

- **Tier 1 — deliverable WITHOUT an account** (scheduled locally on the device): the **day-before** match reminder
  and **Player Spotlight**. No server involved. ⚠️ iOS caps *pending* local notifications at **64/app**, so
  day-before is **windowed to the next 2 fixtures per alerting team**, never the whole season.
- **Tier 2 — watcher-triggered ⇒ needs an account** (sign-in gated): kickoff / goals / halftime / full-time /
  **lineup-posted** + the **V2 Live Activity**. These require a `device_tokens` row, which requires a signed-in
  user (Sign in with Apple → Supabase).

**The bell cascade:** an explicit match-alert bell tap IS the opt-in, so the first time it **cascades the full
default bundle** (day-before + kickoff + goals + HT + FT + lineups + Live Activities via
`applyMatchAlertDefaultsIfFirstTime`) — a complete feature makes the best first impression, and a
bell-on-but-nothing-fires state is the banned "silent success." Because the bundle is mostly Tier 2, a
**signed-out** bell tap presents Sign in with Apple first (success → enable + cascade + toast; cancel → bell
stays off). A plain sign-out **PRESERVES** the Tier-2 types (display-gated on auth, restored exactly on
re-sign-in); only account delete wipes them (`resetServerPushTypes`). National-team alerts key by FIFA code
in `competition_alert_preferences` (separate from the club-id `team_alert_preferences`).

Prefs live in Supabase (offline-first, UserDefaults cache). App side: `NotificationPreferencesStore`,
`TeamAlertStore`, `NotificationScheduler` (Tier 1 local scheduling).

### 1a. Reinstall restore (the alert types) — added 2026-07-22

A reinstall used to bring the per-team BELLS back (`TeamAlertSyncCoordinator` pulls
`team_alert_preferences` down when local is empty) while every alert TYPE stayed off — the banned
"alerts on, nothing can ever fire" state. Two causes, both fixed:

1. `NotificationPrefsSyncService` was **push-only** — nothing ever read `notification_preferences` back.
2. On sign-in the coordinator pushed the fresh install's **all-off** snapshot up, destroying the saved row
   before anything could read it.

**How it works now** (`NotificationSyncCoordinator.decideRestore`, pure + unit-tested):

- **Only on a device with no local choices** — no toggle on AND the first-bell sentinel clear
  (`needsRestore`). Everything else is device-authoritative: no pull, and the push is never gated.
  ⚠️ Keep that gate this narrow. A first cut gated EVERY push on "the restore finished," which silently
  blocked preference syncing for a whole session on a device that had toggles.
- **Saved row with anything on ⇒ restore it VERBATIM.** A type the user deliberately turned off comes back
  off. Device-proven 2026-07-22 (saved `goals=false` → restored `goals` off, everything else on).
- **Nothing worth restoring but a team bell is on ⇒ cascade the default bundle** — never OVER an existing
  selection (guarded on `anyServerPushEnabled`, so signing in via a "Match updates" tap keeps just that,
  while the onboarding bell — Tier-1 day-before only, by design — still cascades).
- **Bells can land after the pull** (separate coordinator, separate Task), so the coordinator observes
  `teamAlerts.enabledTeamIDs` and re-checks the invariant whichever finishes first.
- **Follows are NOT restored** (deliberate, upward-only). The user re-picks clubs; the bells for those
  clubs and all alert types then restore themselves.
- Companion fix: `TeamAlertSyncCoordinator` bails when alerts AND follows are both empty, and used to
  never retry — so a reinstall whose Keychain session restores BEFORE onboarding never got its bells back.
  It now marks only a reconcile that actually ran, and the follows-changed observation retries once.

**Tracing it** (`NotifTrace`, visible in Notification Diagnostics): `prefs-boot` (what the stores loaded
this launch) → `prefs-fetch` (what the SERVER holds + the decision inputs) → `prefs-restore`
(restored / cascaded / skipped, with why) → `prefs-push` (what actually reached Supabase). Added because a
push that never RAN looked identical to one that succeeded.

⚠️ **Testing this in the simulator:** `simctl uninstall` deletes the app container but **NOT** the
preferences domain — `cfprefsd` keeps serving it to the next install, so a "fresh install" boots with the
old toggles on and the restore correctly steps aside. Clear it properly:
`xcrun simctl spawn <UDID> defaults delete com.tiffanyrieth.nwslapp.NWSLApp`. (`-resetOnboarding` is fine
too now — its notif reset writes cleared sentinels instead of `removeObject`, which had the same problem.)
Three test rounds were misread before this was understood; `prefs-boot` is the tell (`local=none` = real).

## 2. Data source & the proxy

- **ESPN's unofficial NWSL endpoints** are the source of truth — but ~1 min behind live, and the **full-season
  `dates=` query serves 25–47 min STALE live state** during games (see `backend.md`).
- The **`nwslapp-proxy` Worker** sits in front: pass-through cache with a **match-state-aware TTL** (30s live /
  300s idle) and, on every `/scoreboard` cache MISS, a **`_cb` cache-bust on the ESPN *upstream*** so ESPN can't
  serve its stale copy (edge-cache key unchanged → ESPN hit count flat).
- ⚠️ **The notification pipeline does NOT use the app's `ESPNService`.** That class is the *in-app display* path
  (Schedule/Match Detail). The **watcher polls the proxy itself**; the two paths only share the proxy's cache.

## 3. The watcher — cron & polling

`nwslapp-match-watcher`, a scheduled Cloudflare Worker (`src/index.ts`):

- **Cron `* * * * *`** — Cloudflare's floor is 1 minute. During a **live window** the tick **double-polls**
  (poll → sleep 30s → poll again cache-busted) so goal/HT/FT latency is ~30s (shipped 2026-07-11).
- Fetches only a **yesterday→tomorrow scoreboard window** (not the full season — parsing ~240 events/min blew the
  CPU budget), via a **service binding to the proxy** (`PROXY.fetch("https://proxy/scoreboard…")`). A public
  `*.workers.dev` fetch between same-account Workers **404s with CF error 1042** — the binding is mandatory.
- **Live-window gate:** only matches with kickoff within `−5 min … +4h` are processed (bounds the KV reads).

## 4. Detection

Per tick, the watcher diffs each in-window match against **KV (`MATCH_STATE`)**:

- **Write-on-change guard** — KV is written only when state actually changes (goal/HT/FT/red/period/anchor),
  cutting a live match from ~120 writes to ~10 (free-tier headroom).
- **`detectEvents`** produces: **kickoff · goal · halftime · full-time · red card** (reds only — keys on ESPN's
  explicit `redCard` boolean, never text) **· VAR correction** (a debounced score *decrease*: wait, re-poll a
  cache-busted scoreboard, fire only if it persists) **· lineup-posted** (polls `/summary` in a 75-min
  pre-kickoff window, fires the tick both XIs are up). Lineup dedup is **retry-until-sent** (two KV markers:
  `lineup-pub:{id}` latches "XIs posted" to stop the `/summary` re-poll; `lineup:{id}` marks the one-shot send
  only once ≥1 recipient is actually reached) — so a 0-recipient tick (a transient Supabase read, or a follower
  who enabled the alert late) retries next tick instead of being permanently dropped, mirroring the V2 LA-start.
  A published-but-0-recipient tick logs the gate breakdown (`teamOptIns`/`prefEligible`) and flags the SUSPICIOUS
  case (followers exist yet resolved to zero) — no silent success.
- **Fire-once ledgers** in `StoredState` (e.g. per-side `redCards`) prevent duplicate sends; a pre-existing KV row
  baselines rather than late-firing.

## 5. APNs auth & the token tables

- **Auth to APNs:** an **ES256 JWT signed with a `.p8` key** (the watcher's APNs key; `APNS_HOST` = production).
  ⚠️ A USB/Xcode **DEBUG** build registers a **sandbox** token → the prod gateway 400s `BadDeviceToken`. Real
  games need a **TestFlight (production)** token; test endpoints take an optional `sandbox:true` to route just
  that call to the sandbox host.
- **Three token tables** (all keyed **per-device** so tokens replace, not accumulate):
  - **`device_tokens`** — the V1 APNs token. Upserted by `DeviceTokenService.registerToken(_:userID:)`.
  - **`live_activity_start_tokens`** — the V2 **push-to-start** token (lets the watcher remote-create an Activity).
  - **per-Activity tokens** — issued once an Activity is running (for direct updates; the cron now prefers the
    broadcast channel, so these are largely legacy).
- **Per-device keying:** every table keys on **`(user_id, device_id)`**, where `device_id` is a **Keychain-stable
  UUID** (`DeviceIdentity.swift`, survives reinstall). A rotation replaces the row in place. The watcher also
  **self-prunes** — a send returning `410 Unregistered` / `400 BadDeviceToken` deletes that token
  (`pruneDeadTokens`). (Zombie-token accumulation was the old V2 "delivered-but-never-renders" bug.)
- ⚠️ **Grants:** any table a Worker reads/writes as `service_role` needs an explicit `grant … to service_role`
  matching the operation (the prune DELETEs `device_tokens`, so it needs `select, delete`).

## 6. Send / fan-out

Two rails, both from the watcher, sharing the JWT. Delivery detail: `push-fanout-scaling.md`.

- **V1 buzz (+ LA push-to-start) → Cloudflare Queues** ($0, free tier). The cron chunks follower tokens (~40/msg)
  and enqueues; a **consumer** drains one message per invocation, each with its **own fresh subrequest budget**,
  so a launch-scale fan-out can't overflow the per-invocation cap. `apns-collapse-id` dedupes. The **V1 card
  image** is rendered by a **third Worker, `nwslapp-card`** (`/thumb/{ABBR}`, satori+resvg — split out because
  those deps blew the cron's cold-start CPU); the watcher 302s `/card/*` → `nwslapp-card`.
- **V2 in-match updates → APNs Broadcast Channels** (iOS 18+). The watcher creates a **channel per match**; the
  `input-push-channel` in the start payload auto-subscribes each Activity; every update/end is **ONE POST**
  (Apple fans out to all subscribers). Flat cost per match regardless of follower count. **iOS 17 = V1 only**
  (graceful degradation — no Live Activities).
- The watcher's `syncLiveActivity` broadcasts on an **event**, on **anchor drift** (`clockStartEpoch` jumps ≥30s —
  each half's late live-flip), on a **stoppage-minute rollover** (the per-minute `90'+N'` in added time), or on
  the **10-min resync floor**; and ends + deletes the channel at FT.

## 7. On the device

App side (`NWSLApp`):

- **Registration (every open — canonical Apple pattern, NOT gated on a toggle):**
  `registerForRemoteNotifications` fires on cold launch + every foreground (`scenePhase .active`). iOS hands the
  token to `AppDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` (`NWSLAppApp.swift`),
  which calls **`PushBridge.shared.didRegister(token:)`** → **`DeviceTokenService`** upserts `device_tokens`
  (guarded — writes only on token change). `didFailToRegister` → Diagnostics (never a bare print).
- **V1 rich push arrives** with `mutable-content: 1` → iOS wakes the **`NotificationServiceExtension`**
  (`NotificationService.swift`), which downloads the card image (following the `/card/*` 302) and attaches it, so
  the banner shows the crest/scoreboard tile. Neutral events (kickoff/lineup/HT/FT/VAR) carry **no image, no
  `mutable-content`** — the NSE stays asleep.
- **V2 Live Activity:** **`LiveActivityManager`** observes `Activity<MatchActivityAttributes>` —
  `pushToStartTokenUpdates` (uploads the start token via `upsertStartToken`, under a **UIKit background-task
  assertion** so a background launch can finish the upload) and `pushTokenUpdates` (per-Activity). Incoming
  broadcast/updates re-render the **widget** (`NWSLLiveActivity/MatchLiveActivity.swift`) from the pushed
  **content-state** (the `MatchActivityAttributes.ContentState` shared struct).
- **Tap → deep-link:** `AppDelegate` → `PushBridge.shared.didTapNotification(eventID:)` → `AppRouter.openMatch`
  → Schedule tab pushes **Match Detail** for that event.

## 8. V1 vs V2 — the role split

**V1 is the interrupt; V2 is the quiet glance.** They are additive and fire *together* on one event (e.g. a goal:
V1 buzzes with the card, V2 silently updates the lock-screen score).

- **V1 push shape** (copy v4, device-tested): title = subject-first with a COLON (`GOAL: Seattle Reign FC`),
  subtitle = scan-ordered detail (`S. Menti 19' · NC 0–1 SEA`); a square crest tile attaches **only** to a GOAL
  (scorer's club) or RED CARD (carded club); kickoff/lineup/HT/FT/VAR are neutral text.
- **V2 render law** (⚠️ read `live-activity-v2.md` §0 before touching any payload): the start push MUST carry an
  `alert` AND be wrapped in `{ aps: … }`, or iOS silently drops it. Buzz-once = `sound:"default"` on start;
  updates/end silent.
- **The clock split:** the widget shows Apple's self-ticking **mm:ss** during 1'–90' (`showsHours:false`), the
  in-app **football minute** (`45'+2'`) ticks in-app only, and in **added time** the watcher broadcasts a
  `stoppageDisplay` `90'+N'` string each minute. (`project_football_clock_decision`.)

## 9. Failure modes & testing

- **No silent failures:** every fallback/parse/retry/empty emits to the **`Diagnostics`** spine (app) / `emitDiag`
  (proxy). The proxy has a deploy-time health check that exits non-zero on a gap.
- **Test without a real game:** the **fake-match harness** (`POST /debug/fake-match`) injects a synthetic fixture
  the cron discovers on its own — the ONLY way to exercise the full organic queue/broadcast path. Plus
  `POST /test-push`, `POST /test-activity`, `POST /test-broadcast`, and `scripts/replay.mjs` /
  `scripts/replay-realtime.mjs`. ⚠️ `1 sent` ≠ rendered — only a real device (or the harness on a device) proves V2.
- **Observability:** `notification_diagnostics` SQL trail (per-device chain), `GET /telemetry/recent` on the proxy,
  `wrangler tail` on the watcher.

### Deep-dive references
- **`live-activity-v2.md`** — the V2 manual (render law §0, tokens, payloads, runbook, incident history).
- **`push-fanout-scaling.md`** — the fan-out architecture (Queues + Broadcast Channels) + cost curve.
- **`backend.md`** — ESPN quirks, the proxy, Supabase schema/grants.
- **`stress-testing.md`** — the 1k/100k sizing for each load path.
