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
- Don't ship placeholder or empty sections.
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
├── NWSLAppApp.swift                — app entry point; launches ScheduleView
├── Models/
│   └── Scoreboard.swift            — Codable structs mirroring ESPN's NWSL scoreboard JSON + Event helpers (kickoff, dayKey, home/away accessors)
├── Services/
│   └── ESPNService.swift           — URLSession + async/await wrapper; fetchScoreboard(year:) hits ?dates=YYYY0101-YYYY1231&limit=500 for the full season; throws ESPNServiceError
├── ViewModels/
│   └── ScheduleViewModel.swift     — @Observable; State enum (idle/loading/loaded/error); exposes day-grouped sections + initial scroll target
├── Views/
│   └── ScheduleView.swift          — full-season schedule list, scrolls to today on first load, pull-to-refresh
├── Components/
│   └── MatchCard.swift             — one row: stacked home/away abbreviations + score (or kickoff time) + status badge (LIVE / FT / scheduled)
└── Assets.xcassets/                — app icons, accent color
```

---

## Current State

The first real feature ships: `ScheduleView` loads the full current NWSL season
in one call (`ESPNService.fetchScoreboard(year:)` →
`?dates=YYYY0101-YYYY1231&limit=500`, ~240 events for 2026), groups events into
day sections in the user's local time zone, and scrolls to today (or the next
upcoming matchday) on first appearance so fans land on what's relevant.
Pull-to-refresh works without yanking the scroll position back. The MVVM spine
is real: `ScheduleViewModel` owns state, `ScheduleView` renders, `ESPNService`
fetches. The temporary `ContentView` smoke test has been removed.

---

## What's Next

1. **(Bug)** Initial scroll position lands at the first game of the season
   instead of today (or the next upcoming matchday). Investigate why
   `initialScrollSectionID` isn't taking effect — likely candidates:
   `.onChange` fires before the `List` has finished laying out the new sections;
   `Section { header: ... }`'s `.id(section.id)` isn't a valid `scrollTo` target
   inside a `List`; or `vm.sections.first?.id` isn't changing the way the guard
   expects. May need `.scrollPosition()` (iOS 17+), a `DispatchQueue.main.async`
   delay inside the `onChange`, or moving the `.id` from the header `Text` onto a
   zero-height marker view inside the section.
2. **(Architecture)** Tab-bar navigation. `ScheduleView` should be a tab, not
   the root. Plan the structure: **Home / Schedule / Standings / Teams / News**.
   Decide which tab opens on launch (likely Home once it exists, Schedule until
   then), and give each tab its own `NavigationStack` so back-stacks survive tab
   switches.
3. **(Enhancement)** Team logos in `MatchCard` via `AsyncImage` —
   `competitor.team.logo` already decodes; needs a placeholder, a small fixed
   frame, and a failure fallback (initials or abbreviation block).
4. Capture a real ESPN response into `NWSLAppTests/Fixtures/scoreboard.json` and
   add a decode-only test for `Scoreboard` + Event helpers (date parsing,
   `dayKey` time-zone behavior).
5. Tap-through to a match detail screen (scorers, lineups, stats, news) — uses
   the `NavigationStack` already in place.
6. Standings view (must show all teams end-to-end, without truncation).
7. Team detail page (profile, roster, schedule filtered to that team).
