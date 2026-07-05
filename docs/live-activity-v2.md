# Live Activity V2 — The Manual

The complete how-it-works + how-to-operate reference for NWSLApp's V2 Live Activity (lock-screen +
Dynamic Island live match card). **Read this BEFORE touching, testing, or troubleshooting anything V2.**
Every claim here is device-proven (dates noted) — several directly contradict Apple's docs and common
AI/LLM assumptions. When in doubt, trust this file over intuition.

---

## 1. What V2 is (and how it splits from V1)

Two independent notification layers ride the same watcher + `.p8` APNs key:

| | V1 — rich push | V2 — Live Activity |
|---|---|---|
| Surface | Notification banner + Notification Center | Persistent lock-screen card + Dynamic Island |
| Role | **The interrupt** — buzzes for kickoff/goal/HT/FT/lineups per the user's toggles | **The quiet glance** — a live scoreboard that sits on the lock screen for the whole match |
| Renders | Text + a server-rendered PNG card (`nwslapp-card` worker `/card`, attached by the NSE) | **Native SwiftUI** drawn ON-DEVICE by the widget target (`NWSLLiveActivity/MatchLiveActivity.swift`) from pushed JSON state |
| Sound | Yes (per toggle; `interruption-level: time-sensitive`) | Never buzzes after start (updates/end are alert-less) |
| Persistence | Stacks in Notification Center (`thread-id: match-<id>`) | Ephemeral: dismisses ~15 min after FT; leaves no history |
| Channel | `apns-push-type: alert`, topic = bundle id | `apns-push-type: liveactivity`, topic = `<bundle>.push-type.liveactivity` |

**They are complementary, not redundant — SETTLED 2026-07-05 after a full device evaluation of
"could V2 replace V1":** it can't, for four proven reasons — (1) LA alerts leave NO Notification
Center record (ephemeral; the whole match story vanishes ≤4h after FT), (2) V2 only reaches devices
with a running Activity, (3) end-push alerts are ignored by iOS (no reliable FT buzz), (4) each new
event overwrites the last on the card (no who-scored history). Goals fire BOTH (V1 buzz + V2 silent
score flip). The premium apps (FIFA/MLS) run the same hybrid for the same reasons.

**V1 redesign (SHIPPED 2026-07-05, watcher `ff93096`):** Title = `Event: scoreline` (caps only on
GOAL / NO GOAL), Subtitle = one detail line (scorer 19' / venue·broadcast / winner), NO body;
attachment = the proxy's square 512px crest (`/crest/{ABBR}`: scoring club on goals, disallowed club
on VAR, winner at FT, else home) — a square attachment IS a clean collapsed thumbnail, which killed
the old wide-card dark-blob problem structurally. Per-event interruption-level: goals/VAR/kickoff/FT
`time-sensitive`, lineups/HT `active`. Scorer HEADSHOTS on goals = phase 2 (scoreboard carries name
only, no athlete id; needs /summary roster id-resolution with an exact-match guard — wrong-face risk).

**V2 is NOT text-only.** The widget bundles real crests in its OWN asset catalog
(`NWSLLiveActivity/Assets.xcassets/Crests`). Gotcha: the widget's out-of-process renderer silently
blanks on heavy Illustrator SVGs (fine in the app) → risky crests are PNG in the widget catalog ONLY;
the app keeps pristine SVG. Team-color gradient banner included. It looks premium; don't let anyone
tell you it can't.

## 2. The two-token system (the #1 source of confusion)

V2 uses **two different APNs tokens with different jobs**. Conflating them causes most misdiagnoses:

1. **Push-to-start token** (`live_activity_start_tokens`) — per-DEVICE, obtained by the app from iOS
   and upserted keyed on `(user_id, device_id)` (Keychain-stable `DeviceIdentity`). The watcher sends
   the START push to this. Registered on every app open (register-on-open, build 23) — requires a
   **signed-in Supabase session** to upsert (no session → `start-token drop: no session` in telemetry
   → that device can never get a V2 card until sign-in).
2. **Per-Activity token** (`live_activities`, keyed per match) — minted by iOS ONLY AFTER an Activity
   actually starts on the device, then uploaded by the app. The watcher sends UPDATE/END pushes to
   this. **It takes MINUTES to appear after the start push** (device receives push → iOS creates the
   Activity → app is background-launched → observer catches the token → Supabase upsert under a UIKit
   background-task assertion). Observed real-world lag: ~30s to ~4 min per device.

**Timing law that follows:** the start MUST fire well before kickoff. `LA_START_LEAD_MS = 20 min`.
A start fired 1 minute before kickoff will "succeed" (APNs 200) and the device will still miss the
opening minutes because its per-Activity token hasn't checked in. This was learned twice (6/30, 7/4).
A catch-up push (KV `la-seen:{matchId}`) brings late-registering devices straight to the current score.

## 3. ⚠️ THE RENDER LAW — what it takes for a card to actually appear

**Device-proven 2026-07-04 (controlled A/B, permission granted, fresh token), contradicting Apple's
docs:** a push-to-start WITHOUT an `alert` object **NEVER renders**. APNs returns 200, the watcher logs
`1/1 ok`, and iOS silently drops it. The three axes:

| Start payload | Result |
|---|---|
| No `alert` | ❌ Never renders (delivered-but-invisible; looks like success server-side) |
| `alert: {title, body}` (no sound key) | ✅ Renders — but BUZZES (omitting sound does NOT silence it) |
| `alert: {title, body, sound: ""}` | ✅ Renders + quiet banner, **no sound/vibration** ← **shipped design** |

Updates and END are alert-less (silent) — that works fine; the law applies to the START only.

**UPDATE-push alerts (device-tested 2026-07-05, pure-V2 run, real NC vs SEA timeline):** an
`alert {title, body, sound}` on an `event: "update"` push DOES buzz + light the screen (kickoff,
goals, and halftime all buzzed via the LA channel alone — capability confirmed, matching Apple's
docs for once). **END-push alerts appear to be IGNORED by iOS** (the FT end push carried an alert;
no buzz). The 2nd-half resume was silent by design (control). Production still sends updates/end
SILENT — the hybrid architecture decision (below) keeps V1 as the buzzer; the update-alert
capability is filed for possible future targeted use (e.g. goal pops the expanded island).
Diagnostic plumbing: `/test-activity` accepts `alert` on any mode; `replay.mjs --la-alerts`.

**Full checklist for a card to appear on a given phone** (each has failed for us at least once):
1. iOS 17.2+ (push-to-start floor; also the app's min OS).
2. **TestFlight/App Store build** — a debug/Xcode build mints SANDBOX tokens; the watcher pushes to
   production APNs → `400 BadDeviceToken`. Re-register from TestFlight.
3. **Signed in** — token upserts require a Supabase session (see §2).
4. Live Activities ON in iOS Settings for the app (`laEnabled=true` in the trail).
5. **The one-time per-app "Allow Live Activities?" prompt answered Allow** — iOS attaches it to the
   app's FIRST-ever presented Activity; a reinstall resets it. (Not the render-blocker — silent still
   fails after Allow — but an unanswered prompt on a fresh install is one more first-run hurdle.)
6. The start push **carries the alert** (the render law above).
7. Push-to-start token in the DB is CURRENT (per-device replace keying, build 23 — the old
   `(user_id, token)` keying accumulated zombie tokens; APNs 200'd dead tokens and nothing rendered).
8. App **not force-quit** (swiped away). Backgrounded/locked is fine — iOS background-launches the
   app. Force-quit is a hard Apple constraint: card may show but the per-Activity token can't upload.
   THE APP DOES NOT NEED TO BE OPEN — that's the whole design; only force-quit breaks it.

**"1/1 ok" ≠ rendered.** It means APNs accepted the request. Whether iOS presented anything is only
knowable on-device (lock screen) or via the app's own observation (`snapshot=N`, `live_activities` row).

## 4. The clock (how the ticking minute works)

- The watcher does NOT push every minute (Cloudflare subrequest cap + APNs pacing make per-minute
  fan-out unscalable). Instead each content-state carries **`clockStartEpoch` = now − elapsed** (a
  "virtual kickoff"), and the WIDGET advances the clock locally (Apple's timer text) between pushes.
- The lock-screen widget deliberately shows Apple's **mm:ss** format; the true football clock
  ("45'+2'") ticks IN-APP only (`MatchClock` + TimelineView). Don't "fix" the widget's mm:ss — that's
  a settled scale decision.
- Drift is corrected by a resync push every ~10 min (`LA_RESYNC_MS`) and at every real event.
- Phase changes come from the watcher diffing the scoreboard each cron minute: kickoff / goals /
  halftime (`staticLabel: "HT"`) / full-time (`"FT"` + END push; no dismissal-date → ~4h linger).
- ⚠️ **ESPN FREEZES `status.clock` at 45:00/90:00 through stoppage time** (observed live 7/4).
  Any clock that re-anchors `now − clock` per poll/push therefore PINS at `+1'` (app) or snaps
  back to 45:00 (widget). THE RULE: anchors must be MONOTONIC — re-anchor only when the clock
  ADVANCES or the period changes. Implemented 7/5 in `MatchStore.reconciledTickAnchors` (app,
  unit-tested) and `StoredState.virtualKickoff` (watcher → `contentStateFromMatch`).
- End-to-end latency: cron floor 1 min + proxy live TTL 30s ⇒ an event reaches phones ≤ ~90s after
  ESPN reflects it.

## 5. ⚽ Soccer timing reality (stop "diagnosing" normal delays)

- **A "8:00 PM" listing is NOT the kickoff whistle.** NWSL/MLS list the broadcast window: anthem/intros
  at 8:00, actual kickoff typically **8:05–8:15**. An 8:07 with no kickoff event is NORMAL — not a bug,
  not a stuck watcher. Don't start troubleshooting until well past :15.
- ESPN's scoreboard flips to `in` LATE relative to the real whistle (proxy cache lag on top) — the
  watcher's kickoff guard is `clock < 600` (was 120, which silently skipped kickoffs).
- Matches also run long: 45'+stoppage per half; FT for an 8pm listing lands ~10pm. The live window
  gate is kickoff−5min → kickoff+4h.

## 6. Payload reference (what the watcher actually sends)

Channel headers (all V2): `apns-topic: <bundle>.push-type.liveactivity`,
`apns-push-type: liveactivity`, `apns-priority: 10`.

- **START** (to push-to-start token): `aps = { timestamp, event: "start",
  "attributes-type": "MatchActivityAttributes", attributes: {matchId, homeAbbr, awayAbbr, competition},
  "content-state": {...}, "stale-date": now+8h, "relevance-score": 100,
  alert: {title: "WAS vs HOU", body, sound: ""} }` ← alert REQUIRED (§3).
- **UPDATE** (to per-Activity token): same minus attributes/alert; `event: "update"`, stale-date +1h.
- **END**: `event: "end"`, final content-state, `dismissal-date` = FT + ~15 min (card lingers, then goes).
- **content-state keys MUST byte-match the Swift struct** (`Shared/MatchActivityAttributes.swift`
  `ContentState`): `homeScore` `awayScore` `phase` (`pre|live|halftime|extraTime|penalties|fulltime`)
  `clockStartEpoch?` `staticLabel?` (+ `lastScorer?`, `broadcast?`). A mismatched/extra-typed key =
  silent decode drop on-device. `compact()` strips nulls so optionals are OMITTED, never null.

Who gets a START: users with match alerts ON for a participating team (`team_alert_preferences`) AND
`notification_preferences.live_activities_enabled = true` AND a registered start token. KV-deduped
per match (`la-start:{matchId}`); fires on the first cron tick inside kickoff−20min.

## 7. Testing runbook (the exact recipes)

**The simulator CANNOT receive push / push-to-start. All V2 testing is real-device.** (Local
`-driveLiveActivity` drives the widget UI in-sim, but the Dynamic Island doesn't composite into
`simctl io screenshot` — pixel checks are device-only.)

Tools (watcher repo):
- `POST /test-activity` (header `x-trigger-secret`): body `{mode: start|update|end, matchId, h, a, hs,
  as, phase, min, sc, comp, token?, alert?: true|{title,body,sound?}}`. `token` present → that ONE
  device; omitted → fan-out. `alert: true` → generic alert (buzzes); `sound: ""` for quiet.
- `scripts/replay.mjs` — replays a real past match compressed onto a wall-clock budget. Key flags:
  `--start-only` / `--updates-only` (two-phase), `--with-v1` (also fire the matching V1 rich pushes —
  the "every toggle on" experience), `--minutes=N`, `--match-id=<fresh-id>` (ALWAYS use a fresh id per
  run so stale per-Activity tokens on other phones can't catch updates), `--ht-hold=<sec>` (dwell at
  halftime), `--start-hold=<sec>` (default 180 — do NOT lower it; see §2 timing law), `--correction`
  (VAR goal-disallowed test), `--dry-run`, `--team=ABBR`, `--event=<espnId>`, `--fixture`.
- Single-device targeting: env `MY_START_TOKEN` (V2 start) + `MY_DEVICE_TOKEN` (V1 pushes). Get them:
  ```sql
  select p.display_name, t.token as start_token, d.token as device_token
  from live_activity_start_tokens t
  join device_tokens d on d.user_id = t.user_id and d.device_id = t.device_id
  join profiles p on p.id = t.user_id;
  ```
  (Join by display_name — `auth.users.email` is an Apple Hide-My-Email relay; email filters fail.)

**The reliable two-phase recipe:** `--start-only` (phone backgrounded, NOT force-quit) → card should
appear ≤ ~30s → wait ~3 min → `select match_id, updated_at from live_activities order by updated_at
desc;` shows the matchId row (proves per-Activity token checked in, **without opening the app**) →
`--updates-only --match-id=<same>`. Single-run works too (the built-in 180s hold); if the first update
logs `0/0`, later steps catch up — not a failure.

Observability, bottom-up order: (1) `notification_diagnostics` SQL trail (per-user, per-device chain:
launch → register → didRegister → device-upsert → push-start-rx/observe/upsert); (2)
`GET /telemetry/recent` on the PROXY (`x-admin-key: BRACKET_ADMIN_KEY`) — `liveActivityTrace`
breadcrumbs incl. `startObserving state=… snapshot=N`, `activityUpdate match=…`, `…upsert ok`,
`start-token drop: no session`; (3) `wrangler tail --format pretty` on the watcher (cron ticks, `LA
start H vs A: n/m`); (4) Cloudflare dashboard per-version metrics. Escalation of last resort: phone on
the Mac, Console.app filtered to `liveactivitiesd` while a start push arrives. Gotchas: `wrangler kv`
reads need `--remote` (local KV is empty and lies); `wrangler tail` silently drops/reconnects.

## 8. Known limits & sharp edges (the can't-do list)

- **No per-minute lock-screen clock pushes** (scale decision — widget mm:ss stands).
- **Force-quit devices are unreachable** for token upload — Apple constraint, uncoverable.
- iOS may throttle/budget push-to-start for spammy apps — space out test starts; don't hammer.
- `stale-date` 8h on start (card grays if the match never goes live). END dismissal: the real cron
  OMITS `dismissal-date` → the FT card lingers on the lock screen up to **Apple's ~4h cap** (dates
  further out are ignored — "stays forever" doesn't exist), user-dismissable anytime (owner request
  2026-07-05). The 15-min quick dismiss survives only on /test-activity so test cards self-clean.
- A start push can arrive on a device whose app was updated in between — tokens survive an app
  UPDATE but NOT a reinstall (Keychain device_id survives; the APNs tokens rotate → per-device
  replace keying handles it; the "Allow" prompt resets on reinstall).
- APNs stores pushes for offline devices and may deliver LATE (no `apns-expiration` set) — old
  imageUrls must keep resolving (the watcher 302s `/card/*` → `nwslapp-card` permanently).
- Two-phone household ≠ one test: each device independently needs sign-in, Allow, current tokens.

## 9. Incident history (why each rule above exists — dates are receipts)

- **6/30:** first device run — service_role grants missing (42501); background token path built
  (#104 → build 21 background-task assertion + retry after the unprotected-Task kill diagnosis).
- **7/1:** render proven on both phones — WITH an alert on the start. Alert then removed per Apple
  docs ("optional") — the silent variant was never device-verified. Widget crest blanking → PNG.
- **7/3:** real games: V1 delivered, V2 never rendered — diagnosed as zombie-token accumulation
  (real, fixed: per-device keying build 23 + watcher prune-on-reject). Silent-start problem hid
  beneath it. Kickoff guard 120→600.
- **7/4 (day):** build 23 verified tokens register (register-on-open); real game: `LA start 1/1`,
  `snapshot=0` — no card despite perfect tokens.
- **7/4 (night):** controlled A/B → THE RENDER LAW (§3). Quiet-banner fix shipped to the cron
  (watcher `33dc59c`); CLAUDE.md gotcha corrected; `sound: ""` proven buzz-free.
- **7/5 (early am):** pure-V2 alert run (real NC vs SEA timeline) → UPDATE alerts buzz
  (kickoff/goals/HT), END alerts ignored → "V2-only" formally rejected, hybrid settled. FT card
  linger → 4h system default (cron drops dismissal-date). V1 redesign shipped (`ff93096`):
  title+subtitle copy system + square crest attachments, dark-blob thumbnails dead.

---
*Update this file the moment a new V2 fact is device-proven — this manual exists because these facts
were re-purchased three separate times. Pointer lives in CLAUDE.md (Deeper context) + memory.*
