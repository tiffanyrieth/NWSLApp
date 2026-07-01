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

Swift 5.9+ / SwiftUI (not UIKit), min iOS 17.2 (`@Observable`; 17.2 = Live Activity push-to-start), Xcode 26.5. `URLSession` + async/await,
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
Decode-only tests read `NWSLAppTests/Fixtures/*.json` via `#filePath`. Driving the sim: cliclick hits
the UIKit tab bar but not SwiftUI buttons reliably — use DEBUG deep-link/launch-arg scaffolds (`idb ui
tap` if installed).

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
**Tier-2 server push** (live match alerts) is a SECOND sibling Worker, **`nwslapp-match-watcher`**
(`~/Projects/nwslapp-match-watcher`): a `* * * * *` cron that diffs the proxy scoreboard (reached via a
**service binding** — same-account Worker→Worker over `*.workers.dev` 404s with CF **error 1042**, so a
public fetch silently fails; the rich-card crest fetch uses the same binding) for
kickoff/goal/halftime/full-time + **VAR goal-correction** (a debounced score *decrease* — re-poll a
cache-busted scoreboard before firing, so an ESPN glitch never sends a false "Goal Disallowed"), looks
up `device_tokens` of users with that alert on, and sends APNs
(ES256 `.p8` JWT). Deployed; `POST /test-push` (`x-trigger-secret`) sends a synthetic push for
on-device E2E (`APNS_HOST` is production). A **V2 Live Activity** layer (lock-screen + Dynamic Island live
score) rides the SAME watcher + `.p8`, ADDITIVE to V1 — but the roles split: **V1 is the interrupt (buzzes
kickoff/goal/HT/FT per the user's toggles); V2 is a SILENT glance.** Gotcha: the push-to-start `alert` is
OPTIONAL — OMIT it so the card renders with NO buzz/banner (adding one double-notifies against V1). Push-to-
start fires **≤20 min pre-kickoff** (a device can take minutes to register its per-Activity token) + a
catch-up push for late tokens. `POST /test-activity` + `scripts/replay.mjs` drive it; app `LiveActivityManager`
mirrors push-to-start/per-Activity tokens under a UIKit background-task assertion (background-launch upload);
detail in `docs/backend.md`. The app side: `registerForRemoteNotifications` → AppDelegate →
`PushBridge` → `DeviceTokenService` upserts `device_tokens` (per-team toggles in `team_alert_preferences`).
**Notifications = PURE OPT-IN (owner rule — no dark patterns):** every toggle defaults OFF, nothing
auto-enables; the user turns on exactly what they want (discovery = Teams coach-mark → gear icon). **Tier 1**
= deliverable without an account (local: day-before, Player Spotlight); **Tier 2** = watcher-triggered ⇒ needs
an account ⇒ sign-in-gated (`tier2Binding`) + reset on sign-out (`resetServerPushTypes`: kickoff/goals/HT/FT
+ the V2 Live Activity). NEVER add a default-on notification.
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
is NOT table privilege (this latent gap 42501'd the first real service_role read).

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
- **`docs/navigation.md`** — each tab's lens + adjacency rules (read when adding/redesigning a screen).
- **`docs/versioning.md`** — the (non-semver) version model + distribution.
- **`docs/roadmap.md`** — What's Next (pending work).
- **`.claude/rules/bracket-battle.md`** + **`.claude/rules/fan-zone.md`** — feature rules that
  **auto-load** (path-scoped) when you touch Bracket / Predict-the-XI / Fan-Zone / Trivia / Home-games
  files; you don't need to open them manually.
