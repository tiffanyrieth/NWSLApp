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

**Proxy (V2, 0.2.0):** The full-season **scoreboard** now routes through a tiny
Cloudflare Worker — `nwslapp-proxy` (sibling repo `~/Projects/nwslapp-proxy`,
GitHub `tiffanyrieth/nwslapp-proxy`, live at
`https://nwslapp-proxy.tiffany-rieth.workers.dev`). It fetches ESPN once,
caches it (Workers Cache API, dynamic TTL — 30s if a game is live, else 300s),
and fans out to all callers; `GET /scoreboard` forwards the query string and
returns ESPN's bytes **unchanged**, so the app's `Scoreboard` decoder is
untouched. Only the scoreboard is proxied — teams, roster, and standings still
hit ESPN directly. Base URL lives in `Config/AppConfig.swift`; DEBUG
`-useESPNDirect` falls back to ESPN. See What's-Next #12 and
`Reference/Sessions/2026-06-08_v2-kickoff-caching-proxy.md`.

**Future:** Expand the proxy to more endpoints + response normalization as
needed; add the gitignored-secrets pattern with Supabase in 0.3.0.

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
    balloon past it. A distinct pre-launch hardening/beta chapter, if one
    emerges, would be 0.3.x.
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
├── NWSLAppApp.swift                   — app entry point; launches RootTabView; forces dark appearance app-wide; DEBUG `-resetOnboarding` launch arg → resets onboarding
├── Config/                            — checked-in (non-secret) app configuration
│   └── AppConfig.swift                — base URLs; scoreboard → Cloudflare proxy by default; DEBUG `-useESPNDirect` → ESPN direct
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
│   ├── TeamContentItem.swift          — ⚠️ Home Module-1 video post (+ YT thumbnail URL)
│   ├── TeamSocialLinks.swift          — ⚠️ per-team social links for TeamDetail
│   └── TriviaQuestion.swift           — ⚠️ one Daily-Trivia question (4 options)
├── Services/                          — ESPNService + ⚠️ curated async seed providers
│   ├── BracketEditionProvider.swift   — ⚠️ Bracket seed + simulated leaderboard
│   ├── ESPNService.swift              — async fetch: scoreboard (via proxy, see AppConfig)/teams/roster/standings
│   ├── FeedContentProvider.swift      — ⚠️ Feed seed: reporters/outlets, all 16 clubs
│   ├── PlayerSpotlightProvider.swift  — ⚠️ one spotlight player per club (16)
│   ├── PredictionMatchProvider.swift  — ⚠️ Predict-the-XI seed (open + settled)
│   ├── StatsProvider.swift            — ⚠️ deterministic simulated per-player stats
│   ├── TeamContentProvider.swift      — ⚠️ Module-1 seed: 2 real YouTube videos/club
│   ├── TeamSocialLinksProvider.swift  — ⚠️ per-team social-account URLs seed
│   └── TriviaQuestionProvider.swift   — ⚠️ 55 hand-written NWSL trivia questions
├── Stores/                            — @Observable shared state → UserDefaults, injected
│   ├── BracketStore.swift             — Bracket picks / points / locked rounds
│   ├── ClubStore.swift                — shared club directory; one fetch, many readers (ID/abbr lookups)
│   ├── FeedPreferencesStore.swift     — Feed content-type toggles + muted sources
│   ├── FollowingStore.swift           — followed clubs + competitions + onboarding gate; DEBUG `debugResetState()` re-test helper
│   ├── MatchStore.swift               — shared season store; one fetch, many readers
│   ├── PredictionStore.swift          — Predict-the-XI picks + season-points snapshot
│   └── TriviaStore.swift              — Daily-Trivia streak/accuracy + one-play/day gate
├── ViewModels/                        — @Observable; one per screen (idle/loading/loaded/error)
│   ├── BracketViewModel.swift         — Bracket session; deterministic community sim
│   ├── FeedViewModel.swift            — chips + filtered items + sources (prefs-aware); clubs ← ClubStore
│   ├── HomeViewModel.swift            — derives Home modules from MatchStore+ClubStore+Following
│   ├── PredictXIViewModel.swift       — Predict session; open/settled split + scoring
│   ├── ScheduleViewModel.swift        — day-grouped sections + filters from MatchStore; My-teams ← ClubStore (error+retry)
│   ├── StandingsViewModel.swift       — one-shot fetchStandings()
│   ├── TeamsViewModel.swift           — thin reader over the shared ClubStore (also feeds Onboarding)
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
│   ├── TeamsView.swift                — all-16 directory; Following floats to top; Follow-competitions row at bottom
│   ├── CompetitionsView.swift         — follow international competitions (reached from TeamsView; reuses onboarding rows)
│   ├── TeamDetailView.swift           — club page: header + social row + Squad·Stats tabs
│   ├── MatchDetailView.swift          — single match (pre/in/post) from the scoreboard Event; pushed from a tapped MatchCard
│   ├── PlayerDetailView.swift         — roster bio + season stat block
│   ├── PlayerSpotlightView.swift      — narrative spotlight tap-through (real YT video hero)
│   ├── StandingsView.swift            — 16-team table (PTS·GP·W·L·D); followed blue
│   ├── FeedView.swift                 — Feed tab: chip bar + chronological FeedCards
│   └── FeedSourcesView.swift          — Feed content preferences: toggles + mute sources
├── Components/                        — reusable view pieces
│   ├── ComingUpRow.swift              — Module-4 compact next-match row per team
│   ├── FeedCard.swift                 — one Feed item (post or article); opens source
│   ├── ImageCache.swift               — in-memory NSCache singleton; backs TeamLogo (no re-download on scroll)
│   ├── MatchCard.swift                — one game: score + status + venue/📺 (dormant badge); taps → MatchDetailView in Schedule
│   ├── PlayerCard.swift               — Squad-grid card; team-color monogram + position
│   ├── PlayerSpotlightCard.swift      — ⚠️ Module-2 player-of-week card (real YT thumbnail)
│   ├── SocialLinkButton.swift         — circular team-tinted social icon; opens account
│   ├── TeamContentCard.swift          — ⚠️ Module-1 real YT thumbnail (crest-tile fallback) + attribution
│   └── TeamLogo.swift                 — team crest via the shared ImageCache (cached; placeholder fallback)
├── Extensions/
│   └── Color+Hex.swift                — teamAccent(hex:) → (fill, legible on-color)
└── Assets.xcassets/                   — app icons, accent color
```

---

## Current State

Root is `RootTabView` — a 5-tab bar (**Home · Schedule · Standings · Teams ·
Feed**), each tab its own `NavigationStack`; the app **lands on Home**. All five
tabs built. The app forces a **dark appearance app-wide**
(`.preferredColorScheme(.dark)` on the root, also covering sheets) — there's no
in-app appearance toggle. Following persists via `UserDefaults` (`FollowingStore`);
SwiftData is used **nowhere**. The season (`MatchStore`) and the club directory
(`ClubStore`) are each fetched **once and shared app-wide** via `.environment` —
one fetch, many readers; the My-teams schedule filter surfaces a real error +
retry if the directory fails (no more silent infinite spinner). Each feature is built per its `Reference/Design/*-spec.md`
(approved in Cowork sessions) and **verified in-sim** via a temporary
launch-env/deep-link scaffold driving deterministic screenshots (UI taps flake
under memory pressure), then removed → gitignored `Reference/Design/*-verification/`.

**Home** (`home-tab-design-spec.md`) — your-teams-first hub; pre-onboarding renders
`OnboardingView` in place. Four modules — (1) "From your teams" content, (2) player
spotlights (one/followed team), (3) "Fan Zone" games, (4) "Coming up" fixtures — all
DERIVED by `HomeViewModel` from `MatchStore` + `FollowingStore`. Fan Zone cards are
ordered Predict → Bracket → Trivia; **Predict the XI shows only when ≥1 club is
followed** (it's inherently personal), Bracket + Trivia always show. Modules 1–2 on
⚠️seeds; no-follows re-presents the picker. Module 1's ⚠️seed is 2 real, recent
videos per club from each team's official YouTube — cards load the real frame
(`img.youtube.com/vi/{id}/…`, crest-tile fallback) and tap straight to the video.

**Fan Zone games** (`games-design-spec.md`) — all three built, each with its own color
+ ⚠️seed + session VM + durable `…Store`: **Daily Trivia** (indigo), **Bracket
Battle** (teal — deterministic seed-weighted "community" sim), **Predict the XI**
(pink — kickoff = offset-from-now so the demo always shows OPEN+SETTLED).

**Player Spotlight** (`spotlight-design-spec.md`) — one mini-profile/followed team
→ narrative `PlayerSpotlightView`; ⚠️`PlayerSpotlightProvider` seeds all 16
(Mondésir/SEA is the written-only fallback), rotated weekly. Each video is a real,
verified player-feature on YouTube, so the card and the detail hero load the real
frame (`img.youtube.com/vi/{id}/…`, crest-tile fallback).

**Feed** (`feed-tab-design-spec.md`) — reporters + news filtered to followed teams
(the conversation *around* your teams; distinct from Home Module 1). Chip bar
(All · per team · League) over ⚠️`FeedContentProvider`. The gear opens real
**Content Preferences** (`FeedSourcesView`): post/article toggles + per-source
mute, persisted in `FeedPreferencesStore`, filtering the live Feed.

**Teams + Following** — `TeamsView` lists all 16 (`/teams`); Follow stars write to
`FollowingStore` (followed float to a "Following" section). Onboarding also offers
followable **international competitions** (`FollowedCompetition` + a follow set);
a **Follow-competitions row at the bottom of `TeamsView`** opens `CompetitionsView`
(same toggle rows) so users who skipped them in onboarding can follow them later.
Persisted, but the schedule isn't competition-aware yet (#13).

**Team detail** (`teams-tab-design-spec.md`) — pinned header + centered social row
(⚠️`TeamSocialLinksProvider`) over **Squad · Stats**. Squad = `PlayerCard` grid
(FWD→GK) → `PlayerDetailView` (bio + season block). Stats = real season summary
(roster W-D-L) + Goals/Assists/Clean-Sheets leaders. Per-player stats are
⚠️simulated (`StatsProvider`, deterministic/position-aware); leaders derive from
them so they match each player page. No formation pitch yet (needs lineup feed).
One `fetchRoster(clubID:)→ClubSquad` powers the page.

**Standings** (`standings-tab-design-spec.md`) — full 16-team table, **PTS · GP ·
W · L · D** only (no GF/GA/GD → avoids horizontal scroll); followed teams blue;
rows → `TeamDetailView`. Endpoint at `apis/v2/…` (not the app `base`).

**Schedule** (`schedule-tab-design-spec.md`) — full season in one
`fetchScoreboard(year:)` (~240 events for 2026); sticky day headers; three filters
(NWSL / My teams / All matches) over one `MatchStore`; cards carry 📍 venue · 📺
broadcast; scrolls to today, re-anchors on filter change. Tapping a card pushes
`MatchDetailView` — a state-aware (pre/in/post) match screen (full names, crests,
score or kickoff, venue + broadcast) built entirely from the scoreboard `Event`,
no extra fetch.

---

## What's Next

Completed work is documented in **Current State**; only pending work is listed
here. Original item numbers are kept so existing cross-references stay valid.

**Near-term / cleanup**
1. **(Perf — DONE)** `TeamLogo` now loads through `ImageCache` (a shared in-memory
   NSCache singleton) instead of bare `AsyncImage`, so crests aren't re-downloaded
   on scroll. In-memory only (disk caching deliberately out of scope).
3. **(Polish)** Pull-to-refresh flips `state` to `.loading` (full-screen spinner);
   keep the list visible during refresh, spinner only on first load.
4. Capture a real ESPN response → `NWSLAppTests/Fixtures/scoreboard.json` + a
   decode-only test for `Scoreboard`/Event helpers (date parsing, `dayKey` TZ).
6. **(DONE — see Current State)** `MatchCard` taps → `MatchDetailView`, built from
   the scoreboard `Event`. Remaining (future): ESPN's per-event `/summary` endpoint
   for the richer detail — lineups, goal scorers, match stats, news.
9. **(Fragility)** `MatchStore.matches(for:)` joins club↔game by `abbreviation`
   (ESPN competitors carry no id). TEMP-commented; a rename silently empties a
   schedule (empty state, not crash). Real fix: a normalized club-id map.
15. **(Cleanup — DONE, see Current State)** Shared `ClubStore` shipped; Teams,
    Onboarding, Home, Schedule, and Feed all read it (one fetch, many readers).
    Remaining: the two *game* VMs (`BracketViewModel`/`PredictXIViewModel`) still
    `try? fetchTeams()` independently for crests — low priority, fold them in too.
16. **(Robustness — DONE)** `ScheduleViewModel`'s swallowed club fetch is gone;
    a failed directory load now surfaces an error + retry on the My-teams path
    instead of an infinite spinner (via `ClubStore`'s error state).
17. **(Bug)** `StandingsView` — the large "Standings" nav title overlaps the
    table's column-header row (#/Team/PTS/GP/W/L/D), which renders on top of /
    too close to the title. Fix the spacing/z-order so the header sits clear
    below the title.

**Feature follow-ups (from shipped redesigns)**
- **Team-detail Stats + PlayerDetailView** — built on ⚠️simulated stats
  (`StatsProvider`). Remaining: a real per-player stats source (ESPN's
  `athletes[].statistics.splits` is sparse — likely the proxy), and a
  most-recent-formation pitch (needs an unmapped lineup endpoint).
- **(Data/Verify) Team social links** — ⚠️`TeamSocialLinksProvider` curated seed;
  verify before ship. Reddit needs a browser check — **KC** (`r/KCCurrent`, low
  confidence), **CHI** (`r/redstars` vs post-rebrand `r/ChicagoStars`); **BOS/DEN/
  LOU** have no subreddit yet (no Reddit icon). YT/IG channel URLs overlap the
  teams `TeamContentProvider` points at — collapse when the real backend lands.
- **Follow-confirmation sheet** — first-time "what following buys you" on the
  header star. No Settings screen exists yet (adjusting follows post-onboarding).
- **Home Module 1** — thumbnails + deep links are now real (⚠️`TeamContentProvider`
  is a curated seed of real YouTube videos; cards load real frames + tap to the
  video). Remaining: build the "See all" destination, and swap the static seed for
  a live team-channel source that refreshes (these specific videos won't rotate or
  re-fetch on their own — a deleted video falls back to the crest tile).
- **Home Module 2 spotlight pipeline** — UI done; thumbnails are now real (each
  YouTube video id drives the card/hero frame). Remaining: a deeper per-team pool
  (weekly rotation cycles a full roster), the opt-in weekly notification, and a
  team-colored badge (needs club hex).
- **Home Module 3 games** — all built; remaining is swapping each off its ⚠️seed +
  social/push layers (real multi-user leaderboards via #12, share-result card,
  kickoff/streak push). Trivia: real question backend. Bracket: real voting backend
  (real "community", not the sim) + rotating editions. Predict: real fixtures +
  lineup feed (live, not the offset clock) + per-category stats + more questions.

**Longer-term (vision — see `Reference/Sessions/` for full rationale)**
11. **Feed backend** — UI on the ⚠️seed. Needs: a real content source (Bluesky/news
    aggregator or proxy); the editorial "no culture-war/political hot takes" gate as
    a real filter (`nwslapp-feed-content-rules.md`); user-added sources (Content
    Preferences already does type toggles + muting; adding accounts needs the
    backend); per-post **team tagging via a Claude Haiku call** that also drops
    non-NWSL content.
12. **Push notifications + the server question.** Scheduled reminders need NO server
    (kickoff times known → local notifications, free on sideload); **live updates
    need a server + APNs + the $99 Program**. The server doubles as the caching
    proxy. The **caching half now exists** — `nwslapp-proxy` (Cloudflare Worker,
    0.2.0) proxies the scoreboard (see Data Source → Proxy). Remaining here: APNs +
    the Program for live push. Full reasoning:
    `Reference/Sessions/2026-06-04_server-pulls-and-push.md`.
13. **Competition-aware schedule.** Groundwork: the three Schedule filters,
    `MatchCard`'s dormant `CompetitionBadge`, and a `FollowedCompetition` model +
    follow set wired to onboarding. Remaining: a competition on `Event` (so a
    followed competition actually filters the schedule + badges populate), plus a
    surface to change competition follows after onboarding (no Settings yet).
14. **Engagement / Home hub** — player spotlights (→ contributor pipeline),
    community links (subreddits/Discords), prediction games. Live as Home modules
    first, graduate to a tab only if earned. (Reuse the push/#12 backend.)
```

