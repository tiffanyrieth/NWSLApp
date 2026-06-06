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
│   ├── Club.swift                  — league club directory model (flat, view-friendly Club) + defensive Decodable wrappers for ESPN's nested /teams payload (TeamsResponse.clubs flattens + sorts active clubs); named Club to avoid colliding with Scoreboard's competitor-level Team. Club also carries optional shortName (ESPN shortDisplayName, e.g. "Angel City"), `var … = nil` defaulted so other Club call sites (Standings) compile unchanged — it's the chip-friendly label for the Feed tab's per-team filters.
│   ├── FeedItem.swift              — one Feed-tab item: a flat, view-friendly FeedItem (kind = .reporterPost | .articleLink; sourceName/handle/platform/timestamp; body for posts, headline+summary for articles; url; teams tags; isLeague) + a FeedTeamTag (abbreviation only — the join key for the per-team filters, matched to followed clubs by abbreviation; the team isn't shown on the card). Codable-shaped so the current TEMP static seed can later be swapped for a real Bluesky/news backend with no view/VM change. Legal: articles hold headline + 1-line summary + link ONLY, never the body.
│   ├── PlayerSpotlight.swift       — one "player of the week" for Home's Module 2 ("Get to know your players"), the Option B "mini profile" per Reference/Design/spotlight-design-spec.md: flat fields = teamAbbreviation join key + playerName/jerseyNumber/position, a 2-3 sentence `bioBlurb` (the Home-card hook), VIDEO fields (videoURL/videoTitle/videoSource — videoURL nil = the written-only fallback, e.g. content that lives only on Facebook), and EXTENDED-PROFILE fields for the detail page (nationality, age [2026 snapshot, nil when uncertain], careerHighlights, funFacts, seasonForm [nil today — volatile]). No duration field (YouTube doesn't expose runtime to the seed). Backed by the TEMP PlayerSpotlightProvider seed; HomeViewModel surfaces one per followed team. Mirrors FeedItem/TeamContentItem's abbreviation-join shape.
│   ├── Roster.swift                — a club's squad + team profile: flat view-friendly Athlete (incl. shortName "T. Rodman") + a ClubSquad result (athletes + team colorHex + standingSummary + record; ClubSquad.standingLine = "4th in NWSL — 21 pts", points derived from the W-D-L record) + defensive RosterResponse wrappers for ESPN's /teams/{id}/roster payload (RosterResponse.squad bundles it; the roster payload ALSO carries team color + standing/record, so ONE fetch powers the whole team page). Roster.grouped() buckets athletes by position FWD→MID→DEF→GK (attackers first — the "meet the team" Squad grid leads with the players fans come to see). NOTE: NWSL headshots are null in ESPN's feed, so Athlete carries no photo — PlayerCard shows a jersey/initials monogram (deliberate, permanent)
│   ├── Scoreboard.swift            — Codable structs mirroring ESPN's NWSL scoreboard JSON + Event helpers (kickoff, dayKey, home/away accessors, venueName, broadcastName). Venue (competition.venue.fullName) + broadcasts (competition.broadcasts[].names) ride the SAME scoreboard response — no extra fetch; decoded defensively (all optional).
│   ├── Standings.swift             — league table: flat view-friendly StandingsRow (rank + a full Club + GP/W/D/L/PTS) + defensive StandingsResponse wrappers for ESPN's standings payload (children[0].standings.entries; StandingsResponse.rows flattens + sorts by rank). Each row carries a Club so it's tappable→TeamDetailView and follow-aware. Stats read by stable `type` key, not display order (draws = ESPN's "ties"). NOTE: standings lives at apis/v2/… NOT the apis/site/v2/… base (the site path returns {})
│   └── TeamContentItem.swift       — one item in Home's Module 1 ("From your teams") — the teams' OWN voices (official YouTube/Instagram/TikTok/Bluesky), distinct from the Feed tab (reporters/news ABOUT your teams). Flat/Codable-shaped: a Platform enum (.youtube/.instagram/.tiktok/.bluesky, each w/ a symbol + isVideo), timestamp, caption, optional durationLabel, url, and a teamAbbreviation join key (crest/name resolved from the followed Club, like FeedItem). Backed by the TEMP TeamContentProvider seed.
├── Services/
│   ├── ESPNService.swift           — URLSession + async/await wrapper; fetchScoreboard(year:) (full season) + fetchTeams() (club directory) + fetchRoster(clubID:) → ClubSquad (one club's squad + team color/standing profile, one call) + fetchStandings() (league table, built from the apis/v2/… path explicitly — not `base`), all routed through a private generic fetch<T:Decodable>; throws ESPNServiceError
│   ├── FeedContentProvider.swift   — ⚠️ TEMP/SCAFFOLDING: curated static seed for the Feed tab. async items() → [FeedItem] drawn from real NWSL reporters/outlets (The Athletic, ESPN, The Equalizer, Just Women's Sports; Meg Linehan, Jeff Kassouf, Steph Yang, et al.) and real, recent storylines, covering ALL 16 clubs (~2 items each) + a few league-wide items. Coverage is deliberately even/league-wide — NOT skewed to any club — so picking ANY team in onboarding surfaces a few listings (the concept-demo goal). Posts paraphrase real storylines (not verbatim quotes). Exists because there's no content backend yet. Swap items() for a real social/news source (or the planned proxy) to remove — the async signature is already shaped for it. Editorial policy (no culture-war/political/identity hot takes) lives here when it becomes a live gate.
│   ├── TeamContentProvider.swift   — ⚠️ TEMP/SCAFFOLDING: curated static seed for Home's Module 1 ("From your teams"). async items() → [TeamContentItem], ~2 per club (all 16). Every url is a REAL, durable account-level link (each team's actual YouTube channel + Instagram profile, verified for 2026 incl. the Denver Summit/Boston Legacy expansion sides); captions paraphrase the kind of content those accounts post. Mirrors FeedContentProvider (relative timestamps, builder fns). Swap items() for a real team-channel aggregator/proxy — same signature; a live source also brings real per-post thumbnails (the seed renders a designed crest tile) + per-post deep links.
│   └── PlayerSpotlightProvider.swift — ⚠️ TEMP/SCAFFOLDING: curated static seed for Home's Module 2 ("Get to know your players"). async spotlights() → [PlayerSpotlight], one real 2026-roster player per club (all 16, incl. expansion sides). Each carries a hand-written bioBlurb + extended profile (nationality/age/careerHighlights/funFacts — durable facts, volatile stats omitted; ages are a 2026 snapshot) AND a REAL, verified player-focused YouTube video (every id confirmed via oembed to resolve to a video whose title names the player — "get to know"/feature/mic'd-up/interview). Sources attributed honestly: some on the team's own channel (Houston Dash, Thorns FC, Racing Louisville, Bay FC, Utah Royals, Washington Spirit), others on league/partner media (NWSL, Victory+, Attacking Third, The Women's Game) — labeled as such. One player (Nérilia Mondésir/SEA) has video nil → written-only fallback (hers lives only on Facebook). Swap spotlights() for a real curated/editorial source — same signature; a live source brings per-post thumbnails + durations + the club color for a team-colored badge.
├── Stores/
│   ├── FollowingStore.swift        — @Observable personalization lens: which clubs the user follows (Set<String> of club IDs), persisted to UserDefaults; injected app-wide via .environment so all tabs share it (NOT a per-screen ViewModel). ALSO tracks hasOnboarded (persisted Bool + completeOnboarding()) — the one-time first-open gate that flips Home from the "Make it yours" picker to the hub; init treats an existing follower as already onboarded so seeded sims/users skip the picker.
│   └── MatchStore.swift            — @Observable shared season store: fetches the full scoreboard ONCE and exposes it app-wide (State enum + events + matches(for: Club)); injected in RootTabView via .environment. ScheduleView renders all of it; Home DERIVES its compact "Coming up" strip from it (next match per followed club via matches(for:)). matches(for:) joins club↔match by abbreviation (TEMP-commented fragility: ESPN competitors carry no id). NOTE: TeamDetailView does NOT read this (the Teams-tab redesign moved schedule to the Schedule tab); matches(for:) now powers HomeView's "Coming up" module (Home's "Around the league" module was removed in the content-leads redesign).
├── ViewModels/
│   ├── HomeViewModel.swift         — @Observable; owns the Home tab's club-directory fetch (idle/loading/loaded/error) + loads two TEMP content seeds, and DERIVES Home's modules from the injected MatchStore + FollowingStore (mirrors ScheduleViewModel's store-handoff). loadClubs() fetches the club directory (resolve followed IDs → full Clubs for crest/name + the abbreviation join) AND pulls the TeamContentProvider/PlayerSpotlightProvider seeds in one pass; the season comes from the shared store. Derivations: teamContent(following:) → Module 1 items for followed clubs, newest-first, capped; spotlights(following:) → Module 2's ONE spotlight PER followed team (spec §Multi-team rotation — follow 2 teams, see 2 cards; each team rotates independently via a deterministic week-of-year pick over that team's spotlights, one player per team today; ordered by the followed clubs' directory/alphabetical order); nextMatches(following:) → Module 4's FollowedFixture per followed club (next non-final match, else most-recent result; upcoming soonest-first) w/ a time-aware label; club(forAbbreviation:) resolves the join key → Club. (aroundTheLeague was removed with the "Around the league" module.)
│   ├── ScheduleViewModel.swift     — @Observable; DERIVES day-grouped sections + initial scroll target from the injected MatchStore; proxies the store's State; view hands it the store + FollowingStore before first load. Owns a Filter enum (nwsl / myTeams / allMatches) and sections(for:)/initialScrollSectionID(for:) so the three filter tabs are three functions over ONE data set. Fetches the club directory ONCE (the only thing it fetches) purely to resolve followed IDs → team abbreviations for the My-teams filter (followedAbbreviations) via a SEPARATE loadClubs() — deliberately decoupled from the season `.idle` guard so the club directory still resolves when another tab (Home, the landing tab) already loaded the shared MatchStore; otherwise the My-teams filter would hang on "Loading your teams…" forever. load() = season + loadClubs() (used by pull-to-refresh); loadClubs() is idempotent (clubs.isEmpty) and called unconditionally on appear. nwsl & allMatches return the full set today (they diverge once non-NWSL competition data exists). NOTE: club fetch is duplicated in Home/Teams/Schedule — a future shared ClubStore could consolidate (What's-Next).
│   ├── TeamsViewModel.swift        — @Observable; State enum (idle/loading/loaded/error); fetches the club directory via ESPNService.fetchTeams()
│   ├── TeamDetailViewModel.swift   — @Observable; State enum holding the ClubSquad from one roster fetch (load(clubID:) → fetchRoster). Exposes positionGroups (via Roster.grouped, FWD-first), accentColorHex (club color for cards/badges), and standingLine (the header's "4th in NWSL — 21 pts"). One fetch feeds the whole page; no MatchStore dependency anymore.
│   ├── StandingsViewModel.swift    — @Observable; same idle/loading/loaded/error State enum; one-shot fetch via ESPNService.fetchStandings() (own per-screen fetch, not the shared MatchStore — standings has no other readers)
│   └── FeedViewModel.swift         — @Observable; owns the Feed tab. Loads the (TEMP seed) items + fetches the club directory (same pattern as Home, idle/loading/loaded/error State, to resolve followed IDs → chips). DERIVES: chips(following) = All + one per followed team (clean text, shortName label) + League; items(following) filters the stream by the selected Filter (.all = followed-teams + league news, newest first · .team(abbrev) = that team incl. multi-team items · .league = league-wide only). Chip↔item matching is by club abbreviation (mirrors MatchStore's join — ESPN gives no stable competitor id). The view passes in the shared FollowingStore.
├── Views/
│   ├── RootTabView.swift           — app root; 5-tab bottom TabView (Home / Schedule / Standings / Teams / Feed), each tab owns its own NavigationStack; LANDS ON HOME; creates the FollowingStore AND the MatchStore and injects both via .environment. ALL FIVE TABS ARE NOW BUILT — no placeholder tab remains (ComingSoonView is now unreferenced).
│   ├── HomeView.swift              — Home tab: the your-teams-first hub. While FollowingStore.hasOnboarded is false it renders OnboardingView in place (tab bar stays visible). Otherwise the hub: a ScrollView of modules per Reference/Design/home-tab-design-spec.md (the 2026-06-06 "content leads" reorder) — (1) "From your teams" = a vertical stack of TeamContentCards (real seeded team-channel content, newest-first, capped — THE HOOK); (2) "Get to know your players" = a vertical stack of PlayerSpotlightCards, ONE per followed team (Option B mini-profile), each a NavigationLink → PlayerSpotlightView; hidden if no followed team has a spotlight; (3) "Play" = a horizontal row of intentional "coming soon" game cards (Daily Trivia / Predict the XI / Bracket Battle) under a competitive subtitle; (4) "Coming up" = a compact ComingUpRow per followed club (real, from MatchStore; hidden when none). ("Around the league" was REMOVED — it duplicated the Schedule tab.) Reads MatchStore + FollowingStore from the environment, hands the store to its view model, loads both once on .task. The no-follows state shows the lead module's "Choose your teams" prompt that re-presents the picker as a sheet. (Spec leftover: the per-section "See all" link is omitted until a full-content destination exists.)
│   ├── OnboardingView.swift        — first-open "Make it yours" team picker (per the Home spec): a single alphabetical List of every club (no grid, no search), each a whole-row follow toggle (filled checkmark when on), with a collapsed-by-default "Also follow international competitions" disclosure (TEMP intentional placeholder — its rows say "Coming soon" and do NOT toggle, because FollowingStore tracks club IDs only; competition-following needs its own data model). A pinned bottom bar shows the running "Follow N teams" count (disabled at 0) + "you can always change this later"; the button calls completeOnboarding() (flips Home to the hub) and dismiss() (so it also works re-presented as a sheet). Reuses TeamsViewModel for the fetch + the shared FollowingStore for the picks.
│   ├── ScheduleView.swift          — full-season schedule as a ScrollView + LazyVStack of cards with sticky day headers; reads the shared MatchStore + FollowingStore (handed to its view model). THREE always-visible segmented filter tabs below the title (NWSL default · My teams · All matches), per Reference/Design/schedule-tab-design-spec.md. Scrolls to today (or next matchday) on first load via .scrollPosition(id:) AND re-anchors to the next upcoming match when the filter changes; the first-load anchor retries once the club directory resolves (My teams needs it — otherwise it'd open at the season opener). My teams with no follows shows a gentle "follow your teams" prompt; pull-to-refresh on the list.
│   ├── TeamsView.swift             — Teams tab: directory of all 16 clubs in a List; a "Following" section floats followed clubs to the top, "All Clubs" lists every club end-to-end. Each row is a sibling pair of buttons — a row button (pushes TeamDetailView via a NavigationPath) + a Follow star (FollowingStore) — NOT nested (a Button inside a NavigationLink swallows the row's nav tap)
│   ├── TeamDetailView.swift        — a club's page, pushed from Teams/Standings (no own NavigationStack): a PINNED header (crest + name + standing line "4th in NWSL — 21 pts" + Follow star) above a segmented sub-tab bar (Squad · Stats); only the selected section scrolls. Squad (default) = the "meet the team" 2-col LazyVGrid of PlayerCards grouped FWD→MID→DEF→GK, each NavigationLink→PlayerDetailView. Stats = an INTENTIONAL placeholder ("Team stats coming soon" — team leaders + formation need per-player stats / lineup data not in the endpoints we map yet; flagged here as a placeholder). Built per Reference/Design/teams-tab-design-spec.md, which removed the old Overview/Schedule sub-tabs (identity audit: schedule→Schedule tab, next-match→future Home). One roster fetch powers everything (cards + header line).
│   ├── PlayerDetailView.swift      — INTENTIONAL placeholder, pushed when a Squad card is tapped (player detail is a future build). Shows the bio we already have from the roster (monogram, name, jersey/position/age/height/nationality) + a "player stats coming soon" panel — deliberate, not blank. Accent color threaded down from TeamDetailView. Becomes the real stats screen when the player-stats endpoint is mapped.
│   ├── PlayerSpotlightView.swift   — the spotlight tap-through (Reference/Design/spotlight-design-spec.md §Tap-through), pushed from a Home Module 2 card; rides Home's NavigationStack (nav-bar back is the explicit affordance). Its own NARRATIVE experience ("meet this person"), deliberately NOT PlayerDetailView ("their stats") — linkable later. Layout: a video hero up top (designed crest tile + play badge; tap opens the source via openURL — hidden when the spotlight is written-only), then the header (jersey badge + name + "Position · Team" + a "Nationality · Age N" identity line that omits whichever is nil), the full bioBlurb, and bulleted "Career highlights" / "Did you know" sections (+ a "This season" section when seasonForm exists, nil today). Jersey badge + tile use the same TEMP app-accent / designed-tile treatment as the card.
│   ├── StandingsView.swift         — Standings tab: a clean league table per the design spec (Reference/Design/standings-tab-design-spec.md). Non-scrolling column header (# · Team · PTS · GP · W · L · D) kept aligned with the scrolling rows via shared fixed Col widths (Grid can't bridge the scroll boundary); all 16 teams end-to-end, no truncation/horizontal scroll. Followed teams render blue (text + soft blue-tint bg) via FollowingStore. Each row is a Button that appends row.club to a NavigationPath → TeamDetailView (same pattern + destination as Teams). Footer = stat legend. Deliberately NO GF/GA/GD or home-away splits (would force horizontal scroll). PTS is bold and fronted at the start of the stat columns.
│   ├── FeedView.swift              — Feed tab: "the world talking about your teams" (reporters, news), built per Reference/Design/feed-tab-design-spec.md. Own NavigationStack; title "Feed" + a top-right settings gear (→ FeedSourcesView sheet). A PINNED horizontal chip bar below the title (All · one per followed team · League — clean text chips, always-visible, like the Schedule filters), over a chronological ScrollView of FeedCards. Reads the shared FollowingStore from the environment, hands it to FeedViewModel, loads once on .task. Per-filter contextual empty states; pull-to-refresh. Distinct from Home Module 1 "From your teams" (direct team content) — Feed is the conversation AROUND your teams.
│   └── FeedSourcesView.swift       — the Feed gear's sheet (source management): a List of the curated default sources powering the Feed today (The Athletic, ESPN, + the four beat reporters with handles) + an INTENTIONAL "Coming soon" section (Add a source / Content preferences, disabled) with explanatory footer. Looks deliberate per the UI rules; becomes the live source manager when a content backend exists.
├── Components/
│   ├── ComingSoonView.swift        — reusable intentional placeholder (SF Symbol + title + "coming soon" copy) for not-yet-built tabs. Currently UNREFERENCED (all five tabs are built) — kept as a ready component for the next structural placeholder rather than deleted.
│   ├── FeedCard.swift              — one Feed item as a rounded card; a single component renders both kinds so they read as one stream. .reporterPost: blue @ avatar + reporter name + "Bluesky — 2h ago" + full body + "View on Bluesky →". .articleLink: gray newspaper avatar + publication + "Article — 4h ago" + bold headline + 1-line summary + "Read on … →" (headline+summary+link ONLY, never body). NO per-team marker on the card (the avatar marks source type only) — the top filter bar is the team selector, so an on-card team tag would be redundant. Whole card opens the source (Environment openURL).
│   ├── MatchCard.swift             — one game as a rounded card: stacked home/away rows (logo + abbreviation — kept as abbreviations to match the NWSL app's schedule convention) + score (or kickoff time) + status badge (LIVE / FT / scheduled) + an info line (📍 venue always · 📺 broadcast for upcoming/live only). Also defines CompetitionBadge + renders a placeholder-ready non-NWSL treatment (3px colored left accent + top pill) gated on an optional `badge` that is NIL today (no Competition data model yet — dormant scaffolding per the schedule spec's competition-aware intent). Used by ScheduleView (Home's "Around the league" module that also used it was removed in the content-leads redesign).
│   ├── TeamContentCard.swift       — Home → Module 1 ("From your teams") card: a thumbnail-forward, IG/YouTube-style content tile — a 16:9 thumbnail, then an attribution line (team crest + name + relative timestamp), the caption, and a "via YouTube/Instagram/…" source tag. Whole card opens the team channel (Environment openURL). TEMP: the thumbnail is a DESIGNED placeholder (team crest on a neutral gradient + play badge / duration / platform glyph), NOT a fetched image — the seed's account-level URLs expose no per-post media; swap in a real thumbnail URL when a content backend lands.
│   ├── PlayerSpotlightCard.swift   — Home → Module 2 ("Get to know your players") card, the Option B mini-profile: "PLAYER OF THE WEEK" label, jersey-number badge, player name, "Position · Team", the 2-3 sentence bioBlurb (the hook), then a video preview (designed crest tile + play badge + videoTitle + "via {source}"). Written-only spotlights (no video) hide the tile and show a "Read full profile →" cue instead. A plain label view — the WHOLE card is wrapped in a NavigationLink in HomeView that pushes PlayerSpotlightView (the video opens there, not from the card). TEMP: badge uses the app accent (Color.teamAccent(hex: nil)) + the tile is a designed placeholder, not a fetched image (Home fetches neither team color nor per-post media); pass the club hex + a real thumbnail when a backend lands.
│   ├── ComingUpRow.swift           — Home → Module 4 ("Coming up") COMPACT row, one per followed team: crest dot + matchup ("Washington vs Houston", short/abbrev names — no invented nicknames) + a time-aware detail line ("Fri, Jul 3 · 8:00 PM" / live clock + score / "FT · 2–1"), with a LIVE badge when in-play. Reuses HomeViewModel.FollowedFixture (replaced the old big NextMatchCard; no extra fetch).
│   ├── PlayerCard.swift            — one player in the Teams → Squad grid: team-color top accent (3px) + jersey/initials monogram in a team-color circle badge + shortName + position. Team color via Color.teamAccent (legible number color picked by luminance). Replaces the old list-row PlayerRow now the squad is a grid.
│   └── TeamLogo.swift              — reusable AsyncImage crest: fixed frame, loading placeholder, neutral failure fallback (no broken-image glyph); used by MatchCard + TeamsView + TeamDetailView + StandingsView
├── Extensions/
│   └── Color+Hex.swift             — Color.teamAccent(hex:) → (fill, on): turns an ESPN team-color hex into a SwiftUI Color plus a legible foreground (black/white by perceived luminance); falls back to the app accent for missing/malformed hex. Used by PlayerCard + PlayerDetailView.
└── Assets.xcassets/                — app icons, accent color
```

---

## Current State

The app root is now `RootTabView` — a conventional 5-tab bottom bar
(**Home · Schedule · Standings · Teams · Feed**), each tab in its own
`NavigationStack` so back-stacks survive tab switches. **All five tabs are now
built** — no placeholder tab remains (the reusable `ComingSoonView` is currently
unreferenced, kept for the next structural placeholder). The app **lands on
Home** (the leftmost tab), its your-teams-first hub. Tab is `Feed` (not `News`)
on purpose, to signal the social-native, "alive" direction (full rationale in the
gitignored `Reference/Sessions/` notes).

**Feed (the world talking about your teams).** Built per
`Reference/Design/feed-tab-design-spec.md` (approved Cowork session). Feed is the
Reddit-replacement layer — reporters, news outlets, fan-adjacent content filtered
to your followed teams — explicitly distinct from Home Module 1 ("From your
teams," direct team content): Feed is the *conversation around* your teams, Home
is the teams *talking to you*. `FeedView` shows the title + a top-right settings
gear, a **pinned horizontal chip bar** below it (**All** · one chip per followed
team (clean text, short name) · **League** for league-wide news), over a
chronological `ScrollView` of `FeedCard`s. A single card component
renders two content types so they read as one stream: **reporter posts** (blue @
avatar, name, "Bluesky — 2h ago", full body, "View on Bluesky →") and **news
article links** (newspaper avatar, publication, "Article — 4h ago", bold headline
+ one-line summary, "Read on The Athletic →" — headline + summary + link only,
never the article body, per the spec's legal note). Cards carry **no per-team
marker** — the top filter bar is the team selector, so an on-card team tag would
be redundant — though an item can be tagged to multiple teams (it then surfaces
under each team's filter). The gear opens `FeedSourcesView` — a sheet listing the
curated default sources (The Athletic, ESPN, The Equalizer, Just Women's Sports +
the beat reporters with handles) plus an intentional "Coming soon" section for
adding/tuning sources. `FeedViewModel` derives the chips and the per-filter
stream; it reads the shared `FollowingStore` and fetches the club directory (same
pattern as Home) to resolve followed IDs → chips, matching content to clubs by
abbreviation. **The content itself is a TEMP curated static seed**
(`FeedContentProvider`) — items drawn from real NWSL reporters/outlets and real,
recent storylines, covering **all 16 clubs** (~2 items each) plus a few
league-wide items, deliberately **even across the league rather than skewed to any
club**, so picking any team in onboarding surfaces a few listings (the
concept-demo goal). The app has no content backend yet; the seed sits behind a
swappable async `items()` so a real social/news source (or the planned caching
proxy) drops in with no change to the ViewModel or views. **Verified in-sim** (via
temporary launch-env scaffolding to land on Feed / select a filter, then removed —
the established pattern, since UI taps flake under this machine's memory
pressure): a user following only **Racing Louisville** (a single arbitrary club)
lands on a populated Feed — the **All** stream mixing that club's items with
league-wide news (ESPN power rankings, a World-Cup-break note, The Equalizer's
stats column), and the **Louisville** filter narrowing to that club's two items (a
Bluesky reporter post + a Just Women's Sports article). Screenshots in the
gitignored verification folder.

**Home (the your-teams-first hub).** Built per
`Reference/Design/home-tab-design-spec.md` (approved Cowork session). On first
open — `FollowingStore.hasOnboarded == false` — Home renders `OnboardingView` in
place (so the tab bar stays visible, signaling depth): the "Make it yours" team
picker, a single alphabetical `List` of every club (no grid, no search) with a
whole-row follow toggle, a collapsed-by-default "international competitions"
disclosure (an intentional placeholder — its rows read "Coming soon" and don't
toggle, since `FollowingStore` tracks club IDs only and competition-following
needs its own data model), and a pinned bottom bar with the running "Follow N
teams" count + "you can always change this later." Tapping it calls
`completeOnboarding()` (persisted) and flips Home to the hub. Existing followers
are treated as already onboarded, so a seeded sim skips the picker. Once
onboarded, the hub is a `ScrollView` of modules in the spec's **content-leads
order** (reordered 2026-06-06 — content first, schedule demoted): **(1) "From
your teams"** — THE HOOK, a vertical stack of `TeamContentCard`s showing the
teams' own channel content (newest-first, capped), each a designed thumbnail +
attribution (crest + team + timestamp) + caption + "via YouTube/Instagram/…" tag,
tapping opens the channel; **(2) "Get to know your players"** — built out per
`Reference/Design/spotlight-design-spec.md` into the **Option B mini-profile**:
ONE `PlayerSpotlightCard` **per followed team** (follow 2 teams → 2 cards) showing
the jersey badge + name + Position·Team, a **2-3 sentence bio blurb** (the hook),
and a **video preview** (designed crest tile + play badge + video title + "via
{source}"); written-only spotlights (no video) show a "Read full profile →" cue
instead. Tapping a card pushes **`PlayerSpotlightView`** — a dedicated narrative
page (video hero that opens the source, then nationality/age, the full bio, and
bulleted career highlights / fun facts), deliberately distinct from the
roster's `PlayerDetailView`; hidden when no followed team has a spotlight;
**(3) "Play"** — a horizontal row of intentional
"coming soon" game cards (Daily Trivia / Predict the XI / Bracket Battle) under a
competitive subtitle, the spec's reserved structural slot; **(4) "Coming up"** — a
**compact** `ComingUpRow` per followed club (crest + matchup + time-aware line),
shrunk down from the old big match cards because the detail lives in the Schedule
tab. **"Around the league" was removed** — it duplicated the Schedule tab. Modules
1 and 2 run on **TEMP curated static seeds** (`TeamContentProvider`,
`PlayerSpotlightProvider`) — real, durable team account URLs + real 2026-roster
players with hand-written bios and **real, oembed-verified player-focused YouTube
videos** (one per club, expansion sides included; one written-only where no video
exists), behind swappable async signatures, since there's no content backend yet. Home owns no season data:
`HomeViewModel.loadClubs()` fetches the club directory (followed IDs → full
`Club`s + the abbreviation join) and the two seeds in one pass, and **derives**
every module from the shared `MatchStore` + `FollowingStore` read from the
environment. The no-follows state shows the lead module's "Choose your teams"
prompt that re-presents the picker as a sheet. **Verified in-sim** (project's
established seed-UserDefaults path — here via the NSArgumentDomain launch-arg
variant, since a stale persisted follow-set in the sim container revealed that
`simctl spawn defaults write` only updates cfprefsd's cache, not what the app
loads; UI taps also flake under this machine's memory pressure, so a temporary
launch-env scroll scaffold captured the lower modules, then removed): seeding three
follows (Portland/Washington/Kansas City) + `hasOnboarded` shows Module 1 leading
with real team content filtered to those clubs (Washington IG "Audi Field is sold
out again," Kansas City YouTube "CPKC Stadium walkout" with a 2:54 duration badge),
Module 2's "Player of the week" (Trinity Rodman, #2, Forward · Washington — the
weekly rotation pick), the "Play" row, and Module 4's compact "Coming up" rows
(Washington vs Houston · Fri Jul 3 · 8:00 PM, Denver vs Kansas City · 9:30 PM,
Portland vs Louisville · Sun Jul 5 · 7:00 PM). Screenshots in the gitignored
`Reference/Design/home-redesign-verification/`.

**Spotlight build-out (Module 2 → Option B + tap-through).** Built per
`Reference/Design/spotlight-design-spec.md`: Module 2 went from one shared weekly
card to **one Option B mini-profile per followed team** (bio blurb + video
preview), and tapping pushes the new narrative `PlayerSpotlightView`.
`PlayerSpotlight` grew to carry the bio, video metadata, and an extended profile;
`PlayerSpotlightProvider` now seeds all 16 with hand-written bios + a real,
**oembed-verified** player-focused YouTube video each (Nérilia Mondésir/SEA is the
written-only fallback — hers lives only on Facebook). `HomeViewModel.spotlight(...)`
became `spotlights(following:)` (one per followed team, per-team weekly rotation).
**Verified in-sim** (established launch-arg seed + a temporary `SPOTLIGHT_VERIFY`
env scaffold to surface Module 2 and the detail pages for deterministic
screenshots, then removed — CLI can't inject taps): seeding Houston/Seattle/
Washington shows two stacked spotlight cards (Messiah Bright · Houston with the
"Mic'd Up with Messiah Bright via Houston Dash" preview, Nérilia Mondésir · Seattle
the written-only variant), the video detail page (Bright — video hero + "Watch on
Houston Dash" + "United States · Age 26" + career highlights), and the written-only
detail page (Mondésir — no video hero, identity line correctly "Haiti" only since
her age is nil). Screenshots in the gitignored
`Reference/Design/spotlight-verification/`.

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

**Team detail page (redesigned per the Teams tab spec).** Tapping a club in Teams
(or a Standings row) pushes `TeamDetailView` (no own `NavigationStack` — it rides
the pushing tab's stack, so the back affordance is free): a **pinned header**
(crest + name + a **standing line** "4th in NWSL — 21 pts" + the same Follow star,
so toggling here reflects everywhere) above a segmented **sub-tab bar — Squad ·
Stats** (only the selected section scrolls). This redesign (per
`Reference/Design/teams-tab-design-spec.md`, approved in a Cowork session)
**removed the old Overview and Schedule sub-tabs** via the spec's identity audit:
schedule belongs to the Schedule tab, and the per-club next-match/recent-result
belongs to the future Home — so Teams now answers exactly one question, "who are
these people?" **Squad** (the default) is the "meet the team" experience: a
2-column `LazyVGrid` of `PlayerCard`s grouped **FWD → MID → DEF → GK** (attackers
first — fans come to see the forwards), each card a team-color top accent + a
jersey/initials monogram in a team-color circle badge + the player's `shortName`
+ position. Tapping a card pushes `PlayerDetailView` (an intentional placeholder
showing the bio we already have + "stats coming soon", since the full player-stats
endpoint isn't mapped yet). **Stats** is likewise an intentional placeholder —
its marquee features (team leaders + a formation pitch) need per-player season
stats and lineup/formation data that **no current endpoint provides**, so it
shows a clean "Team stats coming soon" rather than a half-built table (flagged as
a placeholder in the File Map). The big efficiency win: ESPN's **roster payload
already carries the team color, standing summary, and W-D-L record**, so a single
`ESPNService.fetchRoster(clubID:)` → `ClubSquad` (in `Roster.swift`) powers the
whole page — the colored cards AND the header line (points are derived from the
record, 3·W + D, so no second fetch). `TeamDetailViewModel` holds that `ClubSquad`
and exposes `positionGroups` / `accentColorHex` / `standingLine`; it no longer
touches `MatchStore` (the per-club schedule is gone). Team color comes through a
new reusable `Color.teamAccent(hex:)` helper (`Extensions/Color+Hex.swift`) that
also picks a legible number color (black/white) by luminance. The old list-row
`PlayerRow` was removed in favor of `PlayerCard`. The Teams rows remain **sibling**
buttons (row-button pushes via a `NavigationPath`; Follow star is separate) — a
`Button` nested inside a `NavigationLink` swallows the row's nav tap.
**Verified in-sim** (via a temporary launch-env deep-link into the screen, then
removed — a full tab-navigation XCUITest flaked under the dev machine's 8GB
memory pressure: the app took ~30s+ just to launch, so the test's taps raced a
not-yet-ready UI; the deep-link screenshot path is deterministic and avoids it):
opening Kansas City Current shows the pinned header with crest + **"6th in NWSL
— 21 pts"** (standing line + record-derived points) + Follow star, the **Squad ·
Stats** segmented control, and the Squad grid grouped **Forwards-first** with red
(`cf3339`) top accents, red jersey badges carrying **legible white numbers** (the
luminance-contrast path), `shortName`s, and position labels; tapping a card's
deep-link opens **PlayerDetailView** with the red monogram, the bio grid (jersey
· position · age · height · nationality from the roster), and the "player stats
coming soon" panel. The **Stats** placeholder is build-verified (a static
"coming soon" identical in structure to the rendered PlayerDetail panel + the
proven `ComingSoonView`). Screenshots in the gitignored
`Reference/Design/teams-redesign-verification/`.

**Standings.** The Standings tab (`StandingsView` + `StandingsViewModel`,
`ESPNService.fetchStandings()` → `Standings.swift`) renders the full 16-team
league table per the approved design spec
(`Reference/Design/standings-tab-design-spec.md`): pure reference utility, "the
simplest tab in the app." Six stat columns only — **PTS · GP · W · L · D**
(PTS fronted and bold) — with **GF/GA/GD and home/away
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
status badge. Each card also carries an **info line** — 📍 venue (always, when
known) and 📺 broadcast channel (upcoming/live only — a finished game's channel
is moot) — decoded from the SAME scoreboard response (`competition.venue` /
`broadcasts`), so no extra fetch. Team names stay as **abbreviations** (WAS / KC
/ SD) to match the NWSL app's schedule convention. On first load it scrolls to
today (or the next upcoming matchday) via iOS 17's `.scrollPosition(id:)`.

Built per `Reference/Design/schedule-tab-design-spec.md`, the Schedule now has
**three always-visible segmented filter tabs** below the title: **NWSL**
(default — the full league, so you can discover other games), **My teams** (only
followed clubs' matches, with a gentle follow-prompt when you follow nobody), and
**All matches** (discovery). They're three filter functions over ONE
`MatchStore` data set — no architectural bloat. NWSL and All matches show the
same set today and **diverge once non-NWSL competition data exists** (NWSL =
NWSL + your *followed* competitions; All = *every* tracked competition). The
My-teams filter joins followed club IDs → team abbreviations via a one-time club
directory fetch in `ScheduleViewModel`. Switching filters **re-anchors the
scroll to that filter's next upcoming match**; the first-load anchor retries once
the club directory resolves, so My teams doesn't open stuck at the season opener
(a bug caught + fixed during in-sim verification). `MatchCard` is also
**competition-badge-ready** — it fully renders a 3px colored left accent + a
"CONCACAF W — Semifinal"-style pill, gated on an optional that's `nil` until a
Competition data model exists (dormant scaffolding, no non-NWSL data yet). The
MVVM spine is unchanged: `MatchStore` owns the season data, `ScheduleViewModel`
derives the filtered day-grouped presentation, `ScheduleView` renders.
**Verified in-sim** (via temporary launch-env scaffolding to pick the tab/filter
for deterministic screenshots, then removed): NWSL shows venue + broadcast on
each card (Audi Field · Victory+, BMO Stadium · Prime Video) landing on the next
matchday; My teams (Portland + KC seeded) shows only their games with completed
scores + FT and lands on the next upcoming; the no-follows prompt renders.
Screenshots in gitignored `Reference/Design/schedule-verification/`.

---

## What's Next

1. **(Perf/TEMP)** `TeamLogo` uses bare `AsyncImage`, which has no cross-cell
   image cache — crests re-download every time a card recycles during scroll.
   Acceptable for v1 (small PNGs, lazy rows) and marked with a `TEMP` comment in
   `Components/TeamLogo.swift`. Replace with a shared cache (NSCache-backed
   loader, or route logos through the future Vercel proxy with caching headers)
   and remove the TEMP note.
16. **(Robustness)** `ScheduleViewModel.loadClubs()` swallows a failed club fetch
    via `(try? await service.fetchTeams()) ?? []`, leaving `clubs` empty. If that
    fetch genuinely fails (network/decode), the **My teams** filter shows the
    "Loading your teams…" spinner with no error surface or retry — a rarer, latent
    version of the gating bug just fixed (where the fetch never ran at all). Give
    the club fetch its own error state + a retry affordance (or fold it into the
    shared `ClubStore` from #15) so a failure reads as an error, not an infinite
    spinner.
2. **(DONE)** ~~Teams tab + Following lens.~~ Teams directory of all 16 clubs
   with a Follow star, backed by `FollowingStore` (UserDefaults). Following is a
   cross-cutting *lens*, not its own tab — it will personalize Home
   (your-teams-first) and Feed next. **Next builds on this:**
   - **(DONE)** ~~Team detail page — make Teams rows tappable → push a club page
     (roster, schedule filtered to that club, Follow).~~ Shipped, then **redesigned
     per `Reference/Design/teams-tab-design-spec.md`**: `TeamDetailView` is now a
     pinned header (crest + standing line + Follow) over **Squad · Stats** sub-tabs;
     Squad is a team-colored `PlayerCard` grid (`Roster.swift` `ClubSquad` from one
     roster fetch), cards push `PlayerDetailView`. Also satisfies What's-Next #8.
     **New follow-ups from the redesign:**
     - **Stats sub-tab** is a placeholder — build **team leaders** (top-3 Goals/
       Assists/Clean Sheets) and the **most-recent formation** pitch once the data
       is mapped. Per-player stats DO exist on `athletes[].statistics.splits` in the
       roster payload (sparse — null for some players); the **formation** needs a
       lineup/event-summary endpoint we haven't mapped. Fold into the endpoint pass.
     - **PlayerDetailView** is a placeholder (bio + "stats coming soon") — flesh out
       with real per-player stats (same `statistics.splits` source).
     - The spec's deferred **Follow-confirmation sheet** (first-time "what following
       buys you") still applies to the header star.
   - **(DONE)** ~~Your-teams-first Home — build the Home tab as a hub that leads
     with followed clubs' next match / recent result.~~ Shipped, then **reordered
     per the 2026-06-06 `home-tab-design-spec.md` update (content leads, schedule
     demoted)**: `HomeView` + `HomeViewModel` + `OnboardingView`, landing tab Home.
     First-open "Make it yours" onboarding picker + the hub in the new order —
     **(1) "From your teams"** (real seeded team-channel content, the hook;
     `TeamContentItem`/`TeamContentProvider`/`TeamContentCard`), **(2) "Get to know
     your players"** (real seeded weekly spotlight; `PlayerSpotlight`/
     `PlayerSpotlightProvider`/`PlayerSpotlightCard`), **(3) "Play"** (intentional
     "coming soon" slot), **(4) "Coming up"** (compact `ComingUpRow` strip from
     `MatchStore`). "Around the league" was removed; the big `NextMatchCard` was
     deleted. **New follow-ups from the redesign:**
     - **Module 1 "See all" + real backend** — the spec's per-section "See all"
       link is omitted (no full-content destination view yet); build it, and
       replace the TEMP `TeamContentProvider` seed with a real team-channel source
       (YouTube/IG/Bluesky aggregator or the planned proxy, #11) that also brings
       real per-post thumbnails + deep links (the seed renders a designed crest
       tile and uses durable account-level URLs).
     - **Module 2 spotlight (Option B + tap-through DONE; pipeline pending)** —
       built per `Reference/Design/spotlight-design-spec.md`: one Option B card per
       followed team (bio + video preview) → `PlayerSpotlightView` narrative page;
       `PlayerSpotlightProvider` seeds all 16 with bios + real oembed-verified
       videos. **Still TEMP/pending:** the seed is still a static seed with one
       player per team and a simple per-team week-of-year rotation — a real content
       pipeline (the spec's AI-tagging/proxy layer) is needed to (a) source
       player-focused content per followed team's channels, (b) carry real
       thumbnails + durations (the card/detail render designed crest tiles, no
       duration badge), (c) grow each team's pool so the weekly rotation cycles a
       full roster, and (d) drive the opt-in weekly notification (spec §Notification,
       reuses the Tier-1 local-notification path). A team-colored jersey badge still
       needs the club hex (Home fetches no rosters). The spec's optional one-time
       intro card is also not built. Spotlight does NOT link to `PlayerDetailView`
       by design (can be linked once PlayerDetail has real content).
     - **Module 3 "Play"** is a placeholder structural slot — build the games
       (Daily Trivia, Predict the XI, Bracket Battle); the prediction games reuse
       the same back end as push (#12/#14).
     - **Module 4 venue/broadcast** — the compact strip deliberately omits venue/TV
       (that detail lives in the Schedule tab); no change needed unless the spec
       evolves.
     - **International competitions** in onboarding are a placeholder (rows don't
       toggle) — needs a Competition data model + a separate follow set in
       `FollowingStore`; ties into the competition-aware schedule (#13).
     - The spec's **Follow-confirmation sheet** + "all onboarding choices
       adjustable in Settings" still apply (no Settings screen exists yet).
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
5. **(DONE)** ~~Enrich the schedule cards with broadcast (TV) + venue info.~~
   Shipped: `Event.venueName` / `broadcastName` decode from the existing
   scoreboard response (`competition.venue.fullName`, `broadcasts[].names`), and
   `MatchCard` renders a 📍 venue · 📺 broadcast info line (venue always, channel
   for upcoming/live only). Leftovers: the `venue.address.city` is decoded-able
   but unused (verbose, e.g. "Washington, District of Columbia"); `NextMatchCard`
   on Home could reuse the same info line (small follow-up).
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
   team).~~ See item #2. Roster + Follow shipped, then redesigned (Squad · Stats).
   The **club record/standings header line is now DONE** ("4th in NWSL — 21 pts"),
   built from the roster payload's `standingSummary` + record (no standings fetch
   needed after all). The per-club **schedule** sub-tab was intentionally REMOVED
   in the redesign (identity audit: schedule lives in the Schedule tab).
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
    Overview leads with next match + recent result (the primary use case + the
    first small "alive" seed); Schedule splits Upcoming/Results. Verified in-sim
    (temporary XCUITest, then removed). Deferred follow-ups from this redesign:
    a Follow-confirmation sheet (rename star → "Follow" + first-time "here's what
    following buys you"), a standings/record line in the header (needs the
    standings endpoint), and a future per-team News/Spotlights sub-tab (the
    "alive" work — long-term vision being moved to Claude Cowork).

**Longer-term (vision — see `Reference/Sessions/` for the full discussion):**

11. **(UI DONE — backend pending)** ~~Feed, reimagined~~ — the Feed tab is
    **built** per `Reference/Design/feed-tab-design-spec.md`: `FeedView` +
    `FeedViewModel` + `FeedCard` + `FeedSourcesView` + `FeedItem` (chips per
    followed team, mixed reporter-post / article-link stream, source-management
    gear). It runs today on a **TEMP curated static seed** (`FeedContentProvider`,
    real reporters/outlets + real recent storylines, covering all 16 clubs evenly)
    because there's no content backend.
    **Still needed to make it live:**
    - **Real content source** — replace `FeedContentProvider.items()` with a
      Bluesky/news aggregator (or route through the planned caching proxy);
      the async signature + Codable-shaped `FeedItem` are already set up for it.
    - **Editorial filtering as a real gate** — the spec's "no culture-war /
      political / identity hot takes" policy is currently honored by hand-curating
      the seed; it becomes a real filter (here or server-side) when content is
      live. (The spec references a `nwslapp-feed-content-rules.md` policy memo.)
    - **Source management** — the gear's "Add a source" / "Content preferences" /
      mute are intentional placeholders; wire them once sources are user-editable.
    - **Content tagging (live content)** — the per-team filter chips depend on each
      post being tagged to the right NWSL team(s). With a live source this can't be
      done by source/handle alone — a reporter may cover multiple leagues or write
      about a team off their usual beat. Plan: once the caching proxy exists, run
      each incoming post through a lightweight AI call (Claude Haiku) that reads the
      content and returns the relevant NWSL team tag(s), dropping non-NWSL content.
      That per-post tagging is what makes the filters (and the league-vs-team split)
      reliable.
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
    added later without a painful refactor. **Groundwork in place:** the Schedule
    tab's three filters (NWSL / My teams / All matches) and `MatchCard`'s dormant
    `CompetitionBadge` rendering (left accent + pill) are built and waiting on the
    data. **Still needed:** a `Competition` model on `Event` (so NWSL vs All
    diverge and badges populate), a separate followed-competitions set in
    `FollowingStore`, and the onboarding international-competitions rows wired to
    it. This is the shared blocker behind the schedule filters, the Home/onboarding
    competition placeholders, and badged non-NWSL matches.
15. **(Cleanup)** The club directory (`ESPNService.fetchTeams()`) is now fetched
    independently by `TeamsViewModel`, `HomeViewModel`, and `ScheduleViewModel`.
    Consider a shared `@Observable ClubStore` (like `MatchStore`) injected via
    `.environment` — one fetch, many readers — to also give a clean ID→Club /
    ID→abbreviation lookup that the My-teams filter and Home both need.
14. **Engagement / Home hub** — player spotlights (eventually a contributor
    pipeline), community links (subreddits/Discords), prediction games. These
    live as Home *modules* first and graduate to their own tab only if earned.
    (Prediction games are the Mastermind pattern — they reuse the same back end
    as push; see the server/push session notes.)
