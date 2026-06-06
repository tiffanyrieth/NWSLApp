# NWSLApp — Project Context for Claude

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
- **Persistence:** TBD — start in-memory, add SwiftData if needed.
- **Testing:** Swift Testing (`@Test` + `#expect()`), not XCTest
- **Minimum iOS version:** iOS 17 (enables `@Observable`)
- **Xcode version:** 26.5

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

**Future:** Possibly a Vercel serverless proxy in front of ESPN for caching,
response normalization, and a stable interface.

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

## Distribution

- Simulator + Personal Team sideload (free Apple tier). App Store deferred
  until the project reaches a presentable state.

---

## File Map (UPDATE THIS AFTER EVERY FEATURE)

Markers: ⚠️ = TEMP scaffolding (curated static seed; swap for a real backend —
the async signature is already shaped for it). 🔧 = intentional "coming soon"
placeholder (looks deliberate per the UI rules). Design specs in
`Reference/Design/*-spec.md` hold the full rationale.

```
NWSLApp/
├── NWSLAppApp.swift                   — app entry point; launches RootTabView
├── Models/                            — Codable models (⚠️ = backed by a seed provider)
│   ├── BracketEdition.swift           — Bracket Battle entrants + edition, seed order
│   ├── Club.swift                     — flat Club + ESPN /teams decode wrappers
│   ├── FeedItem.swift                 — one Feed item (post|article) + team tag
│   ├── FollowedCompetition.swift      — international competitions list + follow model
│   ├── PlayerSpotlight.swift          — ⚠️ Home Module-2 player-of-week mini-profile
│   ├── PlayerStats.swift              — per-player season stats + team-leaders models
│   ├── PredictionMatch.swift          — ⚠️ Predict-the-XI match, questions, answer key
│   ├── Roster.swift                   — squad + team profile from one roster fetch
│   ├── Scoreboard.swift               — ESPN scoreboard structs + Event helpers
│   ├── Standings.swift                — table rows (rank + Club + GP/W/D/L/PTS)
│   ├── TeamContentItem.swift          — ⚠️ Home Module-1 team-channel post
│   ├── TeamSocialLinks.swift          — ⚠️ per-team social links for TeamDetail
│   └── TriviaQuestion.swift           — ⚠️ one Daily-Trivia question (4 options)
├── Services/                          — ESPNService + ⚠️ curated async seed providers
│   ├── BracketEditionProvider.swift   — ⚠️ Bracket seed + simulated leaderboard
│   ├── ESPNService.swift              — async fetch: scoreboard/teams/roster/standings
│   ├── FeedContentProvider.swift      — ⚠️ Feed seed: reporters/outlets, all 16 clubs
│   ├── PlayerSpotlightProvider.swift  — ⚠️ one spotlight player per club (16)
│   ├── PredictionMatchProvider.swift  — ⚠️ Predict-the-XI seed (open + settled)
│   ├── StatsProvider.swift            — ⚠️ deterministic simulated per-player stats
│   ├── TeamContentProvider.swift      — ⚠️ Module-1 team-channel seed (~2/club)
│   ├── TeamSocialLinksProvider.swift  — ⚠️ per-team social-account URLs seed
│   └── TriviaQuestionProvider.swift   — ⚠️ 55 hand-written NWSL trivia questions
├── Stores/                            — @Observable shared state → UserDefaults, injected
│   ├── BracketStore.swift             — Bracket picks / points / locked rounds
│   ├── FeedPreferencesStore.swift     — Feed content-type toggles + muted sources
│   ├── FollowingStore.swift           — followed clubs + competitions + onboarding gate
│   ├── MatchStore.swift               — shared season store; one fetch, many readers
│   ├── PredictionStore.swift          — Predict-the-XI picks + season-points snapshot
│   └── TriviaStore.swift              — Daily-Trivia streak/accuracy + one-play/day gate
├── ViewModels/                        — @Observable; one per screen (idle/loading/loaded/error)
│   ├── BracketViewModel.swift         — Bracket session; deterministic community sim
│   ├── FeedViewModel.swift            — chips + filtered items + sources (prefs-aware)
│   ├── HomeViewModel.swift            — derives Home modules from MatchStore+Following
│   ├── PredictXIViewModel.swift       — Predict session; open/settled split + scoring
│   ├── ScheduleViewModel.swift        — day-grouped sections + filters from MatchStore
│   ├── StandingsViewModel.swift       — one-shot fetchStandings()
│   ├── TeamsViewModel.swift           — club directory fetch
│   ├── TeamDetailViewModel.swift      — roster + social links + simulated stats/leaders
│   └── TriviaViewModel.swift          — one Daily-Trivia session (deterministic daily 5)
├── Views/                             — one screen per file
│   ├── RootTabView.swift              — app root; 5-tab TabView; lands on Home; injects stores
│   ├── HomeView.swift                 — your-teams hub: 4 modules; onboarding-in-place
│   ├── DailyTriviaView.swift          — Daily Trivia game (indigo); 5/day
│   ├── BracketBattleView.swift        — Bracket Battle game (teal); vote + lock rounds
│   ├── PredictXIView.swift            — Predict the XI game (pink); per-match questions
│   ├── OnboardingView.swift           — first-open team + competition follow picker
│   ├── ScheduleView.swift             — full-season cards; 3 filters; sticky day headers
│   ├── TeamsView.swift                — all-16 directory; Following floats to top
│   ├── TeamDetailView.swift           — club page: header + social row + Squad·Stats tabs
│   ├── PlayerDetailView.swift         — roster bio + season stat block
│   ├── PlayerSpotlightView.swift      — narrative spotlight tap-through (video hero)
│   ├── StandingsView.swift            — 16-team table (PTS·GP·W·L·D); followed blue
│   ├── FeedView.swift                 — Feed tab: chip bar + chronological FeedCards
│   └── FeedSourcesView.swift          — Feed content preferences: toggles + mute sources
├── Components/                        — reusable view pieces
│   ├── ComingUpRow.swift              — Module-4 compact next-match row per team
│   ├── FeedCard.swift                 — one Feed item (post or article); opens source
│   ├── MatchCard.swift                — one game: score + status + venue/📺 (dormant badge)
│   ├── PlayerCard.swift               — Squad-grid card; team-color monogram + position
│   ├── PlayerSpotlightCard.swift      — ⚠️ Module-2 player-of-week card
│   ├── SocialLinkButton.swift         — circular team-tinted social icon; opens account
│   ├── TeamContentCard.swift          — ⚠️ Module-1 16:9 thumbnail + attribution
│   └── TeamLogo.swift                 — AsyncImage crest (no cache yet — What's-Next #1)
├── Extensions/
│   └── Color+Hex.swift                — teamAccent(hex:) → (fill, legible on-color)
└── Assets.xcassets/                   — app icons, accent color
```

---

## Current State

Root is `RootTabView` — a 5-tab bottom bar (**Home · Schedule · Standings ·
Teams · Feed**), each tab in its own `NavigationStack`; the app **lands on
Home**. All five tabs are built (no placeholder; `ComingSoonView` deleted).
`Feed` (not `News`) signals the social-native direction. Following persists via
`UserDefaults` (`FollowingStore`); SwiftData is used **nowhere**. Each feature
below is built per its `Reference/Design/*-spec.md` (approved in Cowork sessions)
and **verified in-sim** via a temporary launch-env/deep-link scaffold driving
deterministic screenshots (UI taps flake under memory pressure), then removed;
screenshots live in gitignored `Reference/Design/*-verification/` folders.

**Home — the your-teams-first hub** (`home-tab-design-spec.md`, content-leads
order). Pre-onboarding renders `OnboardingView` in place (tab bar stays visible).
A `ScrollView` of modules: (1) "From your teams" TeamContentCards; (2) "Get to
know your players" one PlayerSpotlightCard/followed team; (3) "Play" game row; (4)
"Coming up" ComingUpRow/club. `HomeViewModel` derives every module from the shared
`MatchStore` + `FollowingStore` after one `loadClubs()` pass. Modules 1–2 run on
TEMP seeds; no-follows re-presents the picker as a sheet.

**Play games** (Module 3 "Play"; `games-design-spec.md`) — all three built, no
placeholder. Each has its own color, ⚠️seed provider, session VM, and durable
`…Store`; full mechanics in the File Map view entries. **Daily Trivia** (indigo),
**Bracket Battle** (teal — deterministic seed-weighted "community" sim), **Predict
the XI** (pink — kickoff = offset-from-now so the demo always shows OPEN+SETTLED).
All verified in-sim (scaffolds since removed).

**Player Spotlight** (Module 2; `spotlight-design-spec.md`). One Option-B
mini-profile per followed team → narrative `PlayerSpotlightView`.
⚠️`PlayerSpotlightProvider` seeds all 16 (bios + oembed-verified videos;
Mondésir/SEA written-only fallback); `HomeViewModel.spotlights(following:)` rotates
one player per team weekly.

**Feed — the world talking about your teams** (`feed-tab-design-spec.md`).
Reporters + news filtered to followed teams; distinct from Home Module 1.
`FeedView`: title + settings gear (→ `FeedSourcesView`), pinned chip bar (All ·
per team · League), chronological `FeedCard` stream. ⚠️`FeedContentProvider` seeds
real reporters/outlets across all 16 clubs evenly. The gear opens a real
**Content Preferences** screen (`FeedSourcesView`): persisted post/article-type
toggles + per-source mute, all filtering the live Feed (`FeedPreferencesStore`).

**Teams + Following** (the personalization spine). `TeamsView` lists all 16 clubs
(`/teams`); each Follow star writes to `FollowingStore`; followed clubs float into
a "Following" section. Onboarding also offers followable **international
competitions** (`FollowedCompetition` + a competitions follow set on
`FollowingStore`) — persisted, though the schedule isn't competition-aware yet
(What's-Next #13).

**Team detail** (`teams-tab-design-spec.md`). `TeamDetailView` (pushed from
Teams/Standings): pinned header (crest + name + standingLine + Follow) + a
centered **social-links row** (team-accent `SocialLinkButton`s, only platforms a
club uses; ⚠️`TeamSocialLinksProvider` seed) over **Squad · Stats** sub-tabs.
Squad = team-colored `PlayerCard` grid (FWD→GK) → `PlayerDetailView` (roster bio +
a season stat block). **Stats** shows a real season summary (the roster's W-D-L
record) + Goals/Assists/Clean-Sheets leaders. One `fetchRoster(clubID:)→ClubSquad`
powers the page; per-player stats are ⚠️simulated (`StatsProvider`, deterministic
+ position-aware) and the leaders board is derived from them so it matches each
player page. No formation pitch yet (needs an unmapped lineup feed).

**Standings** (`standings-tab-design-spec.md`). Full 16-team table, **PTS · GP ·
W · L · D** only (GF/GA/GD omitted to avoid horizontal scroll). Non-scrolling
header aligned to scrolling rows; followed teams blue; rows → `TeamDetailView`.
Endpoint at `apis/v2/…` (not the app `base`).

**Schedule** (`schedule-tab-design-spec.md`). Full season in one
`fetchScoreboard(year:)` call (~240 events for 2026) as a `ScrollView`/`LazyVStack`
of MatchCards under sticky day headers. Three segmented filters (NWSL / My teams /
All matches) over one `MatchStore`. Cards carry 📍 venue · 📺 broadcast. Scrolls to
today/next matchday; re-anchors on filter change. `MatchCard` competition-badge-
ready (dormant).

---

## What's Next

Completed work is documented in **Current State**; only pending work is listed
here. Original item numbers are kept so existing cross-references stay valid.

**Near-term / cleanup**
1. **(Perf/TEMP)** `TeamLogo` uses bare `AsyncImage` — no cross-cell cache, so
   crests re-download on scroll. TEMP-commented; replace with a shared
   NSCache-backed loader (or route logos through the future proxy).
3. **(Polish)** Pull-to-refresh flips `state` to `.loading`, swapping the whole
   list for a centered spinner. Keep the list visible during a refresh
   (full-screen spinner only on first load).
4. Capture a real ESPN response into `NWSLAppTests/Fixtures/scoreboard.json` +
   add a decode-only test for `Scoreboard` / Event helpers (date parsing,
   `dayKey` time-zone behavior).
6. Make `MatchCard` tappable → a match detail screen (scorers, lineups, stats,
   news) via the `NavigationStack` already in place.
9. **(Fragility)** `MatchStore.matches(for:)` joins club↔game by `abbreviation`
   (ESPN scoreboard competitors carry no id). Safe today, TEMP-commented; a
   rename/relocation would silently empty a schedule (empty state, not a crash).
   Real fix when a backend exists: a normalized club-id map.
15. **(Cleanup)** The club directory is fetched independently by Teams/Home/
    Schedule VMs. Consider a shared `@Observable ClubStore` injected via
    `.environment` (one fetch, many readers; clean ID→Club / ID→abbreviation
    lookup the My-teams filter and Home both need).
16. **(Robustness)** `ScheduleViewModel.loadClubs()` swallows a failed fetch
    (`(try? …) ?? []`) → the My-teams filter shows an infinite "Loading your
    teams…" spinner with no error/retry. Give it an error state + retry (or fold
    into the ClubStore from #15).

**Feature follow-ups (from shipped redesigns)**
- **Team-detail Stats + PlayerDetailView** — now show ⚠️simulated per-player
  stats (`StatsProvider`): a season summary + Goals/Assists/Clean-Sheets leaders,
  and a per-player season block. Remaining: a real per-player stats source (ESPN's
  `athletes[].statistics.splits` is sparse — likely the proxy) to replace the
  simulation, and a most-recent-formation pitch (needs an unmapped lineup endpoint).
- **(Data/Verify) Team social links** — ⚠️`TeamSocialLinksProvider` is a curated
  seed; verify before any real ship. Reddit handles were confirmed indirectly (the
  firehose is unfetchable here): **KC** (`r/KCCurrent`, lowest
  confidence) and **CHI** (`r/redstars` vs the post-rebrand `r/ChicagoStars`) need
  a browser check; **BOS/DEN/LOU** have no subreddit yet (BOS/DEN are expansion
  sides) and so show no Reddit icon. YT/IG URLs duplicate `TeamContentProvider` —
  collapse into one source when the real backend lands.
- **Follow-confirmation sheet** — first-time "what following buys you" on the
  header star (deferred across specs). No Settings screen exists yet ("all
  onboarding choices adjustable in Settings" still applies).
- **Home Module 1** — build the per-section "See all" destination; replace
  ⚠️`TeamContentProvider` with a real team-channel source (→ real per-post
  thumbnails + deep links).
- **Home Module 2 spotlight pipeline** — UI done; still need a content pipeline
  for real thumbnails/durations, a deeper per-team pool (so the weekly rotation
  cycles a full roster), the opt-in weekly notification, and a team-colored
  badge (needs the club hex). The optional one-time intro card isn't built.
- **Home Module 3 games** — all three built; remaining work is swapping each off
  its TEMP seed and adding social/push layers (all need real multi-user
  leaderboards via #12, a share-result card, and the kickoff/streak push).
  Trivia: real question backend (grow pool / add categories). Bracket Battle: real
  editorial/voting backend so the "community" is real votes (not the simulation);
  rotate themed editions (Best Forward, Best Kit, …). Predict the XI: real
  fixtures + lineup feed (so matches/results are live, not the offset clock — needs
  lineup data); per-category accuracy stats; broaden questions (correct score,
  MOTM).

**Longer-term (vision — see `Reference/Sessions/` for full rationale)**
11. **Feed backend** — UI built on the ⚠️seed. Needs: a real content source
    (Bluesky/news aggregator or the proxy); the editorial "no culture-war /
    political / identity hot takes" gate as a real filter
    (`nwslapp-feed-content-rules.md`); user-added sources (the gear's Content
    Preferences already does post/article toggles + source muting; adding your own
    account needs the backend); and per-post **team tagging via a Claude Haiku call**
    (source/handle alone can't tag reliably) that also drops non-NWSL content.
12. **Push notifications + the server question.** Scheduled reminders need NO
    server (kickoff times known ahead → local notifications, free on the sideload
    tier); **live updates need a server + APNs + the $99 Apple Developer
    Program**. The server doubles as the **caching proxy** (polls ESPN once, fans
    out to clients). Much-later; full reasoning in
    `Reference/Sessions/2026-06-04_server-pulls-and-push.md`.
13. **Competition-aware schedule.** Groundwork in place: the three Schedule
    filters, `MatchCard`'s dormant `CompetitionBadge`, and now a
    `FollowedCompetition` model + a competitions follow set on `FollowingStore`
    wired to the onboarding rows. Remaining: a competition on `Event` (so NWSL vs
    All diverge and badges populate) so a followed competition actually filters the
    schedule, plus a way to change competition follows after onboarding (no
    Settings surface yet — same gap as the follow-confirmation sheet).
14. **Engagement / Home hub** — player spotlights (→ a contributor pipeline),
    community links (subreddits/Discords), prediction games. These live as Home
    modules first and graduate to their own tab only if earned. (Prediction
    games reuse the push/#12 backend.)
```

