# NWSLApp — Project Context for Claude

A one-page cheat sheet of rules/conventions/commands/gotchas for every session. Detailed and
feature-specific context lives in `docs/` + `.claude/rules/` and loads **on demand** (see
**Deeper context** at the bottom) — keep this file lean.

## ⚠️ What this app is — read first

A women's soccer (NWSL) **fandom** app: follow your clubs, keep up with soccer voices (reporters,
club + player social), play/share Fan Zone games (Bracket Battle, Predict the XI, Daily Trivia),
and check scores/schedule/standings. The **fandom** — community, the games, social sharing,
live/"alive" content, personal connection — **is the product.** Scores/schedule/standings are
table stakes that must work but are **not** the differentiator.

- **Anti-pattern (matters):** don't shrink the fandom side into a stats-app (ESPN/March-Madness)
  mold. When a design emphasizes fandom/social/playful content, **build it that way** — don't trim it.
- **Litmus test:** "Would I open this today if I opened it yesterday?" A surface that looks identical
  because the data is static is a bug — the app is built to feel alive.
- **Priority order:** (1) **ALIVE** features (live content pipelines + fan engagement) → (2) **core**
  (scores/schedule/standings/stats — must work, not the differentiator) → (3) **hardening**
  (bugs/tests/robustness). Never put 3 above 1.
- **Owner:** Tiffany Rieth. Personal project → production-quality iOS skills + a real App Store app.

## State

Production-quality **v0.4.2**, used daily. **Online-only: NO demo/seed/fake data in the running app**
— every surface shows live data or an honest "Couldn't load — tap to retry" (seed/fixtures live only
in previews + tests). Treat it as a real product; never suggest a demo/placeholder mode.

## Stack

Swift 5.9+ / SwiftUI (not UIKit), min iOS 17.2 (`@Observable`; 17.2 = Live Activity push-to-start), Xcode 27.0 beta 2. `URLSession` + async/await,
no third-party HTTP. UserDefaults (small local state) + **Supabase** (Postgres, durable per-user once
signed in); SwiftData nowhere. Sign in with Apple → Supabase (Apple auth + RLS). The **only**
third-party dep is `supabase-swift` (SPM). Testing = **Swift Testing** (`@Test`/`#expect`), not XCTest.
Secrets in gitignored `Config/Secrets.swift` (anon key is public — RLS is the real boundary).

## Commands

```bash
# Build (Debug) for a booted simulator
xcodebuild build -scheme NWSLApp -destination 'platform=iOS Simulator,id=<SIM_ID>' -configuration Debug
# Unit tests
xcodebuild test -scheme NWSLApp -destination 'platform=iOS Simulator,id=<SIM_ID>' -only-testing:NWSLAppTests
xcrun simctl list devices booted                                   # find the booted sim id
xcrun simctl install <SIM_ID> <NWSLApp.app>
xcrun simctl launch  <SIM_ID> com.tiffanyrieth.nwslapp.NWSLApp
```
DEBUG args: `-resetOnboarding`, `-useESPNDirect`, `-startTab <home|schedule|standings|teams|feed>`.
Decode-only tests read `NWSLAppTests/Fixtures/*.json` via `#filePath`. **Driving the sim:** `idb` is
installed — start `idb_companion --udid <SIM>`, then `idb ui tap <x> <y>` (DEVICE points) + `idb ui
describe-all` (element frames + a11y labels — exact for locating/measuring UI) are the reliable way to
tap SwiftUI and verify layout. cliclick is fine for SCROLL drags + UIKit hit targets, but its synthetic
clicks get SWALLOWED by SwiftUI buttons inside a nested horizontal-scroll (e.g. a chip in the pinned
Club News header) — don't trust it there. DEBUG deep-link/launch-arg scaffolds remain a fallback.

## Architecture (MVVM, strict separation)

`Models/` (Codable, no UI/net) · `Services/` (API clients, no UI) · `ViewModels/` (`@Observable`,
state-enum `idle`/`loading`/`loaded`/`error`) · `Stores/` (`@Observable` shared state → UserDefaults,
injected via `.environment`, one-fetch-many-readers) · `Views/` (one screen per file, minimal logic) ·
`Components/` (reusable) · `DesignSystem/` (`DSColor`/`DSMetrics`/`DSText` tokens, dark-only). Prefer
`@Observable` over `ObservableObject`. Folders are created when their first real file lands.

## Data sources (essentials — full detail in `docs/backend.md`)

ESPN's unofficial NWSL endpoints (base in `Config/AppConfig.swift`) — **decode defensively**: scores
are `String` not `Int`, scoreboard needs `&limit=500` for a full season, standings sit on a different
base, endpoints break/rate-limit without notice. Most traffic routes through the **`nwslapp-proxy`
Cloudflare Worker** (sibling repo `~/Projects/nwslapp-proxy`); DEBUG `-useESPNDirect` bypasses it.
**Roster** routes through the proxy's `/roster` too (last-known-good KV: ESPN intermittently serves an
implausibly small squad — e.g. 1 player — so the proxy caches a plausible roster and serves it with a
`proxyCachedAsOf` marker → app shows a "Roster as of …" note; teams/standings still hit ESPN directly).
**Kickoff weather** routes through the proxy's `/weather?event={id}` too — a PAST match's kickoff-hour
temperature + sky condition from **Open-Meteo** (free, no key; ESPN carries NO NWSL weather). Keyed by a
static **ESPN-venue-id**→lat/lon table (id-keyed so a rename can't silently break it), the exact kickoff
HOUR (not the daily high), **cached write-once in KV** (a finished match's weather is immutable → lazy
backfill covers all history, no cron/watcher); night-aware via `is_day` (sun/moon icon). PAST-ONLY;
envelope versioned for a later forecast mode. Shows as a quiet stamp under the MatchDetail header.
**Tier-2 server push** (live match alerts) is a SECOND sibling Worker, **`nwslapp-match-watcher`**
(`~/Projects/nwslapp-match-watcher`): a `* * * * *` cron that diffs the proxy scoreboard (reached via a
**service binding** — same-account Worker→Worker over `*.workers.dev` 404s with CF **error 1042**, so a
public fetch silently fails; the rich-card crest fetch uses the same binding) for
kickoff/goal/halftime/full-time + **lineup-posted** (polls `/summary` in a 75-min pre-kickoff window) +
**VAR goal-correction** (a debounced score *decrease* — re-poll a
cache-busted scoreboard before firing, so an ESPN glitch never sends a false "Goal Disallowed"), looks
up `device_tokens` of users with that alert on, and sends APNs
(ES256 `.p8` JWT). Deployed; `POST /test-push` (`x-trigger-secret`) sends a synthetic push for
on-device E2E (`APNS_HOST` is production). A **V2 Live Activity** layer (lock-screen + Dynamic Island live
score) rides the SAME watcher + `.p8`, ADDITIVE to V1 — but the roles split: **V1 is the interrupt (buzzes
kickoff/goal/HT/FT per the user's toggles); V2 is a QUIET glance.** ⚠️ Gotcha (device-proven 2026-07-04,
contradicts Apple's docs): the push-to-start **`alert` is REQUIRED to render** — omit it and APNs 200s but
iOS NEVER presents the card (this shipped invisible Activities on every real game). The buzz-free shape is
`alert` **+ `sound: ""`** (card + quiet banner, no sound/vibration; omitting the sound key still BUZZES).
Updates/end stay alert-less. Also: iOS shows a one-time per-app "Allow Live Activities?" prompt with the
app's FIRST presented Activity (a reinstall resets it). Push-to-
start fires **≤20 min pre-kickoff** (a device can take minutes to register its per-Activity token) + a
catch-up push for late tokens. `POST /test-activity` + `scripts/replay.mjs` drive it; app `LiveActivityManager`
mirrors push-to-start/per-Activity tokens under a UIKit background-task assertion (background-launch upload);
detail in `docs/backend.md`. The app side: `registerForRemoteNotifications` → AppDelegate →
`PushBridge` → `DeviceTokenService` upserts `device_tokens` (per-team toggles in `team_alert_preferences`).
**Register on EVERY open (canonical Apple pattern — NOT gated on a toggle):** `registerForRemoteNotifications`
fires on cold launch + every foreground (`scenePhase .active`); a signed-in user whose iOS permission was
reset (reinstall) but who has any alert on is auto-re-prompted then registered (denied → honest surface, never
a silent "alerts on but no token"). The OLD gate — register only if already `.authorized`, permission requested
only by a bell toggle — left opt-in/reinstalled users with an EMPTY `device_tokens` (no token ⇒ no pushes at
all). Upsert is guarded (writes only on token change); `didFailToRegister` → Diagnostics (never a bare print).
**Token lifecycle = PER-DEVICE, replace-not-accumulate:** every APNs token table (`device_tokens`,
`live_activity_start_tokens`) keys on **`(user_id, device_id)`**, `device_id` = a Keychain-stable per-device
UUID (`DeviceIdentity.swift`, survives reinstall). So each device keeps ONE current token (a rotation
replaces it in place; the same user on two devices = two rows), instead of piling up a dead token per
reinstall/rotation. The watcher ALSO self-prunes — a send returning `410 Unregistered`/`400 BadDeviceToken`
deletes that token (`pruneDeadTokens`). This accumulation of zombie tokens (the old `(user_id, token)`
keying) was the V2 Live-Activity "delivered-but-never-renders" bug; per-device + prune fixed it (build 23).
**Notifications = OPT-IN (owner rule — no dark patterns):** nothing auto-enables at onboarding/launch;
the user turns on exactly what they want. **Nuance (owner, match-alerts):** an EXPLICIT match-alert
bell tap IS the opt-in, so it CASCADES the full default bundle the first time (day-before + kickoff +
goals + halftime + full-time + lineups + Live Activities via `applyMatchAlertDefaultsIfFirstTime`) — a complete
feature makes the best first impression; a bell-on-nothing-fires state is the banned "silent failure
that looks like success." First-time only (a sentinel respects later manual edits; reset on sign-out).
Because the bundle is mostly Tier-2, a signed-out bell tap presents Sign in with Apple FIRST
(intercept: success → enable+cascade+toast, cancel → bell stays off). **Tier 1** = deliverable without
an account (local: day-before, Player Spotlight); **Tier 2** = watcher-triggered ⇒ needs an account ⇒
sign-in-gated (`tier2Binding` / the bell intercept) + reset on sign-out (`resetServerPushTypes`:
kickoff/goals/HT/FT + lineup-posted + V2 Live Activity). **Lineup-posted (Stage D, done):** the watcher polls
`/summary` (cache-busted via the proxy binding) in a 75-min pre-kickoff window and pushes "Lineups in" the tick
BOTH XIs are posted (≥11 starters/side, KV-deduped); the app shows the pre-match XI in `MatchDetailView`'s
future layout. UI groups kickoff+HT+FT under one "Match updates" toggle (grouping only — each still gates its
own column server-side). NEVER auto-enable a notification WITHOUT an explicit user
action. National-team alerts: bell keyed by FIFA code → `competition_alert_preferences` (separate from
the club-id `team_alert_preferences`); the watcher polls the 7 NT feeds + fans out by code.
Per-user state in **Supabase**, offline-first (UserDefaults cache). **Follows sync = RESTORE-ONLY launch
reconcile:** launch `reconcile` NEVER deletes a server row — a wiped/un-onboarded device restores the full
server set, and only local-only follows upload. **Unfollows propagate solely via the explicit per-toggle
`removeFollow`** (a signed-in unfollow), so no launch-time race can prune. (This replaced an earlier
device-authoritative mirror whose launch prune deleted rows under the reinstall onboarding race — the
"only the oldest follow survives" data-loss bug. A returning signed-in user is restored + skips onboarding;
`RootTabView` shows a brief "Restoring…" until reconcile resolves, never the picker.) **Trade-off:** a
signed-out/offline unfollow won't reach the server and reappears on reinstall — recoverable, and harmless
to alerts (alerts are a separate table + coordinator; follows ≠ alerts). Two devices diverging offline →
last writer wins (fine at current scale). **Gotcha (grants):** a new per-user table needs `grant … to
authenticated` or signed-in queries fail silently with `42501` (RLS ≠ privilege); **AND** any table a
**Worker reads/writes as `service_role`** — the watcher (`device_tokens`, `*_preferences`,
`team_alert_preferences`, `live_activity_*`) OR the proxy (`profiles`, for the SIWA `apple_refresh_token`)
— needs an explicit `grant … to service_role` too: default privileges don't cover it, and bypassing RLS
is NOT table privilege (this latent gap 42501'd the first real service_role read). The grant must match
the **operation**: the watcher's `pruneDeadTokens` DELETEs `device_tokens`, so a `select`-only grant
strands dead tokens — grant `select, delete`. And any secret the proxy signs into a JWT **raw** (SIWA
`APPLE_TEAM_ID`/`SIWA_KEY_ID`) must be whitespace-clean — a trailing newline signs a JWT Apple rejects
as `invalid_client`; set via **stdin, never copy-paste** (`printf '%s' … | wrangler secret put`).

## Workflow & engineering practices (requirements — flag the trade-off before bypassing)

- **Branch first, never `main`:** `feature/<desc>`; `git status` clean before starting; state what
  you'll touch. Local hooks (`hooks/`): `pre-commit` blocks commits to main, `pre-push` blocks
  force/delete of main (`--no-verify` bypasses; fresh clone runs `git config core.hooksPath hooks`).
- **Build to spec, not to minimum.** Design-doc numbers are requirements, not suggestions — no
  scaled-down versions. A feature isn't "shipped" until EVERY sub-item is automated + verified (no
  partial credit; a scaffold needing manual steps ≠ the feature). Don't reclassify work as "deferred."
- **Prove it live.** Verify with evidence (curl the proxy/REST, screenshot the sim, trace the code
  path) — never reason from an unverified assumption.
- **NO SILENT FAILURES (app-wide):** every unexpected condition (fallback/API-fail/stale/parse/retry/
  unexpected-empty) emits telemetry to the `Diagnostics` spine (os_log + `@Observable` ring, visible in
  dev/TestFlight). Fail LOUD to the engineer; fail HONESTLY to the user (degraded → subtle truthful
  indicator; blocked → clear message + retry). Banned: blank screens, infinite spinners, silent
  fallbacks indistinguishable from success — a failure must never look like success. Spans the proxy
  (`emitDiag` + a deploy-time health check that exits non-zero on any gap).
- **Plan for scope:** a change touching 3+ files or a new pattern → present a plan + get approval first.
  No new dependency without explaining why the built-in won't work + approval.
- **No force-unwraps (`!`)** unless a comment explains why it's safe. Temp architecture-bending code
  carries a `TEMP` comment (what/why/when-removed).
- **Before "done":** builds AND runs in the sim with no errors, **manually verified in-sim**
  (compiling ≠ working); update `docs/FILEMAP.md`; commit message `<Area>: <what changed>` (specific,
  present-tense); confirm before pushing (don't auto-push).
- **Build bump ⇒ consider the update gate (don't auto-couple).** On a TestFlight/App Store build bump,
  the forced-update gate's `minBuild` (proxy `/config`, `MIN_APP_BUILD`) is a manual FLOOR decoupled from
  the build number — it does NOT auto-track "latest". NEVER raise it on every bump (that force-updates
  every user) and NEVER to a build that isn't live+installable yet (walls users with nowhere to go).
  Raise it + redeploy ONLY to retire a broken/incompatible build, and ONLY after the newer build is
  available. Detail: `docs/versioning.md`.
- **Git:** **squash-merge** PRs (one commit on main; OK to combine related branches). Never commit
  secrets. Commits use the owner's GitHub no-reply email
  `286203575+tiffanyrieth@users.noreply.github.com`. CLAUDE.md / commits / PRs / comments stay
  neutral/professional — never reveal owner preferences; use arbitrary teams for examples.
- **`gh` auth expires mid-session:** `git push` keeps working but `gh` API calls (PR create/merge,
  `gh api`) fail `HTTP 401` → owner runs `gh auth refresh -h github.com`. A push that succeeds but a
  PR-merge that 401s is this, not a permissions problem.

## Collaboration

Doubles as a way to build durable iOS/SWE skills — understanding each change matters as much as
shipping it. Explain non-obvious decisions/trade-offs as you go; note why a new file/folder is
organized that way; briefly explain a pattern (MVVM, state enums, async/await, Codable) the first time
it appears. **If a request reflects a misunderstanding or would introduce bad practice, say so and
propose the better approach.** **Decision split:** the owner owns design/UX/product calls and defers
fine engineering logistics to Claude AFTER a reasoned explanation — explain-then-recommend, don't
over-ask on low-level forks, never guess product/cost calls. **Nothing is impossible:** never answer
"can we do X?" with "not possible / no API" — research the menu of paths + costs, let the owner decide.

## UI rules

- **Dark appearance app-wide**, no toggle (page `#1C1C1E`, cards `#2C2C2E`).
- Persistent UI (tab/nav bars) never obscures scrollable content (respect safe areas); every drilled-in
  view has an explicit back affordance (don't rely on edge-swipe alone); nav resets to root on tab tap.
- **Back button = bare ‹ chevron** (native iOS, MLS/Athletic-style), screen name as a centered inline
  title, via `nativeBackButton(title:)` (`DSText.swift` — full mechanism in its doc comment);
  identity-header screens (MatchDetail/TeamDetail/PlayerDetail) pass no title. Don't use
  `.toolbarRole(.editor)` or hide the bar (breaks edge-swipe).
- **Dynamic Type:** size text via `.dsFont(...)` (`@ScaledMetric`), NOT raw `.font(.system(size:))`;
  crests/flags scale on the same `.body` axis; **capped at AX1** at the root so dense tables don't break.
- **Team naming:** one team as subject → full club name (Gotham FC); **two-team contexts (match cards,
  match detail, comparisons, standings rows) → CREST + ABBREVIATION (e.g. WAS), never crest-less text or
  full names.** ESPN has no nickname field.
- **Crest rule:** bare crests via `TeamLogo`, no ring (only player monograms get a ring). **Team
  colors:** `DesignTeamColors` by abbreviation; use each club's default brand colors — no manual
  overrides without a documented rendering conflict.
- Clarity over density (~4–5 schedule cards/screen; avoid oversized cards); schedule shows the full
  season. Placeholders only as deliberate "Coming soon" (flagged in the File Map), never blank/broken.

## Deeper context (read on demand — NOT loaded every turn)

- **`docs/FILEMAP.md`** — every file + one-liner. Read to locate code. **Update it after every feature.**
- **`docs/backend.md`** — ESPN quirks, the proxy (routes / headshots / crests / bracket engine),
  Supabase schema + migrations.
- **`docs/live-activity-v2.md`** — ⚠️ THE V2 MANUAL. Read BEFORE touching/testing/troubleshooting
  anything Live Activity: the render law (alert REQUIRED, `sound:""` = quiet), two-token system +
  20-min lead, testing runbook (replay.mjs / test-activity / telemetry), AI-misconception traps
  (V2 is NOT text-only; app does NOT need to be open; "1/1 ok" ≠ rendered; 8pm listing ≠ 8pm kickoff).
- **`docs/navigation.md`** — each tab's lens + adjacency rules (read when adding/redesigning a screen).
- **`docs/versioning.md`** — the (non-semver) version model + distribution.
- **`docs/roadmap.md`** — What's Next (pending work).
- **`.claude/rules/bracket-battle.md`** + **`.claude/rules/fan-zone.md`** — feature rules that
  **auto-load** (path-scoped) when you touch Bracket / Predict-the-XI / Fan-Zone / Trivia / Home-games
  files; you don't need to open them manually.
