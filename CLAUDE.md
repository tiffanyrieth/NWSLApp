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
  KV pool). Server-side Haiku (`claude-haiku-4-5`, KV-cached) does both relevance AND
  team-tagging for the third-party buckets: reporter + league-outlet Bluesky and news
  RSS are gated (isNWSL, strict — national-team/international/foreign/men's dropped),
  team-tagged, and filtered to the requested teams (off-topic + non-followed-team +
  general-chatter dropped; genuine league-wide kept). Fails toward DROP for social
  (fail-open for news). Club-official + player accounts are trusted fast paths (own
  abbr, no Haiku). Every card carries a `sourceType` (club·reporter·player·league·news)
  for the app's Feed chips. Plus a flood cap + dedupe.
- **Headshots** (`src/headshots.ts`): `GET /headshots` serves an `{espnAthleteId: nwslGuid}`
  map (built from the public NWSL SDP JSON API name-matched to ESPN rosters, ~98%; weekly cron
  + admin `POST /headshots/run`; union-merged in KV with an `unmatched`/`overrides`/`meta`
  audit). The app builds the NWSL Cloudinary headshot URL on-device. Pure mapping — no image bytes.
- **Crests** (`GET /crest?team=WAS`): serves a team's crest as a transparent PNG from KV
  (`crest:{ABBR}`). The NWSL CDN is named-transform-only (no client-side transparent PNG) and
  returns SVG for ~11 of 16 teams, so `scripts/load_crests.mjs` rasterizes all 16 OFFLINE via
  `sharp` (SVG + PNG sources → 384px, uniform modest padding) and loads them to KV. `TeamLogo`
  prefers this, ESPN PNG fallback on 404. 5 teams (CHI/KC/BOS/DEN/GFC) have no vector source —
  lateral vs ESPN; the 11 SVG teams gain real crispness. Re-run the loader if a club rebrands.
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
- **Back-button = PARENT, not self.** A drill-in's back chevron must read the screen you came
  FROM ("‹ Schedule", "‹ Home", "‹ Standings"), never the current screen's name. The pushing
  screen passes its own name as an `origin`/label; the child renders it via `navigationContextLabel`.
  (SwiftUI's automatic back-title doesn't propagate here because the tab roots hide their bars for
  custom headers, so the parent name is passed explicitly.) Don't hardcode the current screen's name.
  On full-bleed detail screens the header (crests + score, etc.) carries identity, so there's **no
  centered nav title** — just the parent back button. `TeamDetailView` takes an `origin` and renders
  "‹ {origin}" directly (Teams→"Teams", Standings→"Standings"); `MatchDetailView` does the same.
- Navigation state resets predictably (tapping a tab returns to its root).
- Placeholders allowed only as intentional scaffolding: a clean "Coming soon" state (never
  blank/broken) AND flagged in the File Map. A placeholder must look deliberate, not forgotten.
- The schedule shows the full season, not a rolling window.
- Clarity over density — screens should breathe (~4–5 schedule cards/screen; avoid oversized
  NWSL/MLB-style cards).
- **Dark appearance app-wide**, no toggle (page `#1C1C1E`, cards `#2C2C2E`).
- **Crest rule:** bare crests via `TeamLogo`, no ring (only player monograms get a ring).
- **Team colors:** `DesignTeamColors` by abbreviation so ESPN near-black primaries stay legible.
  **Always use each club's default brand colors; do not add manual color overrides (e.g. the
  Portland→gold override) unless there's a documented rendering conflict. Remove existing overrides
  that aren't justified.**
- **Team naming:** one team as subject → full club name (Gotham FC). **Two-team contexts (match
  cards, match detail, head-to-head/season comparisons, standings rows, recent form in a matchup)
  always use CREST + ABBREVIATION (e.g. WAS) — never full club names and never crest-less text. Full
  club names appear only in single-club contexts (club page, Teams directory, following lists). Crests
  are never dropped in favor of text.** ESPN has no nickname field.

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

- **Versioning model (owner's, NOT classic semver — follow this).** A **`minor.0` (e.g.
  `0.4.0`) is a big flagship release**, like Apple shipping iOS **26.0** — it bundles a pile of
  features and can span **several TestFlight builds** under the *same* marketing version (e.g.
  0.4.0 build 9 = QOL, build 10 = headshots). **Do NOT bump the patch digit for a new feature** —
  features stay at `.0`. **Patches (`0.4.1`, `0.4.2`…) are reserved for BUG FIXES** discovered
  after the big release. A **minor bump (`0.4` → `0.5`)** starts the next big release era. Reserve
  **1.0.0** for the first public App Store launch.
- **Releases so far:** `0.1.x` offline prototype; `0.3.x` the **backbone** (demo → fully live, all
  real data, capped at 0.3.9). **`0.4.0` = the "fully-working app" flagship** — shipping as
  successive builds: **build 9 = QOL** (Home round-robin + per-team chips, the Notifications hub,
  Support, polish); **headshots is a later 0.4.0 build**, not a new version. 0.4.1+ would be bug-fix
  follow-ups.
- **Xcode fields:** "Marketing Version" (`CFBundleShortVersionString`, human-facing — stays `0.4.0`
  across the flagship's builds) + "Build" (`CFBundleVersion`, a monotonic int bumped on every
  TestFlight upload — this is what increments per feature build). Tag releases in git. Proxy-only
  changes don't bump the app version.
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
│   ├── ContentCard.swift              — unified ALIVE-content model: 7 layouts + `sourceType` (club·reporter·player·league·news, for Feed chips) + StalenessWindow (Home 72h / Feed 7d, 6-card-floored)
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
│   ├── ContentRoundRobin.swift        — pure Home Module-1 fair-share: `balanced` (guaranteed-per-team round-robin + content-type interleave + chronological fill + follow-scaled cap) + `advancedOffsets` (pull-refresh rotation). Unit-tested
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
│   ├── HeadshotStore.swift            — @MainActor @Observable `.shared`; fetches the `/headshots` map (espnAthleteId→NWSL GUID) once per launch; `guid(forAthleteID:)`; best-effort (failure → monograms)
│   ├── GameCenterIDs.swift            — GameKit ID constants (4 leaderboards + 6 achievements) + pure cross-game score helpers (GameKit-free, unit-tested)
│   ├── GameCenterManager.swift        — @MainActor @Observable `.shared`; `authenticate()` is idempotent + LAZY (called on-appear from the 3 game screens + Profile leaderboards strip, NOT at launch) + best-effort submit/report + syncAll + showDashboard (GKAccessPoint). The only file importing GameKit
│   ├── TeamAlertPrefsSyncService.swift— Supabase `team_alert_preferences` client (per-team on/off upsert/fetchAll, composite key); RLS-scoped
│   ├── SupportStore.swift             — @MainActor @Observable StoreKit 2 layer for Support: 4 tip tiers (one-time consumables + monthly subs), load/purchase/restore, `purchased` thank-you flag
│   ├── PredictLeaderboardService.swift— Supabase per-team Predict board: upsertScore + standings(team); offline fallback to local you-row
│   ├── TriviaLeaderboardService.swift — Supabase league-wide Trivia best-streak board: upsertScore + standings; offline fallback
│   ├── PredictionScoring.swift        — pure Predict-the-XI scorer (Mastermind partial, max 88). Unit-tested
│   ├── RecentForm.swift               — pure last-5 W/D/L per club from the season (MatchStore); feeds Standings "Last 5"; `result(scored:conceded:)` is the one shared W/D/L rule (MatchDetailViewModel.form reuses it). Unit-tested
│   ├── PredictionMatchProvider.swift  — ↩︎ Predict the XI simulated-leaderboard fallback only
│   ├── FeedContentProvider.swift      — ↩︎ Feed seed → [ContentCard] (Feed is live via /feed)
│   ├── PlayerSpotlightProvider.swift  — ↩︎ one spotlight player per club (live via /spotlight)
│   ├── TeamContentProvider.swift      — ↩︎ Module-1 seed → [ContentCard] (live via /team-videos)
│   ├── TeamSocialLinksProvider.swift  — ↩︎ per-team social-account URLs (stable reference list)
│   ├── TriviaService.swift            — Daily-Trivia client: triviaQuestions→/trivia; live-or-↩︎seed
│   └── TriviaQuestionProvider.swift   — ↩︎ 55 hand-written trivia questions (live via /trivia)
├── Stores/                            — @Observable shared state → UserDefaults, injected
│   ├── AppRouter.swift                — tab selection (AppTab); `openMatch(eventID:)` live-push tap; `tabReselected`/`reselectNonce` (re-tap-active-tab signal → Schedule snaps to today); DEBUG `-startTab`
│   ├── AuthStore.swift                — @MainActor; Sign in with Apple → Supabase user; profile upsert; cached displayName; deleteAccount
│   ├── BracketStore.swift             — Bracket per-edition/round draft + one-way submit + banked points + cached edition (`bracket.v2.*`)
│   ├── ClubStore.swift                — shared club directory; one fetch, many readers
│   ├── FeedPreferencesStore.swift     — Feed content-type toggles + muted sources + `defaultFeedFilter` (the chip the Feed opens to, raw string)
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
│   ├── FeedViewModel.swift            — source-class chips (All/News/Clubs/Reporters/Players, by `sourceType` w/ layout fallback; Reporters also covers league outlets) + filtered [ContentCard] (follows∩ OR league, 7d staleness); cards ← ContentService
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
│   ├── RootTabView.swift              — app root; 5-tab TabView; injects stores; restores session + coordinators; Game Center syncAll (auth/foreground — auth itself is deferred to the game screens, not started here); routes live-push tap
│   ├── HomeView.swift                 — your-teams hub (facelift: custom 32pt header + avatar): 4 modules; Module-1 round-robin + per-team chips (2+ teams, each active chip in its club color) + adaptive labels (1 team) + "See more →"; Module-2 "Weekly Player Spotlight" carousel; Module-3 Fan Zone = featured lead card + tiles row; refetch on pull + follows-change
│   ├── HomeContentListView.swift      — "See more from your teams" full firehose: ALL followed-team content, no cap, reverse-chron, respects the active team chip (+ `HomeTeamChips` bar: [All] + per-team)
│   ├── ProfileView.swift              — account & settings sheet: identity / Fan Zone stats (🏆 Leaderboards → Game Center dashboard) / Settings (Notifications row → hub · Support row → SupportView) / My Teams / Account
│   ├── NotificationsView.swift        — the ONE notifications hub (QOL v2): §Match alerts (per-team on/off) · §Alert types (5 global, dimmed when no team on) · §Activity; tier-aware sign-in gate; pushed from Teams bell/Manage + Profile row
│   ├── SupportView.swift              — "Support NWSLApp" (StoreKit tips): hero · one-time/monthly toggle · 4 tip tiers · CTA · Restore · "Where it goes" · thank-you state
│   ├── DailyTriviaView.swift          — Daily Trivia game (indigo); 5/day; results screen w/ best-streak leaderboard
│   ├── BracketBattleView.swift        — Bracket Battle (teal): 5 screens — Edition Intro · Voting · Save/Submit · Results · Bracket Overview
│   ├── PredictXIView.swift            — Predict the XI (pink): open fixtures + Results breakdown + per-team leaderboard cards
│   ├── XIPickerView.swift             — Predict picker sheet: formation chips → pitch-grid slots → scoreline → Save/Submit (+ Game Center first-prediction)
│   ├── OnboardingView.swift           — first-open team + competition follow picker
│   ├── SignInPromptView.swift         — sign-in half-sheet shown ONLY on a genuine sign-in-required action (Bracket submit); never auto-presented post-onboarding
│   ├── NotificationAuthPromptView.swift — contextual "sign in for live alerts" half-sheet (Tier 2)
│   ├── ScheduleView.swift             — color-block redesign: full-season cards; compact filter chips (NWSL · My teams · International); "SAT · MAR 14" date headers + TODAY chip; scroll-to-today + tap-active-tab→today; International shows a designed "coming soon" empty state (no comp data yet)
│   ├── TeamsView.swift                — all-16 directory: ONE continuous list (followed floated to top, no section headers) + subtitle; follow-competitions row; per-row 🔔 alert toggles (followed) + "{N} teams · Manage" line at the followed/unfollowed boundary + nav-bar 🔔 → NotificationsView
│   ├── CompetitionsView.swift         — follow international competitions
│   ├── TeamDetailView.swift           — club page: header (⭐ follow) + social row + Squad·Stats tabs
│   ├── MatchDetailView.swift          — state-aware match (color-block redesign): full-bleed scaled-Card-C header (team wash under a transparent nav bar, 72pt crests, score under each crest, temporal-state center) + `origin`-driven "‹ {parent}" back button; past=Play-by-Play/Lineups/Stats (cyan/orange tab underline; Play-by-Play rows = left team-color crest box + cyan minute + glyph (soccerball.inverse goal / colored card / green-up-red-down sub "on for {out}") + running scoreline on goals + goal wash; formation pitch + BENCH), live=poll & LIVE pill, future=info grid + How-to-Watch + comparison + form. All cards `dsBgCard`
│   ├── CombinedPitchView.swift        — BOTH teams' XIs on ONE pitch; Lineups default
│   ├── FormationPitchView.swift       — single-team XI on a pitch; per-team list fallback
│   ├── PlayerDetailView.swift         — roster bio + season stat block
│   ├── PlayerSpotlightView.swift      — editorial spotlight: ghosted jersey # + hero, This Season grid, Story (Haiku blurb), Fast Facts + Watch
│   ├── StandingsView.swift            — color-block table (redesign): inline header + "TOP 8 ADVANCE" pill; one rounded card; team-color left edge + color-coded abbr per row; PTS hero; cols # · TEAM · PTS · GP · W · D · L · LAST 5; cyan PLAYOFF LINE (top-8) dims below; followed-row tint/★; Last-5 derived from MatchStore via RecentForm
│   ├── FeedView.swift                 — Feed tab (facelift): custom header (title+gear+subtitle) + source-class chip bar (All/News/Clubs/Reporters/Players) + chronological ContentCardViews; opens to the `defaultFeedFilter` chip
│   └── FeedSourcesView.swift          — Feed content preferences: Default-view picker + content-type toggles + mute sources
├── Components/
│   ├── BroadcastInfo.swift / BroadcastLink.swift — "How to Watch" DB + broadcast→watch-URL
│   ├── Chip.swift                     — pill filter chip (Schedule + Feed chip bars); optional `compact` (13pt) for the redesigned Schedule bar
│   ├── BroadcastChip.swift            — color-coded broadcast pill (handoff palette, substring-matched); schedule cards now, match detail at #2 (separate from BroadcastInfo's color DB)
│   ├── ContentCardView.swift          — single entry point; routes a ContentCard by layout → the 3 card views; facelift: adds the 3px team-color LEFT-EDGE bar (color-block motif, replaces the per-card top stripe) for all layouts
│   ├── ThumbnailContentCard.swift / AvatarContentCard.swift / ArticleContentCard.swift — the ContentCard layouts
│   ├── SettingsToggleRow.swift        — shared settings primitives: `SettingsToggleRow` + `SettingsGroup` (optional subtitle) + `SettingsRowDivider` (NotificationsView)
│   ├── PlatformBadge.swift            — platform glyph (YT/Bluesky/TikTok/IG/article/reddit)
│   ├── FormBadge.swift                — W/D/L form badge (optional `size`/`fontSize`, default 22; `MatchResult` convenience init)
│   ├── GameCard.swift                 — Fan Zone game tile (facelift: 200×160, radial accent-glow corner + emoji + status pill + badge)
│   ├── FeaturedGameCard.swift         — Fan Zone facelift: full-width featured lead card (glowing medallion + FEATURED eyebrow + title + tagline + solid-accent CTA) anchoring Module 3; remaining games render as GameCard tiles below
│   ├── HowToWatchCard.swift / MDInfoCard.swift / StatComparisonBar.swift — match-detail tiles (redesign: HowToWatch = title + FREE/SUBSCRIPTION badge + BroadcastChip + access + tip + "Find it" → verbatim per-device steps from BroadcastInfo; MDInfoCard = label/value, no emoji)
│   ├── PitchDot.swift / PlayerDot.swift / PlayerCard.swift — player markers/cards (team-color monogram, no headshots)
│   ├── ComingUpRow.swift / EventTimelineRow.swift / FlowLayout.swift — Home/match rows + wrapping layout
│   ├── ImageCache.swift / TeamLogo.swift — cached team crests; TeamLogo's `teamAbbreviation` prefers the crisp NWSL crest (proxy `/crest`) with the ESPN PNG as fallback
│   ├── MatchCard.swift                — schedule card → MatchDetailView; color-block redesign (CardC): team-color wash from both edges, 60pt ring-free crests, scores under crests, center temporal state (cyan KICKOFF+time / pulsing LIVE+orange clock / green FT), broadcast chip + venue rail, uniform height across states. (`CompetitionBadge` struct kept here — used by MatchDetailView.)
│   ├── PlayerHeadshot.swift           — circular player headshot via HeadshotStore→Cloudinary (ImageCache), jersey-monogram fallback; wraps the monogram on all 6 avatar surfaces (a 404/unmapped keeps the monogram)
│   ├── PlayerSpotlightCard.swift      — Module-2 facelift hero (~400pt): team-gradient card, headshot in the right ~half wide-fade-masked into the gradient, text in a left zone (GET TO KNOW eyebrow + name + #·pos·club + 2-line teaser + Read-her-story pill); tri-state photo load → ghost jersey# + crest fallback on no-GUID OR CDN 404 (never empty)
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

- **Home** (`home-tab-design-spec.md` + facelift `design-handoff/home.jsx`) — your-teams hub;
  pre-onboarding renders `OnboardingView` in place. Facelift: custom 32pt header + avatar; content
  cards carry the color-block left-edge team bar; per-team chips active in each club's color; Fan
  Zone leads with a full-width featured card + tiles row. Four modules: (1) "From your teams" content
  cards, (2) "Weekly Player Spotlight" (team-gradient hero), (3) Fan Zone games, (4) "Coming up". All
  live. Module 1 uses a **round-robin fair-share** (every
  followed team a guaranteed minimum, interleaved across teams AND content types so a quiet club
  or club news isn't buried by a loud team's clips), **per-team chips** ([All] + each followed
  club's abbreviation — shown only at 2+ teams; at 1 team the chips hide and cards drop their
  redundant team badge/name), and a **"See more →"** full-firehose screen; pull-to-refresh
  refetches + rotates the window when nothing's new, and a follows change refetches (see
  `ContentRoundRobin`).
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
    (best-effort, no-ops when not signed in). Auth is **deferred** — `authenticate()` fires lazily
    when a game screen or the Profile leaderboards strip appears, never at launch, so the GC sign-in
    banner stays out of the first impression. *App-side shipped; the 4 boards + 6 achievements are
    created in App Store Connect (status "Prepare for Submission") — live-verify happens on the next
    TestFlight build.*
- **Player Spotlight** (`spotlight-design-spec.md`) — Home Module 2, section "Weekly Player Spotlight"
  (facelift: ~400pt team-gradient hero, headshot soft-masked into the gradient, text in a left zone,
  ghost#+crest fallback when no headshot is available) — one mini-profile per followed team, live
  via `/spotlight` (real player + ESPN stats + a Haiku "why watch" blurb, weekly rotation).
- **Player headshots** (`Reference/Feed update/Player Headshots Handoff.md`, Phase A) — real
  player photos replace the jersey-number monograms on all 6 avatar surfaces (squad cards,
  player detail, Player Spotlight, formation pitch dots, Bracket matchup dots, Predict-XI
  picker slots) via `PlayerHeadshot` + `HeadshotStore`. The proxy `/headshots` route serves an
  espnAthleteId→NWSL-GUID map (SDP JSON API name-matched to ESPN rosters, ~98%, weekly cron);
  the app builds the NWSL Cloudinary URL on-device (`t_w_240`/`t_w_480`) and loads via
  `ImageCache`. A player with no photo (404) or no mapping keeps the monogram.
- **Team crests — NWSL source (Phase B3)** — all 16 crests now come from NWSL via the proxy
  `/crest` route (crisper than ESPN's raster for the 11 vector teams; lateral for the 5
  PNG-only teams), wired into every `TeamLogo` surface with the ESPN PNG as a safe fallback.
  Uniform modest padding. (Phase B2 Team Detail *banners* deferred pending a licensing review.)
- **Feed** (`feed-tab-design-spec.md` + facelift `design-handoff/feed.jsx`) — reporters + news +
  social filtered to followed teams + league. Facelift: custom header + the Avatar/Article card
  reorg (two-line identity, platform dot, team pill + time, full-width news image). **Source-class
  chip bar** (All · News · Clubs · Reporters · Players — by each card's `sourceType`; Reporters also
  covers NWSL media/league-outlet accounts) over the live `/feed` cards; a **default-chip** setting +
  the mute list live behind the gear (`FeedSourcesView`). The proxy now Haiku-team-tags the
  reporter/league bucket + filters to followed teams (see Data Source), so reporter/league posts
  carry a team color and off-topic/non-followed content is dropped server-side.
- **Content Cards** — one `ContentCard` model + `ContentCardView` router back BOTH Home Module 1
  and Feed via 7 layouts, with a placement gate (Home = team voices; Feed = wider) + staleness
  (Home 72h / Feed 7d, 6-card-floored). All live via `ContentService` → proxy.
- **Teams + Following** — `TeamsView` lists all 16 (followed float up); onboarding + a bottom row
  offer international competitions (persisted; schedule not competition-aware yet).
- **Team detail** (`teams-tab-design-spec.md`) — pinned header + social row over Squad · Stats.
  Squad = `PlayerCard` grid → `PlayerDetailView`; Stats = season summary + leaders from real ESPN
  stats (actor-cached).
- **Standings** (redesign — `design-handoff/standings.jsx`) — color-block table: inline header +
  "TOP {N} ADVANCE" pill, one rounded card, a team-color left edge + color-coded abbreviation per row, PTS
  as the hero number, cols `# · TEAM · PTS · GP · W · D · L · LAST 5`, a cyan PLAYOFF LINE at the `playoffSpots`
  (8) cutoff with rows below dimmed, followed-row tint + ★. The **Last 5** column has no ESPN source, so it's
  derived from the shared season (`MatchStore`) via the pure `RecentForm` helper. (GP kept vs the mock — owner.)
- **Schedule** (redesign — `design-handoff/schedule-cards.jsx`, "Color Block") — full season in one
  `fetchScoreboard(year:)`. Cards: team-color wash from both edges, 60pt ring-free crests, scores under
  each crest, a temporal-state center column (cyan KICKOFF + cyan time / pulsing red LIVE + orange clock /
  green FT + "FULL TIME"), and a broadcast color-chip + venue rail (kept on past games too). Uniform card
  height across states. "SAT · MAR 14" date headers with a TODAY chip. Filters **NWSL · My teams ·
  International** (International is wired but data-less → a designed "coming soon" empty state until the
  schedule goes competition-aware). Opens scrolled to today; **tapping the active Schedule tab snaps back
  to today** (`AppRouter.reselectNonce`).
- **Match detail** (redesign — `design-handoff/match-detail.jsx`) — a scaled-up Card C: a full-bleed
  team-color wash header (transparent nav bar, 72pt ring-free crests, score under each crest, temporal
  state in the center), a parent-reflecting "‹ {origin}" back button, and one card surface (`dsBgCard`).
  Adapts to temporal state (Past/Live/Future): past/live = Summary/Lineups/Stats tabs (cyan/orange
  underline; cyan/orange minute markers; green-up/red-down sub glyph; **the formation pitch with real
  headshots — the crown jewel, unchanged**; BENCH-labelled bench), future = info grid + How-to-Watch
  (verbatim per-device tips) + season comparison + recent form. Header from the `Event`, `/summary`
  layers the rest. (The supports() pitch-relaxation was investigated and **skipped** — all 93 real past
  matches already render the pitch; nothing falls back to the text list.)
- **Accounts** — Sign in with Apple → a Supabase user (`AuthStore`). Sign-in is **never**
  auto-prompted (no post-onboarding nag); `SignInPromptView` appears only when the user taps
  something that genuinely requires an account (Fan Zone submit, Tier-2 notifications). The app
  stays fully working on the UserDefaults cache when signed out.
- **Notifications — Tier 1 / LOCAL** (`local-notifications-spec.md`) — `NotificationScheduler`
  delivers a day-before match reminder + a weekly Player Spotlight; permission on first toggle-on.
- **Notifications hub — Follow vs Alerts** (QOL v2 `Reference/Feed update/QOL v2 - Notification
  Redesign + Support.md`) — every notification setting lives on ONE screen (`NotificationsView`),
  reached from three doors (Teams nav-bar 🔔, Teams "{N} teams · Manage" line, Profile "Notifications"
  row). Following a club (⭐) and match alerts for it (🔔) are independent: per-team is a simple
  **ON/OFF** bell (on the Teams rows + hub §1, `TeamAlertStore` = `Set<String>` → UserDefaults +
  Supabase `team_alert_preferences`); the **alert TYPES are global** (hub §2, `NotificationPreferencesStore`:
  day-before[Tier 1] + kickoff/goals/halftime/full-time[Tier 2]), dimmed+inert when no team is on.
  §3 Activity (Fan Zone, Spotlight) is global. **First-tap doorway** (Bell-Tap fix): a Teams row
  bell tapped before the hub has ever been visited *pushes the hub* instead of toggling (the
  `notifications.hubVisited` flag) — so the user sees the options before opting in; later taps are a
  quick on/off. The bell **never** requests iOS permission (that fires only from inside the hub on a
  first toggle-on). **Invariant: Tier 2 ON ⟹ signed in** — Tier-2 types default OFF and only default
  ON for a signed-IN user's first hub visit (`markHubVisited(isSignedIn:)`); Tier-2 toggles present an
  honest sign-in gate (`NotificationAuthPromptView`) when signed out and don't flip until sign-in;
  **sign-out resets the 4 Tier-2 types OFF**. Tier-1 (day-before, Player Spotlight) defaults ON
  (delivers signed-out). Migration seeds a followed team ON only if a global match-day toggle was on.
  Unfollow clears a team's alerts. lineup/subs/cards not shown.
- **Support NWSLApp** (QOL v2 §5) — optional StoreKit tips (`SupportView` + `SupportStore`) from the
  Profile Settings group: 4 tiers (Corner Kick/Free Kick/Penalty Kick/Hat Trick), one-time or monthly,
  "where it goes" + thank-you state. App stays free; supporters get no extra features. Local
  `NWSLApp.storekit` config (+ scheme ref) makes it sim-testable; ASC product creation is owner-gated.

---

## What's Next

Completed work lives in **Current State**; only pending work here. Ordered by the priority order
at the top (ALIVE > core > hardening).

**Owner-gated App Store Connect / backend setup — ✅ ALL DONE (2026-06-14):**
- ✅ **Game Center** — the 4 leaderboards + 6 achievements are created in App Store Connect
  (status "Prepare for Submission"), matching the ids in `GameCenterIDs.swift`. App side shipped.
  (The sandbox/live-verify happens naturally on the next TestFlight build.)
- ✅ **Support IAP products** — the 4 consumables + 4 monthly subs are created in App Store Connect
  (ids in `NWSLApp.storekit` / QOL v2 spec §5). They show "Missing Metadata" until the app is
  submitted (the first subscription must ship attached to a new app version) — expected, not a blocker.
- ✅ **In-App Purchase capability** enabled (Xcode Signing & Capabilities + the ASC Paid Apps agreement).
- ✅ **`team_alert_preferences` Supabase table** — CREATED (it never existed; the old-column `alter`
  was a no-op, so it was created fresh with RLS + the `authenticated` grant per `supabase/schema.sql`).
  Code-verified: `TeamAlertPrefsSyncService` upserts `user_id/team_id/alerts_enabled` on the composite
  key, matching the table. Signed-in per-team alert sync is now live end-to-end.

**QOL — 0.4.0 build 9 (first build of the flagship):** improving the experience of what's already
alive. Handoffs: `Reference/Feed update/QOL Update Handoff.md` (Changes 1+3) + `QOL v2 - Notification
Redesign + Support.md` (the notification redesign, which superseded the original Change 2). **Shipped**:
Home round-robin balancing + pull-to-refresh rotation + "See more →"; Home per-team chips; the
one-screen **Notifications hub** (per-team on/off bells + global alert types + honest sign-in gate +
sign-out Tier-2 reset); the **Support** (StoreKit tips) screen; Teams single-list + subtitle;
Feed/content-card polish. (App Store Connect / backend setup to finish it is the owner-gated
checklist above.) Still pending, as they come up from real use:
- **YouTube Shorts thumbnail pillarbox (#2)** — DEFERRED by owner (revisiting). Vertical Shorts'
  static `hqdefault.jpg` has baked-in side bars the client can't crop; the fix is proxy-side (choose
  a bar-free thumbnail / crop the content region in `nwslapp-proxy`). Not started.
- **Pull-to-refresh polish** — keep the list visible during refresh (spinner only on first load),
  not flipping `state` to `.loading` full-screen.
- ✅ **Server-push per-team targeting (done 2026-06-14)** — the match-watcher Worker now gates pushes
  on `team_alert_preferences(alerts_enabled=true)` per team (the bell), ∩ the global
  `notification_preferences` type toggle — so a push reaches only users who enabled alerts for THAT
  team, not every follower. Deployed (`nwslapp-match-watcher` `src/supabase.ts`).
- **Bracket follow-ups (optional):** exact season-stat seeding for stat editions; more stat
  templates (GK/Mid/Def); a full bracket-TREE graphic (its own design pass). Owner still to curate
  the Best Goal Celebration creative edition (loads as data via `scripts/load_creative_edition.mjs`).
- **Home Module follow-ups:** spotlight no-repeat-per-season + opt-in weekly notif. (✓ "See more"
  destination + refetch-on-follows-change shipped in 0.4.0.)
- **Player headshots — Phase B2 banners (DEFERRED — licensing):** the Team Detail banner image
  (`team-player-header/{teamGUID}`, WebP) is on hold while the owner reviews whether a full club
  graphic crosses a licensing line that crests/names don't (the disclaimer model covers
  names/logos). B1 mechanics are proven; revisit later.

**Hardening (do after ALIVE work):**
- Capture a real ESPN response → `Fixtures/scoreboard.json` + a decode-only test for
  `Scoreboard`/Event helpers (date parsing, `dayKey` TZ).
- `MatchStore.matches(for:)` joins club↔game by `abbreviation` (no id on ESPN competitors) — a
  rename silently empties a schedule. Fix: a normalized id map.
- Team social links — verify a couple of subreddit handles (KC `r/KCCurrent`; CHI `r/redstars`
  vs `r/ChicagoStars`; BOS/DEN/LOU none).
- **Club-page links data pass** — the redesigned Club page (#5) renders OFFICIAL + Fan-community
  link pills only for platforms present in `TeamSocialLinksProvider` (currently reddit/bluesky/IG/
  YT/TikTok). The design also spec's **Website · Shop · Tickets** (OFFICIAL) and **Discord** (Fan
  community); these aren't in the data yet, so they're gracefully omitted. Curate per-club URLs for
  all 16 (add cases to `SocialPlatform` + the provider). Discord is spotty — not every club has one.

**Longer-term:**
- **Push — Tier 2 (SERVER push)** — code-complete through Stage C (app side + Worker
  `~/Projects/nwslapp-match-watcher`: 1-min cron, KV state-diff, APNs `.p8` JWT; kickoff · goal ·
  halftime · full-time). Infra provisioned + APNs verified. Remaining: flip `APNS_HOST`
  sandbox→production at TestFlight; on-device E2E; Stage D (subs + lineup-posted).
- **Competition-aware schedule** — groundwork exists (3 filters, dormant `CompetitionBadge`,
  `FollowedCompetition`). Remaining: a competition field on `Event` + a follow-edit surface.
- **Feed** — user-added sources; richer filtering. (Reddit deferred — noisy.)
- **Weather** — kickoff-temp header slot (API key, venue→coords, fetch-at-kickoff).
