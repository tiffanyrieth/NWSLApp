# NWSLApp — Project Context for Claude

## ⚠️ PRIORITY FRAMEWORK — READ FIRST

This app's differentiator is NOT stats, scores, or schedules. Every sports app has those.
This app exists because it feels ALIVE — fresh content every time you open it, fan engagement
that brings people together, and a personal connection to your teams and players.

PRIORITY ORDER (non-negotiable):
1. ALIVE FEATURES — Live content pipelines (YouTube → Home, Bluesky/Reddit → Feed, Spotlight rotation, Fan Zone rounds)
2. CORE FUNCTIONALITY — Scores, schedule, standings, stats (table stakes, must work, but not the differentiator)
3. HARDENING — Bug fixes, decode tests, abbreviation fragility, pull-to-refresh polish

Never prioritize category 3 over category 1. If someone asks "what's next?", the answer
is always the highest incomplete item in category 1 unless it's physically blocked.

The litmus test: "Would I open this app today if I opened it yesterday?"
If the answer is no because the content hasn't changed, that's the #1 priority to fix.

## Overview

**What:** A native iOS app for tracking the NWSL (National Women's Soccer
League) — live scores, full-season schedule, standings, team pages, and match
details.

**Why:** Personal project to build production-quality iOS skills and ship a
real consumer app. Long-term goal: App Store distribution.

**Scope:** A full-featured league app built incrementally over many releases —
schedule, standings, teams, player and match detail, and personalization over
time — not a single-screen demo. Architecture and conventions are chosen to
grow with it.

**Owner:** Tiffany Rieth

---

## Tech Stack

- **Language:** Swift 5.9+
- **UI:** SwiftUI (not UIKit)
- **State:** `@Observable` (modern) over `ObservableObject` where possible
- **Networking:** `URLSession` + `async/await`. No third-party HTTP libraries
  unless justified.
- **Persistence:** UserDefaults for small local state (follows, game stats);
  Supabase (Postgres) as the durable per-user source of truth once signed in.
  SwiftData still used nowhere.
- **Auth / per-user backend:** Sign in with Apple → **Supabase**
  (Postgres + native Apple auth + Row-Level Security). The project's **first and
  only third-party dependency** is the **Supabase Swift SDK** (`supabase-swift`,
  SPM) — justified because rolling raw URLSession calls would mean reimplementing
  JWT refresh, RLS header injection, and session keychain storage. Credentials
  live in a **gitignored `Config/Secrets.swift`** (template: `Secrets.example`);
  the anon key is a public client key — RLS is the real boundary.
- **Testing:** Swift Testing (`@Test` + `#expect()`), not XCTest
- **Minimum iOS version:** iOS 17 (enables `@Observable`)
- **Xcode version:** 26.5

---

## Commands

```bash
# Build (Debug) for a booted simulator
xcodebuild build -scheme NWSLApp \
  -destination 'platform=iOS Simulator,id=<BOOTED_SIM_ID>' -configuration Debug

# Run the unit tests
xcodebuild test -scheme NWSLApp \
  -destination 'platform=iOS Simulator,id=<BOOTED_SIM_ID>' -only-testing:NWSLAppTests

xcrun simctl list devices booted                 # find the booted sim id
xcrun simctl install <SIM_ID> <NWSLApp.app>      # install a built .app
xcrun simctl launch  <SIM_ID> com.tiffanyrieth.nwslapp.NWSLApp
```

DEBUG launch args: `-resetOnboarding`, `-useESPNDirect`, `-useSeedContent`,
`-startTab <home|schedule|standings|teams|feed>`. Decode-only tests read
`NWSLAppTests/Fixtures/*.json` off disk via `#filePath` (no bundle membership).
**Driving the sim:** synthetic taps (cliclick) are unreliable for SwiftUI
controls — the UIKit tab bar responds but NavigationLinks/Buttons/Pickers often
don't, so in-sim verification uses temporary DEBUG deep-link/launch-arg scaffolds
(then removed). `idb ui tap` (HID-level) is the more robust route if installed.

---

## Architecture

**Pattern:** MVVM (Model–View–ViewModel) with strict separation.

- `Models/` — `Codable` structs matching API responses; no UI or networking
- `Services/` — API clients (e.g. `ESPNService.swift`); no UI logic
- `ViewModels/` — `@Observable` classes that own view state; use the
  state-enum pattern (`idle` / `loading` / `loaded` / `error`)
- `Views/` — SwiftUI views, one screen per file; minimal logic
- `Components/` — reusable view pieces (cards, badges, etc.)

Folders are created when their first real file lands, not preemptively.

---

## Data Source

**Primary:** ESPN's unofficial NWSL endpoints (community reverse-engineered,
not officially supported).

- Base URL: `https://site.api.espn.com/apis/site/v2/sports/soccer/usa.nwsl/`
- Scoreboard (full season):
  `scoreboard?dates=YYYY0101-YYYY1231&limit=500`
- Other endpoints to map as needed: standings, teams, news

**Known quirks (decode defensively):**
- Scores decode as `String` (`"0"`), not `Int`.
- Event timestamps sometimes arrive without seconds — custom date parsing is
  required (handled in `Event.kickoff`).
- The default scoreboard response caps at ~100 events; `&limit=500` returns the
  full season (~240 events for 2026).
- Standings lives at `apis/v2/…` NOT the `apis/site/v2/…` base (the site path
  returns `{}`).
- Player headshots are null for every NWSL athlete — squad cards show a
  jersey/initials monogram, not a photo (permanent, not a TODO).
- Feed articles are legal-limited to headline + summary + link — never the
  article body (reporter posts may carry full text).
- Endpoints are unsupported and undocumented — they can change shape, break, or
  rate-limit without notice. Fail gracefully.

**Proxy (V2, 0.2.0):** A tiny Cloudflare Worker — `nwslapp-proxy` (sibling repo
`~/Projects/nwslapp-proxy`, GitHub `tiffanyrieth/nwslapp-proxy`, live at
`https://nwslapp-proxy.tiffany-rieth.workers.dev`). **Pass-through caching routes**
(`proxyAndCache`, Workers Cache API, match-state-aware TTL): `GET /scoreboard` and
`GET /summary?event={id}` (0.3.1) forward to ESPN and return bytes **unchanged** (app
decoders untouched); summary TTL via `chooseSummaryTTL` (finished→1yr, live→30s,
future→daily 7am UTC). **Content routes** (build + normalize to JSON): `/team-videos`,
`/feed`, `/spotlight` (B2). Teams/roster/standings still hit ESPN directly. Base URLs
in `Config/AppConfig.swift`; DEBUG `-useESPNDirect` falls back to ESPN. See
`Reference/Sessions/2026-06-08_v2-kickoff-caching-proxy.md`.

**Per-user backend (V2, 0.2.x):** **Supabase** is the stateful/per-user layer
(boundary: Workers = stateless/global; Supabase = stateful/per-user). **Sign in
with Apple** creates a Supabase user; a `profiles` row and a `follows` row-set
(team IDs, Row-Level-Security'd to the owner) persist per account. The app stays
**offline-first**: UserDefaults is the immediate local cache and the app never
blocks on the network to show follows; Supabase is the durable truth. On sign-in
the local and server follow sets are **merged (union — never delete)**, written
back down locally (covers new-device restore) and pushed up; afterwards each
follow/unfollow mirrors to Supabase best-effort. Only **clubs** sync (not
competitions yet). The Supabase client is built from the gitignored `Secrets`
(see `Config/AppConfig.swift` sibling `Services/SupabaseManager.swift`). The
Postgres schema (tables + RLS + the required `authenticated` grants) is checked
in at `supabase/schema.sql` — RLS alone isn't enough; a missing table grant fails
queries with `42501`. See `Reference/Sessions/2026-06-09_supabase-accounts-setup.md`.

**Future:** Expand the proxy to more endpoints + response normalization as
needed; leaderboard tables, competition-follow sync, and Tier-2 push build on
this account system.

---

## Workflow & Engineering Practices

This project follows a deliberate, disciplined workflow. Treat the steps below
as requirements, not suggestions. If a request would bypass one — even in the
name of moving quickly — pause, flag it, and explain the trade-off before
proceeding.

**Before starting any session**
1. Run `git status` and report what's there. If there are uncommitted changes,
   resolve them (commit or stash) before starting new work.
2. Check the current branch. Never work on `main` — create a
   `feature/<short-description>` branch first. If the working branch is `main`,
   stop and branch before making changes.
3. State what we're about to do and which files you expect to touch.

**During work**
4. For any change touching 3+ files or introducing a new pattern, present a
   plan and get approval before editing.
5. Don't add a dependency (Swift Package, library) without first explaining why
   the built-in option won't work and getting approval.
6. No force-unwraps (`!`) in Swift unless a comment explains why it's safe.

**Before a feature is "done"**
7. The app builds and runs in the iOS Simulator with no errors.
8. The feature is manually verified in the simulator — confirmed working, not
   just compiling.
9. Commit messages are specific and present-tense, formatted
   `<Area>: <what changed>` (e.g. `Schedule: Add loading state while fetching
   matches`).
10. Update the **File Map** and **Current State** sections below to reflect
    what now exists.
11. Confirm before pushing to the remote. Don't auto-push.

**Never**
- Commit directly to `main`. Work on a feature branch and merge via PR.
- Skip simulator verification. "It compiles" is not "it works."
- Commit secrets, API keys, or tokens. Use a gitignored config or environment
  variable.

**Local enforcement:** the `hooks/` folder holds git hooks that back the
branch rule on this machine — `pre-commit` blocks commits onto `main`, and
`pre-push` blocks deleting/force-pushing `main` (warns on a direct push). They
are local guardrails, not policy: bypass with `--no-verify`, and a fresh clone
must run `git config core.hooksPath hooks` to enable them. (GitHub server-side
protection needs Pro on a private repo.) See `hooks/README.md`.

**Known gotcha — `gh` auth expires mid-session.** The `gh` keyring token can go
stale partway through a session: `git push` keeps working (separate credential
helper) and `gh auth status` still reports "Logged in", but every `gh` API call
(`gh pr create`/`merge`/`view`, `gh api`) fails with `HTTP 401: Requires
authentication`. Fix: re-run `gh auth refresh -h github.com` (interactive —
the user runs it), then retry. So when a push succeeds but the follow-up PR
merge 401s, it's this, not a permissions problem.

---

## Collaboration Preferences

This project doubles as a way to build durable iOS and software-engineering
skills, so understanding each change matters as much as shipping it. When
working in this repo:

- Explain the reasoning behind non-obvious decisions and trade-offs as you go,
  not just the resulting code.
- When introducing a new file or folder, note why it's organized that way.
- The first time a pattern appears (MVVM, state enums, `async`/`await`,
  `Codable`), briefly explain how it works.
- If a request reflects a misunderstanding or would introduce bad practice, say
  so and propose the better approach instead of silently complying.
- Favor idiomatic, maintainable Swift/SwiftUI over quick shortcuts.

---

## UI Requirements

- Persistent UI (tab bars, nav bars) must never obscure scrollable content —
  respect safe-area insets.
- Every drilled-in view has an explicit back affordance; don't rely on the
  edge-swipe gesture alone.
- Navigation state resets predictably (tapping a tab returns to its root).
- Placeholder tabs/sections are allowed only as intentional structural
  scaffolding — and only when they (a) show a clean "Coming soon" state (never a
  blank or broken screen), and (b) are flagged as placeholders in the File Map.
  The bar is: a placeholder must look deliberate, not forgotten.
- The schedule displays the full season, not a rolling window.
- Clarity over density — screens should breathe.

---

## Navigation Identity

Each tab has a distinct job. When adding or redesigning a feature, check that
the *lens* matches the section and that adjacent sections stay consistent.
Full rationale in `Reference/navigation-architecture.md`.

- **Home** — your teams, right now. Personal + temporal. The engagement hub.
- **Schedule** — when do they play, what happened? Full-season calendar.
- **Standings** — where does your team sit? League position + competitive context.
- **Teams** — the club directory + deep dives. Season-level, relational.
- **Feed** — the conversation around your teams. Reporter/journalist voices.

**Adjacency rule:** when you change a section, check its neighbors. Schedule
cards and MatchDetailView share visual language. Team Page and MatchDetailView
share player data through different lenses (season vs. match). Home Module 1
(team content) and Feed (reporter content) are distinct voices — don't blur them.

---

## Distribution

- Simulator + Personal Team sideload (free Apple tier). App Store deferred
  until the project reaches a presentable state.

---

## Versioning

Two separate numbering systems — don't conflate them.

- **Phase names ("V1", "V2")** are internal chapters, not release numbers. V1 =
  the vision prototype (seed data, no backend). V2 = the real-backend era
  (proxy, accounts, live Feed). Use them in planning/notes only.
- **Release numbers** follow semver (`MAJOR.MINOR.PATCH`) and the project is
  **pre-1.0**: `0.x` means "not yet publicly released / still stabilizing."
  - **A minor bump = a whole new CHAPTER of the app, not a single feature.**
    0.1 set the grain: the *entire* prototype — all ~22 PRs, whole new tabs and
    games included — is **0.1.x**, one minor. So the *entire* backend era (proxy
    + accounts + Feed + push + player photos + every fix and surprise along the
    way) is likewise **one chapter → 0.2.x**, however many PRs it takes.
  - **Patch (third digit) = each shipped update inside the chapter.** Pre-1.0
    this includes new features, not just bug fixes (strict "patch = bugfix only"
    is a post-1.0 rule). The proxy (**0.2.0**), accounts, Feed, etc. are patch
    steps climbing under 0.2.x — they do NOT each earn their own minor. *Worked
    example:* proxy **0.2.0** → accounts ≈ **0.2.3** → live Feed ≈ **0.2.9** →
    game backends ≈ **0.2.15**, all still inside 0.2.x.
  - **A chapter's theme is a center of gravity, not a fence.** 0.2.x is *about*
    the backend, but pre-1.0 it also absorbs the bug fixes and small unrelated
    improvements that get shipped alongside — they ride the same 0.2.x patch
    line rather than spawning their own minor. Only a genuinely new *era* (a
    whole new tab, a major redesign, a distinct pre-launch beta) earns the next
    minor. Routine fixes and polish do not.
  - **Reserve 1.0.0 for the first public App Store launch.** Because a chapter
    is one minor, you arrive at 1.0 from somewhere low (≈0.2–0.3) and never
    balloon past it.
  - **Current line (owner's call):** **0.3.x = the BACKBONE chapter** (demo →
    live). **0.3.8** = the feed/content work (B1 News · B2 Spotlight · B3a chips ·
    B3b Instagram). **0.3.9** = the rest of the backbone (Fan Zone games + B4
    sweep). **0.4.x = QOL** — improving the *experience* of what's already alive,
    not backbone infrastructure.
- **Xcode has two fields, both required:** "Marketing Version"
  (`CFBundleShortVersionString`, the human-facing `0.2.0`) and "Build"
  (`CFBundleVersion`, a monotonic integer bumped on *every* TestFlight upload —
  TestFlight rejects a duplicate build number even when the marketing version
  is unchanged).
- **Tag releases in git** at each milestone (`git tag v0.2.0`) so repo history
  tracks the version line alongside the per-PR commits.

---

## File Map (UPDATE THIS AFTER EVERY FEATURE)

Markers: ⚠️ = TEMP scaffolding (curated static seed; swap for a real backend —
the async signature is already shaped for it). 🔧 = intentional "coming soon"
placeholder (looks deliberate per the UI rules). Design specs in
`Reference/Design/*-spec.md` hold the full rationale.

```
NWSLApp/
├── NWSLAppApp.swift                   — app entry point; launches RootTabView; forces dark appearance app-wide; DEBUG `-resetOnboarding` launch arg → resets onboarding; `AppDelegate` (@UIApplicationDelegateAdaptor) captures the APNs token + handles foreground-present/tap → PushBridge (Tier 2)
├── NWSLApp.entitlements               — Sign in with Apple + `aps-environment` (development; Xcode flips to production on archive) for Tier-2 push
├── Config/                            — app configuration
│   ├── AppConfig.swift                — base URLs; scoreboard + summary → Cloudflare proxy (0.3.1); DEBUG `-useESPNDirect`; `liveContentEnabled` flag (ON) + `teamVideosURL` (Home: YouTube + news + club Instagram) + `feedURL` (Feed: Bluesky + RSS news + player Instagram) + `spotlightURL` (Module 2: B2/0.3.8); shared `contentRouteURL`
│   ├── Secrets.swift                  — 🔒 GITIGNORED Supabase URL + anon key (not committed)
│   └── Secrets.example                — checked-in template for Secrets.swift (non-`.swift` so it never compiles)
├── DesignSystem/                      — token layer mirroring the Claude Design handoff; the app-chrome palette (team colors stay dynamic via Color+Hex)
│   ├── DSColor.swift                  — `Color.ds*` tokens (bg/fg/accent/status/game/match-state); dark-only literal hex
│   ├── DSMetrics.swift                — `enum DS` spacing, radii, avatar/crest sizes, game-card dims
│   └── DSText.swift                   — modifiers: `.trackedCaps()`, `.sectionTitle()`, `.navigationContextLabel("…")` (left "‹ Label" on pushed screens), `Font.dsScore`
├── Models/                            — Codable models (⚠️ = backed by a seed provider)
│   ├── BracketEdition.swift           — Bracket Battle LIVE models (0.3.9): BracketRound (escalating points, any power-of-2 pool) · Entrant/Matchup/Edition (64→6 rounds, flat Codable)
│   ├── Club.swift                     — flat Club + ESPN /teams decode wrappers (now decodes brand color/alternateColor → ring crests)
│   ├── ContentCard.swift              — ⚠️ unified ALIVE-content model: 7 layouts (youtube/blueskyTeam·Text·Media/blueskyReporter/newsArticle/socialVideo/instagramFallback) + StalenessWindow (Home 72h / Feed 7d, each **6-card-floored** → never-empty, 0.3.7); Codable-shaped for the live pipeline; supersedes FeedItem+TeamContentItem
│   ├── FollowedCompetition.swift      — international competitions list + follow model
│   ├── AthleteStatistics.swift        — ESPN Core API /statistics decode: category→field flatten → PlayerSeasonStats
│   ├── MatchSummary.swift             — ESPN /summary decode: lineups+formation, boxscore stats, key-events timeline
│   ├── PlayerSpotlight.swift          — Home Module-2 player-of-week mini-profile; Codable; `espnAthleteId` + `seasonStatLine` carry the LIVE `/spotlight` data (B2/0.3.8); `statStrip` prefers real stats, else seed `demoSeasonStats`
│   ├── PlayerStats.swift              — per-player season stats + team-leaders models (view-facing; real ESPN Core API data)
│   ├── XIPrediction.swift             — LIVE Predict-the-XI model (Fan Zone game 1, 0.3.9): PositionGroup · Formation (string→11 slots) · PredictionFixture · XIPrediction (draft→submitted) · ActualResult (from /summary, w/ `make(from:)` builder) · PredictionScore breakdown. Two-phase: roster pre-match → /summary answer key post-match
│   ├── Roster.swift                   — squad + team profile from one roster fetch
│   ├── Scoreboard.swift               — ESPN scoreboard structs + Event helpers
│   ├── Standings.swift                — table rows (rank + Club + GP/W/D/L/PTS)
│   ├── TeamSocialLinks.swift          — ⚠️ per-team social links for TeamDetail
│   └── TriviaQuestion.swift           — ⚠️ one Daily-Trivia question (4 options)
├── Services/                          — ESPNService + Supabase clients + ⚠️ curated async seed providers
│   ├── BracketEditionProvider.swift   — ⚠️ OFFLINE-FIRST sample Bracket edition (real forwards, 16) + sample leaderboard; live edition = Supabase
│   ├── BracketScoring.swift           — pure Bracket scorer: escalating per-round points + rule-derived max (546 for 64; mock's 468 is a slip). Unit-tested (BracketScoringTests)
│   ├── BracketService.swift           — Bracket data boundary: currentEdition/results/leaderboard/submit; ⚠️ Supabase reads/writes STUBBED (offline sample fallback) — next step
│   ├── AthleteStatsCache.swift        — actor; session cache of PlayerSeasonStats by athlete+year (backs seasonStats)
│   ├── ContentService.swift           — ALIVE content client: `homeCards(…)`→`/team-videos`, `feedCards(…)`→`/feed` ([ContentCard]), `spotlightCards(…)`→`/spotlight` ([PlayerSpotlight], B2/0.3.8); gated by `liveContentEnabled` (ON) + DEBUG `-useSeedContent`; failure → seed (offline-first)
│   ├── ESPNService.swift              — async fetch: scoreboard + summary (proxy)/teams/roster/standings + seasonStats (Core API, parallel per-athlete, best-effort)
│   ├── FollowSyncService.swift        — Supabase `follows` table client (fetch/push/add/remove); RLS-scoped per user
│   ├── DeviceTokenService.swift       — Supabase `device_tokens` client (register/remove APNs token); RLS-scoped; modeled on FollowSyncService
│   ├── NotificationPrefsSyncService.swift — Supabase `notification_preferences` client; whole-row upsert of the 9-flag snapshot so the watcher Worker honors "goals: off"
│   ├── NotificationScheduler.swift    — @MainActor; owns LOCAL (Tier 1) scheduling: day-before reminder + weekly spotlight; cancel-all/rebuild, deterministic ids; observes matches/clubs/follows/prefs; not env-injected (prompt in ProfileView)
│   ├── PushBridge.swift               — @MainActor @Observable `.shared` sink bridging UIKit AppDelegate (APNs token, notification tap) → the observable world (deliberate singleton; delegate can't be env-injected)
│   ├── SupabaseManager.swift          — the one shared SupabaseClient (built from Secrets)
│   ├── FeedContentProvider.swift      — ⚠️ Feed seed → [ContentCard]: reporter/news/social, 16 clubs + league — now the offline-first FALLBACK only (Feed is LIVE via `/feed`, A2/0.3.6)
│   ├── PlayerSpotlightProvider.swift  — ⚠️ one spotlight player per club (16) — now the offline-first FALLBACK only (Module 2 is LIVE via `/spotlight`, B2/0.3.8)
│   ├── PredictionScoring.swift        — pure Predict-the-XI scorer: XIPrediction × ActualResult → PredictionScore (Mastermind partial; players+3/position+2/formation+5/exact+10/result+3/perfect+15; max 88). Unit-tested (PredictXIScoringTests)
│   ├── PredictionMatchProvider.swift  — ⚠️ Predict-the-XI SIMULATED LEADERBOARD only now (the match slate went LIVE 0.3.9; real multi-user board = Game Center item)
│   ├── TeamContentProvider.swift      — ⚠️ Module-1 seed → [ContentCard]: 2 real YouTube videos/club + Bluesky/IG/social variants for marquee clubs
│   ├── TeamSocialLinksProvider.swift  — ⚠️ per-team social-account URLs seed
│   └── TriviaQuestionProvider.swift   — ⚠️ 55 hand-written NWSL trivia questions
├── Stores/                            — @Observable shared state → UserDefaults, injected
│   ├── AppRouter.swift                — tab selection (AppTab); RootTabView binds the TabView; Home's "Full schedule →" jumps tabs; `openMatch(eventID:)` + `pendingMatchEventID` for a live-push tap (TEMP seam: lands on Schedule); DEBUG `-startTab` init for in-sim verification
│   ├── AuthStore.swift                — @MainActor; Sign in with Apple → Supabase user; profile upsert; cached displayName; deleteAccount (⚠️ TEMP — real auth-user deletion needs a server fn); knows nothing about follows
│   ├── BracketStore.swift             — Bracket per-edition/round draft + one-way submit + banked points + cached edition summary (Home gate); `bracket.v2.*`
│   ├── ClubStore.swift                — shared club directory; one fetch, many readers (ID/abbr lookups)
│   ├── FeedPreferencesStore.swift     — Feed content-type toggles + muted sources
│   ├── FollowSyncCoordinator.swift    — @MainActor; the ONLY follows↔Supabase bridge (sign-in union-merge + ongoing sync); not env-injected
│   ├── NotificationSyncCoordinator.swift — @MainActor; Tier-2 twin: the ONLY device-token + notif-prefs↔Supabase bridge; observes auth/prefs/PushBridge.deviceToken; pushes best-effort once signed in; not env-injected
│   ├── FollowingStore.swift           — followed clubs + competitions + onboarding gate + sign-in-prompt flag; pure/offline-first; `onFollowsChanged`/`merge(ids:)` seams; DEBUG `debugResetState`
│   ├── MatchStore.swift               — shared season store; one fetch, many readers
│   ├── NotificationPreferencesStore.swift — Profile's 9 notif toggles; `onPreferenceChanged` → NotificationScheduler; `snapshot` → NotificationSyncCoordinator. LOCAL delivers day-before+spotlight; 6 live-event toggles mirror to Supabase once signed in; Fan Zone persists intent only
│   ├── PredictionStore.swift          — Predict-the-XI durable state (0.3.9): predictions[fixtureID:XIPrediction] (draft/submitted) + scores[fixtureID:PredictionScore], JSON under `predict.v2.*`; submit is one-way; `seasonPoints`/`hasPredicted` preserved for Home/Profile readers
│   └── TriviaStore.swift              — Daily-Trivia streak/accuracy + one-play/day gate
├── ViewModels/                        — @Observable; one per screen (idle/loading/loaded/error)
│   ├── BracketViewModel.swift         — Bracket session: round phase (open/submitted/closed/scored), progress, results, leaderboard, settled-round scoring
│   ├── FeedViewModel.swift            — content-type chips (All/News/Social — Social = reporter+club Bluesky+player IG/TikTok; B3a 0.3.8 folded "Reporters" in) + filtered [ContentCard] (follows∩ OR league, placement≠home, 7d staleness) + sources (prefs-aware); cards ← `ContentService.feedCards` (live `/feed`, seed fallback); clubs ← ClubStore
│   ├── HomeViewModel.swift            — derives Home modules from MatchStore+ClubStore+Following; Module-1 via ContentService (live-or-seed)
│   ├── MatchDetailViewModel.swift     — one match: temporalState (past/live/future) + /summary fetch + live refresh + preview
│   ├── PredictXIViewModel.swift       — Predict the XI slate (0.3.9 LIVE): builds open fixtures (each followed team's next match) from MatchStore+ClubStore+Following; scores newly-settled SUBMITTED predictions via /summary; lazy per-team roster cache; simulated leaderboard
│   ├── XIPickerViewModel.swift        — in-flight Predict the XI picker session: formation + slot→athlete + scoreline; hydrates from a draft, read-only once submitted; roster sheet groups (slot's band first)
│   ├── ScheduleViewModel.swift        — day-grouped sections + filters from MatchStore; My-teams ← ClubStore (error/retry)
│   ├── StandingsViewModel.swift       — one-shot fetchStandings
│   ├── TeamsViewModel.swift           — thin reader over the shared ClubStore (feeds Onboarding too)
│   ├── TeamDetailViewModel.swift      — roster + social links + real season stats/leaders (seasonStats)
│   └── TriviaViewModel.swift          — one Daily-Trivia session (deterministic daily 5)
├── Views/                             — one screen per file
│   ├── RootTabView.swift              — app root; 5-tab TabView (selection ← AppRouter); injects stores; restores session + FollowSyncCoordinator + NotificationSyncCoordinator; registers for remote notifications if authorized; routes a tapped live-push (PushBridge → AppRouter.openMatch)
│   ├── HomeView.swift                 — your-teams hub: 4 modules + profile-avatar button (→ ProfileView sheet); spotlight carousel; onboarding-in-place
│   ├── ProfileView.swift              — account & settings sheet (from Home avatar): identity / Fan Zone stats / notif toggles (7 shown; lineup/subs hidden until Stage D) / My Teams / Account; offline-first (signed-out CTA); Tier-2 toggles `requiresSignIn` → NotificationAuthPromptView; grant → registerForRemoteNotifications
│   ├── DailyTriviaView.swift          — Daily Trivia game (indigo); 5/day
│   ├── BracketBattleView.swift        — Bracket Battle (teal, 0.3.9): 5 screens — Edition Intro · Voting · Save/Submit · Results · Bracket Overview; sign-in at submit
│   ├── PredictXIView.swift            — Predict the XI game (pink, 0.3.9 LIVE): Open-for-predictions fixtures (draft/submitted/closed) + Results score breakdown + simulated leaderboard
│   ├── XIPickerView.swift             — Predict the XI picker sheet: formation chips → pitch-grid slots (tap → roster sheet) → scoreline steppers → Save draft / Submit (lock at kickoff−2h, one-way)
│   ├── OnboardingView.swift           — first-open team + competition follow picker
│   ├── SignInPromptView.swift         — one-time post-onboarding "save your picks" sheet (official Sign-in-with-Apple button + skip)
│   ├── NotificationAuthPromptView.swift — contextual "sign in for live alerts" half-sheet (Tier 2 requires sign-in); shown when a live-event toggle flips on while signed out; honest why-copy + skip
│   ├── ScheduleView.swift             — full-season cards; 3 filters; sticky day headers
│   ├── TeamsView.swift                — all-16 directory; Following floats to top; Follow-competitions row at bottom
│   ├── CompetitionsView.swift         — follow international competitions (from TeamsView; reuses onboarding rows)
│   ├── TeamDetailView.swift           — club page: header + social row + Squad·Stats tabs; accent ← design palette (dark-legible)
│   ├── MatchDetailView.swift          — state-aware match (navy header + cyan/orange tab underline): past=Summary/Lineups/Stats, live=+30s poll & LIVE pill, future=info grid + How-to-Watch + season comparison + form
│   ├── CombinedPitchView.swift        — BOTH teams' XIs on ONE pitch (home top / away bottom), reuses FormationPitchView placement; Lineups default
│   ├── FormationPitchView.swift       — single-team XI on a pitch (by formation string); the per-team list fallback when a side can't be placed
│   ├── PlayerDetailView.swift         — roster bio + season stat block
│   ├── PlayerSpotlightView.swift      — editorial spotlight: ghosted jersey # + split-name hero, This Season grid (real stats via `statStrip`), Story (Haiku blurb), Fast Facts + Watch (hidden when empty — live cards)
│   ├── StandingsView.swift            — 16-team table (abbr · PTS·GP·W·L·D); pinned column header (no title overlap); followed-row tint
│   ├── FeedView.swift                 — Feed tab: content-type chip bar + chronological ContentCardViews
│   └── FeedSourcesView.swift          — Feed content preferences: toggles + mute sources
├── Components/                        — reusable view pieces
│   ├── BroadcastInfo.swift            — "How to Watch" database (per-partner note + per-device steps), ported from the handoff BROADCAST_INFO
│   ├── BroadcastLink.swift            — broadcast name → streaming-service watch URL (unknown→nil); backs the tappable 📺
│   ├── Chip.swift                     — pill filter chip (active=accent / inactive=card); for Schedule + Feed chip bars
│   ├── ContentCardView.swift          — single entry point; routes a ContentCard by layout → the 3 card views below (Home + Feed call only this)
│   ├── ThumbnailContentCard.swift     — ⚠️ thumbnail-forward cards (layouts 1 youtube / 6 socialVideo) + ThumbnailHeader (bg image-or-gradient + stripe/play/duration/crest/platform overlay slots)
│   ├── AvatarContentCard.swift        — ⚠️ avatar-led cards (layouts 2/3/4/7) + shared atoms TeamRingAvatar, EngagementRow, CTARow
│   ├── ArticleContentCard.swift       — news-article card (layout 5): source row (club crest / article-badge) + time, headline, blurb, optional 80×80 thumb, team-color top stripe (matches video cards); LIVE on Home via club-site OG news (0.3.5)
│   ├── PlatformBadge.swift            — shared rounded platform glyph (YT/Bluesky/TikTok/IG/article/reddit color+SF-Symbol)
│   ├── FormBadge.swift                — W/D/L form badge (token-colored)
│   ├── GameCard.swift                 — Fan Zone game tile (170×138, game-accent border + emoji + status + badge)
│   ├── HowToWatchCard.swift           — future-match expandable broadcast guide (service tile + "Find it" → device rows)
│   ├── MDInfoCard.swift               — future-match info tile (emoji + tracked label + value) for Venue/Broadcast/Competition
│   ├── PitchDot.swift                 — one player marker (team-colored disc + jersey + last name); Formation/Combined pitch
│   ├── ComingUpRow.swift              — Module-4 row: crest-vs-crest + team-colored abbrs + time/result
│   ├── EventTimelineRow.swift         — one timeline entry: minute + icon (goal/card/sub) + player(s) + assist + abbr
│   ├── FlowLayout.swift               — wrapping Layout (iOS16) — backs the Lineups substitute chips
│   ├── ImageCache.swift               — in-memory NSCache singleton; backs TeamLogo (no re-download)
│   ├── MatchCard.swift                — V2: bare TeamLogo crests + hairline status column + orange live clock + venue/📺; → MatchDetailView
│   ├── PlayerDot.swift                — Bracket player chip: team-ring jersey monogram + name/abbr (no headshots); backs the matchup cards
│   ├── PlayerCard.swift               — Squad-grid card; team-color monogram + position
│   ├── StatComparisonBar.swift        — head-to-head split bar (team-colored values | tracked-caps label | split track); past + future
│   ├── PlayerSpotlightCard.swift      — Module-2 profile card: PLAYER OF THE WEEK + jersey + hook + stat strip (`statStrip` = real-or-demo) + Read-spotlight
│   ├── SocialLinkButton.swift         — circular team-tinted social icon; opens account
│   └── TeamLogo.swift                 — team crest via the shared ImageCache (cached; placeholder fallback)
├── Extensions/
│   ├── Color+Hex.swift                — Color(hex:) init (for DSColor); teamAccent/teamFillOnDark (lifts dark brands); resolveMatchColors → two distinct, dark-legible team colors
│   ├── Date+RelativeAgo.swift         — shared "2h ago" RelativeDateTimeFormatter (5 of 7 content cards)
│   ├── Club+BrandColor.swift          — Club → brandHex/accentColor (design palette → id-override → ESPN); team-color accents for Home/ComingUp
│   ├── DesignTeamColors.swift         — the handoff's curated 16-team palette by abbreviation (authoritative; fixes ESPN near-black primaries → gray)
│   └── TeamBrandColors.swift          — per-team-id brand-color overrides for clubs ESPN gets wrong (e.g. Angel City Sol Rosa coral); consulted before ESPN's hexes
└── Assets.xcassets/                   — app icons, accent color
```

---

## Current State

Root is `RootTabView` — a 5-tab bar (**Home · Schedule · Standings · Teams ·
Feed**), each its own `NavigationStack`; **lands on Home**. **Dark appearance
app-wide**; no toggle. Following persists via `UserDefaults` (`FollowingStore`);
SwiftData used **nowhere**. The season (`MatchStore`) + club directory (`ClubStore`)
are each fetched **once and shared app-wide** via `.environment`; the My-teams schedule
filter surfaces a real error + retry if the directory fails. Features are built per
`Reference/Design/*-spec.md` and **verified in-sim** via a temporary screenshot scaffold
(see Commands), then removed.

**Design-system redesign (0.3.x — its own chapter, all 6 phases shipped)** — fidelity pass
vs the Claude Design handoff (`Reference/nwslapp-design-system/`). The `DesignSystem/` token
layer (dark-only hex; page `#1C1C1E`, cards `#2C2C2E`) backs every screen. **Crest rule:**
bare via `TeamLogo`, no ring (only player monograms get one). **Team colors:**
`DesignTeamColors` by abbreviation, so ESPN near-black primaries stay legible. **Nav:**
pushed screens show a left "‹ Label" via `.navigationContextLabel(…)`.

**Accounts & follow sync** (`…/2026-06-09_supabase-accounts-setup.md`) — Sign in with Apple →
a **Supabase** user (`AuthStore` upserts `profiles`; `RootTabView` restores the session +
starts `FollowSyncCoordinator`). **Optional/offline-first**: skippable post-onboarding
`SignInPromptView`; skipping leaves the app fully working on the UserDefaults cache. Sync
mechanics (union-merge, RLS, clubs-only) → Architecture / Per-user backend.

**Notifications — Tier 1 / LOCAL** (0.3.2; `local-notifications-spec.md`) —
`NotificationScheduler` (held alive by `RootTabView`) delivers two phone-scheduled alerts:
**day-before match reminder** (−24h) + **weekly Player Spotlight** (Mon 10am); permission on
first toggle-on. **Tier 2 / SERVER push** → What's-Next #12.

Per-screen behavior (full file detail in the File Map; specs in `Reference/Design/*-spec.md`):

- **Home** (`home-tab-design-spec.md`) — your-teams hub; pre-onboarding renders
  `OnboardingView` in place. Four `HomeViewModel` modules: (1) "From your teams" (Content
  Cards, LIVE), (2) spotlights (LIVE), (3) "Fan Zone" games, (4) "Coming up". Games ordered
  Predict → Bracket → Trivia (**Predict only when ≥1 club followed**); no-follows re-presents
  the picker.
- **Fan Zone games** (`games-design-spec.md`) — **Predict the XI** (pink) **LIVE** (0.3.9):
  pick a followed team's XI + formation + scoreline pre-match, auto-scored Mastermind-style
  vs ESPN `/summary` (max 88; Draft→Submit one-way, closes kickoff−2h, only submitted score).
  **Visibility rule (all games):** hidden EVERYWHERE (Home card + screen) when nothing
  active/upcoming — Predict's gate = followed-team fixture **within 28 days**; the module
  hides when no game is visible. **Bracket Battle** (teal) — APP-SIDE LIVE (0.3.9): the real
  64-player / 6-round community-voting tournament (5 screens per the Claude Design ref;
  escalating scoring Rd64+5…Final+40; draft→submit one-way; sign-in at submit; gate hides when
  no active edition). Renders an offline-first sample edition; **real Supabase voting + the
  ESPN/Haiku edition-generation engine are PENDING** (the votes are stubbed — see What's Next).
  **Daily Trivia** (indigo) still ⚠️seed. Leaderboards simulated (real = Game Center).
- **Player Spotlight** (`spotlight-design-spec.md`) — one mini-profile/followed team →
  `PlayerSpotlightView`. **LIVE** (B2/0.3.8) via proxy `/spotlight`: real player + ESPN stats
  + a Haiku "why watch" blurb, weekly rotation. Seed = offline-first fallback.
- **Feed** (`feed-tab-design-spec.md`) — reporters + news + social filtered to followed
  teams + league (distinct from Home Module 1). **Content-type** chip bar (All/News/Social —
  Social = every individual voice; B3a/0.3.8 folded "Reporters" in) over the LIVE `/feed`
  cards; gear → `FeedSourcesView` (type toggles + per-source mute).
- **Content Cards** (`we-are-going-to-iridescent-otter.md`) — one `ContentCard` model +
  `ContentCardView` router back BOTH Home Module 1 and the Feed via 7 layouts. Placement
  gate (Home = team voices; Feed = wider; `.both` either) + staleness (Home 72h / Feed 7d,
  6-card-floored, 0.3.7). **All LIVE** via `ContentService` → proxy (seed = fallback).
  **Home** ← `/team-videos` = YouTube + club OG news + club IG. **Feed** ← `/feed` = Bluesky
  map (reporters + league + 13/16 clubs; club Bluesky is `.feed`) + News + player IG.
  Server-side: Haiku relevance filter (`claude-haiku-4-5`, KV-cached), 3/account flood cap,
  `dedupeByContent`. B-item detail (B1 News RSS→Haiku-gate→OG-enrich · B2 `/spotlight` · B3a
  chips · B3b Apify IG cron→KV, TikTok deferred) → File Map + `Reference/Feed update/…handoff`.
- **Teams + Following** — `TeamsView` lists all 16 (followed float up); onboarding + a bottom
  row offer **international competitions** (persisted; schedule not competition-aware yet, #13).
- **Team detail** (`teams-tab-design-spec.md`) — pinned header + social row
  (⚠️`TeamSocialLinksProvider`) over **Squad · Stats**. Squad = `PlayerCard` grid (FWD→GK) →
  `PlayerDetailView`. Stats = season summary + Goals/Assists/Clean-Sheets leaders from **real
  ESPN stats** (`ESPNService.seasonStats`, actor-cached) (#8).
- **Standings** (`standings-tab-design-spec.md`) — full 16-team table (**PTS·GP·W·L·D**);
  followed rows tinted → `TeamDetailView`.
- **Schedule** (`schedule-tab-design-spec.md`) — full season in one `fetchScoreboard(year:)`;
  sticky day headers; 3 `MatchStore` filters; cards carry 📍 venue · 📺 broadcast; scrolls
  to today.
- **Match detail V2** (`match-detail-v2-spec.md`, `-polish.md`) — `MatchDetailView` + VM
  adapt to temporal state (Past/Live/Future); header from the `Event`, `/summary` (proxy)
  layers the rest (failure → header-only); `resolveMatchColors` keeps sides distinct.

---

## What's Next

Completed work lives in **Current State**; only pending work here. Item numbers are kept so
cross-references stay valid. **Ordered by the PRIORITY FRAMEWORK** — Category 1 (ALIVE)
always outranks 2/3.

**Category 1 — ALIVE features (TOP PRIORITY).** Do these before any Category 2/3 work and
before any TestFlight ship. The content pipeline is LIVE end-to-end (Home + Feed; YouTube ·
club OG news · Bluesky · News RSS · Instagram · Player Spotlight). **Backbone sequence**
(`Reference/BACKBONE.md` + `Reference/Feed update/` handoff): A1/A2 · B1 · B2 · B3a · **B3b
all SHIPPED**.
- **Fan Zone games (0.3.9):** swap the ⚠️seed games for live rounds, in order —
  ~~**Predict the XI** (LIVE)~~ ✅ → **Bracket Battle** 🔨 app-side LIVE (5 screens + models +
  scoring + store/VM + Home gate, on branch `feature/bracket-battle`); **NEXT for Bracket =
  the real-voting backend**: Supabase schema (`bracket_editions`/`_matchups`/`_votes` RLS +
  grants/`_scores`/`bracket_leaderboard` view) + wire `BracketService` submit/results/
  leaderboard to Supabase (currently TEMP-stubbed) + one seeded edition; then the proxy Worker
  edition-generation engine (ESPN stats-seeded + Haiku creative themes + scheduled round
  advancement/tallying). → **Daily Trivia** (question pool) → **Game Center** (GameKit
  leaderboards across all three). Then **B4 final sweep** → ship **0.3.9** (QOL begins at 0.4.0).
- **A3 Reddit → Feed** — DEFERRED (noisy; subreddits live in Teams). IG now via Apify (B3b).

**Category 3 — HARDENING** (cleanup/robustness — do AFTER Category 1, never above it)
3. **(Polish)** Keep the list visible during pull-to-refresh (spinner only on first load),
   not flipping `state` to `.loading` full-screen.
4. Capture a real ESPN response → `NWSLAppTests/Fixtures/scoreboard.json` + a decode-only
   test for `Scoreboard`/Event helpers (date parsing, `dayKey` TZ).
6. **Match-detail V2 follow-ups (remaining):** `/headshots` route + NWSL-GUID↔ESPN-id map →
   headshots on pitch dots/`PlayerCard`; future-preview season averages; dynamic
   `currentSeasonYear`.
9. **(Fragility)** `MatchStore.matches(for:)` joins club↔game by `abbreviation` (no id
   on ESPN competitors); a rename silently empties a schedule. Fix: a normalized id map.
18. **Weather API + kickoff-temp header slot** — its own push (API key in Secrets,
    venue→coords, fetch-at-kickoff). The header info row already renders conditionally, so
    re-adding the 🌡 slot is a one-line change.

**Feature follow-ups (from shipped redesigns)**
- **Team-detail Stats + PlayerDetailView** — on **real** ESPN stats (#8). Remaining: a
  most-recent-formation pitch.
- **(Data/Verify) Team social links** — ⚠️`TeamSocialLinksProvider` seed; verify Reddit
  (**KC** `r/KCCurrent`, **CHI** `r/redstars` vs `r/ChicagoStars`; **BOS/DEN/LOU** none).
- **Follow-confirmation sheet** — first-time "what following buys you" on the header star.
- **Home Module 1** — LIVE. Remaining: a "See all" destination + refetch-on-follows-change.
- **Home Module 2 spotlight** — LIVE (B2/0.3.8). Remaining: no-repeat-per-season,
  player-video match, opt-in weekly notif, badge, refetch-on-follows-change.
- **Home Module 3 games** — the live swap is the **Fan Zone (0.3.9)** work in Category 1.

**Longer-term (vision — see `Reference/Sessions/`)**
11. **Feed backend** — Bluesky + Haiku filter LIVE. Remaining: user-added sources; richer
    filtering. (Reddit/A3 deferred.)
12. **Push notifications.** Tier 1 (LOCAL) shipped 0.3.2. Tier 2 (SERVER push)
    code-complete through Stage C (≈0.4.x; PR #32) — app side + Worker (private sibling
    `~/Projects/nwslapp-match-watcher`: 1-min cron, KV state-diff via `/scoreboard`, APNs
    `.p8` JWT; detects kickoff · goal · halftime · full-time). Infra provisioned + APNs
    verified 2026-06-10 (`push_infra_provisioned` memory). **Remaining:** flip `APNS_HOST`
    sandbox→production at TestFlight; on-device E2E (waits on July break). **Stage D (next):
    subs + lineup-posted** (needs per-match `/summary`). (See `…/2026-06-04_server-pulls-and-push.md`.)
13. **Competition-aware schedule.** Groundwork: 3 Schedule filters, `MatchCard`'s dormant
    `CompetitionBadge`, `FollowedCompetition` + follow set. Remaining: a competition field
    on `Event` + a follow-edit surface.
14. **Engagement / Home hub** — spotlights, community links, prediction games. Home modules
    first; a tab only if earned.
