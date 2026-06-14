# NWSLApp — Project Context for Claude

## ⚠️ WHAT THIS APP IS — READ FIRST

**A women's soccer (NWSL) fandom app.** It's a lively hangout for fans: follow your
clubs, keep up with your favorite soccer voices (reporters, club + player social),
play and share Fan Zone mini-games (Bracket Battle, Predict the XI, Daily Trivia),
and check scores, schedule, and standings. The **fandom** — community, the games,
social sharing, live/"alive" content, and a personal connection to your teams — **is
the product.** Scores/schedule/standings are table stakes that must work, but they are
**not** the differentiator.

**Anti-pattern to avoid (this matters):** do NOT treat this like a traditional
sports/stats app (an ESPN/March-Madness clone) and shrink the fandom side. When a
design plan (e.g. from Claude Design) emphasizes fandom, social, or playful content,
**build it that way** — don't slot it into a stats-app mold or trim the fandom content
down. The fandom half and the sports half are equally core; the fandom half is what
makes the app worth opening.

**The litmus test:** "Would I open this app today if I opened it yesterday?" If a
surface looks identical because the data is static, that's a bug — the app is built to
feel alive (fresh content every open, fan engagement, personal connection).

**Priority order when deciding what to work on:**
1. **ALIVE features** — live content pipelines (YouTube/club news/Bluesky → Home & Feed,
   Player Spotlight rotation, Fan Zone games) and fan engagement.
2. **Core functionality** — scores, schedule, standings, stats (must work; not the differentiator).
3. **Hardening** — bug fixes, tests, robustness. Never above category 1.

**Owner:** Tiffany Rieth. Personal project to build production-quality iOS skills and
ship a real consumer app; long-term goal is App Store distribution.

---

## State of the app

The app is **fully live and in production-quality state** (v0.4.0) — real data
everywhere, used daily by the owner + testers as their primary NWSL app. There is **no
demo/fake data** in normal operation; curated seed data survives only as an **offline
fallback** (live data is always primary). Treat the app as a real, working product when
building — never suggest a "demo" mode or scaled-down placeholder.

Every surface pulls live: ESPN (scores/schedule/standings/teams/rosters/match detail
via a caching proxy), the content pipeline (Home + Feed: YouTube · club-site news ·
Bluesky · news RSS · Instagram · Player Spotlight, all via the proxy), the three Fan
Zone games (real Supabase leaderboards), and Sign-in-with-Apple accounts (Supabase).

---

## Tech Stack

- **Language/UI:** Swift 5.9+, SwiftUI (not UIKit). Min iOS 17 (for `@Observable`). Xcode 26.5.
- **State:** `@Observable` (modern) over `ObservableObject`.
- **Networking:** `URLSession` + `async/await`. No third-party HTTP libraries.
- **Persistence:** UserDefaults for small local state (follows, game stats); **Supabase**
  (Postgres) as the durable per-user source of truth once signed in. SwiftData used nowhere.
- **Auth / per-user backend:** Sign in with Apple → **Supabase** (Postgres + native Apple
  auth + Row-Level Security). The project's **only** third-party dependency is the
  **Supabase Swift SDK** (`supabase-swift`, SPM) — justified vs raw URLSession (JWT refresh,
  RLS headers, keychain session). Credentials live in gitignored `Config/Secrets.swift`
  (template `Secrets.example`); the anon key is a public client key — RLS is the real boundary.
- **Testing:** Swift Testing (`@Test` + `#expect()`), not XCTest.

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
**Driving the sim:** synthetic taps (cliclick) are unreliable for SwiftUI controls — the
UIKit tab bar responds but NavigationLinks/Buttons/Pickers often don't, so in-sim
verification uses temporary DEBUG deep-link/launch-arg scaffolds (then removed). `idb ui
tap` (HID-level) is more robust if installed.

---

## Architecture

**MVVM** with strict separation:
- `Models/` — `Codable` structs matching API responses; no UI or networking.
- `Services/` — API clients (ESPN, Supabase, content); no UI logic.
- `ViewModels/` — `@Observable` classes owning view state; state-enum pattern
  (`idle`/`loading`/`loaded`/`error`).
- `Stores/` — `@Observable` shared app state → UserDefaults, injected via `.environment`
  (one fetch, many readers).
- `Views/` — one screen per file; minimal logic. `Components/` — reusable pieces.
- `DesignSystem/` — `DSColor`/`DSMetrics`/`DSText` token layer (dark-only). Team colors
  stay dynamic via `Color+Hex`.

Folders are created when their first real file lands, not preemptively.

---

## Data Source

**Primary:** ESPN's unofficial NWSL endpoints (community reverse-engineered, unsupported).
- Base: `https://site.api.espn.com/apis/site/v2/sports/soccer/usa.nwsl/`
- Scoreboard (full season): `scoreboard?dates=YYYY0101-YYYY1231&limit=500`

**Known quirks (decode defensively):**
- Scores decode as `String` (`"0"`), not `Int`.
- Event timestamps sometimes lack seconds — custom parsing in `Event.kickoff`.
- Default scoreboard caps ~100 events; `&limit=500` returns the full season.
- Standings lives at `apis/v2/…` NOT the `apis/site/v2/…` base.
- Player headshots are null for every NWSL athlete — squad cards show a jersey/initials
  monogram, not a photo (permanent, not a TODO).
- Feed articles are legal-limited to headline + summary + link — never the article body.
- Endpoints can change shape, break, or rate-limit without notice. Fail gracefully.

**Proxy (Cloudflare Worker `nwslapp-proxy`)** — sibling repo `~/Projects/nwslapp-proxy`
(GitHub `tiffanyrieth/nwslapp-proxy`), live at `https://nwslapp-proxy.tiffany-rieth.workers.dev`.
- **Pass-through caching:** `GET /scoreboard`, `GET /summary?event={id}` forward to ESPN
  and return bytes **unchanged** (app decoders untouched); match-state-aware TTL.
- **Content routes** (build + normalize to JSON `[ContentCard]` / models): `/team-videos`
  (Home: YouTube + club OG news + club Instagram), `/feed` (Feed: Bluesky reporters/clubs +
  news RSS + player Instagram), `/spotlight` (Player Spotlight), `/trivia` (Daily Trivia
  KV pool). Server-side does Haiku relevance filtering (`claude-haiku-4-5`, KV-cached), a
  flood cap, and dedupe.
- **Bracket engine:** `src/bracket.ts` + `bracket-engine.ts` — auto-generate 64-player
  editions from ESPN, tally votes + advance rounds on a cron, rotate creative↔stats editions.
- Teams/roster/standings still hit ESPN directly. Base URLs in `Config/AppConfig.swift`;
  DEBUG `-useESPNDirect` bypasses the proxy.

**Per-user backend (Supabase):** boundary = Workers (stateless/global) vs Supabase
(stateful/per-user). Sign in with Apple → a Supabase user; a `profiles` row + `follows`
row-set (RLS'd to the owner) persist per account. **Offline-first:** UserDefaults is the
immediate local cache; the app never blocks on the network to show follows. On sign-in
local and server follow sets are **merged (union — never delete)**. Schema (tables + RLS +
the required `authenticated` GRANTs) is checked in at `supabase/schema.sql`. **Gotcha:**
RLS alone isn't enough — a new per-user table needs `grant … to authenticated` or signed-in
queries silently fail with `42501`. The Supabase client is built from gitignored `Secrets`
(see `Services/SupabaseManager.swift`).

---

## Workflow & Engineering Practices

Treat these as requirements. If a request would bypass one, pause, flag it, explain the
trade-off before proceeding.

**Build to spec, not to minimum.** Numbers in a design doc are requirements, not
suggestions. Don't ship scaled-down versions that need follow-up to reach spec. A feature
isn't "shipped"/checked off until EVERY sub-item is automated + verified — no partial
credit; a scaffold needing manual steps ≠ the feature. Don't reclassify required work as
"deferred."

**Prove it live.** Verify "it works" with evidence (curl the proxy/REST, screenshot the
sim, trace the code path) — never reason from an unverified assumption.

**Before starting a session:** `git status` (resolve uncommitted changes first); never
work on `main` — branch `feature/<desc>` first; state what you'll touch.

**During work:** for a change touching 3+ files or a new pattern, present a plan and get
approval first. Don't add a dependency without explaining why the built-in won't work +
approval. No force-unwraps (`!`) unless a comment explains why it's safe. Temporary code
that bends architecture carries a `TEMP` comment (what/why/when-removed).

**Before "done":** app builds AND runs in the simulator with no errors; the feature is
**manually verified in-sim** (compiling ≠ working); commit messages are specific,
present-tense, `<Area>: <what changed>`; update the **File Map** + **Current State** below;
confirm before pushing (don't auto-push).

**Git:** never commit to `main` — work on a feature branch, merge via **squash-merge** PR
(one commit on main; OK to combine related branches into one PR). Never commit secrets.
Commits use the owner's GitHub no-reply email (`286203575+tiffanyrieth@users.noreply.github.com`).
CLAUDE.md/commits/PRs/comments stay neutral/professional — never reveal owner preferences;
use arbitrary teams for examples.

**Local hooks** (`hooks/`): `pre-commit` blocks commits onto `main`; `pre-push` blocks
deleting/force-pushing `main`. Bypass with `--no-verify`; a fresh clone runs
`git config core.hooksPath hooks` to enable. See `hooks/README.md`.

**`gh` auth expires mid-session:** the token can go stale — `git push` keeps working but
`gh` API calls (`gh pr create`/`merge`, `gh api`) fail `HTTP 401`. Fix: owner runs
`gh auth refresh -h github.com`, then retry. So a push that succeeds but a follow-up PR
merge that 401s is this, not a permissions problem.

---

## Collaboration Preferences

This project doubles as a way to build durable iOS/software-engineering skills —
understanding each change matters as much as shipping it.
- Explain the reasoning behind non-obvious decisions/trade-offs as you go.
- When introducing a new file/folder, note why it's organized that way.
- First time a pattern appears (MVVM, state enums, `async`/`await`, `Codable`), briefly
  explain how it works.
- If a request reflects a misunderstanding or would introduce bad practice, say so and
  propose the better approach.
- **Decision split:** the owner owns design/UX/product calls; defers fine engineering
  logistics to Claude AFTER a reasoned explanation. Explain-then-recommend; don't over-ask
  on low-level forks, but never guess product/cost calls.
- **Nothing is impossible:** never answer "can we do X?" with "not possible / no API."
  Research alternatives, present the menu of paths + costs/tradeoffs, let the owner decide.

---

## UI Requirements

- Persistent UI (tab/nav bars) must never obscure scrollable content — respect safe areas.
- Every drilled-in view has an explicit back affordance; don't rely on edge-swipe alone.
- Navigation state resets predictably (tapping a tab returns to its root).
- Placeholders allowed only as intentional scaffolding: a clean "Coming soon" state (never
  blank/broken) AND flagged in the File Map. A placeholder must look deliberate, not forgotten.
- The schedule shows the full season, not a rolling window.
- Clarity over density — screens should breathe (~4–5 schedule cards/screen; avoid oversized
  NWSL/MLB-style cards).
- **Dark appearance app-wide**, no toggle (page `#1C1C1E`, cards `#2C2C2E`).
- **Crest rule:** bare crests via `TeamLogo`, no ring (only player monograms get a ring).
- **Team colors:** `DesignTeamColors` by abbreviation so ESPN near-black primaries stay legible.
- **Team naming:** two teams together → abbreviations (WAS 1–0 ORL); one team as subject →
  full club name (Gotham FC). ESPN has no nickname field.

---

## Navigation Identity

Each tab has a distinct lens. When adding/redesigning, check the lens matches and neighbors
stay consistent. Full rationale in `Reference/navigation-architecture.md`.
- **Home** — your teams, right now. Personal + temporal. The engagement hub (live content,
  Player Spotlight, Fan Zone games, "Coming up").
- **Schedule** — when do they play / what happened? Full-season calendar.
- **Standings** — where does your team sit?
- **Teams** — the club directory + deep dives.
- **Feed** — the conversation around your teams (reporter/journalist/social voices).

**Adjacency rule:** Home Module 1 (team content) and Feed (reporter/social voices) are
distinct — don't blur them. Schedule cards and MatchDetailView share visual language.

---

## Versioning & Distribution

- **Semver, pre-1.0.** A **minor bump = a whole chapter** of the app, not a single feature;
  patches (third digit) are each shipped update inside the chapter (pre-1.0 this includes
  features, not just fixes). Reserve **1.0.0** for the first public App Store launch.
- **Chapters:** `0.1.x` was the offline prototype; `0.3.x` was the **backbone** (demo →
  fully live, all real data) — **shipped at 0.3.9**. **`0.4.x` = QOL** — improving the
  *experience* of what's already alive (content balancing, polish, UX), not new backbone
  plumbing; **0.4.0** landed the handoff's three changes (Home round-robin balancing + chips,
  per-team Follow vs Alerts).
- **Xcode fields:** "Marketing Version" (`CFBundleShortVersionString`, human-facing) +
  "Build" (`CFBundleVersion`, a monotonic int bumped on every TestFlight upload). Tag
  releases in git (`git tag v0.3.9`). Proxy-only changes don't bump the app version.
- **Distribution:** Simulator + Personal Team sideload now; Dev Program is active (paid);
  TestFlight (OTA) for tester install. App Store deferred until presentable.

---

## File Map (UPDATE THIS AFTER EVERY FEATURE)

Marker: ↩︎ = curated seed used as an **offline-first fallback** (live data is primary; the
seed serves only when the network fails or DEBUG `-useSeedContent` is set). 🔧 = intentional
"coming soon" placeholder. Design specs in `Reference/Design/*-spec.md`.

```
NWSLApp/
├── NWSLAppApp.swift                   — app entry; launches RootTabView; forces dark; DEBUG `-resetOnboarding`; AppDelegate (APNs token + foreground/tap → PushBridge)
├── NWSLApp.entitlements               — Sign in with Apple + aps-environment (push) + game-center (Game Center)
├── Config/
│   ├── AppConfig.swift                — base URLs; scoreboard/summary → proxy; DEBUG `-useESPNDirect`; `liveContentEnabled`; content route URLs (teamVideos/feed/spotlight/trivia)
│   ├── Secrets.swift                  — 🔒 GITIGNORED Supabase URL + anon key
│   └── Secrets.example                — checked-in template (non-.swift so it never compiles)
├── DesignSystem/
│   ├── DSColor.swift                  — `Color.ds*` tokens (dark-only hex)
│   ├── DSMetrics.swift                — `enum DS` spacing/radii/avatar/crest/game-card dims
│   └── DSText.swift                   — modifiers: `.trackedCaps()`, `.sectionTitle()`, `.navigationContextLabel("…")`, `Font.dsScore`
├── Models/
│   ├── BracketEdition.swift           — Bracket Battle: BracketRound/Entrant/Matchup/Edition (64→6 rounds, flat Codable)
│   ├── Club.swift                     — flat Club + ESPN /teams decode (brand/alternate color → crests)
│   ├── ContentCard.swift              — unified ALIVE-content model: 7 layouts + StalenessWindow (Home 72h / Feed 7d, 6-card-floored)
│   ├── FollowedCompetition.swift      — international competitions list + follow model
│   ├── AthleteStatistics.swift        — ESPN Core API /statistics → PlayerSeasonStats
│   ├── MatchSummary.swift             — ESPN /summary: lineups+formation, boxscore, key-events timeline
│   ├── PlayerSpotlight.swift          — Home Module-2 player-of-week; `espnAthleteId`+`seasonStatLine` carry live data; `statStrip` prefers real, else ↩︎`demoSeasonStats`
│   ├── PlayerStats.swift              — per-player season stats + team-leaders (real ESPN data)
│   ├── Roster.swift                   — squad + team profile from one roster fetch
│   ├── Scoreboard.swift               — ESPN scoreboard structs + Event helpers
│   ├── Standings.swift                — table rows (rank + Club + GP/W/D/L/PTS)
│   ├── TeamSocialLinks.swift          — ↩︎ per-team social links for TeamDetail
│   ├── TriviaQuestion.swift           — one Daily-Trivia question (4 options)
│   └── XIPrediction.swift             — Predict the XI: PositionGroup · Formation · PredictionFixture · XIPrediction (draft→submitted) · ActualResult · PredictionScore
├── Services/
│   ├── BracketScoring.swift           — pure Bracket scorer (tiered per-round points). Unit-tested
│   ├── ContentRoundRobin.swift        — pure Home Module-1 fair-share: `balanced` (guaranteed-per-team round-robin + chronological fill + follow-scaled cap) + `advancedOffsets` (pull-refresh rotation) + `passes` (content-type chip classifier) + `HomeContentFilter`. Unit-tested
│   ├── BracketService.swift           — Bracket Supabase client: currentEdition/results/leaderboard/submit; offline-sample fallback
│   ├── AthleteStatsCache.swift        — actor; session cache of PlayerSeasonStats
│   ├── ContentService.swift           — ALIVE content client: homeCards→/team-videos, feedCards→/feed, spotlightCards→/spotlight; gated by `liveContentEnabled`; failure → ↩︎seed
│   ├── ESPNService.swift              — async fetch: scoreboard + summary (proxy)/teams/roster/standings + seasonStats (Core API)
│   ├── FollowSyncService.swift        — Supabase `follows` client (fetch/push/add/remove); RLS-scoped
│   ├── DeviceTokenService.swift       — Supabase `device_tokens` client (APNs token); RLS-scoped
│   ├── NotificationPrefsSyncService.swift — Supabase `notification_preferences` upsert
│   ├── NotificationScheduler.swift    — @MainActor; LOCAL (Tier 1) scheduling: day-before reminder (global type ∩ teams with alerts on) + weekly spotlight (global)
│   ├── PushBridge.swift               — @MainActor @Observable `.shared`; UIKit AppDelegate (APNs/tap) → observable world
│   ├── SupabaseManager.swift          — the one shared SupabaseClient (built from Secrets)
│   ├── GameCenterIDs.swift            — GameKit ID constants (4 leaderboards + 6 achievements) + pure cross-game score helpers (GameKit-free, unit-tested)
│   ├── GameCenterManager.swift        — @MainActor @Observable `.shared`; auth + best-effort submit/report + syncAll + showDashboard (GKAccessPoint). The only file importing GameKit
│   ├── TeamAlertPrefsSyncService.swift— Supabase `team_alert_preferences` client (per-team on/off upsert/fetchAll, composite key); RLS-scoped
│   ├── SupportStore.swift             — @MainActor @Observable StoreKit 2 layer for Support: 4 tip tiers (one-time consumables + monthly subs), load/purchase/restore, `purchased` thank-you flag
│   ├── PredictLeaderboardService.swift— Supabase per-team Predict board: upsertScore + standings(team); offline fallback to local you-row
│   ├── TriviaLeaderboardService.swift — Supabase league-wide Trivia best-streak board: upsertScore + standings; offline fallback
│   ├── PredictionScoring.swift        — pure Predict-the-XI scorer (Mastermind partial, max 88). Unit-tested
│   ├── PredictionMatchProvider.swift  — ↩︎ Predict the XI simulated-leaderboard fallback only
│   ├── FeedContentProvider.swift      — ↩︎ Feed seed → [ContentCard] (Feed is live via /feed)
│   ├── PlayerSpotlightProvider.swift  — ↩︎ one spotlight player per club (live via /spotlight)
│   ├── TeamContentProvider.swift      — ↩︎ Module-1 seed → [ContentCard] (live via /team-videos)
│   ├── TeamSocialLinksProvider.swift  — ↩︎ per-team social-account URLs (stable reference list)
│   ├── TriviaService.swift            — Daily-Trivia client: triviaQuestions→/trivia; live-or-↩︎seed
│   └── TriviaQuestionProvider.swift   — ↩︎ 55 hand-written trivia questions (live via /trivia)
├── Stores/                            — @Observable shared state → UserDefaults, injected
│   ├── AppRouter.swift                — tab selection (AppTab); `openMatch(eventID:)` live-push tap; DEBUG `-startTab`
│   ├── AuthStore.swift                — @MainActor; Sign in with Apple → Supabase user; profile upsert; cached displayName; deleteAccount
│   ├── BracketStore.swift             — Bracket per-edition/round draft + one-way submit + banked points + cached edition (`bracket.v2.*`)
│   ├── ClubStore.swift                — shared club directory; one fetch, many readers
│   ├── FeedPreferencesStore.swift     — Feed content-type toggles + muted sources
│   ├── FollowSyncCoordinator.swift    — @MainActor; the ONLY follows↔Supabase bridge (sign-in union-merge + ongoing sync)
│   ├── NotificationSyncCoordinator.swift — @MainActor; device-token + notif-prefs↔Supabase bridge
│   ├── TeamAlertStore.swift           — @Observable; per-team match-alert ON/OFF (`enabledTeamIDs: Set<String>`) → UserDefaults; `migrateFromGlobalIfNeeded` seeds followed teams iff a global match-day toggle was on; `onAlertChanged` sync seam
│   ├── TeamAlertSyncCoordinator.swift — @MainActor; per-team on/off↔Supabase bridge + clears a team's alerts when it leaves the followed set (alerts require following)
│   ├── FollowingStore.swift           — followed clubs + competitions + onboarding gate; offline-first; DEBUG `debugResetState`
│   ├── MatchStore.swift               — shared season store; one fetch, many readers
│   ├── NotificationPreferencesStore.swift — Profile's 9 notif toggles; → NotificationScheduler / NotificationSyncCoordinator
│   ├── PredictionStore.swift          — Predict-the-XI durable state: predictions+scores by fixtureID (`predict.v2.*`); `seasonPoints` + `points(forTeam:)` + `scoredTeams`
│   └── TriviaStore.swift              — Daily-Trivia streak/bestStreak/accuracy + one-play/day gate
├── ViewModels/                        — @Observable; one per screen (idle/loading/loaded/error)
│   ├── BracketViewModel.swift         — Bracket session: round phase, progress, results, leaderboard, settled-round scoring (+ Game Center submit)
│   ├── FeedViewModel.swift            — content-type chips (All/News/Social) + filtered [ContentCard] (follows∩ OR league, 7d staleness); cards ← ContentService
│   ├── HomeViewModel.swift            — derives Home modules from MatchStore+ClubStore+Following; Module-1 via ContentService
│   ├── MatchDetailViewModel.swift     — one match: temporalState (past/live/future) + /summary + live refresh + preview
│   ├── PredictXIViewModel.swift       — Predict slate (open fixtures per followed team) + scoring via /summary + real per-team leaderboards (+ Game Center submit)
│   ├── XIPickerViewModel.swift        — in-flight XI picker: formation + slot→athlete + scoreline; read-only once submitted
│   ├── ScheduleViewModel.swift        — day-grouped sections + filters from MatchStore
│   ├── StandingsViewModel.swift       — one-shot fetchStandings
│   ├── TeamsViewModel.swift           — thin reader over the shared ClubStore
│   ├── TeamDetailViewModel.swift      — roster + social links + real season stats/leaders
│   └── TriviaViewModel.swift          — one Daily-Trivia session; questions ← TriviaService; non-repeating daily-5 (unit-tested); real best-streak leaderboard (+ Game Center submit)
├── Views/                             — one screen per file
│   ├── RootTabView.swift              — app root; 5-tab TabView; injects stores; restores session + coordinators; Game Center authenticate + syncAll (launch/auth/foreground); routes live-push tap
│   ├── HomeView.swift                 — your-teams hub: 4 modules + profile-avatar button; spotlight carousel; onboarding-in-place; Module-1 round-robin + content-type chips + "See more →"; refetch on pull + follows-change
│   ├── HomeContentListView.swift      — "See more from your teams" full firehose: ALL followed-team content, no cap, reverse-chron, respects the active chip (+ shared `HomeContentChips` bar)
│   ├── ProfileView.swift              — account & settings sheet: identity / Fan Zone stats (🏆 Leaderboards → Game Center dashboard) / Settings (Notifications row → hub · Support row → SupportView) / My Teams / Account
│   ├── NotificationsView.swift        — the ONE notifications hub (QOL v2): §Match alerts (per-team on/off) · §Alert types (5 global, dimmed when no team on) · §Activity; tier-aware sign-in gate; pushed from Teams bell/Manage + Profile row
│   ├── SupportView.swift              — "Support NWSLApp" (StoreKit tips): hero · one-time/monthly toggle · 4 tip tiers · CTA · Restore · "Where it goes" · thank-you state
│   ├── DailyTriviaView.swift          — Daily Trivia game (indigo); 5/day; results screen w/ best-streak leaderboard
│   ├── BracketBattleView.swift        — Bracket Battle (teal): 5 screens — Edition Intro · Voting · Save/Submit · Results · Bracket Overview
│   ├── PredictXIView.swift            — Predict the XI (pink): open fixtures + Results breakdown + per-team leaderboard cards
│   ├── XIPickerView.swift             — Predict picker sheet: formation chips → pitch-grid slots → scoreline → Save/Submit (+ Game Center first-prediction)
│   ├── OnboardingView.swift           — first-open team + competition follow picker
│   ├── SignInPromptView.swift         — one-time post-onboarding "save your picks" sheet
│   ├── NotificationAuthPromptView.swift — contextual "sign in for live alerts" half-sheet (Tier 2)
│   ├── ScheduleView.swift             — full-season cards; 3 filters; sticky day headers
│   ├── TeamsView.swift                — all-16 directory; Following floats up; follow-competitions row; per-row 🔔 alert toggles (followed) + "{N} teams · Manage" line + nav-bar 🔔 → NotificationsView
│   ├── CompetitionsView.swift         — follow international competitions
│   ├── TeamDetailView.swift           — club page: header (⭐ follow) + social row + Squad·Stats tabs
│   ├── MatchDetailView.swift          — state-aware match: past=Summary/Lineups/Stats, live=poll & LIVE pill, future=info grid + How-to-Watch + comparison + form
│   ├── CombinedPitchView.swift        — BOTH teams' XIs on ONE pitch; Lineups default
│   ├── FormationPitchView.swift       — single-team XI on a pitch; per-team list fallback
│   ├── PlayerDetailView.swift         — roster bio + season stat block
│   ├── PlayerSpotlightView.swift      — editorial spotlight: ghosted jersey # + hero, This Season grid, Story (Haiku blurb), Fast Facts + Watch
│   ├── StandingsView.swift            — 16-team table (abbr · PTS·GP·W·L·D); pinned header; followed-row tint
│   ├── FeedView.swift                 — Feed tab: content-type chip bar + chronological ContentCardViews
│   └── FeedSourcesView.swift          — Feed content preferences: toggles + mute sources
├── Components/
│   ├── BroadcastInfo.swift / BroadcastLink.swift — "How to Watch" DB + broadcast→watch-URL
│   ├── Chip.swift                     — pill filter chip (Schedule + Feed chip bars)
│   ├── ContentCardView.swift          — single entry point; routes a ContentCard by layout → the 3 card views
│   ├── ThumbnailContentCard.swift / AvatarContentCard.swift / ArticleContentCard.swift — the ContentCard layouts
│   ├── SettingsToggleRow.swift        — shared settings primitives: `SettingsToggleRow` + `SettingsGroup` (optional subtitle) + `SettingsRowDivider` (NotificationsView)
│   ├── PlatformBadge.swift            — platform glyph (YT/Bluesky/TikTok/IG/article/reddit)
│   ├── FormBadge.swift                — W/D/L form badge
│   ├── GameCard.swift                 — Fan Zone game tile (game-accent border + emoji + status + badge)
│   ├── HowToWatchCard.swift / MDInfoCard.swift / StatComparisonBar.swift — match-detail tiles
│   ├── PitchDot.swift / PlayerDot.swift / PlayerCard.swift — player markers/cards (team-color monogram, no headshots)
│   ├── ComingUpRow.swift / EventTimelineRow.swift / FlowLayout.swift — Home/match rows + wrapping layout
│   ├── ImageCache.swift / TeamLogo.swift — cached team crests
│   ├── MatchCard.swift                — schedule card → MatchDetailView
│   ├── PlayerSpotlightCard.swift      — Module-2 profile card
│   └── SocialLinkButton.swift         — circular team-tinted social icon
├── Extensions/
│   ├── Color+Hex.swift                — Color(hex:); teamAccent/teamFillOnDark; resolveMatchColors
│   ├── Date+RelativeAgo.swift         — shared "2h ago" formatter
│   ├── Club+BrandColor.swift          — Club → brandHex/accentColor (design palette → id-override → ESPN)
│   ├── DesignTeamColors.swift         — curated 16-team palette by abbreviation (authoritative)
│   └── TeamBrandColors.swift          — per-team-id brand-color overrides for clubs ESPN gets wrong
└── Assets.xcassets/                   — app icons, accent color

supabase/schema.sql                    — Postgres schema: profiles, follows, device_tokens, notification_preferences, team_alert_preferences (on/off), bracket_*, prediction_scores, trivia_scores (tables + RLS + authenticated GRANTs)
NWSLApp.storekit                       — local StoreKit 2 config (4 tip consumables + monthly subs) for in-sim Support testing; referenced by the shared scheme. ASC products owner-gated
```

---

## Current State

Root is `RootTabView` — a 5-tab bar (**Home · Schedule · Standings · Teams · Feed**), each
its own `NavigationStack`, lands on Home. Dark appearance app-wide. The season (`MatchStore`)
+ club directory (`ClubStore`) are each fetched once and shared app-wide via `.environment`.

- **Home** (`home-tab-design-spec.md`) — your-teams hub; pre-onboarding renders `OnboardingView`
  in place. Four modules: (1) "From your teams" content cards, (2) Player Spotlight, (3) Fan
  Zone games, (4) "Coming up". All live. Module 1 uses a **round-robin fair-share** (every
  followed team a guaranteed minimum, interleaved so a quiet club isn't buried by a loud one),
  **content-type chips** ([All][Videos][News][Social], in-memory, reset on refresh), and a
  **"See more →"** full-firehose screen; pull-to-refresh refetches + rotates the window when
  nothing's new, and a follows change refetches (see `ContentRoundRobin`).
- **Fan Zone games** (`games-design-spec.md`) — all three LIVE with **real Supabase
  leaderboards**:
  - **Predict the XI** (pink): pick a followed team's XI + formation + scoreline pre-match,
    auto-scored Mastermind-style vs ESPN `/summary` (max 88; Draft→Submit one-way, closes
    kickoff−2h). **Per-team leaderboard** (`prediction_scores`) — you're ranked among fans of
    your own club. Gate: a followed-team fixture within 28 days.
  - **Bracket Battle** (teal): a league-wide **fandom** community-voting tournament (NOT March
    Madness) — a themed 64-player/6-round edition (Best Forward, or owner-curated creative like
    Best Goal Celebration); you predict who the crowd advances, scored on real Supabase votes
    (`bracket_scores`). The proxy Worker engine auto-generates editions, tallies + advances
    rounds (cron), and rotates creative↔stats. Gate: an active/upcoming edition.
  - **Daily Trivia** (indigo): a league-wide pool served from the proxy `/trivia` route (KV,
    owner-loaded via `nwslapp-proxy scripts/load_trivia.mjs`); deterministic non-repeating
    daily-5. **League-wide best-streak leaderboard** (`trivia_scores`). Pool starts small (~40)
    and grows over time via the loader — the ~500 in the spec is an aspiration, not a launch gate.
  - **Visibility rule (all games):** a game with nothing active/upcoming is hidden everywhere
    (Home card + screen); the Fan Zone module hides when none is visible.
  - **Game Center** (GameKit) is layered on top: native leaderboards/achievements (4 boards +
    6 achievements) via `GameCenterManager`/`GKAccessPoint`, additive on the Supabase boards
    (best-effort, no-ops when not signed in). *App-side shipped; going live needs the owner's
    App Store Connect config (enable Game Center + create the records per
    `Reference/game-center-app-store-connect-checklist.md`) + a sandbox-account verify.*
- **Player Spotlight** (`spotlight-design-spec.md`) — one mini-profile per followed team, live
  via `/spotlight` (real player + ESPN stats + a Haiku "why watch" blurb, weekly rotation).
- **Feed** (`feed-tab-design-spec.md`) — reporters + news + social filtered to followed teams +
  league. Content-type chip bar (All/News/Social) over the live `/feed` cards; gear →
  `FeedSourcesView`.
- **Content Cards** — one `ContentCard` model + `ContentCardView` router back BOTH Home Module 1
  and Feed via 7 layouts, with a placement gate (Home = team voices; Feed = wider) + staleness
  (Home 72h / Feed 7d, 6-card-floored). All live via `ContentService` → proxy.
- **Teams + Following** — `TeamsView` lists all 16 (followed float up); onboarding + a bottom row
  offer international competitions (persisted; schedule not competition-aware yet).
- **Team detail** (`teams-tab-design-spec.md`) — pinned header + social row over Squad · Stats.
  Squad = `PlayerCard` grid → `PlayerDetailView`; Stats = season summary + leaders from real ESPN
  stats (actor-cached).
- **Standings / Schedule** — full 16-team table (PTS·GP·W·L·D, followed-row tint); full season in
  one `fetchScoreboard(year:)`, sticky day headers, 3 filters, scrolls to today.
- **Match detail** (`match-detail-v2-spec.md`) — `MatchDetailView` adapts to temporal state
  (Past/Live/Future); header from the `Event`, `/summary` layers the rest.
- **Accounts** — Sign in with Apple → a Supabase user (`AuthStore`); skippable post-onboarding
  `SignInPromptView`; the app stays fully working on the UserDefaults cache when signed out.
- **Notifications — Tier 1 / LOCAL** (`local-notifications-spec.md`) — `NotificationScheduler`
  delivers a day-before match reminder + a weekly Player Spotlight; permission on first toggle-on.
- **Notifications hub — Follow vs Alerts** (QOL v2 `Reference/Feed update/QOL v2 - Notification
  Redesign + Support.md`) — every notification setting lives on ONE screen (`NotificationsView`),
  reached from three doors (Teams nav-bar 🔔, Teams "{N} teams · Manage" line, Profile "Notifications"
  row). Following a club (⭐) and match alerts for it (🔔) are independent: per-team is a simple
  **ON/OFF** bell (on the Teams rows + hub §1, `TeamAlertStore` = `Set<String>` → UserDefaults +
  Supabase `team_alert_preferences`); the **alert TYPES are global** (hub §2, `NotificationPreferencesStore`:
  day-before[Tier 1] + kickoff/goals/halftime/full-time[Tier 2]), dimmed+inert when no team is on.
  §3 Activity (Fan Zone, Spotlight) is global. Tier-2 toggles present an honest sign-in gate
  (`NotificationAuthPromptView`) when signed out and don't flip until sign-in; **sign-out resets the
  4 Tier-2 types OFF** (they can't deliver without an account). Migration seeds a followed team ON
  only if a global match-day toggle was on. Unfollow clears a team's alerts. lineup/subs/cards not shown.
- **Support NWSLApp** (QOL v2 §5) — optional StoreKit tips (`SupportView` + `SupportStore`) from the
  Profile Settings group: 4 tiers (Corner Kick/Free Kick/Penalty Kick/Hat Trick), one-time or monthly,
  "where it goes" + thank-you state. App stays free; supporters get no extra features. Local
  `NWSLApp.storekit` config (+ scheme ref) makes it sim-testable; ASC product creation is owner-gated.

---

## What's Next

Completed work lives in **Current State**; only pending work here. Ordered by the priority order
at the top (ALIVE > core > hardening).

**Owner-gated (to fully close 0.3.9):**
- **Game Center go-live** — owner enables Game Center in App Store Connect + creates the 4
  leaderboards + 6 achievements (`Reference/game-center-app-store-connect-checklist.md`), then a
  joint sandbox-account live-verify. App side is shipped + handles the not-yet-enabled state gracefully.

**QOL (0.4.x — the current chapter): improving the experience of what's already alive.** Handoffs:
`Reference/Feed update/QOL Update Handoff.md` (Changes 1+3) + `QOL v2 - Notification Redesign +
Support.md` (the notification redesign, which superseded the original Change 2). **Shipped at 0.4.0**:
Home round-robin balancing + pull-to-refresh rotation + "See more →"; Home content-type chips; the
one-screen **Notifications hub** (per-team on/off bells + global alert types + honest sign-in gate +
sign-out Tier-2 reset); the **Support** (StoreKit tips) screen. Owner-gated to finish: drop the old
per-type columns on the live `team_alert_preferences` table (run the alter in `supabase/schema.sql`);
create the Support IAP products + subscription group in App Store Connect (ids in the v2 spec §5) +
enable the in-app-purchase capability. Still pending, as they come up from real use:
- **Pull-to-refresh polish** — keep the list visible during refresh (spinner only on first load),
  not flipping `state` to `.loading` full-screen.
- **Server-push per-team targeting** — the match-watcher Worker still reads the global
  `notification_preferences`; repoint it to read `team_alert_preferences` per team when Tier 2 goes
  live (the app side already writes per-team intent).
- **Bracket follow-ups (optional):** exact season-stat seeding for stat editions; more stat
  templates (GK/Mid/Def); a full bracket-TREE graphic (its own design pass). Owner still to curate
  the Best Goal Celebration creative edition (loads as data via `scripts/load_creative_edition.mjs`).
- **Home Module follow-ups:** spotlight no-repeat-per-season + opt-in weekly notif. (✓ "See more"
  destination + refetch-on-follows-change shipped in 0.4.0.)

**Hardening (do after ALIVE work):**
- Capture a real ESPN response → `Fixtures/scoreboard.json` + a decode-only test for
  `Scoreboard`/Event helpers (date parsing, `dayKey` TZ).
- `MatchStore.matches(for:)` joins club↔game by `abbreviation` (no id on ESPN competitors) — a
  rename silently empties a schedule. Fix: a normalized id map.
- Headshots: `/headshots` route + NWSL-GUID↔ESPN-id map → headshots on pitch dots/`PlayerCard`.
- Team social links — verify a couple of subreddit handles (KC `r/KCCurrent`; CHI `r/redstars`
  vs `r/ChicagoStars`; BOS/DEN/LOU none).

**Longer-term:**
- **Push — Tier 2 (SERVER push)** — code-complete through Stage C (app side + Worker
  `~/Projects/nwslapp-match-watcher`: 1-min cron, KV state-diff, APNs `.p8` JWT; kickoff · goal ·
  halftime · full-time). Infra provisioned + APNs verified. Remaining: flip `APNS_HOST`
  sandbox→production at TestFlight; on-device E2E; Stage D (subs + lineup-posted).
- **Competition-aware schedule** — groundwork exists (3 filters, dormant `CompetitionBadge`,
  `FollowedCompetition`). Remaining: a competition field on `Event` + a follow-edit surface.
- **Feed** — user-added sources; richer filtering. (Reddit deferred — noisy.)
- **Weather** — kickoff-temp header slot (API key, venue→coords, fetch-at-kickoff).
