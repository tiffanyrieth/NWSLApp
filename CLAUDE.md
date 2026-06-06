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
├── NWSLAppApp.swift                — app entry point; launches RootTabView
├── Models/
│   ├── BracketEdition.swift        — Bracket Battle (Play game 2): BracketEntrant (teamAbbreviation join + playerName + credential) + BracketEdition (title/theme + entrants in SEED order) + BracketRoundLabel (round titles from matchup count). Seed: ⚠️BracketEditionProvider; bracket tree + simulated results derived in BracketViewModel.
│   ├── Club.swift                  — flat view-friendly Club + defensive wrappers for ESPN's /teams payload (TeamsResponse.clubs flattens/sorts active clubs). Named Club to avoid colliding with Scoreboard's competitor-level Team. Optional shortName = chip label for Feed filters.
│   ├── FeedItem.swift              — one Feed item (kind = .reporterPost | .articleLink; source/handle/platform/timestamp; body or headline+summary; url; teams tags; isLeague) + FeedTeamTag (abbreviation join key). Legal: articles hold headline+summary+link only, never the body.
│   ├── PlayerSpotlight.swift       — Home Module 2 "player of the week" (Option B mini-profile): teamAbbreviation join + name/jersey/position + bioBlurb + video fields (videoURL nil = written-only fallback) + extended profile (nationality/age/careerHighlights/funFacts; seasonForm nil today). Seed: ⚠️PlayerSpotlightProvider.
│   ├── PredictionMatch.swift       — Predict the XI (Play game 3): PredictionMatch (home/away abbreviation join + kickoff as an OFFSET-from-now so the demo always has open+settled matches + final score) holding PredictionQuestions (PredictionCategory .formation 2pts/.startingGK 1pt/.captain 2pts/.firstScorer 3pts + icon, prompt, PredictionOptions, answer-key correctOptionID revealed only once settled). Seed: ⚠️PredictionMatchProvider; open/settled split + scoring derived in PredictXIViewModel.
│   ├── Roster.swift                — a club's squad + profile: Athlete (incl. shortName "T. Rodman") + ClubSquad (athletes + colorHex + standingSummary + record; standingLine "4th in NWSL — 21 pts", points derived from record) from ESPN's /teams/{id}/roster — ONE fetch powers the team page. grouped() buckets FWD→MID→DEF→GK. NOTE: NWSL headshots null → monogram, no photo (permanent).
│   ├── Scoreboard.swift            — ESPN scoreboard structs + Event helpers (kickoff, dayKey, home/away, venueName, broadcastName). Venue + broadcasts ride the same response (no extra fetch); decoded defensively (all optional).
│   ├── Standings.swift             — league table: StandingsRow (rank + full Club + GP/W/D/L/PTS) + wrappers (rows flattens/sorts by rank). Each row carries a Club (tappable + follow-aware). Stats read by stable `type` key (draws = ESPN "ties").
│   ├── TeamContentItem.swift       — Home Module 1 ("From your teams") — teams' OWN channels (Platform enum .youtube/.instagram/.tiktok/.bluesky each w/ symbol + isVideo, timestamp/caption/durationLabel/url + teamAbbreviation join). Distinct from Feed (news ABOUT teams). Seed: ⚠️TeamContentProvider.
│   └── TriviaQuestion.swift        — one Daily-Trivia question (id, question, four options, correctIndex, Category + Difficulty enums; correctAnswer convenience). Seed: ⚠️TriviaQuestionProvider; daily 5 derived in TriviaViewModel, stats in TriviaStore.
├── Services/
│   ├── ⚠️BracketEditionProvider.swift — curated Bracket Battle seed; async edition()→one "Best Goalkeeper" edition (16 real GKs, one/club, in editorial seed order) + leaderboardOpponents() (sample usernames + fixed points for the simulated board). Durable credentials, 2026 snapshot.
│   ├── ESPNService.swift           — URLSession + async/await; fetchScoreboard(year:) + fetchTeams() + fetchRoster(clubID:)→ClubSquad + fetchStandings() (builds the apis/v2/… path explicitly), all via a private generic fetch<T:Decodable>; throws ESPNServiceError.
│   ├── ⚠️FeedContentProvider.swift  — curated Feed seed; async items()→[FeedItem] from real reporters/outlets (The Athletic, ESPN, The Equalizer, Just Women's Sports + beat reporters), all 16 clubs (~2 each) + league items, deliberately even. Editorial policy (no culture-war/political hot takes) lives here when it becomes a live gate.
│   ├── ⚠️PredictionMatchProvider.swift — curated Predict-the-XI seed; async matches()→3 sample matches (2 SETTLED w/ final scores + answer keys, 1 OPEN) of 4 questions each + leaderboardOpponents() for the simulated board. Kickoff offsets keep open/settled stable over time. Illustrative 2026 snapshot (shared keeper list w/ Bracket seed), invented results.
│   ├── ⚠️TeamContentProvider.swift  — curated Module-1 seed; async items()→[TeamContentItem], ~2/club. URLs are real account-level links (each team's YouTube/IG, incl. 2026 expansion sides).
│   ├── ⚠️TriviaQuestionProvider.swift — async questions()→55 hand-written NWSL questions, all 16 clubs, mixed difficulty across six categories. Leans on DURABLE facts, avoids volatile current-season trivia.
│   └── ⚠️PlayerSpotlightProvider.swift — async spotlights()→one real 2026 player/club (all 16) w/ hand-written bio + extended profile + a real oembed-verified player YouTube video (sources attributed honestly). One written-only fallback (Mondésir/SEA, lives only on Facebook).
├── Stores/
│   ├── BracketStore.swift          — @Observable Bracket Battle durable state → UserDefaults, injected app-wide: editionID + picks (matchup→entrant, JSON) + lockedRoundCount (= currentRound) + points + roundCount. beginEdition resets only on edition change; lockRound banks points in-order + idempotent; restart() for demo replay. No day-gate (play-through cadence).
│   ├── FollowingStore.swift        — @Observable personalization lens: followed club IDs (Set<String>) → UserDefaults; injected app-wide via .environment. ALSO tracks hasOnboarded (first-open gate + completeOnboarding()); an existing follower is treated as already onboarded so seeded sims skip the picker.
│   ├── MatchStore.swift            — @Observable shared season store: fetches the full scoreboard ONCE; exposes State + events + matches(for:Club). Schedule renders all of it; Home derives "Coming up". matches(for:) joins club↔match by abbreviation (TEMP-commented fragility: ESPN competitors carry no id).
│   ├── PredictionStore.swift       — @Observable Predict-the-XI durable state → UserDefaults, injected app-wide: picks (question→option, JSON) + a seasonPoints snapshot (pushed by the VM so the Home card needn't re-score). setPick guarded by a caller-supplied `locked` flag (the VM knows kickoff, the store doesn't); reset() for demo replay. No scoring/lock logic here.
│   └── TriviaStore.swift           — @Observable Daily-Trivia durable stats → UserDefaults, injected app-wide: streak/bestStreak, lifetime accuracy, lastScore, lastCompletedDay. hasPlayedToday = one-scored-play/day gate; recordCompletion(correct:outOf:) idempotent for the day; now/calendar injectable for tests.
├── ViewModels/
│   ├── BracketViewModel.swift      — @Observable; one Bracket Battle session. load() pulls the edition, builds the bracket by standard seeding (1v16…), and DETERMINISTICALLY simulates the "community" (SplitMix64 seeded by a stable hash of each matchup id, seed-weighted so favourites usually advance) → stable winners + vote %s. Derives rounds/champion/correctPicks/leaderboard (sample opponents + You). Best-effort club fetch for crests (game stays playable if it fails).
│   ├── HomeViewModel.swift         — @Observable; loadClubs() fetches the club directory + both content seeds in one pass; DERIVES every module from the injected MatchStore + FollowingStore. teamContent(following:) / spotlights(following:) (one per followed team, deterministic weekly rotation) / nextMatches(following:) / club(forAbbreviation:).
│   ├── PredictXIViewModel.swift     — @Observable; one Predict-the-XI session. load() pulls the slate, best-effort club fetch for crests, and pushes the scored seasonPoints into the store. Resolves kickoff = now + offset against an injectable clock → open vs settled (open=editable/hidden answers, settled=read-only/scored). Scores settled matches by category points; derives season total + simulated leaderboard (sample opponents + You) + your rank.
│   ├── ScheduleViewModel.swift     — @Observable; derives day-grouped sections + scroll target from MatchStore. Filter enum (nwsl/myTeams/allMatches) → three functions over ONE data set. A SEPARATE idempotent loadClubs() (decoupled from the season .idle guard) resolves followed IDs → abbreviations for My-teams. NOTE: club fetch duplicated across Home/Teams/Schedule (→ future ClubStore, What's-Next #15).
│   ├── TeamsViewModel.swift        — @Observable; State enum (idle/loading/loaded/error); fetchTeams().
│   ├── TeamDetailViewModel.swift   — @Observable; State holds the ClubSquad from one roster fetch. Exposes positionGroups (FWD-first), accentColorHex, standingLine. No MatchStore dependency.
│   ├── StandingsViewModel.swift    — @Observable; one-shot fetchStandings() (own per-screen fetch, no shared store).
│   ├── TriviaViewModel.swift       — @Observable; one Daily-Trivia SESSION. loadDaily() locks today's 5 via a deterministic daily shuffle (private SplitMix64 seeded by day number — stable all day, no persistence). Transient play state (currentIndex/selectedIndex/isRevealed/correctCount/picks/isFinished) + select→submit→advance/finish; commits to TriviaStore on finish.
│   └── FeedViewModel.swift         — @Observable; loads the seed + club directory. chips(following) = All + per followed team + League; items(following) filters by Filter (.all/.team/.league, newest first). Chip↔item match by abbreviation.
├── Views/
│   ├── RootTabView.swift           — app root; 5-tab TabView (Home/Schedule/Standings/Teams/Feed), each its own NavigationStack; LANDS ON HOME; creates + injects FollowingStore, MatchStore, TriviaStore, BracketStore, PredictionStore via .environment. All five tabs built (no placeholder tab).
│   ├── HomeView.swift              — Home hub (home-tab-design-spec.md, content-leads order). Pre-onboarding renders OnboardingView in place (tab bar stays visible). Hub modules: (1) "From your teams" TeamContentCards (the hook); (2) "Get to know your players" PlayerSpotlightCards, one/followed team → PlayerSpotlightView (hidden if none); (3) "Play" game row (all three live: Daily Trivia → DailyTriviaView, Bracket Battle → BracketBattleView, Predict the XI → PredictXIView); (4) "Coming up" ComingUpRow/club. No-follows → "Choose your teams" picker sheet. ("Around the league" removed.)
│   ├── DailyTriviaView.swift       — Daily Trivia (rides Home's stack): 5 MC/day, select→submit (green/red reveal, A–D badges)→next→results (score, 🔥streak, all-time accuracy + per-question review). One scored play/day (locked summary on re-open). Indigo accent. Reads TriviaStore, owns session via TriviaViewModel.
│   ├── BracketBattleView.swift     — Bracket Battle (rides Home's stack): header (title/theme + R16·QF·SF·F progress pills + points/rank) over stacked rounds — current round = tap-to-vote matchups + "Lock in" (reveals winner + vote %s, banks a point per correct pick), closed rounds collapse to compact results (green ✓/red ✗). Champion banner + simulated leaderboard (You highlighted) on completion; "Play again" resets. Teal accent. Reads BracketStore, derives via BracketViewModel.
│   ├── PredictXIView.swift         — Predict the XI (rides Home's stack): header (season points + rank) over the slate — OPEN matches show tappable prediction questions (formation/GK/captain/scorer, each w/ a +pts chip) that auto-save (picks lock at kickoff, no manual submit; footer reads "Locked in — editable until kickoff"); SETTLED matches collapse to a results review (your pick vs actual, green ✓/red ✗, points earned, final score). Simulated season leaderboard (You highlighted) + "Reset predictions". Pink accent. Reads PredictionStore, derives via PredictXIViewModel.
│   ├── OnboardingView.swift        — first-open "Make it yours" picker: alphabetical List, whole-row follow toggle, collapsed "international competitions" disclosure (🔧 rows don't toggle — needs a Competition model), pinned "Follow N teams" bar → completeOnboarding() + dismiss(). Reuses TeamsViewModel + FollowingStore.
│   ├── ScheduleView.swift          — full-season ScrollView + LazyVStack of cards, sticky day headers (schedule-tab-design-spec.md). THREE segmented filters (NWSL/My teams/All matches). Scrolls to today/next matchday; re-anchors on filter change (first-load anchor retries once clubs resolve). No-follows prompt; pull-to-refresh.
│   ├── TeamsView.swift             — Teams directory (all 16) in a List; a "Following" section floats followed clubs to the top. Each row = sibling buttons (row pushes TeamDetailView via NavigationPath + separate Follow star — NOT nested, which would swallow the nav tap).
│   ├── TeamDetailView.swift        — club page (rides pushing tab's stack; teams-tab-design-spec.md): PINNED header (crest + name + standingLine + Follow star) over Squad · Stats sub-tabs. Squad = 2-col LazyVGrid of PlayerCards (FWD→GK) → PlayerDetailView. Stats = 🔧 (needs per-player/lineup data). One roster fetch powers all.
│   ├── PlayerDetailView.swift      — 🔧 pushed from a Squad card: roster bio (monogram, name, jersey/position/age/height/nationality) + "stats coming soon". Accent threaded from TeamDetailView.
│   ├── PlayerSpotlightView.swift   — spotlight tap-through (rides Home's stack; spotlight-design-spec.md): video hero (opens source; hidden when written-only), header (jersey + name + Position·Team + Nationality·Age, omitting nils), full bioBlurb, bulleted career highlights / fun facts. Narrative, deliberately NOT PlayerDetailView.
│   ├── StandingsView.swift         — league table (standings-tab-design-spec.md): non-scrolling header (# · Team · PTS · GP · W · L · D) aligned to scrolling rows via shared fixed Col widths; all 16 end-to-end. Followed teams blue. Rows → TeamDetailView. NO GF/GA/GD (would force horizontal scroll). PTS bold/fronted. Footer legend.
│   ├── FeedView.swift              — Feed tab (feed-tab-design-spec.md): own NavigationStack; title + settings gear (→ FeedSourcesView). PINNED chip bar (All · per followed team · League) over a chronological ScrollView of FeedCards. Per-filter empty states; pull-to-refresh. Distinct from Home Module 1.
│   └── FeedSourcesView.swift       — 🔧 gear sheet: List of curated default sources + a "Coming soon" section (Add a source / Content preferences, disabled).
├── Components/
│   ├── ComingSoonView.swift        — reusable 🔧 (SF Symbol + "coming soon"). Currently UNREFERENCED (all tabs built); kept for the next structural placeholder.
│   ├── FeedCard.swift              — one Feed item, a single component for both kinds. .reporterPost: @ avatar + name + "Bluesky — 2h ago" + body + "View on …". .articleLink: newspaper avatar + publication + headline + 1-line summary + "Read on …" (never body). No per-team marker. Whole card opens the source.
│   ├── MatchCard.swift             — one game: stacked home/away rows (logo + abbreviation) + score/kickoff + status badge (LIVE/FT/scheduled) + info line (📍 venue always · 📺 broadcast upcoming/live only). CompetitionBadge + non-NWSL treatment gated on an optional `badge` NIL today (dormant scaffolding).
│   ├── TeamContentCard.swift       — Module-1 card: 16:9 thumbnail + attribution (crest + team + timestamp) + caption + "via YouTube/Instagram/…" tag. Whole card opens the channel. TEMP: designed crest-tile placeholder, not a fetched image.
│   ├── PlayerSpotlightCard.swift   — Module-2 Option-B card: "PLAYER OF THE WEEK" + jersey badge + name + Position·Team + bioBlurb + video preview (or "Read full profile →" when written-only). Plain label, wrapped in a NavigationLink in HomeView. TEMP: app-accent badge + designed tile.
│   ├── ComingUpRow.swift           — Module-4 compact row/team: crest dot + matchup (short names) + time-aware line ("Fri, Jul 3 · 8:00 PM" / live clock+score / "FT · 2–1") + LIVE badge. Reuses HomeViewModel.FollowedFixture.
│   ├── PlayerCard.swift            — Squad-grid card: team-color top accent (3px) + jersey/initials monogram in a team-color badge + shortName + position (legible number via luminance).
│   └── TeamLogo.swift              — reusable AsyncImage crest: fixed frame, loading placeholder, neutral failure fallback. TEMP: no cross-cell cache (What's-Next #1). Used by MatchCard/Teams/TeamDetail/Standings.
├── Extensions/
│   └── Color+Hex.swift             — Color.teamAccent(hex:) → (fill, on): ESPN hex → SwiftUI Color + legible black/white foreground by luminance; falls back to the app accent. Used by PlayerCard + PlayerDetailView.
└── Assets.xcassets/                — app icons, accent color
```

---

## Current State

Root is `RootTabView` — a 5-tab bottom bar (**Home · Schedule · Standings ·
Teams · Feed**), each tab in its own `NavigationStack`; the app **lands on
Home**. All five tabs are built (no placeholder tab; `ComingSoonView` is
unreferenced). Tab is `Feed` (not `News`) on purpose, to signal the
social-native direction. Following persists via `UserDefaults` (`FollowingStore`);
SwiftData is used **nowhere**. Each feature below is built per its
`Reference/Design/*-spec.md` (approved in Cowork sessions) and **verified
in-sim** — the established pattern is a temporary launch-env/deep-link scaffold
driving deterministic screenshots (UI taps flake under this machine's memory
pressure), then removed; screenshots live in gitignored
`Reference/Design/*-verification/` folders.

**Home — the your-teams-first hub** (`home-tab-design-spec.md`, content-leads
order). Pre-onboarding (`hasOnboarded == false`) renders `OnboardingView` in
place (tab bar stays visible). A `ScrollView` of modules: (1) "From your teams"
TeamContentCards (the hook); (2) "Get to know your players" one
PlayerSpotlightCard per followed team; (3) "Play" game row (all three games
live); (4) "Coming up" ComingUpRow per club. Home owns no season data —
`HomeViewModel.loadClubs()` fetches the club directory + both seeds in one pass
and derives every module from the shared `MatchStore` + `FollowingStore`.
Modules 1–2 run on TEMP seeds; no-follows re-presents the picker as a sheet.

**Play games** (Module 3 "Play"; `games-design-spec.md`) — all three built, no
Play placeholder remains. Each has its own identity color, ⚠️seed provider,
session VM, and durable `…Store`. **Daily Trivia** (indigo) — 5 MC/day,
select→submit→reveal→results (score/streak/accuracy + review); one scored
play/day (Wordle-style lock); deterministic daily pick (SplitMix64 by day
number). **Bracket Battle** (teal) — single-elim "Best Goalkeeper" (16 real GKs,
one/club); vote each matchup, **lock** a round to reveal winner + vote split +
bank a point/correct pick, next round opens below (no calendar gate); the
"community" is a deterministic, seed-weighted simulation (stable across launches)
standing in for real multi-user voting; champion banner + simulated leaderboard
on completion. **Predict the XI** (pink) — per-match formation/GK/captain/scorer
predictions (2/1/2/3 pts) that auto-save and lock at kickoff (no manual submit);
OPEN (editable, hidden answers) vs SETTLED (read-only results review) split +
scoring derived in the VM; kickoff modelled as an **offset from now** so the demo
always has both states; season points → simulated leaderboard. All verified
in-sim (temporary launch-env deep-link scaffolds, then removed).

**Player Spotlight** (Module 2; `spotlight-design-spec.md`). One Option-B
mini-profile per followed team (bio blurb + video preview) → narrative
`PlayerSpotlightView` (deliberately distinct from the roster's `PlayerDetailView`).
⚠️`PlayerSpotlightProvider` seeds all 16 with hand-written bios + real
oembed-verified player videos (Mondésir/SEA is the written-only fallback).
`HomeViewModel.spotlights(following:)` rotates one player per team weekly.

**Feed — the world talking about your teams** (`feed-tab-design-spec.md`).
Reporters + news filtered to followed teams; distinct from Home Module 1 (Feed =
the conversation *around* your teams). `FeedView`: title + settings gear (→
`FeedSourcesView`), pinned chip bar (All · per team · League), chronological
`FeedCard` stream (reporter posts + article links). ⚠️`FeedContentProvider` seeds
real reporters/outlets across all 16 clubs evenly.

**Teams + Following** (the personalization spine). `TeamsView` lists all 16
clubs (`/teams`); each row's Follow star writes to `FollowingStore` (shared via
`.environment`). Followed clubs float into a "Following" section.

**Team detail** (`teams-tab-design-spec.md`). `TeamDetailView` (pushed from
Teams/Standings): a pinned header (crest + name + standingLine "4th in NWSL — 21
pts" + Follow) over **Squad · Stats** sub-tabs. Squad = team-colored `PlayerCard`
grid (FWD→GK) → `PlayerDetailView`. Stats + PlayerDetailView are intentional
placeholders (need per-player/lineup data not yet mapped). One
`fetchRoster(clubID:)→ClubSquad` powers the whole page — color, standing, and
record all ride the roster payload (points derived, no second fetch). Team color
via `Color.teamAccent(hex:)`. The old Overview/Schedule sub-tabs were removed
(identity audit: schedule → Schedule tab).

**Standings** (`standings-tab-design-spec.md`). Full 16-team table, **PTS · GP ·
W · L · D** only (GF/GA/GD + home/away splits omitted to avoid horizontal scroll
— connection over stat overload). Non-scrolling header aligned to scrolling
rows; followed teams blue; rows → `TeamDetailView`. The standings endpoint lives
at `apis/v2/…` (not the app `base`); team id matches `/teams`, so no id mapping.

**Schedule** (`schedule-tab-design-spec.md`). Full season in one
`fetchScoreboard(year:)` call (~240 events for 2026) as a `ScrollView` /
`LazyVStack` of MatchCards under sticky day headers (~4–5/screen, abbreviations
like WAS/KC/SD). Three segmented filters (NWSL / My teams / All matches) =
functions over one `MatchStore`. Each card carries 📍 venue · 📺 broadcast (from
the same response). Scrolls to today/next matchday; re-anchors on filter change.
NWSL & All match today, diverge once non-NWSL competition data exists.
`MatchCard` is competition-badge-ready (dormant).

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
- **Team-detail Stats + PlayerDetailView** — both placeholders. Build team
  leaders (top-3 Goals/Assists/Clean Sheets — per-player stats exist on
  `athletes[].statistics.splits`, sparse) and a most-recent-formation pitch
  (needs an unmapped lineup endpoint); flesh out PlayerDetailView from the same
  stats source.
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
    (`nwslapp-feed-content-rules.md`); live source management (the gear's
    placeholders); and per-post **team tagging via a Claude Haiku call**
    (source/handle alone can't tag reliably) that also drops non-NWSL content.
12. **Push notifications + the server question.** Scheduled reminders need NO
    server (kickoff times known ahead → local notifications on-device, free on
    the sideload tier); **live updates need a server + APNs + the $99 Apple
    Developer Program**. The server doubles as the **caching proxy** (polls ESPN
    once, fans out to all clients). Much-later milestone; full reasoning in
    `Reference/Sessions/2026-06-04_server-pulls-and-push.md`.
13. **Competition-aware schedule.** Groundwork in place (the three Schedule
    filters + `MatchCard`'s dormant `CompetitionBadge`). Needs a `Competition`
    model on `Event` (so NWSL vs All diverge and badges populate), a separate
    followed-competitions set in `FollowingStore`, and the onboarding
    international-competitions rows wired up. Shared blocker behind the schedule
    filters, the Home/onboarding competition placeholders, and badged matches.
14. **Engagement / Home hub** — player spotlights (→ a contributor pipeline),
    community links (subreddits/Discords), prediction games. These live as Home
    modules first and graduate to their own tab only if earned. (Prediction
    games reuse the push/#12 backend.)
```

