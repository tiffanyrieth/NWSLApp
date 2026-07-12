# Live Activity V2 — The Manual

The complete how-it-works + how-to-operate reference for NWSLApp's V2 Live Activity (lock-screen +
Dynamic Island live match card). **Read this BEFORE touching, testing, or troubleshooting anything V2.**
Every claim here is device-proven (dates noted) — several directly contradict Apple's docs and common
AI/LLM assumptions. When in doubt, trust this file over intuition.

---

## 0. ⛔ THE START-PAYLOAD LAW (LOCKED — device-proven 2026-07-11) — read this first, it supersedes §3/§6 conflations

**The V2 start push has TWO INDEPENDENT requirements. Conflating them cost ~10 debugging cycles and
multiple weekends. Never reason about one as if it were the other.**

**(1) RENDER — does the card appear at all?** Needs BOTH, together:
  - **(a) an `alert` object** in the payload — no alert ⇒ APNs returns 200 but iOS silently drops it
    (the render law, device-proven 7/4); AND
  - **(b) the payload wrapped in `{ "aps": { … } }`** on the wire. `buildStartAps` returns the *contents*
    of `aps`; the sender MUST wrap it. The inline path (`postLiveActivity`, `JSON.stringify({ aps })`)
    and V1 (`toPayload` returns `{aps,…}`) do. **The 7/9 Queues redesign moved la-start to
    `enqueueLaStart` and stored the CONTENTS unwrapped → every queued start went out with NO `aps`
    envelope → APNs 200 (`1 sent`) but iOS silently dropped it. THIS was the 7/10 total no-show on
    three real games — NOT the sound.** Fixed 2026-07-11: `payload: { aps: buildStartAps(...) }`.

**(2) BUZZ — does it vibrate on arrival?** Purely the `sound` value, and ONLY affects the buzz, never
  whether it renders:
  - `sound: "default"` → renders + **one arrival buzz** ← **SHIPPED (owner wants the arrival buzz).**
  - `sound: ""` → renders but **SILENT** (device-verified 7/11 — a correctly-wrapped `""` start lands
    with no buzz). *This corrects §3/§6/§6b's "`sound:""` is flaky / never presents" claims: those
    real-game failures were the missing `{aps}` envelope (1b), misattributed to the sound.*

Updates + end pushes carry **NO alert** → silent (the Athletic pattern). Only the START buzzes.

**THE PROVEN-GOOD START PAYLOAD (device-verified via the fake-match harness, 2026-07-11):**
```jsonc
{ "aps": {
    "event": "start", "attributes-type": "…", "attributes": {…}, "content-state": {…},
    "input-push-channel": "<channelId>",        // iOS-18 broadcast subscribe — at aps ROOT, NOT in alert
    "stale-date": …, "relevance-score": 100,
    "alert": { "title": "…", "body": "…", "sound": "default" }   // alert REQUIRED; sound = arrival buzz
} }
```

**🔒 THE CHANGE RULE (this is why it keeps breaking — enforce it):** NEVER change the start payload's
**envelope, alert, or sound** on the strength of Apple's docs, a Reddit thread, or any theory. Apple's
docs said "alert is optional" — the device said otherwise, and that mistake recurred for weeks. A change
to this payload is valid **only after a REAL-DEVICE test proves it renders + buzzes** — either a real
game OR the fake-match harness (§7). **"APNs 1 sent" ≠ rendered; only a card on a physical phone counts.**

**VERIFICATION TOOL — the fake-match harness (built 2026-07-11):** `POST /debug/fake-match` (secret-gated)
writes a KV flag that the cron discovers and runs through the FULL organic path (kickoff-window gate →
`startTokensForTeams` preference gate → Queue enqueue → consumer drain → APNs → device) — the ONLY
on-demand way to test the queue path (`/test-activity` uses the inline send and can't reproduce a
queue-path bug). Brother-safe via the real preference gate (pick teams they don't follow). Runbook in §7.

**HARDENING TODO (prevent recurrence structurally):** make `buildStartAps` return the FULL `{ aps: … }`
payload so there is exactly one representation and the wrap/unwrap mismatch is impossible; add a pinning
unit test asserting the enqueued la-start payload has a top-level `aps` key + `aps.alert.sound=="default"`.

---

## 1. What V2 is (and how it splits from V1)

Two independent notification layers ride the same watcher + `.p8` APNs key:

| | V1 — rich push | V2 — Live Activity |
|---|---|---|
| Surface | Notification banner + Notification Center | Persistent lock-screen card + Dynamic Island |
| Role | **The interrupt** — buzzes for kickoff/goal/HT/FT/lineups per the user's toggles | **The quiet glance** — a live scoreboard that sits on the lock screen for the whole match |
| Renders | Text + a server-rendered PNG card (`nwslapp-card` worker `/card`, attached by the NSE) | **Native SwiftUI** drawn ON-DEVICE by the widget target (`NWSLLiveActivity/MatchLiveActivity.swift`) from pushed JSON state |
| Sound | Yes (per toggle; `interruption-level: time-sensitive`) | **Buzzes ONCE on arrival** (`sound: "default"` on the start), then SILENT — updates/end are alert-less (§3 arrival-buzz law) |
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

## 3. ⚠️ THE RENDER LAW + THE ARRIVAL-BUZZ LAW — what it takes for a card to actually appear

**Part 1 — the alert object is REQUIRED (device-proven 2026-07-04):** a push-to-start WITHOUT an
`alert` object **NEVER renders**. APNs returns 200, the watcher logs `1/1 ok`, and iOS silently drops it.

**Part 2 — THE ARRIVAL-BUZZ LAW (corrected 2026-07-09 against the 7/5 A/B logs — supersedes the earlier
"`sound:""` renders buzz-free" claim, which was OVERFIT):** a start with **`sound: ""` (fully silent) is
UNRELIABLE — on real games it OFTEN NEVER PRESENTS.** The A/B is unambiguous in the owner's own words:
silent → *"does not show up on my phone"*; sounded → *"went straight to my lock screen"* (7/5 03:35–03:40).
The old clean claim was built on ONE controlled A/B moment + an ambiguous 11:41 "organic" render where a
V1 lineup buzz co-occurred with the card's arrival (the buzz she felt was likely V1's, not proof the
silent card self-presented).

| Start payload | Result |
|---|---|
| No `alert` | ❌ Never renders (delivered-but-invisible; looks like success server-side) |
| `alert: {…, sound: ""}` (fully silent) | ⚠️ **FLAKY — often never presents on real games.** Renders *sometimes* in a manual test (flaky-positive), which is exactly the trap that burned us repeatedly (Fri/Sat live games failed, tests "passed"). **Do NOT ship.** |
| `alert: {…, sound: "default"}` (buzz once) | ✅ Renders reliably + a single arrival buzz ← **shipped design (2026-07-09)** |

**Likely WHY (owner's hypothesis — reasoned, not Apple-documented):** a Live Activity is a **persistent,
power-drawing lock-screen surface**, so iOS appears to enforce a **one-time arrival announcement** (a buzz)
the first time the card appears — a privacy/awareness guarantee that the user knows *something just parked
itself on their lock screen*. After that first announcement, **silent updates are honored**. This matches
other apps' V2 cards (The Athletic buzzes once on arrival, silent after). The BEHAVIOR is device-proven;
the RATIONALE is a strong hypothesis.

**Shipped design = BUZZ-ONCE:** START carries `alert` + `sound: "default"` (one buzz on arrival); every
UPDATE and END is alert-less/SILENT (that works fine — the law is START-only). V1 still owns the
per-event interrupts; V2's single arrival buzz is the Athletic pattern.

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

- During **regular play (1'–90')** the watcher does NOT push every minute (per-minute fan-out for the
  whole match is ~90× waste). Each content-state carries **`clockStartEpoch` = now − elapsed** (a
  "virtual kickoff") and the WIDGET advances the clock locally (Apple's `Text(timerInterval:)`) between
  pushes, in **mm:ss** with **`showsHours:false`** (so the 68th minute reads `68:12`, not `1:08:12`).
  The true football minute ("45'+2'") still ticks IN-APP only (`MatchClock` + TimelineView). Don't
  "fix" the widget's mm:ss for regular play — that's a settled scale decision.
- ⚠️ **SUPERSEDED FOR STOPPAGE ONLY (build 26, 2026-07-11):** in **added time** the widget DOES show
  the football label. Apple's timer can't format `90'+2'`, and once Broadcast Channels shipped (7/9) a
  per-minute push became cheap (ONE POST/channel, follower-independent, only ~2–8 min/match). So the
  watcher computes **`stoppageDisplay`** from the monotonic anchor (`stoppageLabel`, mirrors
  `MatchClock.minuteLabel`) and broadcasts it each minute past the cap; the widget renders it verbatim
  instead of the mm:ss timer. `nil` during 1'–90' → widget falls back to the local clock. **Widget
  render is device-verify PENDING build 26** (watcher half deployed; drive it via the fake-match harness
  into a frozen-cap window + watch Apple's broadcast throttle — `1 sent` ≠ rendered).
- Drift is corrected by a resync push at every real event, on the ~10-min floor (`LA_RESYNC_MS`), on a
  **stoppage-label rollover**, AND — new 2026-07-11 — the instant the anchor (`clockStartEpoch`) jumps
  **≥30 s** (`LA_DRIFT_RESYNC_SEC`). The anchor is stable during smooth play but lurches at each half's
  late live-flip; without the drift trigger the card sat behind for up to 10 min at the start of BOTH
  halves (owner-observed). Zero extra pushes during smooth play. Deployed; real-game verify pending.
- Phase changes come from the watcher diffing the scoreboard each cron minute: kickoff / goals /
  halftime (`staticLabel: "HT"`) / full-time (`"FT"` + END push; no dismissal-date → ~4h linger).
- ⚠️ **ESPN FREEZES `status.clock` at 45:00/90:00 through stoppage time** (observed live 7/4).
  Any clock that re-anchors `now − clock` per poll/push therefore PINS at `+1'` (app) or snaps
  back to 45:00 (widget). THE RULE: anchors must be MONOTONIC — re-anchor only when the clock
  ADVANCES or the period changes. Implemented 7/5 in `MatchStore.reconciledTickAnchors` (app,
  unit-tested) and `StoredState.virtualKickoff` (watcher → `contentStateFromMatch`).
- ⚠️ **ESPN advances `period` → 2 at the START of the halftime break** (observed live 7/5; `state`
  stays `"in"`, clock frozen at 2700). So "period changed" alone is NOT the second-half restart. The
  watcher's original anchor rule re-based on that break-start period flip and its `Math.min` guard
  then pinned the anchor there — the ~15-min break leaked into `clockStartEpoch` and the widget read
  **1:31 at the 31st minute of the second half** (the 7/5 live bug). THE RULE: reconcile the anchor
  ONLY while the clock is RUNNING (`clockRunning` in watcher `events.ts` — in-progress and not
  HALFTIME/SHOOTOUT); a pause leaves the anchor untouched, so the period re-base fires at the real
  restart and absorbs the break (regression-locked in watcher `test/clock.test.ts`, watcher PR #20).
  NOTE: `replay.mjs`/`/test-activity` bypass `nextState` and re-anchor from the passed minute — a
  replay CANNOT reproduce this class of bug; only a real game (or the unit tests) exercises it.
- End-to-end latency: the cron floor is 1 min, but during a live window the tick **double-polls**
  (poll → sleep 30 s → poll again cache-busted, shipped 2026-07-11), so with the proxy's 30s live TTL an
  event reaches phones ≤ ~30–60s after ESPN reflects it (was ~90s).

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
  "attributes-type": "MatchActivityAttributes", attributes: {matchId, homeAbbr, awayAbbr, competition,
  isNational?}, "content-state": {...}, "stale-date": now+8h, "relevance-score": 100,
  alert: {title: "WAS vs HOU", body, sound: "default"}, "input-push-channel"?: <id> }` ← alert REQUIRED
  and `sound: "default"` (buzz once) REQUIRED for reliable presentation (§3). `input-push-channel`
  (iOS 18) subscribes the created Activity to the match's broadcast channel for all later updates.
- **UPDATE** (to per-Activity token): same minus attributes/alert; `event: "update"`, stale-date +1h.
- **END**: `event: "end"`, final content-state, `dismissal-date` = FT + ~15 min (card lingers, then goes).
- **content-state keys MUST byte-match the Swift struct** (`Shared/MatchActivityAttributes.swift`
  `ContentState`): `homeScore` `awayScore` `phase` (`pre|live|halftime|extraTime|penalties|fulltime`)
  `clockStartEpoch?` `staticLabel?` (+ `lastScorer?`, `broadcast?`, and the per-side detail added
  2026-07-06: `homeScorers?`/`awayScorers?` [string[], chronological "C. Hutton 5'" lines, watcher-
  capped 4/side with a "+N more" 4th] + `homeRedCards?`/`awayRedCards?` [ints, REDS only, omitted at
  0] + `stoppageDisplay?` [string "90'+2'", set 2026-07-11 ONLY in added time — the widget renders it
  instead of the mm:ss timer; omitted during 1'–90']). A mismatched/extra-typed key = silent decode drop on-device. `compact()` strips nulls so
  optionals are OMITTED, never null. New keys are additive-optional BOTH ways: old app builds ignore
  unknown keys (synthesized Codable), and the Swift fields are Optional so old payloads decode —
  `lastScorer` stays as the old builds' fallback line.

Who gets a START: users with match alerts ON for a participating team (`team_alert_preferences`) AND
`notification_preferences.live_activities_enabled = true` AND a registered start token. KV-deduped
per match (`la-start:{matchId}`); fires on the first cron tick inside kickoff−20min.

⚠️ **UPDATES NOW BROADCAST (2026-07-09, `docs/push-fanout-scaling.md`).** The watcher no longer sends
per-Activity-token UPDATE/END pushes. Instead it creates a **broadcast channel per match**, the start
payload's `input-push-channel` subscribes each Activity to it (iOS 18, OS-level — no app code), and every
in-match update is **ONE broadcast POST** to the channel (Apple fans out). The `live_activities`
per-Activity token table + app upload still exist (harmless) but the cron ignores them. This
**structurally kills the old "per-Activity token lag → real-game updates silently missed" failure**
(the likely Fri/Sat-2026-07 killer): the channel doesn't wait on a per-device token. iOS <18 devices
can't subscribe to channels → they get V1 only (graceful degradation; app gates the start-token
registration to iOS 18+).

## 6b. ⚠️ What a SCRIPT test proves vs. what only a REAL GAME proves (the lesson that cost us weekends)

Tests passed; then weekend live games failed — repeatedly (Fri/Sat failed, Sun finally worked). Why the
gap, and what to trust:

- **Same between test route & real cron:** identical `startLiveActivity` / APNs payload (alert, sound,
  content-state). So **payload-behavior findings DO transfer** (e.g. silent-vs-sounded rendering — §3).
- **A script test does NOT prove:** (1) **the START's real-world reliability** — a `sound:""` start
  renders *sometimes* in a manual test (flaky-positive), so a passing test is NOT evidence a real game
  will present; (2) **preference gating** — the test routes fan to *all* tokens (`allStartTokens`), the
  cron gates on `team_alert_preferences ∩ live_activities_enabled ∩ start token`; (3) the **≤20-min
  timing window + KV dedup**; (4) the **queue transport** (cron enqueues, test sends direct — same
  payload, different path); (5) **environment** — a USB/debug build's SANDBOX token is unreachable by the
  production cron (test routes use `sandbox:true`; real games need a TestFlight/production token).
- **RULE: never declare the V2 START "done" off a script test.** The start's flakiness only surfaces
  under real conditions. Buzz-once (§3) is the mitigation; **a real live game is the only proof.** The
  broadcast change makes UPDATE coverage representative, but the START still needs a real game to trust.

## 7. Testing runbook (the exact recipes)

**⚠️ THE SIMULATOR PRESENTS LIVE ACTIVITIES *NOT AT ALL* — device-only, full stop.** This is
stronger than "can't receive push," and it's an AI-trap that has cost time (re-confirmed 2026-07-06
on Xcode 27 / Device Hub): a LOCAL `Activity.request` — the DEBUG `-driveLiveActivity` driver, no
push involved — DOES start (you'll see `liveActivityTrace activityUpdate match=… state=active` in the
trace), but iOS renders **nothing** in the sim: no lock-screen banner, no Dynamic Island, nothing to
`simctl io screenshot`. So do NOT try to eyeball the widget layout (scorers, red-card rects, pre-match
island, clock) in the simulator — there is no surface to capture. An earlier note that the driver
"drives the widget UI in-sim" was WRONG. What the DEBUG driver IS good for: exercising the
state-transition CODE and confirming the app compiles + starts/updates/ends an Activity without
crashing (watch the trace). The VISUAL is verified only on a TestFlight/real-device build — same as
push, delivery, and the render law. All V2 testing that involves seeing pixels is real-device.

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
  ⚠️ **`replay.mjs` uses `/test-activity` = the INLINE send. It CANNOT reproduce a queue-path bug** (it
  wraps the payload correctly regardless). It proves presentation, not the organic delivery path.
- **`POST /debug/fake-match` — the FAKE-MATCH HARNESS (built 2026-07-11): the ONLY on-demand test of the
  full ORGANIC path** (cron discovers → gate → **Queue → consumer** → APNs → device). Writes a KV flag
  (`debug:fake-match`) that `runWatch`'s `readFakeMatch` injects into the LA-start pass ONLY (never V1/
  lineup). Body `{minutes?=5, homeId?=18206(ORL), homeAbbr?, awayId?=15360(CHI), awayAbbr?}` or
  `{clear:true}`. Brother-safe by the real preference gate — pick teams your test device follows and the
  other doesn't. Recipe: (1) confirm the test device has that team's alerts ON + Live Activities ON +
  app opened once (fresh start token); (2) fire it; (3) watch `enqueued LA start … → drained …: 1 sent`
  in `wrangler tail` AND the card+buzz on the phone. Set it directly (no secret) via wrangler:
  ```bash
  # kickoff 4 min out (inside the 20-min window ⇒ fires on the next cron tick):
  echo '{"id":"fakematch-'$(date +%s000)'","date":"<ISO now+4min>","homeId":"18206","homeAbbr":"ORL","awayId":"15360","awayAbbr":"CHI"}' \
    | npx wrangler kv key put "debug:fake-match" --namespace-id <MATCH_STATE ns> --remote --ttl 900 --path /dev/stdin
  # cleanup after: delete debug:fake-match + any la-start:fakematch-* / la-chan:fakematch-* keys.
  ```
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

- **No per-minute clock pushes DURING REGULAR PLAY** (widget mm:ss self-ticks, `showsHours:false`). The
  ONE exception (build 26): **added time** DOES push a `stoppageDisplay` "90'+2'" each minute — bounded
  ~2–8 min/match, ONE broadcast/channel (follower-independent), so it's cheap. Full-match per-minute
  pushes are still out.
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
- **7/10–7/11 — THE BIG ONE (see §0):** on three real 8pm games the organic cron fired every start
  (`enqueued → drained: 1 sent`) but **NO card appeared on any device.** Chased the sound for hours
  (owner right that it wasn't broadcast/throttle). Root cause found by code diff: **`enqueueLaStart`
  stored `buildStartAps(...)` UNWRAPPED — the queue path sent the payload with no `{aps}` envelope**, so
  APNs 200'd and iOS silently dropped it. The 7/9 Queues redesign introduced it; V1 was unaffected
  (`toPayload` already wraps). Fix = `payload: { aps: buildStartAps(...) }`. **Device-verified 7/11 via
  the new fake-match harness (§7)** on the full organic path: `sound:""` renders SILENT, `sound:"default"`
  renders + buzzes once → shipped `"default"`. Correction to §3/§6/§6b: the "`sound:""` is flaky / never
  presents" claim was **misattributed — it was the envelope, not the sound.** THE §0 PAYLOAD LAW + the
  change-rule exist because of this incident.
- **7/9:** push fan-out redesign SHIPPED (V1 + LA-start → Cloudflare Queues; V2 in-match → APNs
  **Broadcast Channels**, channel-per-match) + USWNT V2 (flag render, national colors) — all device-proven
  via `/test-broadcast`. AND the manual's `sound:""` "renders buzz-free" claim was **corrected against the
  7/5 A/B logs** (it was overfit to one moment + an ambiguous organic render): fully-silent start is
  FLAKY on real games → **buzz-once** (`sound: "default"`) shipped as the reliable design (arrival-buzz
  law §3), UPDATE/END stay silent. The "tests pass, weekends fail" lesson recorded in §6b.
- **7/11 (night) — real games Spirit + Angel City:** V2 card **DEVICE-PROVEN CORRECT** end-to-end on
  live games (both goals, NC goal + VAR no-goal disallow + revert, clean FT; push-to-start on time for
  the 2nd game while the 1st was live). Two clock issues surfaced + fixed (device-verify PENDING build 26):
  (a) widget rolled to `1:08` at the 60th min → `showsHours:false`; (b) card ran behind for ~10 min at
  each half start (only re-anchored on the 10-min floor) → **drift-triggered resync** on a ≥30s anchor
  jump (deployed). Also owner-approved: **stoppage `90'+N'` on the widget** via a per-minute broadcast in
  added time (watcher deployed, widget build 26) — the old "never push per-minute" rule now yields for
  stoppage only (Broadcast Channels made it cheap). SEPARATELY (NOT a V2 bug — the app's own screen): the
  in-app clock/score stuck all game because **ESPN's full-season scoreboard query serves 25–47 min stale
  live state** — fixed proxy-side (upstream `_cb` bust, deployed) + app windowed poll (build 26). The
  in-app monotonic stoppage clock itself was proven CORRECT live (`90'+1'`→`90'+7'`→FT).

---
*Update this file the moment a new V2 fact is device-proven — this manual exists because these facts
were re-purchased three separate times. Pointer lives in CLAUDE.md (Deeper context) + memory.*
