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
│   ├── Roster.swift                — a club's squad: flat view-friendly Athlete + defensive RosterResponse wrappers for ESPN's /teams/{id}/roster payload (RosterResponse.players flattens). Roster.grouped() buckets athletes by position (GK→DEF→MID→FWD). NOTE: NWSL headshots are null in ESPN's feed, so Athlete carries no photo — PlayerRow shows a jersey monogram (deliberate, permanent)
│   ├── Scoreboard.swift            — Codable structs mirroring ESPN's NWSL scoreboard JSON + Event helpers (kickoff, dayKey, home/away accessors)
│   └── Standings.swift             — league table: flat view-friendly StandingsRow (rank + a full Club + GP/W/D/L/PTS) + defensive StandingsResponse wrappers for ESPN's standings payload (children[0].standings.entries; StandingsResponse.rows flattens + sorts by rank). Each row carries a Club so it's tappable→TeamDetailView and follow-aware. Stats read by stable `type` key, not display order (draws = ESPN's "ties"). NOTE: standings lives at apis/v2/… NOT the apis/site/v2/… base (the site path returns {})
├── Services/
│   └── ESPNService.swift           — URLSession + async/await wrapper; fetchScoreboard(year:) (full season) + fetchTeams() (club directory) + fetchRoster(clubID:) (one club's squad) + fetchStandings() (league table, built from the apis/v2/… path explicitly — not `base`), all routed through a private generic fetch<T:Decodable>; throws ESPNServiceError
├── Stores/
│   ├── FollowingStore.swift        — @Observable personalization lens: which clubs the user follows (Set<String> of club IDs), persisted to UserDefaults; injected app-wide via .environment so all tabs share it (NOT a per-screen ViewModel)
│   └── MatchStore.swift            — @Observable shared season store: fetches the full scoreboard ONCE and exposes it app-wide (State enum + events + matches(for: Club)); injected in RootTabView via .environment. ScheduleView renders all of it, TeamDetailView renders a club's slice, future Home leads with followed clubs' next match. matches(for:) joins club↔match by abbreviation (TEMP-commented fragility: ESPN competitors carry no id)
├── ViewModels/
│   ├── ScheduleViewModel.swift     — @Observable; DERIVES day-grouped sections + initial scroll target from the injected MatchStore (no longer fetches); proxies the store's State; view hands it the store before first load
│   ├── TeamsViewModel.swift        — @Observable; State enum (idle/loading/loaded/error); fetches the club directory via ESPNService.fetchTeams()
│   ├── TeamDetailViewModel.swift   — @Observable; State enum for the ROSTER fetch only (matches come from the shared MatchStore); load(clubID:) → fetchRoster; positionGroups via Roster.grouped
│   └── StandingsViewModel.swift    — @Observable; same idle/loading/loaded/error State enum; one-shot fetch via ESPNService.fetchStandings() (own per-screen fetch, not the shared MatchStore — standings has no other readers)
├── Views/
│   ├── RootTabView.swift           — app root; 5-tab bottom TabView (Home / Schedule / Standings / Teams / Feed), each tab owns its own NavigationStack; lands on Schedule for now (flip `selection` default to .home once Home exists); creates the FollowingStore AND the MatchStore and injects both via .environment; Home/Feed are ComingSoonView PLACEHOLDERS (Schedule/Standings/Teams are built)
│   ├── ScheduleView.swift          — full-season schedule as a ScrollView + LazyVStack of cards with sticky day headers; reads the shared MatchStore (handed to its view model); scrolls to today (or next matchday) on first load via .scrollPosition(id:); pull-to-refresh
│   ├── TeamsView.swift             — Teams tab: directory of all 16 clubs in a List; a "Following" section floats followed clubs to the top, "All Clubs" lists every club end-to-end. Each row is a sibling pair of buttons — a row button (pushes TeamDetailView via a NavigationPath) + a Follow star (FollowingStore) — NOT nested (a Button inside a NavigationLink swallows the row's nav tap)
│   ├── TeamDetailView.swift        — a club's page, pushed from Teams (no own NavigationStack): a PINNED header (crest + name + Follow star) above a segmented sub-tab bar (Overview · Schedule · Squad); only the selected section scrolls. Overview (default) = next match + recent result, derived from MatchStore via Event.statusState (no extra fetch/date math); Schedule = the club's MatchStore.matches(for:) slice split into Upcoming/Results (reusing MatchCard); Squad = roster grouped by position via PlayerRow. Replaces the old single long scroll (header→full schedule→roster) where the roster was buried below the season — now it's one tap. Roster loads independently so its failure never blanks header/Overview/Schedule. (Three reversible design calls: default tab, segmented-vs-underline control, schedule order.)
│   └── StandingsView.swift         — Standings tab: a clean league table per the design spec (Reference/Design/standings-tab-design-spec.md). Non-scrolling column header (# · Team · PTS · GP · W · L · D) kept aligned with the scrolling rows via shared fixed Col widths (Grid can't bridge the scroll boundary); all 16 teams end-to-end, no truncation/horizontal scroll. Followed teams render blue (text + soft blue-tint bg) via FollowingStore. Each row is a Button that appends row.club to a NavigationPath → TeamDetailView (same pattern + destination as Teams). Footer = stat legend. Deliberately NO GF/GA/GD or home-away splits (would force horizontal scroll). PTS is bold and fronted (Tiffany's column order).
├── Components/
│   ├── ComingSoonView.swift        — reusable intentional placeholder (SF Symbol + title + "coming soon" copy) for not-yet-built tabs; drives the 4 placeholder tabs in RootTabView
│   ├── MatchCard.swift             — one game as a rounded card: stacked home/away rows (logo + abbreviation) + score (or kickoff time) + status badge (LIVE / FT / scheduled); reused by ScheduleView + TeamDetailView's schedule slice
│   ├── PlayerRow.swift             — one roster player: jersey-number / initials monogram avatar (NWSL has no headshots) + name + details line (position · age · height · nationality); used by TeamDetailView
│   └── TeamLogo.swift              — reusable AsyncImage crest: fixed frame, loading placeholder, neutral failure fallback (no broken-image glyph); used by MatchCard + TeamsView + TeamDetailView + StandingsView
└── Assets.xcassets/                — app icons, accent color
```

---

## Current State

The app root is now `RootTabView` — a conventional 5-tab bottom bar
(**Home · Schedule · Standings · Teams · Feed**), each tab in its own
`NavigationStack` so back-stacks survive tab switches. **Schedule**,
**Standings**, and **Teams** are built; Home/Feed render a shared, intentional
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

**Team detail page + shared `MatchStore`.** Tapping a club in Teams pushes
`TeamDetailView` (no own `NavigationStack` — it rides the Teams tab's stack, so
the back affordance is free): a **pinned header** (crest + name + the same
Follow star, so toggling here reflects everywhere) above a segmented **sub-tab
bar — Overview · Schedule · Squad** (only the selected section scrolls). This
replaced an earlier single long scroll (header → full schedule → roster) where
the roster was buried below the whole season; every reference app
(Athletic/MLS/NWSL) fronts the team page with sub-tabs, so now the roster is one
tap. **Overview** (the default) leads with next match + recent result — derived
from `MatchStore` via `Event.statusState`, no extra fetch or date math, and the
app's first small "alive" seed (the "when's the next game / what was the score"
use case). **Schedule** splits the club's slice into Upcoming/Results; **Squad**
is the roster grouped by position. The schedule slice introduced the app's second
app-wide store: `MatchStore` (`@Observable`, created in `RootTabView`, injected
via `.environment` alongside `FollowingStore`) fetches the full season **once**
and serves it to every screen — `ScheduleView` was refactored to read from it
(its view model now *derives* sections/scroll-target rather than fetching), and
`MatchStore.matches(for: club)` returns a club's games (joined by abbreviation —
a TEMP-commented fragility, since ESPN's scoreboard competitors carry no id;
verified all 16 clubs' abbreviations match across `/teams` and `/scoreboard`).
The roster comes from `ESPNService.fetchRoster(clubID:)` → `Roster.swift`,
rendered via `PlayerRow` with **jersey-number monogram avatars** because NWSL
headshots are null in ESPN's feed (a deliberate, permanent choice). Roster loads
on its own `TeamDetailViewModel` state, independent of the schedule, so a roster
failure never blanks the header + Overview/Schedule. The Teams rows were
reworked into **sibling** buttons (row-button pushes via a `NavigationPath`;
Follow star is separate) — a `Button` nested inside a `NavigationLink` swallows
the row's navigation tap, which we hit and fixed. Verified in-sim (UI-test
driven, then removed): Teams → tap a club pushes the page with a working back
button and lands on **Overview** (next match + recent-result cards reusing
`MatchCard`); the **Squad** sub-tab reaches the roster in one tap (~24 players
grouped GK/DEF/MID/FWD with monogram avatars and position·age·height·nationality);
the **Schedule** sub-tab shows Upcoming then Results; tapping the header star
toggles Follow **without navigating** and floats the club into Teams' Following
section; and Schedule's scroll-to-today still lands on the July matchday after
the store refactor. (Note: the sub-tab label "Schedule" shares its name with the
bottom tab-bar item — purely an a11y/test-targeting wrinkle, not user-facing.)

**Standings.** The Standings tab (`StandingsView` + `StandingsViewModel`,
`ESPNService.fetchStandings()` → `Standings.swift`) renders the full 16-team
league table per the approved design spec
(`Reference/Design/standings-tab-design-spec.md`): pure reference utility, "the
simplest tab in the app." Six stat columns only — **PTS · GP · W · L · D**
(Tiffany's chosen order, PTS fronted and bold) — with **GF/GA/GD and home/away
splits deliberately omitted** because they'd force horizontal scrolling on a
phone and serve a stat-obsessive audience that already has FotMob/ESPN; this
app's thesis is connection over stat overload. All 16 teams show end-to-end (no
truncation, no horizontal scroll); the column header sits outside the
`ScrollView` so it stays put while rows scroll, kept aligned with the rows by
shared fixed column widths (a `Grid` can't bridge the scroll boundary). Each row
carries a full `Club` so it's tappable → `TeamDetailView` (the exact same
NavigationPath-append pattern and destination as the Teams tab) and **follow-aware**:
followed teams render blue (blue text + a soft blue-tint background) via the
shared `FollowingStore`, so your teams jump out on open. A footer stat legend
spells out the abbreviations for new fans. The standings endpoint is the one ESPN
path NOT under the app's `base` — it lives at `apis/v2/…` (not `apis/site/v2/…`,
which returns `{}`), so `fetchStandings()` builds that URL explicitly; the
standings team `id` is the same ESPN team id as `/teams`, so the `Club` built
from a row navigates and follows correctly with no id mapping. Verified in-sim:
all 16 teams load rank-sorted with crests and correct PTS/GP/W/L/D; seeding two
followed clubs (Portland + Washington) surfaces both as blue-highlighted rows;
column order matches the spec; landing tab reverted to Schedule after testing.

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
position back. The MVVM spine is real: `MatchStore` owns the season data,
`ScheduleViewModel` derives the day-grouped presentation, `ScheduleView`
renders, `ESPNService` fetches. (The fetch call itself now lives in `MatchStore`,
not the view model — see the Team-detail section above.)

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
   - **(DONE)** ~~Team detail page — make Teams rows tappable → push a club page
     (roster, schedule filtered to that club, Follow).~~ Shipped: `TeamDetailView`
     + `TeamDetailViewModel` + shared `MatchStore` + `Roster.swift` + `PlayerRow`.
     Also satisfies What's-Next #8.
   - **Your-teams-first Home** — build the Home tab as a hub that leads with
     followed clubs' next match / recent result (the "My teams" view *is* Home,
     not a separate tab). **Now unblocked:** the shared `MatchStore` already
     answers "this club's next match" — Home is mostly assembly over the same
     store + `FollowingStore`.
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
7. **(DONE)** ~~Standings view (must show all teams end-to-end, without
   truncation).~~ Shipped: `StandingsView` + `StandingsViewModel` +
   `Standings.swift` + `ESPNService.fetchStandings()`, wired into RootTabView.
   Clean PTS·GP·W·L·D table, all 16 teams end-to-end, followed teams highlighted
   blue, rows tap into TeamDetailView. Deferred follow-ups: surface GD
   contextually when two teams are tied on points (spec note — not a permanent
   column); a club record/standings line in the TeamDetailView header can now
   reuse this endpoint (What's-Next #8 leftover).
8. **(DONE)** ~~Team detail page (profile, roster, schedule filtered to that
   team).~~ See item #2. Roster, club schedule, and Follow shipped; club
   record/standings header is deferred (needs the standings endpoint — fold into
   the endpoint-mapping pass).
9. **(Fragility)** `MatchStore.matches(for: club)` joins a club to its games by
   `abbreviation` (string), because ESPN's scoreboard competitor `Team` carries
   no id. Verified safe today (all 16 clubs' abbreviations match across `/teams`
   and `/scoreboard`), TEMP-commented in `MatchStore.swift`. A rename/relocation
   would silently empty a club's schedule (the page shows a visible empty state,
   not a crash). Real fix when a back end exists: a normalized club-id map, or a
   proxy that attaches a stable id to every competitor.
10. **(DONE)** ~~`TeamDetailView` lists the **full** season schedule above the
    roster, so reaching the roster is a long scroll.~~ Redesigned around the
    competitor pattern (Athletic/MLS/NWSL all front the team page with sub-tabs):
    a pinned header (crest + name + Follow) above a segmented **Overview ·
    Schedule · Squad** control — roster is now one tap, not a long scroll.
    Overview leads with next match + recent result (Tiffany's #1 use case + the
    first small "alive" seed); Schedule splits Upcoming/Results. Verified in-sim
    (temporary XCUITest, then removed). Deferred follow-ups from this redesign:
    a Follow-confirmation sheet (rename star → "Follow" + first-time "here's what
    following buys you"), a standings/record line in the header (needs the
    standings endpoint), and a future per-team News/Spotlights sub-tab (the
    "alive" work — long-term vision being moved to Claude Cowork).

**Longer-term (vision — see `Reference/Sessions/` for the full discussion):**

11. **Feed, reimagined** — social-native news (reporters' Bluesky/Twitter, team
    IG/TikTok) tailored to followed teams, not a closed-loop press-release feed.
12. **Push notifications + the server/back-end question.** The day-before/day-of
    heads-up + the live ladder (lineup → kickoff → goals → half → full). This is
    the first feature the iPhone can't do alone. Key split we worked out: the
    **scheduled reminders need NO server** (kickoff times are known ahead, so
    schedule local notifications on-device — free, works on the current sideload
    tier), while **live updates need a server + APNs** (and the **$99 Apple
    Developer Program**, which the free Personal-Team tier can't do remote push
    on). A small server (Cloudflare Workers / Supabase / a Raspberry-Pi stopgap)
    also doubles as the **caching proxy** that polls ESPN once and fans out to
    all clients — the "future Vercel proxy." This is a **much-later** milestone;
    full reasoning, free-tier options, and the Eras-Tour-Mastermind analogy are
    captured in `Reference/Sessions/2026-06-04_server-pulls-and-push.md`.
13. **Competition-aware schedule** — don't hardwire to a single league; make
    matches carry a competition so Challenge Cup, Concacaf W, and USWNT can be
    added later without a painful refactor.
14. **Engagement / Home hub** — player spotlights (eventually a contributor
    pipeline), community links (subreddits/Discords), prediction games. These
    live as Home *modules* first and graduate to their own tab only if earned.
    (Prediction games are the Mastermind pattern — they reuse the same back end
    as push; see the server/push session notes.)
