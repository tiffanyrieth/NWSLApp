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

```
NWSLApp/
├── NWSLAppApp.swift                — app entry point; launches RootTabView
├── Models/
│   ├── Club.swift                  — league club directory model (flat, view-friendly Club) + defensive Decodable wrappers for ESPN's nested /teams payload (TeamsResponse.clubs flattens + sorts active clubs); named Club to avoid colliding with Scoreboard's competitor-level Team
│   └── Scoreboard.swift            — Codable structs mirroring ESPN's NWSL scoreboard JSON + Event helpers (kickoff, dayKey, home/away accessors)
├── Services/
│   └── ESPNService.swift           — URLSession + async/await wrapper; fetchScoreboard(year:) (full season) + fetchTeams() (club directory), both routed through a private generic fetch<T:Decodable>; throws ESPNServiceError
├── Stores/
│   └── FollowingStore.swift        — @Observable personalization lens: which clubs the user follows (Set<String> of club IDs), persisted to UserDefaults; injected app-wide via .environment so all tabs share it (NOT a per-screen ViewModel)
├── ViewModels/
│   ├── ScheduleViewModel.swift     — @Observable; State enum (idle/loading/loaded/error); exposes day-grouped sections + initial scroll target
│   └── TeamsViewModel.swift        — @Observable; same State enum; fetches the club directory via ESPNService.fetchTeams()
├── Views/
│   ├── RootTabView.swift           — app root; 5-tab bottom TabView (Home / Schedule / Standings / Teams / Feed), each tab owns its own NavigationStack; lands on Schedule for now (flip `selection` default to .home once Home exists); creates the FollowingStore and injects it via .environment; Home/Standings/Feed are ComingSoonView PLACEHOLDERS
│   ├── ScheduleView.swift          — full-season schedule as a ScrollView + LazyVStack of cards with sticky day headers; scrolls to today (or next matchday) on first load via .scrollPosition(id:); pull-to-refresh
│   └── TeamsView.swift             — Teams tab: directory of all 16 clubs in a List; a "Following" section floats followed clubs to the top, "All Clubs" lists every club end-to-end; each row has a Follow star toggle wired to FollowingStore (from the environment). Rows not yet tappable (team detail page is next)
├── Components/
│   ├── ComingSoonView.swift        — reusable intentional placeholder (SF Symbol + title + "coming soon" copy) for not-yet-built tabs; drives the 4 placeholder tabs in RootTabView
│   ├── MatchCard.swift             — one game as a rounded card: stacked home/away rows (logo + abbreviation) + score (or kickoff time) + status badge (LIVE / FT / scheduled)
│   └── TeamLogo.swift              — reusable AsyncImage crest: fixed frame, loading placeholder, neutral failure fallback (no broken-image glyph); used by MatchCard + TeamsView, reused by future Standings
└── Assets.xcassets/                — app icons, accent color
```

---

## Current State

The app root is now `RootTabView` — a conventional 5-tab bottom bar
(**Home · Schedule · Standings · Teams · Feed**), each tab in its own
`NavigationStack` so back-stacks survive tab switches. **Schedule** and
**Teams** are built; Home/Standings/Feed render a shared, intentional
`ComingSoonView` placeholder. The app deliberately **lands on Schedule** (not
the leftmost Home tab) since Home is still a placeholder — flip `selection`'s
default to `.home` once Home is real. Tab is `Feed` (not `News`) on purpose, to
signal the social-native, "alive" direction (full rationale in the gitignored
`Reference/Sessions/` notes). Verified in-sim: lands on Schedule, all 5 tabs
render, Schedule's scroll-to-today still works inside the tab, and a placeholder
tab shows the clean "coming soon" screen.

**Teams + Following (personalization spine).** The Teams tab (`TeamsView` +
`TeamsViewModel`, `ESPNService.fetchTeams()`) lists all 16 clubs from ESPN's
`/teams` endpoint, decoded via `Club.swift`. Each row has a Follow star wired to
`FollowingStore` — an `@Observable` set of followed club IDs persisted to
`UserDefaults`, created once in `RootTabView` and shared with every tab via
`.environment` (so Home/Feed can read the same lens later). Followed clubs float
into a "Following" section above the full "All Clubs" list. Verified in-sim: all
16 clubs load alphabetically with crests; seeding `UserDefaults` then launching
surfaces the Following section (persistence read-path confirmed; the toggle
writes the identical key/format). This is the foundation the "your-teams-first
Home" and tailored Feed will build on. Note: SwiftData is now in use **nowhere**
— following persists via `UserDefaults` (right-sized for a small ID set).

`ScheduleView` loads the full current NWSL season in one call
(`ESPNService.fetchScoreboard(year:)` → `?dates=YYYY0101-YYYY1231&limit=500`,
~240 events for 2026) and presents it as an MLS-app-style vertical scroll of
game **cards** (`ScrollView` + `LazyVStack`, ~4–5 per screen) grouped under
sticky local-day headers. Each `MatchCard` shows both teams' crests
(`TeamLogo` → `AsyncImage`) and abbreviations with score or kickoff time and a
status badge. On first load it scrolls to today (or the next upcoming matchday)
via iOS 17's `.scrollPosition(id:)` — the previous `List` + `ScrollViewReader`
approach couldn't anchor reliably; this lands correctly (verified in-sim:
skipped the March opener and the empty June FIFA window, landed on the July
matchday). A `hasScrolledToToday` guard keeps pull-to-refresh from yanking the
position back. The MVVM spine is real: `ScheduleViewModel` owns state,
`ScheduleView` renders, `ESPNService` fetches.

---

## What's Next

1. **(Perf/TEMP)** `TeamLogo` uses bare `AsyncImage`, which has no cross-cell
   image cache — crests re-download every time a card recycles during scroll.
   Acceptable for v1 (small PNGs, lazy rows) and marked with a `TEMP` comment in
   `Components/TeamLogo.swift`. Replace with a shared cache (NSCache-backed
   loader, or route logos through the future Vercel proxy with caching headers)
   and remove the TEMP note.
2. **(DONE)** ~~Teams tab + Following lens.~~ Teams directory of all 16 clubs
   with a Follow star, backed by `FollowingStore` (UserDefaults). Following is a
   cross-cutting *lens*, not its own tab — it will personalize Home
   (your-teams-first) and Feed next. **Next builds on this:**
   - **Team detail page** — make Teams rows tappable → push a club page (roster,
     schedule filtered to that club, Follow). This is also What's-Next #8.
   - **Your-teams-first Home** — build the Home tab as a hub that leads with
     followed clubs' next match / recent result (the "My teams" view *is* Home,
     not a separate tab).
   - **Extend the lens to players** later (the "watch 1–2 players a week"
     mechanic). See `Reference/Sessions/` for full rationale.
3. **(Polish)** Pull-to-refresh flips `state` to `.loading`, which swaps the
   whole card list for a centered `ProgressView` mid-refresh (pre-existing, not
   introduced by the card redesign). Consider keeping the list visible during a
   refresh (only show the full-screen spinner on the very first load) so the
   refresh control's own spinner carries the interaction.
4. Capture a real ESPN response into `NWSLAppTests/Fixtures/scoreboard.json` and
   add a decode-only test for `Scoreboard` + Event helpers (date parsing,
   `dayKey` time-zone behavior).
5. **(Enhancement)** Enrich the schedule cards with the broadcast (TV) and
   venue info real fans need — this is what the NWSL/MLS apps surface per game.
   No new endpoint required: the scoreboard response we already fetch includes
   `competition.venue.fullName` (+ city) and `competition.broadcasts` /
   `geoBroadcasts` (e.g. `["ION"]`). Decode those onto the model and add a
   compact third line to `MatchCard` (stadium · network). Likely the moment to
   bump cards toward MLS-style ~4-per-screen once they carry more detail.
6. Make `MatchCard` tappable → push a match detail screen (scorers, lineups,
   stats, news) via the `NavigationStack` already in place.
7. Standings view (must show all teams end-to-end, without truncation).
8. Team detail page (profile, roster, schedule filtered to that team).

**Longer-term (vision — see `Reference/Sessions/` for the full discussion):**

9. **Feed, reimagined** — social-native news (reporters' Bluesky/Twitter, team
   IG/TikTok) tailored to followed teams, not a closed-loop press-release feed.
10. **Push notifications** — the day-before/day-of heads-up + the live ladder
    (lineup → kickoff → goals → half → full). This is the first feature the
    iPhone can't do alone: it needs a server polling the schedule + APNs, i.e.
    the "future Vercel proxy" becomes a real backend.
11. **Competition-aware schedule** — don't hardwire to a single league; make
    matches carry a competition so Challenge Cup, Concacaf W, and USWNT can be
    added later without a painful refactor.
12. **Engagement / Home hub** — player spotlights (eventually a contributor
    pipeline), community links (subreddits/Discords), prediction games. These
    live as Home *modules* first and graduate to their own tab only if earned.
