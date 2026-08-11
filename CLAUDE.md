# NWSLApp — Project Context for Claude

A one-page cheat sheet of rules/conventions/commands/gotchas for every session. Detailed and
feature-specific context lives in `docs/` + `.claude/rules/` and loads **on demand** (see
**Deeper context** at the bottom) — keep this file lean.

## ⚠️ What this app is — read first

A women's soccer (NWSL) **fandom** app: follow your clubs, keep up with soccer voices (reporters,
club + player social), play/share Fan Zone games (The Bracket, Predict the XI, Know Her Game, NWSL Trivia),
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
- **Sizing calibration (not enterprise, not toy):** solo indie dev, **free** app, **tip-jar-only**
  revenue. Size for **~1k active users at launch** (mandatory — a few hundred one-team fans enabling
  alerts must all get pushes) and architect for **100k over years**. Fixed monthly cost that triggers
  at small scale is disqualifying; prefer flat tiers over metered billing. Full method + the two
  stress tests (1k mandatory / 100k headroom) in **`docs/stress-testing.md`** — read before any
  scaling/sizing/publish-readiness work.
  **⚠️ THE BANNED LENS:** never reason from CURRENT usage ("only 2 users → plenty of headroom /
  that can wait until launch") — every load/reliability question is asked **as if the app ships
  tomorrow** (hundreds of one-club fans from one subreddit post). It produced the APNs 50-device
  near-miss AND two wrong calls on 2026-07-16 (watcher polling burned 23% of the request cap at
  zero users; error alerting misjudged as deferrable). Defer only when the 1k test PASSES or the
  lever is a flip-anytime config — never because today's traffic is small (stress-testing.md §0).
- **Privacy/monetization stance (owner, 2026-07-16 — values vs mechanics):** VALUES are promises —
  no ads, no data sold, no third-party/cross-app tracking, no dark patterns. MECHANICS stay flexible —
  say "free, tip-supported," never vow "free forever"/"no paywalls ever" (Swift Alert precedent), and
  anonymous FIRST-PARTY aggregate usage/diagnostics counters are ALLOWED (target App Store label: Data
  Not Linked to You; the Diagnostics spine already ships this way). Don't write absolutist product
  vows into public copy or docs; don't read the old "no tracking" line as banning anonymous counters.

## State

Production-quality **v0.4.5 (build 32)**, used daily. **Online-only: NO demo/seed/fake data in the running app**
— every surface shows live data or an honest "Couldn't load — tap to retry" (seed/fixtures live only
in previews + tests). Treat it as a real product; never suggest a demo/placeholder mode.

## Stack

Swift 5.9+ / SwiftUI (not UIKit), min iOS 17.2 (`@Observable`; 17.2 = Live Activity push-to-start), Xcode 27.0 beta 2. `URLSession` + async/await,
no third-party HTTP. UserDefaults (small local state) + **Supabase** (Postgres, durable per-user once
signed in); SwiftData nowhere. Sign in with Apple → Supabase (Apple auth + RLS). The **only**
third-party dep is `supabase-swift` (SPM) — a deliberate minimal-dependency stance, but a PREFERENCE to
weigh, not an absolute (revisit on merits if a feature genuinely justifies one). The 2026-07-09 push
fan-out review weighed + DECLINED Firebase and the chosen fix (Cloudflare Queues + APNs Broadcast
Channels) adds **no** app dependency, so the line stays true. Testing = **Swift Testing** (`@Test`/`#expect`), not XCTest.
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
DEBUG args: `-resetOnboarding`, `-useESPNDirect`, `-startTab <home|schedule|standings|teams|feed>`,
`-debugOpenMatch <espnEventID>` (deep-links a match detail tap-free — for in-sim verification),
`-signInAsTestFan <n>` (DEBUG-only: signs in as seeded fan `seed+000n@seed.nwslapp.test` instead of the
owner's Apple ID, so the SIM stops writing to her real Superfan/Predict rows — every gate keys on
`isSignedIn`, and the seeder sets `name_is_custom` so the Fan Zone gate passes. Needs the Supabase EMAIL
provider enabled with signups DISABLED. Push DELIVERY still can't be tested in a sim at all).
Decode-only tests read `NWSLAppTests/Fixtures/*.json` via `#filePath`. **Driving the sim — idb HID WORKS
again** (2026-07-22; Xcode 27 only MOVED `SimulatorKit` to `Contents/SharedFrameworks/`, where idb doesn't
look — point it at 26.6, which still has it at the old path):
`DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer idb_companion --udid <SIM>`, then
`… idb --companion localhost:<port> ui tap <x> <y>` (the client's unix socket isn't created — read the port
from the companion's `{"grpc_port":…}` line; coords are DEVICE points). ⚠️ SwiftUI **Toggles need
`--duration 0.12`** — an instantaneous tap is swallowed; and `ui describe-all` frames report the element's
**top**, so tap `y + height/2`. `describe-all` (frames + a11y labels) is exact for locating/measuring UI.
cliclick is fine for SCROLL drags + UIKit hit targets, but its synthetic
clicks get SWALLOWED by SwiftUI buttons inside a nested horizontal-scroll (e.g. a chip in the pinned
Club News header) — don't trust it there. DEBUG deep-link/launch-arg scaffolds remain a fallback.

## Architecture (MVVM, strict separation)

`Models/` (Codable, no UI/net) · `Services/` (API clients, no UI) · `ViewModels/` (`@Observable`,
state-enum `idle`/`loading`/`loaded`/`error`) · `Stores/` (`@Observable` shared state → UserDefaults,
injected via `.environment`, one-fetch-many-readers) · `Views/` (one screen per file, minimal logic) ·
`Components/` (reusable) · `DesignSystem/` (`DSColor`/`DSMetrics`/`DSText` tokens, dark-only). Prefer
`@Observable` over `ObservableObject`. Folders are created when their first real file lands.
**`Packages/`** (repo root, outside every target's synced folder) — local SPM packages that make key
seams **compiler-enforced** (risk-driven: isolate fragile/high-blast-radius code, not what's easiest):
`LiveActivityContract` (the app↔widget ActivityKit data contract, linked by both targets) +
`MatchClockKit` (live-clock engine + the consolidated display guard). ActivityKit code needs `#if
os(iOS)` (unavailable off-iOS breaks host indexing). Add more only when a seam earns it.

## Data sources & backend (MAP — detail lives in `docs/`, auto-loaded per subsystem)

**Online-only** (live data or an honest "Couldn't load — tap to retry"; NO demo/seed in the running app).
Most traffic routes through three sibling Cloudflare Workers in `~/Projects/`: **`nwslapp-proxy`** (ESPN
passthrough + cache, roster pipeline, `/weather`, `/predict/community`, bracket engine, crests/headshots) ·
**`nwslapp-match-watcher`** (`* * * * *` cron → live push, reaches the proxy via a **service binding**) ·
**`nwslapp-card`** (push-image renderer). DEBUG `-useESPNDirect` bypasses the proxy. Per-user state lives in
**Supabase** (Postgres, RLS + Sign in with Apple), offline-first via a UserDefaults cache.

**⚠️ Don't reason about this from scratch — every subsystem's source-of-truth doc AUTO-LOADS via
`.claude/rules/` the moment you touch its files.** That's the whole point of the docs (they're the living map
of what the app actually uses, and they stop wrong-direction rabbit holes). When you touch one, read it.

| Touch these files… | Rule auto-loads | Source-of-truth doc(s) |
|---|---|---|
| ESPN / proxy / roster / weather / scoreboard / standings | `backend-data-sources.md` | `docs/backend.md` (+ `roster-source-research.md`) |
| Live Activity / notifications / watcher / widget / match-clock | `live-activity-notifications.md` | `docs/{live-activity-v2, notifications, push-fanout-scaling}.md` |
| National teams | `national-teams.md` | `docs/national-teams.md` |
| Per-user sync (follows / alerts / progress) | `data-sync.md` | `docs/data-sync.md` |
| Fan Zone games / The Bracket | `fan-zone.md` / `bracket-battle.md` | `docs/{fan-zone, know-her-game}.md` |

**The handful of traps you must know BEFORE you'd know which file to open** (everything else lives in the
docs above — go read them):

- **ESPN's endpoints are UNOFFICIAL — decode DEFENSIVELY.** Scores are `String` not `Int`; `/scoreboard`
  needs `&limit=500` for a full season; endpoints break/rate-limit without notice.
- **⚠️ `state=="post"` does NOT mean FINISHED** (a suspended / wind-hold match reports `post` +
  `completed:false`). Anything meaning "the result is settled" MUST use **`Event.isFinalResult` /
  `isUnfinishedPost`** (app), the watcher's `isUnfinishedPost`, or the proxy's `chooseSummaryTTL` — **all
  FAIL-OPEN** (only `completed:false`/an explicit non-final status blocks; a sparse payload scores as
  before). Live-proven cost: a fake FT graded Predict wrong and killed the Live Activity.
- **The live clock + V2 Live Activity are FRAGILE and DEVICE-PROVEN — NEVER edit them from first
  principles.** `status.clock` freezes at 45:00/90:00; ESPN keeps `state=="in"` through halftime. Read
  `docs/live-activity-v2.md` **§0 (the START-PAYLOAD LAW)** before touching/testing any of it — `1 sent` ≠
  rendered, and this subsystem took weeks to get right.
- **Notifications = two tiers, OPT-IN, no dark patterns.** Tier 1 = local (no account: day-before, spotlight);
  Tier 2 = watcher-triggered (needs Sign in with Apple, sign-in-gated + display-gated). NEVER auto-enable a
  notification without an explicit user action. (The opt-in ruling + the restore line are SETTLED —
  `docs/decisions.md`.)
- **Supabase grants:** a new per-user table needs `grant … to authenticated` (RLS ≠ privilege → silent
  `42501`); any table a Worker reads/writes as `service_role` also needs `grant … to service_role` **matching
  the operation** (a `select`-only grant strands a coordinator that also DELETEs).
- **Feeds carry MORE than we parse — check `docs/backend.md`'s parsed-vs-unparsed inventory FIRST** before
  proposing any new data source or fetch (e.g. `/summary` already holds `commentary`/`leaders`/`videos`; IG
  and social content is scraped via **Bright Data**, proxy-side).

## Workflow & engineering practices (requirements — flag the trade-off before bypassing)

- **Branch first, never `main`:** `feature/<desc>`; `git status` clean before starting; state what
  you'll touch. Local hooks (`hooks/`): `pre-commit` blocks commits to main, `pre-push` blocks
  force/delete of main (`--no-verify` bypasses; fresh clone runs `git config core.hooksPath hooks`).
- **Build to spec, not to minimum.** Design-doc numbers are requirements, not suggestions — no
  scaled-down versions. A feature isn't "shipped" until EVERY sub-item is automated + verified (no
  partial credit; a scaffold needing manual steps ≠ the feature). Don't reclassify work as "deferred."
- **Prove it live.** Verify with evidence (curl the proxy/REST, screenshot the sim, trace the code
  path) — never reason from an unverified assumption.
- **Debug bottom-up; pull logs before blaming a third party.** Start at the SIMPLEST/nearest causes
  (our own code, config, a typo, stale creds, does-it-repro-elsewhere/other-device/other-account,
  cache/DNS) and work outward — NEVER jump to an external culprit (Cloudflare/ISP/Apple/APNs/DNS/a
  regional outage) before ruling those out. Track record: the root cause has been US every time (stale
  APNs tokens; an `aps` field Apple rejected) and NEVER the third party. When a log would pinpoint it —
  ESPECIALLY the in-app `Diagnostics`/telemetry, or `wrangler tail`/KV — but running it is GATED to the
  owner, don't reason past the missing data toward a worst-case guess: say so plainly and hand the owner
  the EXACT command to run (in the terminal) or step to check, and ask them to paste the output back.
  Missing logs = ask for them, not a license to speculate.
- **NO SILENT FAILURES (app-wide):** every unexpected condition (fallback/API-fail/stale/parse/retry/
  unexpected-empty) emits telemetry to the `Diagnostics` spine (os_log + `@Observable` ring, visible in
  dev/TestFlight). Fail LOUD to the engineer; fail HONESTLY to the user (degraded → subtle truthful
  indicator; blocked → clear message + retry). Banned: blank screens, infinite spinners, silent
  fallbacks indistinguishable from success — a failure must never look like success. Spans the proxy
  (`emitDiag` + a deploy-time health check that exits non-zero on any gap). The spine also carries
  **MetricKit** crash/hang crumbs (`metricKitDiagnostic`, device-only delivery) and is watched by PUSH
  alerting (2026-07-17): proxy error-spike → **Resend** email (≥8 error events/15min, 1/hr throttle;
  EXCLUDES `image fetch …` apiFailures — expected IG-CDN/thumbnail flakiness, still in Diagnostics but doesn't page);
  watcher tick → **healthchecks.io** heartbeat (dead cron ⇒ external email); all arms LIVE since
  2026-07-27. ⚠️ The pager scans **only** proxy-origin `sdiag:` records and deliberately skips client
  `/telemetry` (spoofable) — so an iOS **app crash can never page**; Apple's own crash notice is the only
  signal. ⭐ **Proxy diags persist in KV for 30d and are dumpable — the fastest bottom-up evidence for any
  proxy incident:** `wrangler kv key list --binding FEED_TAGS --remote --prefix "sdiag:"` + `kv key get`
  per key (this is how the 2026-W31 missing-club was root-caused to a seconds-long ESPN blip). SEPARATE quiet channel: **anonymous Level-3 usage counters**
  (`Analytics.swift` → proxy `/analytics` → Supabase `analytics_counters` daily rollups; six events,
  NO ids/IP ever, one batch per session — measures the product, never the person).
- **Plan for scope:** a change touching 3+ files or a new pattern → present a plan + get approval first.
  No new dependency without explaining why the built-in won't work + approval.
- **⚠️ CLOSE-OUT ROLL CALL (mandatory on any multi-item plan, design handoff, or numbered spec).** Before
  claiming done, list EVERY deliverable the spec asked for BY NAME with a status: **built / skipped /
  blocked**. Not a summary of what you built — a roll call of what was ASKED FOR. If an item is skipped
  or blocked, say so in that list and why, in the same message. **Nothing may be silently omitted, and
  no scoped item may be deferred on your own judgment — if you think something should be deferred, STOP
  and ask.**
  **Why this exists (the failure it targets):** the model rarely *decides* to defer. It sees a dependency
  that isn't ready, silently reclassifies the item as "not yet actionable," and reports done on the rest
  — believing it finished. So "don't defer" rules keep failing; they aim at a decision that never
  consciously happens. A roll call makes omission impossible to do quietly: you must type "SKIPPED" next
  to the item, which the owner can overrule in the same message instead of rediscovering it in the sim
  three sessions later. Track record: a detailed Fan Zone design handoff had 4 of 5 items silently
  dropped across three sessions; Trivia's round backbone was dropped a 4th time on 2026-07-23.
- **⚠️ KNOWLEDGE-BASE WRITE PATH — relocate, never delete; prove before you cut.** `docs/`, memory, and this
  file are a hard-won knowledge base — facts here took weeks + real devices to learn and are NOT
  reconstructable from training, so a future session that "cleans up" can silently destroy them (the size
  trace shows CLAUDE.md only ever GREW — nothing was lost until a condense pass threatened it). Rules when you
  edit any of them: **(1)** removing a load-bearing fact (anything ⚠️/🔒/device-proven, or any gotcha/ruling)
  requires **proving it's obsolete** — cite why it's no longer true — OR, if you're only condensing, **move it
  into its owning `docs/*.md` FIRST**, then leave a pointer. Never delete a fact to "save space"; relocate it
  (precedent: the "restore three facts that CLAUDE.md compressed" commit). **(2)** Never reverse a SETTLED
  ruling or a PROVISIONALLY-DONE call in **`docs/decisions.md`** by quietly editing prose — argue against the
  entry in the open and get the owner's explicit OK. **(3)** KB-diff close-out: when a session touched
  docs/memory/CLAUDE.md, `git diff` it and list every REMOVAL with a status (relocated-to-X / obsolete-
  because-Y / owner-approved), the same roll call deliverables get. The SessionStart size check is a prompt to
  **relocate detail to a doc, NEVER to trim facts away.**
  **Why this rule is FIRM (owner 2026-08-06 — the reasoning, so it isn't loosened later):** the danger is not
  sloppy text, it's a specific blind spot. Some subsystems LOOK like standard training knowledge and are not —
  **V2 Live Activity push** is the canonical case: push-to-start / broadcast-channel fan-out / the payload
  render law are an Apple feature built for premium sports apps, exactly where training is THIN, yet it
  pattern-matches to "ordinary notifications." So the model's instinct to generalize/trim is most confident
  precisely where it's most wrong — it trims the wall of V2-LA detail as "redundant," the next session works
  the fragile system without the full picture, and code breaks it AGAIN (this happened ~7 times). The rule
  exists because the model's judgment about "what's needed" is the untrustworthy part; loosening it re-opens
  the exact judgment call that caused the damage. Default is **don't decide — relocate.**
  **THE ONE EXCEPTION — `docs/roadmap.md` (owner 2026-08-06):** the roadmap is the owner's PERSONAL
  task-tracking doc (her "sticky notes"), not durable knowledge. The relocate-never-delete rule and the
  KB-diff roll-call do **NOT** apply to it — when the owner directs removal of a roadmap item, just delete it,
  no relocation/roll-call ceremony. Durable lessons belong in the SYSTEM docs (`docs/live-activity-v2.md`,
  `notifications.md`, `backend.md`, `decisions.md`, …), which keep the full protection. Only caveat: if a
  roadmap entry being deleted carries a device-proven lesson not captured in a system doc, one-line flag it
  first ("this had lesson X — keep it in a system doc?"); if she says drop it, it's dropped.
- **BACKBONE IS NEVER DEFERRED FOR A MISSING FRONT END.** Build the structure AS IF the generator /
  content pipeline / data source already works — the app should be waiting on the pipeline, never the
  reverse. "The questions aren't generated biweekly yet" is NOT a reason to skip the round model, the
  landing page, or the retention rule. (Owner's fiber analogy: you don't defer the main feeder lines
  because no customers have signed up and the neighborhood nodes aren't placed — that reasoning can
  never fire in favor of building backbone, so the backbone never gets built.) Deferral doesn't save
  work either; it multiplies it — each skipped item costs a sim run to discover, a turn to report, and
  a context rebuild, and still has to be written.
- **Nothing stays pending past the day it's decided** — deploys especially. A merged-but-undeployed
  change becomes a phantom bug the owner burns hours on weeks later. Merge and deploy same-day; if a
  step can't happen today, say so explicitly in the roll call.
- **No force-unwraps (`!`)** unless a comment explains why it's safe. Temp architecture-bending code
  carries a `TEMP` comment (what/why/when-removed).
- **Before "done":** builds AND runs in the sim with no errors, **manually verified in-sim**
  (compiling ≠ working); update `docs/FILEMAP.md`; commit message `<Area>: <what changed>` (specific,
  present-tense); confirm before pushing (don't auto-push).
- **AX1 check = part of "done" for any new/redesigned screen** (`simctl ui <SIM> content_size
  accessibility-medium`). Dynamic Type caps at AX1, so it's the largest size the app promises and must
  lose NO data. Bar, severity ladder, cap rationale: `docs/roadmap.md` ♿ gate.
- **Stress-test gate = part of "done" for load-bearing features.** Any NEW or REBUILT feature/subsystem
  that adds or changes a **load path** (DB reads/writes, network, push fan-out, KV/storage, cron) must be
  run through the **`docs/stress-testing.md` §5** method and shown to **pass the 1k SIZE test** (+ note the
  100k lever) BEFORE it's done — never ship/rebuild a section that
  silently fails 1k/100k because we never re-tested it. Record the result in that doc's §6/§7. Pure
  UI/cosmetic changes with no new load path are exempt (the gate is about load, not pixels).
- **Build bump ⇒ consider the update gate (don't auto-couple).** On a TestFlight/App Store build bump,
  the forced-update gate's `minBuild` (proxy `/config`, `MIN_APP_BUILD`) is a manual FLOOR decoupled from
  the build number — it does NOT auto-track "latest". NEVER raise it on every bump (that force-updates
  every user) and NEVER to a build that isn't live+installable yet (walls users with nowhere to go).
  Raise it + redeploy ONLY to retire a broken/incompatible build, and ONLY after the newer build is
  available. ⚠️ **Raised for the first time 2026-07-31: `MIN_APP_BUILD = 31`, retiring builds ≤30.**
  ORDER MATTERS — the app bump ships first, then the proxy deploys once build 31 is live on TestFlight;
  deploying the gate early walls every user on 30 with nowhere to go. Detail: `docs/versioning.md`.
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
- **Reuse the shared component library — don't re-roll** (pre-launch design pass, 2026-07-17): buttons →
  `DSButton`; error/empty → `RetryStateView`; team colors → `Color.teamColor(…)`; team-color card washes →
  `TeamWashBackground` (`TeamColorWash.swift`); player avatars →
  `PlayerHeadshot`; voice pills → `CategoryPill`; broadcast/platform colors → `BroadcastBrand`/`PlatformBrand`.
  Style via `ds*` tokens ONLY — no UIKit `Color(.systemGray*/.systemGroupedBackground/.separator)`, no raw
  `.white` (→ `dsFgPrimary`), no raw `.font` for readable text (→ `.dsFont`; fixed-size monograms/badges/
  numeric columns exempt), correct/wrong = `dsSuccess`/`dsError`. **Fan Zone = two visual families**
  (competitive arena vs community cards) — the full contract auto-loads from `.claude/rules/fan-zone.md`
  (Design consistency §). Build future games WITH this, not around it — the Superfan Zone + team-color
  washes already do, and the NWSL Trivia round rebuild (2026-07-23) closed the last community-family drift.
- Persistent UI (tab/nav bars) never obscures scrollable content (respect safe areas); every drilled-in
  view has an explicit back affordance (don't rely on edge-swipe alone). Tabs keep their OWN nav stack
  across switches (**The Athletic model, owner-confirmed 2026-07**); re-tapping the ALREADY-active tab
  pops it to root (intended affordance, PENDING). Do NOT reset on every tab tap — that's ESPN's jarring
  model (owner rejected), and `.id()` on a TabView child desyncs selection from content (tried, reverted).
- **Back button = bare ‹ chevron** (native iOS, MLS/Athletic-style), screen name as a centered inline
  title, via `nativeBackButton(title:)` (`DSText.swift` — full mechanism in its doc comment);
  identity-header screens (MatchDetail/TeamDetail/PlayerDetail) pass no title. Don't use
  `.toolbarRole(.editor)` or hide the bar (breaks edge-swipe).
- **Dynamic Type:** size text via `.dsFont(...)` (`@ScaledMetric`), NOT raw `.font(.system(size:))`;
  crests/flags scale on the same `.body` axis; **capped at AX1** at the root so dense tables don't break.
  **⚠️ 12pt readable-font FLOOR (owner 2026-08-06):** no readable prose renders below `.dsFont(12)` at
  default size — 12 is the AX1-critical floor (below 10-11 stays illegible even after scaling), set after
  the owner's mom (70s) couldn't read the app and the Sim's desktop-scale render hid it
  ([[feedback_size_for_phone_not_desktop]]). EXEMPT: `trackedCaps` eyebrows (11pt but small-caps+tracking
  read larger), fixed numeric columns / badge letters / monograms, non-text indicators (5-7pt dots). A
  13-14pt "must-read secondary" tier is a parked follow-up (roadmap). Size for the phone in the hand, not
  the Sim — err larger.
  **⚠️ CONTRAST FLOOR (owner 2026-08-11) — the color-axis peer of the font floor:** readable text uses
  **`dsFgPrimary` or `dsFgSecondary` ONLY.** `dsFgTertiary`/`dsFgQuaternary` are **DECORATION ONLY** (icons
  beside a label, dividers, dots, disabled, "TBD"/"VS" placeholders) — they FAIL WCAG AA as text on cards
  (2.33:1 / 1.53:1). Below primary white, express hierarchy with **weight/size, not a darker gray**; never
  `.foregroundStyle(.secondary)` / `.white.opacity()` for readable prose (bypasses the tokens). Every
  readable fg×bg pairing must clear **WCAG AA 4.5:1** (3:1 large/bold) — enforced by `DSColorContrastTests`
  (`Color.wcagContrastRatio`). Set after invisible dark-on-dark text shipped (the weather footer at 1.5–2.3:1);
  AI — Design's handoffs AND ours — kept reaching for tertiary as "a dimmer text color." Same exemptions as
  the font floor. [[feedback_invisible_dark_on_dark_text]].
- **Team naming:** one team as subject → full club name (Gotham FC); **two-team contexts (match cards,
  match detail, comparisons, standings rows) → CREST + ABBREVIATION (e.g. WAS), never crest-less text or
  full names.** ESPN has no nickname field.
- **Crest rule:** bare crests via `TeamLogo`, no ring (only player monograms get a ring). **Crests are
  PROMINENT — render them LARGE, never shrunk toward an icon/spec size; the crest is the team's identity
  (players/fans lift it to their chest) and outranks the abbreviation/name text. AI keeps shrinking them;
  don't — err larger** (à la The Athletic; owner directive, e.g. the LA card crest is 48pt). **Team
  colors:** `DesignTeamColors` by abbreviation; use each club's default brand colors — no manual
  overrides without a documented rendering conflict.
- Clarity over density (~4–5 schedule cards/screen; avoid oversized cards); schedule shows the full
  season. Placeholders only as deliberate "Coming soon" (flagged in the File Map), never blank/broken.

## Deeper context (read on demand — NOT loaded every turn)

- **`docs/FILEMAP.md`** — every file + one-liner. Read to locate code. **Update it after every feature.**
- **`docs/decisions.md`** — ⚠️ the SETTLED-rulings + owner-iterating ledger (restore line, opt-in, KHG
  no-repeats, banned lens, privacy stance; Superfan v1 provisional). Never reverse an entry by editing prose —
  argue against it in the open first. Read before "improving" any settled behavior.
- **`docs/backend.md`** — ESPN quirks, the proxy (routes / headshots / crests / bracket engine),
  Supabase schema + migrations.
- **`docs/live-activity-v2.md`** — ⚠️ THE V2 MANUAL. Read BEFORE touching/testing/troubleshooting
  anything Live Activity: the render law (alert REQUIRED, `sound:""` = quiet), two-token system +
  20-min lead, testing runbook (replay.mjs / test-activity / telemetry), AI-misconception traps
  (V2 is NOT text-only; app does NOT need to be open; "1/1 ok" ≠ rendered; 8pm listing ≠ 8pm kickoff).
- **`docs/notifications.md`** — the WHOLE notification pipeline (V1 + V2) end-to-end: match event → proxy →
  watcher cron → detect → APNs (Queues / Broadcast Channels) → device → render. A **PERMANENT** reference —
  this connective sports-app knowledge (channels, clock anchoring, the fragile V2 wiring) is **NOT
  reconstructable from training**, so read it before ANY notification / Live-Activity / watcher / clock change.
- **`docs/fan-zone.md`** — ⚠️ THE FAN ZONE SYSTEM DOC. How the four games actually work end-to-end: the
  two families, the **cadence engine** (biweekly rounds are STAGGERED — both community games stay
  playable; the anchor is a cross-repo contract with the proxy), state ownership (what's local vs
  Supabase and why), progress restore, retention, scoring/Superfan, and an add-a-fifth-game checklist.
  Read before touching any game. The BUILD RULES stay in `.claude/rules/fan-zone.md` (auto-loads).
- **`docs/navigation.md`** — each tab's lens + adjacency rules (read when adding/redesigning a screen).
- **`docs/versioning.md`** — the (non-semver) version model + distribution.
- **`docs/roadmap.md`** — What's Next (OPEN blockers only; the owner's personal punch-list). Done/dropped
  items are removed, not archived — git history keeps the record, and durable lessons live in the system
  docs. It is exempt from the KB relocate-never-delete rule (see the KNOWLEDGE-BASE WRITE PATH bullet).
- **`docs/roster-source-research.md`** — the 2026-07-29/30 live-verified research on ESPN vs the NWSL
  SDP API: two error classes (fabrication vs lagging fact), invariants-first correction design, what SDP
  has/lacks, live-games verdict (stay on ESPN). Read BEFORE any roster-source or cross-check work.
- **`docs/stress-testing.md`** — the launch-readiness charter: indie-sizing calibration, the two stress
  tests (1k mandatory / 100k headroom), the efficiency-first rule, and the 8-step method for stress-testing
  any subsystem + a checklist of what still needs it. Read before any scaling/sizing/publish-readiness work.
- **`docs/push-fanout-scaling.md`** — the launch-scale APNs fan-out fix — **BUILT + deployed + device-
  proven 2026-07-09**: **V1 buzz + LA push-to-start → Cloudflare Queues** ($0); **V2 in-match updates →
  APNs Broadcast Channels** (channel-per-match, iOS 18+; iOS 17 = V1-only graceful degradation); Firebase
  declined; Workers Paid $5/mo = the ~10–15k-user expansion slot. Read before push-scale/launch work.
- **`.claude/rules/*.md`** — path-scoped rules that **auto-load** when you touch matching files, forcing the
  right source-of-truth doc into context so a subsystem is never edited from first principles. No need to open
  manually: `bracket-battle` + `fan-zone` (Bracket / Predict / Fan-Zone / Trivia / Home-games — fan-zone
  carries the build LOGIC GATE + the KHG-pipeline pointer) · `live-activity-notifications` (Live-Activity /
  MatchClock / push-token / NSE / widget → the V2+notifications docs) · `backend-data-sources` (ESPN / proxy /
  roster / weather / scoreboard / standings → `backend.md`) · `national-teams` (NT files → `national-teams.md`)
  · `data-sync` (sync coordinators/services → `data-sync.md`).
