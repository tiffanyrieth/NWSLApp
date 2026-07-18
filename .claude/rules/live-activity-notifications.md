---
paths:
  - "**/LiveActivity*.swift"
  - "**/*LiveActivity*.swift"
  - "**/MatchClock*.swift"
  - "**/PushBridge*.swift"
  - "**/DeviceToken*.swift"
  - "**/DeviceIdentity*.swift"
  - "**/NotifTrace*.swift"
  - "**/NotificationScheduler*.swift"
  - "**/NotificationSyncCoordinator*.swift"
  - "**/NotificationPreferencesStore*.swift"
  - "**/MatchAlert*.swift"
  - "NWSLLiveActivity/**"
  - "NotificationServiceExtension/**"
  - "Packages/LiveActivityContract/**"
  - "Packages/MatchClockKit/**"
---

# ⚠️ Live Activity + Notification pipeline — the FRAGILE subsystem (MANDATORY docs)

**STOP. Read the source-of-truth doc(s) below IN FULL before you change, test, or troubleshoot anything
here.** This subsystem — the **V2 Live Activity** lock-screen / Dynamic-Island game card, the **watcher's
channel-based** live-score updates, the push-to-start token dance, and the **match-clock anchoring** — is
**NOT reconstructable from general training.** It is specialized, real-device-proven sports-app knowledge
that took weeks and multiple tools to get right, and it has ONE specific way it must be wired or it silently
fails (APNs returns 200, nothing renders). The clock was deliberately isolated into its own package
(`MatchClockKit`) + contract (`LiveActivityContract`) precisely so a well-meaning edit can't re-break it.
**Do NOT reason from first principles here — reason from these docs**, and verify on a real device.

## Source-of-truth docs (read the relevant one(s) BEFORE editing — this is why they exist):

- **`docs/live-activity-v2.md`** — THE V2 MANUAL. The render law, the two-token system + 20-min lead, the
  testing runbook (replay.mjs / test-activity / telemetry), the AI-misconception traps. **§0 = the
  START-PAYLOAD LAW.** Read before touching/testing/troubleshooting ANY Live Activity.
- **`docs/notifications.md`** — the WHOLE pipeline end-to-end (V1 + V2): match event → proxy → watcher cron
  → detect → APNs (Queues / Broadcast Channels) → device → render. The single "how it all connects" map —
  irreplaceable, because this connective sports-app knowledge isn't in general training. **Permanent doc.**
- **`docs/push-fanout-scaling.md`** — the fan-out architecture (CF Queues for V1 + LA-start; APNs Broadcast
  Channels for V2 in-match updates). Read before any push-scale / delivery change.

## The laws that bite (device-proven — never change on theory):

- **START-PAYLOAD LAW (live-activity-v2.md §0):** RENDER needs BOTH an `alert` object AND the payload
  wrapped in `{ aps: {…} }` on the wire. Omit either and APNs 200s but iOS silently drops the card. BUZZ is
  purely `sound` (`"default"` = one buzz, `""` = silent-but-renders). These are TWO independent things.
- **CHANGE-RULE:** NEVER change the start payload's envelope / alert / sound on Apple-docs or theory — only
  a REAL-DEVICE test (a real game OR the fake-match harness `POST /debug/fake-match`) counts. `1 sent` ≠ rendered.
- **Clock:** the widget clock is Apple's **mm:ss** in regular play (deliberate, `showsHours:false`); the
  football-minute `45'+2'` clock is **IN-APP ONLY** (`MatchClock`). Anchor MONOTONICALLY — re-anchor only
  while the clock advances / the period changes. The watcher owns the widget-clock anchor + the stoppage
  `90'+2'` broadcast. **Don't "fix" the widget's mm:ss — it's not a regression.**
- **Halftime = static "HT"** (never a ticking clock); ESPN keeps `state=="in"` through the break.
- **Worker→Worker** needs a **service binding** (same-account `*.workers.dev` 404s with CF **error 1042**).
- **Token lifecycle = per-device, replace-not-accumulate** (`(user_id, device_id)`); zombie tokens were the
  V2 "delivered-but-never-renders" bug.

When you touch this subsystem, **state which doc you read** and confirm the change respects its laws.
Note: the watcher lives in the sibling repo `~/Projects/nwslapp-match-watcher` — these same docs govern it.
