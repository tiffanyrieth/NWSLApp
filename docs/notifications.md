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
   ⚠️ Goal scorer attribution is BEST-EFFORT AT THE FIRING TICK: the one-shot fires on the SCORE
   FLIP and attaches the scorer from whatever scoring play the scoreboard carries at that instant
   (`events.ts` parsePlays/latestPlayFor) — normally same-tick, but a play ESPN hasn't published
   yet (observed on an immediately-VAR-reviewed goal) means the notification goes out with the
   team-name fallback and NEVER re-fires. The LA card's scorer lines DO backfill (rebuilt every
   tick); the push does not. By design — don't "fix" by re-firing (double-buzz per goal).
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
  and the **Know Her Game "new round" nudge** (see the delivery-timing rule below — it's local but follows the
  *scheduled* model). No server involved. ⚠️ iOS caps *pending* local notifications at **64/app**, so
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

### 1·. Delivery timing — event-driven vs scheduled (⚠️ STANDING RULE, owner 2026-08-14)

This is a **second, orthogonal axis** to the Tier 1/Tier 2 (local-vs-watcher-push) split above — do not
conflate them. Tier is about *who delivers*; this is about *when*. **NWSL is a worldwide sport** (the #1
women's league globally; the app supports 100+ followable national teams; core fans in London, Lagos, and
Sydney follow international stars — Kerr at Gotham, Banda at Pride). So notification timing must be
correct for the whole globe, **never** reasoned about as if every user were in the US. The recurring AI
failure this rule targets: "NWSL → US league → US timezones only," which shipped a KHG nudge that fired
*before* content existed for anyone east of the publisher.

**Event-driven (real-time) notifications** fire at their real/absolute instant, **globally simultaneous**,
timezone-agnostic — the immediacy *is* the value (a 3 AM goal alert is the point). Members: **kickoff,
halftime, full-time, goals, red card, VAR/no-goal, lineup posted, the 24h day-before match reminder, and
the lock-screen V2 Live Activity.** The day-before reminder belongs here because it is anchored to a real
event (kickoff − 24h); it stays absolute-instant (`DayBeforeSpec.fireDate`) and is easy to toggle off.

**Scheduled (content) notifications** — anything NOT a live-match event (a "new content" nudge) — are
delivered on the **local-time model**, three layers:
1. **Anchor** to a good local hour: **10:00 AM local**.
2. **Gate** so it never precedes the content going live: fire at `max(local 10 AM, the content's global
   availability instant + a small buffer)`. Content publishes at ONE global UTC instant; only the *nudge*
   is per-timezone.
3. **Quiet-hours guard**: never at/after **9:00 PM local** — roll to the next morning's 10 AM. (No
   midnight pings for the far-east.)
   This is the standard worldwide pattern (per-user local-time delivery + quiet hours + decouple
   publish-from-notify — Duolingo, Spotify, news digests, every major push platform). **Any new
   scheduled notification inherits this model — do not re-derive per-feature.**

Members & availability instants (the "content live" moment for the gate):
- **Know Her Game "new round" nudge** — availability = **Monday 10:00 UTC** (the watcher's publish pass,
  `FanZoneCadence.knowHerPublishHourUTC`, mirrors the watcher's `KNOWHER_PUBLISH_HOUR_UTC`). Implemented
  as local Tier-1 one-shots in `NotificationScheduler.spotlightFireDate` /`spotlightSpecs`, cadence-gated
  to KHG drop weeks via `FanZoneCadence.upcomingKnowHerDrops`, re-armed on foreground. **Worked cases:**
  LA/NY → Mon 10 AM local; Hawaii → Mon 10 AM (no midnight); London → ~11 AM; Sydney → ~8 PM same-day;
  Auckland → Tue 10 AM.
- **NWSL Trivia** — **gets NO "new round" notification** by owner decision. (Its round is deterministic at
  the 00:00 UTC boundary; `availabilityInstant(for: .trivia,…)` exists for completeness/future use only.)
- **The future Fan Zone bracket-round nudge** (`fanZoneRounds` toggle, delivery unbuilt) inherits this
  model when built. Its toggle copy is narrowed to bracket-only (Trivia is notification-free).
- **Predict results** (`predictResults`) — a Tier-2 *watcher push*, brought onto the local-time model
  2026-08-14 (was a fixed 14:00-UTC blast = midnight in Sydney). Because a server push can't be scheduled
  on-device, the fan's timezone is stored server-side: the app writes `device_tokens.timezone`
  (`TimeZone.current.identifier`) on token registration, re-uploading whenever the token OR the tz changes
  (`NotificationSyncCoordinator` — so travel / a DST shift refreshes it). The watcher's
  `maybeRunPredictResultsPass` runs as an **hourly local-morning wave** (a KV hour-marker, replacing the
  once-daily hour-14 gate): each UTC hour it pushes unseen + un-notified predictors whose device is at
  **10:00 local now** (`qualifiesForLocalMorning`, IANA id via `Intl`; **null tz → legacy 14:00-UTC**, so
  un-migrated apps are unchanged and the rollout is deploy-order-safe). Idempotency is now **per-`(event,
  user)`** via the `predict_result_notified` ledger (the old single per-fixture KV marker would have
  stranded every timezone after the first wave); a `predict-nopredictors:${eventId}` KV marker keeps the
  cheap no-predictor short-circuit. Supervised verify: `POST /predict-results-run?dryRun=1&atHourUTC=<h>`
  (secret-gated) returns the cohort a given hour's wave would push without sending. Limitation: a result
  settling after a zone's 10:00 waits until next day's 10:00 for that zone (still far better than a
  midnight blast; the result is viewable in-app immediately regardless).

**⚠️ LOCAL vs SERVER localization are NOT the same amount of work — budget accordingly.** The *policy*
above is three lines ("fire at each fan's 10 AM, after content, not at night"), but the *machinery* depends
entirely on **who holds the clock**, and this is the trap: the two look identical on paper and are wildly
different to build.
- **A LOCAL notification (Tier 1: KHG nudge, day-before) gets localization almost free.** The device reads
  its own `TimeZone.current` at fire time — the phone *is* the clock. It self-schedules, iOS makes the
  one-shot idempotent, and it's fully provable in the Simulator. No backend, no stored tz, no dedupe.
- **A SERVER push (Tier 2: Predict results) turns "10 AM local" into a small distributed-systems problem.**
  The Worker has no idea where anyone is and can't "wait until it's 10 AM for user X." So localizing a
  server push costs, every time: **(1)** collect the tz on-device + **transmit + store** it
  (`device_tokens.timezone`); **(2)** keep it **fresh** (re-upload on DST/travel — a stored value goes
  stale, a live read never does — the stale-tz guard in `NotificationSyncCoordinator`); **(3)** **sweep**
  hourly instead of waiting (the 24-wave `maybeRunPredictResultsPass`); **(4)** **dedupe across the sweep**
  (the per-`(event,user)` `predict_result_notified` ledger — a single per-fixture marker BREAKS under
  waves); **(5)** **DST-harden** the server-side hour math (IANA + `Intl`, target kept clear of the
  01:00–03:00 spring-forward gap, try/catch a garbage id); **(6)** coordinate **three deploys** (app ·
  migration · watcher) with an ordering dependency; **(7)** build a **dry-run** affordance because the live
  path can't be proven in a sim. **The lesson for the next Tier-2 nudge (e.g. bracket-round results as a
  push): the hour is one line; the tz pipeline + hourly sweep + idempotency ledger already exist — reuse
  `device_tokens.timezone` / `qualifiesForLocalMorning` / the notified-ledger pattern, don't re-derive.**

### 1a. Reinstall restore — ⛔ SUPERSEDED 2026-08-01, BEING REMOVED

> ⛔ **READ THIS BEFORE THE SECTION BELOW. Half of what it describes is GONE (shipped 2026-08-03).**
> The owner's line: **detailed PREFERENCES may restore; the generic "who do I follow" may not.**
> - **Alert TYPES still restore** — everything below about `decideRestore` is CURRENT. They land
>   INERT: `NotificationsView` greys + disables the Alert-types section until a bell is on, so a
>   restored type applies to nothing until the user deliberately enables a team.
> - **Per-team/NT BELLS no longer restore.** `TeamAlertSyncCoordinator` is UPWARD-ONLY. A reinstall
>   is a clean slate; NOT re-selecting a team is a real signal, not data loss.
>
> **⚠️ WHY THIS BANNER EXISTS.** The section below frames the restore as the FIX for the banned
> "alerts on, nothing can fire" state. Read cold, that makes REMOVING it look like reintroducing a
> bug — which is exactly why this idea came back ~7 times across months, each time costing the owner
> another re-explanation. It is not a bug fix to protect. It is a v0.1 concept ("everything lives on
> the server and pushes down") that was written before the app had the shape it has now.
>
> **Why it never paid:** it saves ~2 taps across a 16-club picker and saves NO scrolling — the user
> still has to find and tap each club. And a reinstall is frequently someone RESETTING a broken
> state, where pulling server data back down defeats the entire purpose.
>
> **The state it caused (owner device, 2026-08-01):** an uninstall revokes iOS notification
> permission, but the restore switched bells back ON — so a bell read enabled while nothing could
> ever fire. Removing the restore deletes that bug rather than special-casing it.
>
> Removal + the open sub-question (do alert TYPES go clean-slate too): `docs/roadmap.md`, the
> 2026-08-01 sweep. **Everything below is HISTORY — do not cite it as intended behaviour.**

#### (historical) The 2026-07-22 restore

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
Full-time detection, the Live Activity teardown, and the fixture index's `ended` mark all require
`!unfinishedPost` (2026-07-30): a SUSPENDED match reports `state "post"` with `completed:false` +
`STATUS_SUSPENDED`, and treating that as final fired a false FT push, irrecoverably ended the LA
(push-to-start is gated on `ko >= now`), and stopped polling the fixture — `test/suspension.test.ts`.
- Fetches only a **yesterday→tomorrow scoreboard window** (not the full season — parsing ~240 events/min blew the
  CPU budget), via a **service binding to the proxy** (`PROXY.fetch("https://proxy/scoreboard…")`). A public
  `*.workers.dev` fetch between same-account Workers **404s with CF error 1042** — the binding is mandatory.
- **Live-window gate:** only matches with kickoff within `−5 min … +4h` are processed (bounds the KV reads).
- **CLUB feeds = league + cups (2026-08-06):** the club event list merges `CLUB_FEEDS`
  (`nwsl` + `usa.nwsl.cup` + `concacaf.w.champions_cup`, `fixtures.ts`) — a followed club's Challenge
  Cup / Champions Cup matches ride the SAME detect loop, LA-start pass, and lineup pass as league play
  (fan-out keys on ESPN team id, so a foreign opponent simply matches zero followers). Each event
  remembers its source feed → the short competition label ("Challenge Cup" / "CONCACAF" /
  "NWSL Playoffs" via `season.slug`) on the V2 card + V1 kickoff subtitle, and the lineup pass's
  `/summary?league=` param. Cup feeds are seasonal → fixture-window gating makes them free at rest.
- **The once-daily post-match Predict-results pass** (Change 8, `runPredictResultsPass`) **rides the
  SAME per-minute cron** — `maybeRunPredictResultsPass` hour-checks for ~14:00 UTC + a KV day-marker
  fires it exactly once (the free plan's 5-cron account cap is fully spoken for: proxy 4 + watcher 1 —
  an earlier "second cron `0 14 * * *`" note here was stale; receipt: watcher `wrangler.jsonc` crons +
  the `maybeRunPredictResultsPass` doc comment, corrected 2026-08-06). It reads the same
  yesterday→tomorrow window, keeps SETTLED finals
  (`state "post" && !unfinishedPost`), and for each pushes a GENERIC "your result is in" alert (no score
  — the hook; the in-app reveal is the payoff) to the match's predictors who (a) opted into the
  standalone `predict_results` pref AND (b) haven't opened their result. Recipients:
  `predictResultRecipients` = `predict_submission_marks` MINUS `predict_result_seen` (the seen mark the
  app writes on result-open) gated by `predict_results`, resolved to `device_tokens` — NO team-alert
  gate (predicting IS the opt-in). KV one-shot `predict-result:{eventId}` (retry-until-sent). The payload
  carries **`predictEventID`** (NOT `eventID` — a bare `eventID` routes to Match Detail; the app's tap
  handler branches to the Predict result screen on the separate key).
- **The MONDAY Know Her Game publish pass** (2026-08-12 weekend/Monday split, `maybeRunKnowHerPublishPass`)
  rides the SAME per-minute cron: UTC **Monday, hour 10** (= 3am PDT — after Sunday-night finals settle,
  before the earliest US 10am-local nudge), a once-per-week KV marker fires it once. It calls the proxy's
  `/knowher/publish-verified` (via the `PROXY` binding, holding `KNOWHER_INGEST_KEY`), which injects fresh
  ESPN stats + Lever 1 into the weekend-verified pool and publishes. No-op until `KNOWHER_INGEST_KEY` is set
  on the watcher (armed only after the supervised first run). Full design: `docs/know-her-game.md §5c`.

⏰ **Scheduled-push delivery time — LOCAL vs fixed-UTC (both follow-ups DONE 2026-08-14):**
- **KHG "new players" Monday nudge → cadence-aware + globally clamped** (`NotificationScheduler.
  spotlightFireDate`/`spotlightSpecs`). Fires only on KHG drop weeks (not the old fixed weekly timer that
  mis-fired on Trivia off-weeks), at `max(local Mon 10am, publish + buffer)` with a 9pm quiet-hours guard —
  so a far-east fan is never nudged before the Monday-10:00-UTC publish. See the delivery-timing rule above.
- **Predict "results ready" push → per-user local-morning wave** (`device_tokens.timezone` +
  `qualifiesForLocalMorning` + `predict_result_notified`). See the Predict-results bullet in the
  delivery-timing rule above for the full mechanism; null-tz devices still fall back to the 14:00-UTC send.

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

- **V1 push shape — copy v4, device-tested. THIS IS THE FULL SPEC** (it used to live in CLAUDE.md; moved here
  2026-07-31 so there is exactly one copy). Title = subject-first with a **COLON**, never an em-dash
  (`GOAL: Seattle Reign FC`). Subtitle = **scan-ordered** detail, and the order differs PER EVENT because what
  you need first differs:
  | Event | Subtitle | Why |
  |---|---|---|
  | Goal | **scorer first, then scoreboard** — `S. Menti 19' · NC 0–1 SEA` | you already know who's playing; you want who scored |
  | Red card | **minute-first player, NO scoreline** — `23' E. Wheeler` | the scoreline is not the news, and including it implies it changed |
  | Halftime / Full-time | **scoreline ONLY** — no last-scorer at HT, no "…win" tail at FT | the result IS the message; anything appended dilutes it |
  **Caps** are used ONLY on `GOAL` / `NO GOAL`. **No `body`** — title + subtitle only.
  A square crest **tile** attaches **only** to a GOAL (scorer's club) or RED CARD (carded club);
  kickoff / lineup / HT / FT / VAR corrections are **NEUTRAL** — no image, no `mutable-content`. ⚠️ Owner rule
  (2026-07-10, after an away-team "Lineups in" shipped the HOME crest): a single crest **misreads for the other
  team's fans** on any event that isn't attributable to one club.
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
