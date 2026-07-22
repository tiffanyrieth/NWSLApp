---
paths:
  - "**/FanZone*.swift"
  - "**/Predict*.swift"
  - "**/XI*.swift"
  - "**/*Prediction*.swift"
  - "**/Trivia*.swift"
  - "**/KnowHer*.swift"
  - "**/Bracket*.swift"
  - "**/Superfan*.swift"
  - "**/CommunityResults*.swift"
  - "**/HomeView*.swift"
---

# Fan Zone & game visibility rules

The Fan Zone leads Home (**top module**, above Club News) — the four games (Predict the XI, Bracket
Battle, Know Her Game, NWSL Trivia) plus a cross-game Superfan summary. (Bracket Battle's own engine/ops
live in `.claude/rules/bracket-battle.md`.)

## ⚠️ Building or CHANGING a game — the LOGIC GATE (run BEFORE "done")

Fan Zone games are **bespoke stateful logic** (scoring rules, submission lifecycle, leaderboards, per-user
state synced across reinstall/offline). Security + crash-safety are checklist-able and stay good on their
own; **game logic is not** — every new game, and every change to scoring / points / state / a leaderboard,
is a fresh chance to reintroduce a whole-feature bug that a happy-path build won't reveal. So whenever you
BUILD a game OR change its scoring/points/state/leaderboard, trace these six and confirm EACH before
calling it done. This is the game-logic twin of the load stress-test gate (`docs/stress-testing.md §5`);
run it at BUILD time, not a review months later. Every item maps to a real bug this codebase shipped:

1. **Scoring idempotency** — can scoring run TWICE (retry / re-entry / double-tap) and double-count or go
   negative? Additive server writes must be guarded (a marker/flag) so a re-run is a no-op. *(the bracket
   tally re-scored every 5 min on a mid-write failure; Predict clobbered the season total downward.)*
2. **Double-action guard** — a fast double-tap must not enqueue two submits/writes (a SYNCHRONOUS in-flight
   flag flipped before the first await, not one set inside the async Task).
3. **Deadline / lifecycle** — can a user act after the window closes? submit after the deadline, answer
   after the reveal, play twice per cycle? Gate the ACTION (server-adjacent), not just the entry UI.
4. **List / leaderboard scale** — EVERY leaderboard/list query is `.limit`-ed and rendered LAZILY
   (`LazyVStack`, never `ScrollView{VStack}`). Never fetch or eagerly render an unbounded set. Cap it (top-N
   + the user's own row) at DESIGN time — an uncapped board is a launch-blocking hang at 1k, per the BANNED
   LENS (CLAUDE.md: size as if publishing TOMORROW), not a "someday" problem. **When the owner asks for a
   leaderboard, PROPOSE the cap** (e.g. top-100 + your row) as part of the design, don't wait to be asked.
5. **Reinstall / offline** — does per-user state (scores, streaks, picks) survive a reinstall, or clobber
   the server downward / drop to a wrong state? Monotonic totals use `max`/`GREATEST`, never plain overwrite;
   local-only state the user would "own" is either server-backed or a documented, accepted trade-off.
6. **Partial-failure atomicity** — if a multi-step write dies BETWEEN steps, does the retry double-apply or
   wedge? Make the retriable step idempotent (upsert-on-conflict) and gate the non-idempotent (scoring) step.

Plus the standing hard rule: **ZERO fabricated data** — honest empty/loading, never fake rivals or padded
counts. NOTE: this gate catches the "should never have shipped" 80%; the subtlest failure-TIMING bugs
(a write dying between two specific steps) sometimes still need an adversarial logic review as the backstop
— the gate is the build-time net, a periodic review is the safety net, not one or the other.

## Home layout (`HomeView.swift` + `Components/FanZoneCard.swift`)

A **single horizontal row** of uniform, compact game cards (`FanZoneCarouselCard`) under a **bold white
"Fan Zone" header** (`dsFont(20, weight: .heavy)`, a peer of the "Club News" title — App Store shelf
model; ADDENDUM v2 replaced the old muted `trackedCaps()` eyebrow), in a snapping
`ScrollView(.horizontal)` — two cards + a peek show at rest (`design_handoff_fanzone_home`; replaced
the old full-width stacked `FanZoneGameCard`s).
**FIXED order, never sorted by deadline:** `Predict → Bracket → Know Her → Trivia` (`visibleGames`) —
Predict + Bracket are the app's stars and must lead; NWSL Trivia sits last (owner order). Each card is driven by a flat
`FanZoneCardModel` built in HomeView: accent-tinted icon + game name + one context line + one accent
`compactStatus` line (Predict shows the deadline countdown e.g. "2d left"; Bracket "Vote now"; Trivia
"Play now"; submitted/played collapses to "Picks locked in" / "Done today"). The old progress bar +
season-points badge were **dropped** — those richer affordances live on each game's own screen.
**Predict card is deadline-forward when following 2+ predictable teams:** with one open fixture it
names the specific matchup ("WAS vs HOU · … · 2d left"); with 2+ (`openPredictFixtures.count >= 2`)
the context goes generic ("N predictions open") and the countdown is the SOONEST deadline across all
open (unsubmitted) predictions — never naming one team. Tapping through lists every followed team's
next fixture (one per team) in `PredictXIView` — unchanged.
The **Superfan summary is the TRAILING card** at the end of the row (`SuperfanCard`,
`GameCenterScores.superfanTotal`; the card body is display-only — the Game Center submit still happens in
`GameCenterManager.syncAll`) — but as of Fan Zone v2 it is **TAPPABLE → `SuperfanDetailView`**, a cross-game
season stats hub (season total, competitive tier + percentile, per-game breakdown, "Your best moments"),
backed by the `superfan_scores` Supabase table + `SuperfanService`/`SuperfanStats` (`SuperfanTier`/
`SuperfanStanding`; season-scoped, passes the 1k stress gate). Gated to **≥2 games played AND total > 0**
(`superfanBannerVisible`; it counts games *played*, so it stays even when a game is hidden). Countdowns via the pure
`compactCountdown(to:from:)`. Each game keeps its accent: predict `dsGamePredict` (pink), bracket
`dsGameBracket` (teal), know-her `dsGameSpotlight` (amber), trivia `dsGameTrivia` (indigo). Below the
row, **Club News** is a PINNED
section header (title + chip bar) — presentation only; its data/scoping/balancing/chip-requery logic
is untouched (DO-NOT-TOUCH). The whole Fan Zone block still hides when no game is active (offseason).

**Spacing (ADDENDUM v2):** the `hub` uses `LazyVStack(spacing: 0, pinnedViews:)` with every gap set by
explicit per-module padding — NOT stack spacing (which a pinned `Section` header→content gap inherits,
the old ~28pt chips→card void). Targets: Home→Fan Zone ≈8, Fan Zone header→row 8, carousel→Club News 20
(the section break, as `playSection` bottom padding so it scrolls away leaving the pinned header flush),
title→chips 11, **chips→first card 12** (the `clubNewsHeader` bottom padding), card→card 10; below-Club-News
breaks (Spotlight/Upcoming) are 24pt bottom pads on the preceding always-rendered content.
**Club News card density (Home only, `unified == false`):** `ArticleContentCard`/`ThumbnailContentCard`
render **152pt media** (top-center aspect-fill crop), a 15pt/2-line article headline, and tighter
10/12 footer padding for ~2.5 cards/screen. **Social (`FeedView`, `unified == true`) is unchanged** —
still 16:9 / 200/180pt media + 16pt/3-line headlines; every density tweak is gated on `!unified`.
**News-first "2-of-3" opener (QQL rule):** on FIRST load only, the first 3 Club News cards are exactly
**2 club-news articles + 1 non-article** (video/social), then a free recency mix. `ContentRoundRobin`
floats ≤2 lead-eligible articles (`ArticlePriority.quota = 2`, relative-staleness guard, round-robined
across clubs) and reserves slot 3 for the freshest non-article so the opener never becomes an all-news
wall. `HomeViewModel` passes it only when `!hasRefreshed`; **pull-to-refresh drops it → all cards fair
game** (free mix). Unit-tested (`ContentRoundRobinTests`).

## Visibility gates (do NOT break these)

| Game | Visible when | Hidden when |
|---|---|---|
| Predict the XI | a followed team has a fixture within `PredictionFixture.activeWindow` (28 days) | no upcoming fixture for any followed team |
| Bracket Battle | `BracketStore.hasActiveEdition` | no active edition |
| Daily Trivia | always | never |
| Fan Zone section | ≥1 game visible | all games hidden (offseason) |

A game with nothing active/upcoming is hidden **everywhere** (card + screen) — no dead links.

## Predict the XI

`PredictionFixture` (`opponentAbbreviation`, `kickoff`, `deadline` = kickoff − 2h; `activeWindow`
28d) · `XIPrediction` (`slots` [Int:String], 11 to be `isComplete`; `draft → submitted`, one-way
lock) · `PredictionStore` (`predict.v2.*`, `seasonPoints`, `points(forTeam:)`) · `PredictionScoring`
(Mastermind partial, max 88; unit-tested) · per-team leaderboards (`PredictLeaderboardService` — a
read failure shows only your real local score). The open-fixtures slate + scoring (via `/summary`)
live in `PredictXIViewModel`; the in-flight picker is `XIPickerViewModel` / `XIPickerView`. **Auto-pick**
(`XIPickerViewModel.autoPick()`, button in the picker's FORMATION header) = beginner quick-fill: random
formation + a distinct random player per slot (position-blind, score untouched); re-tap to re-roll.

## Know Her Game

**BIWEEKLY** per-team player quiz (community family — the KHG-as-template for the Trivia rebuild). It
**alternates the Fan Zone quiz slot with NWSL Trivia** (Week 1 = KHG); editions are numbered "Round N"
(proxy-stamped), Know Her Game as a season of rounds. `KnowHerPool`/`KnowHerPlayer`/`KnowHerQuestion`
(mirrors proxy `src/knowher.ts`) · `KnowHerGameStore` (`knowher.v1.*`, per-edition scores keyed
`{weekKey}-{team}-{athleteId}`, edition streak, PERSISTED `previousPool` = "Last round" grace window kept
only if the immediately-prior KHG edition (biweekly = 1–2 ISO weeks back)) · `KnowHerGameViewModel`
(transient session) · results via the shared `CommunityResultsView` (amber `dsGameSpotlight`). Flow:
`KnowHerLandingView` — a small landing hub (not just a team selector) with three persistent sections
(This round · Last round · How players are chosen), plus an honest "all caught up" state when every
followed team is exhausted this round → `KnowHerGameView` (intro→question→result, `Entry .play/.review`).
Content is fully-automated (see `docs/know-her-game.md`). One featured player per followed team per round;
hidden when no followed team has a featured player.

## NWSL Trivia

**UI FACELIFT DONE, question-engine redesign STILL PARKED.** The interface was rebuilt onto the **community
family** (Fan Zone v2 — Know Her Game is the template): `DailyTriviaView` now has an intro screen, progress
DOTS, tap-to-answer with auto-advance (no Submit button), the shared `ScoreRing`, a score-based title, a
"+N points" Superfan pill, and the shared `CommunityResultsView` panel (indigo `dsGameTrivia`) as the
post-game payoff. **CADENCE IS UNCHANGED** — the separate **Daily → WEEKLY question-sourcing redesign**
(`docs/nwsl-trivia-weekly-redesign.md`) is still to build; until it lands Trivia stays DAILY: 5 questions/day,
one scored play per local day (Wordle-style gate), copy still daily ("Today's quiz", "day streak").
`TriviaStore` (streak/bestStreak/totalCorrect/accuracy); `TriviaService` throws on failure OR empty pool
(online-only, no seed). The old league-wide best-streak board (`TriviaLeaderboardService`) is retired from the UI.

## Sign-in & honesty

Games are **browsable signed-out**, but **sign-in + a chosen display name are MANDATORY to PLAY** —
gated at the first ranked ACTION, no skip. The gate is `FanZoneGate` (`Components/FanZoneGate.swift`):
`.fanZoneGate(isRequested:gameName:accent:onAuthorized:)` → a no-skip "Sign in to play" step (only escape is
"Go back", which cancels the action) → a REQUIRED display-name step (`DisplayNameEntry`, prefilled with
Apple's name) → then `onAuthorized` runs. Already signed-in + named → runs immediately, no sheet.
Action points: **Bracket** "Make your picks" (intro→voting), **Predict** the open-fixture tap (→picker),
**Trivia** the first "Submit Answer". Because entry is gated, downstream submits are always signed in.
(Replaced the old skippable model — `FanZoneIntroView` + an at-submit `SignInPromptView` "Not now" — under
which users could play + submit signed-out and their results went nowhere; both files deleted.) The
display name is the leaderboard identity (Supabase `profiles`/`*_scores.display_name`, NOT GameCenter's
auto alias); editable in Profile via the same `DisplayNameEntry`. ZERO fabricated data: honest
empty/loading states, never fake rivals or padded counts; a read failure shows only the user's real local
value. Game Center (`GameCenterManager`) is additive on top of the Supabase boards.

## Design consistency — two families + shared components (established 2026-07-17, `docs/old/design-audit.md`)

The whole Fan Zone was moved onto the DesignSystem tokens + a shared component library (pre-launch design
audit). **Build every FUTURE game — a Superfan zone, the NWSL Trivia rebuild, anything new — WITH this,
not around it. Reuse what's shared; never reintroduce raw UIKit colors/fonts.** (This is exactly the "so
we don't have to run that report again" contract.)

**Two visual families — the surface signals the mode before the copy does:**
- **COMPETITIVE** (Predict the XI + Bracket Battle) = the ARENA look: `Color.dsBgPrimary` (black) page +
  `Color.dsMdCard` (navy) cards. Reads "ranked / leaderboard."
- **COMMUNITY** (NWSL Trivia + Know Her Game) = the CANONICAL app-card look: `Color.dsBgGrouped` page +
  `Color.dsBgCard` cards. Reads "play + compare / community stats."
- Each game keeps its OWN accent regardless of family — Predict `dsGamePredict` (pink), Bracket
  `dsGameBracket` (teal), Trivia `dsGameTrivia` (indigo), Know Her `dsGameSpotlight` (amber). A NEW game
  picks a family + a `dsGame*` token; **add a token, never hardcode a hex.**

**Reuse these — do NOT re-roll (all already wired across the Fan Zone):**
- Buttons → `DSButton`. Error/empty states → `RetryStateView` (retry renders through DSButton). Team
  colors → `Color.teamColor(for:liftOnDark:fallback:)`. Player avatars → `PlayerHeadshot` (ring + monogram
  are the caller's overlay). Voice pills → `CategoryPill`. The "how everyone did" panel →
  `CommunityResultsView` (shared by both community games; takes the caller's accent). Team-color card
  washes → `TeamWashBackground` (`Components/TeamColorWash.swift`, Fan Zone v2) — a subtle one- or two-team
  color wash over a base surface; already on the Predict fixture/result cards + the per-team "Predictors"
  leaderboard card, and `MatchCard` migrated onto it.
- Surfaces + text via DS tokens ONLY: no `Color(.systemGroupedBackground)` / `.systemGray*` / `.separator`;
  no raw `.white` (→ `Color.dsFgPrimary`); no raw `.font(.system/.headline…)` for READABLE text (→
  `.dsFont`). **EXEMPT — keep `.font(.system)`:** monograms/badge letters inside fixed-size dots + fixed-
  width numeric columns (rank/points/count) — a container that doesn't scale must not scale its text.
- Correct/wrong = `dsSuccess`/`dsError`, never raw `.green`/`.red`.

**The sign-in gate is game-tinted + generic:** `.fanZoneGate(…accent:…)` takes the tapped game's accent and
its copy covers BOTH leaderboards AND community stats. Don't revert it to hardcoded teal or a competitive-
only "ranked game" line — a new game just passes its own accent.
