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

> **This file = the BUILD RULES** (what you must/mustn't do). **`docs/fan-zone.md` = the SYSTEM DOC**
> (how it all works: the two families, the cadence engine + its stagger, state ownership local-vs-server,
> progress restore, retention, scoring). Read that when you need the machinery rather than the
> constraints. Bracket ops: `.claude/rules/bracket-battle.md`. **Know Her Game content pipeline** (the
> biweekly Claude cloud routine, the ⚠️ model trap in `job_config.ccr…model`, the `--allow-ledger-bypass`
> guard, `SEASON_ANCHOR` cadence): **`docs/know-her-game.md` §5 — read it before touching KHG generation/
> ingest**, and never edit the owner-owned prompt wording without an explicit decision.

The Fan Zone leads Home (**top module**, above Club News) — the four games (Predict the XI, The Bracket,
Know Her Game, NWSL Trivia) plus a cross-game Superfan summary. (The Bracket's own engine/ops
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
7. **Published rules are CONTRACTS — never "optimize" around one.** If a rules/how-it-works screen states a
   guarantee, the state that enforces it is the FEATURE, not bookkeeping you may adjust for a better
   outcome. Before changing any eligibility ledger / streak / cadence / scoring state, go READ the in-app
   rules text (e.g. `KnowHerLandingView.swift` `howPlayersAreChosen`) and confirm the change doesn't
   contradict it. **"The old content is deleted, so no user would notice" is NOT a defence** — a user who
   PLAYED an edition experienced it; deleting the artifact doesn't undo the experience. *(2026-07-27: I
   proposed reclaiming 32 already-featured players from finished KHG editions because their content had
   been regenerated with a better model. That would have broken the printed rule "Each player is only
   featured once per season — no repeats." The owner caught it. Her reasoning is the standard: she'd
   already know the answers so she'd learn nothing; the marquee names would crowd out the lesser-known
   players the back half of the season exists to surface; and a player only HAS so many interesting facts,
   so a second quiz would largely repeat the first. The ONLY legitimate reclaim is a SAME-edition content
   correction — republishing the same weekKey hours later, where each player is still featured exactly
   once.)* Corollary: when a rules screen and the code disagree, that's a BUG in one of them — reconcile it,
   don't quietly follow the code (the KHG operator page described the pre-2026-07-21 `minutes > 0` gate long
   after the real floor became `KHG_MIN_MINUTES = 100`, and that stale line misled a session).

Plus the standing hard rule: **ZERO fabricated data** — honest empty/loading, never fake rivals or padded
counts. ⚠️ Scope: this bans the APP inventing rivals. It does NOT ban the pre-launch BACKEND test
population (proxy `scripts/seed_test_fans.mjs` → real `auth.users` under `@seed.nwslapp.test`, purged
before launch, guarded by `health_check_seed_accounts.mjs`) — see `docs/fan-zone.md` §8. Related ruling
(2026-07-22): **no Fan Zone surface hides itself at low scale** — Superfan's tier/ladder and the quiz
percentages render from the first player, paired with raw counts so small-N can't overstate. Don't
"restore" a minimum-participants gate. NOTE: this gate catches the "should never have shipped" 80%; the subtlest failure-TIMING bugs
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
`SuperfanStanding`; season-scoped, passes the 1k stress gate). **ALWAYS VISIBLE (owner, 2026-08-03)** — the old `superfanBannerVisible` gate (≥2 games played AND
total > 0) is GONE. The card is how a NEW user learns the Fan Zone keeps score at all; hiding it until
they had already played meant it could only ever confirm what they knew. At zero it reads an honest
"Fan · 0". ⚠️ Do not re-gate it on having played. Countdowns via the pure
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
**⚠️ Carousel card metrics (2026-08-06, #245 — vertical space is scarce here, don't let it creep):** the
card is **`kFanZoneCardMinHeight` = 135pt** (the pre-7/27 compact size), a **MINIMUM not a hard cap** — it
holds 135 at default text size but GROWS with Dynamic Type, so **AX1 expands** (verified: no overlap, CTAs
still aligned, carousel truncation of a long title is fine — full value is one tap away). The context uses
**`.lineLimit(2, reservesSpace: true)`** so it always reserves TWO lines top-aligned: a 1-line context is
"line 1 = text, line 2 = blank", every card is the same height, and the **CTAs bottom-align** across all
cards. ⚠️ Don't hard-CAP the height (breaks AX1); don't remove `reservesSpace` (ragged CTAs return); don't
add a growing element like the reverted Superfan teaser. ⚠️ **A played/done card is NOT dimmed** — the old
`.opacity(0.7)` was unreadable on the dark page; the "Done this week/today" status line is the completed cue.
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
| Predict the XI | a followed team has a fixture within `PredictionFixture.activeWindow` (28 days) | no FUTURE fixture at all (true offseason). A mid-season BREAK week shows the PAUSED state ("No NWSL matches this week — predictions open <date>") with boards browsable, never a hidden card |
| The Bracket | `BracketStore.hasActiveEdition` | no active edition |
| NWSL Trivia | always | never |
| Fan Zone section | ≥1 game visible | all games hidden (offseason) |

A game with nothing active/upcoming is hidden **everywhere** (card + screen) — no dead links.

## Predict the XI

`PredictionFixture` (`opponentAbbreviation`, `kickoff`, `deadline` = kickoff − 2h; `activeWindow`
28d) · `XIPrediction` (`slots` [Int:String], 11 to be `isComplete`; `draft → submitted`, one-way
lock) · `PredictionStore` (`predict.v2.*`, `seasonPoints`, `points(forTeam:)`) · `PredictionScoring`
(Mastermind partial, max 88; unit-tested) · per-team leaderboards (`PredictLeaderboardService` — a
read failure shows only your real local score) with **TWO CLOCKS** (owner comp-arena ruling): a
season board AND a per-soccer-week ROUND board (`predict_round_scores`; a 2-game week is ONE round;
round tab labeled with a DATE RANGE, never "Week N" — no official NWSL matchweek numbering exists). The open-fixtures slate + scoring (via `/summary`)
live in `PredictXIViewModel`; the in-flight picker is `XIPickerViewModel` / `XIPickerView`. **Auto-pick**
(`XIPickerViewModel.autoPick()`, button in the picker's FORMATION header) = beginner quick-fill: random
formation + a distinct random player per slot, drawn from that slot's own POSITION BAND (score untouched);
re-tap to re-roll a different player within each band. ⚠️ It was deliberately POSITION-BLIND until
2026-07-28 — the owner reversed that after using it: blind picks made auto-pick something you had to
undo rather than build on. Don't restore the old behaviour from a stale comment. A band that runs
short (a random 5-3-2 against four defenders) backfills from outfielders before any spare keeper, so
the XI is always complete and a keeper never lands up front.

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

**THE SELECTION RULES (printed in-app, `KnowHerLandingView.swift`) — treat as a contract, see gate #7:**
(1) players who have STARTED matches are featured first; (2) then players with **100+ minutes** this
season (`KHG_MIN_MINUTES = 100`, proxy `rankEligible`); (3) **each player is featured once per season — no
repeats**, enforced by the KV ledger `knowher:featured:{season}` (season-scoped, so it self-resets). Rank =
starts desc → minutes desc → athleteId (NOT name — A–Z would permanently bury clubs/players).
**⭐ THE WHY — KHG is a season-long CURRICULUM, and the three rules are its syllabus** (owner, 2026-07-27;
this intent is NOT reconstructable from the code — read it before "improving" any part of the selection):
a season is a fresh start for a fan who just picked a club (local, overseas-and-will-never-attend, or
converted by a game last year) and **doesn't know the players yet**; existing fans still have room to go
deeper. So EARLY season you learn who to look out for *right now* — and the rules never encode "famous",
they encode **who is currently on the pitch** (starters first), which is honest and verifiable; a star
surfacing in Round 1 is a side effect of her playing, not a popularity bias. MID season the depth players
become eligible as they earn starts / cross 100', so the curriculum deepens on its own. **The goal: by
season's end the fan has a firm grasp of every player on the club worth knowing.**
Three consequences: (1) **no-repeats is the ENGINE, not a constraint** — without it the game re-teaches
the stars forever and never reaches the squad players, so the arc collapses; (2) the 100' floor exists to
filter roster filler (4th GKs, one-off cameos) — players not "important enough to learn"; (3) ⚠️ **"no
eligible player this round" is TEMPORARY, never terminal — a club can go quiet for several rounds and then
re-open.** Eligibility is recomputed from LIVE stats every cycle (`rankEligible`, "DYNAMIC RE-ENTRY"), so
a player returning from an ACL who is eased back as a 10-minute sub becomes eligible the moment she crosses
100' or starts; a season-ending injury elsewhere turns a bench/close-out sub into a starter. Owner
(2026-07-27): that ebb and flow **IS part of the game flow.** So a quiet round is NOT "curriculum
complete", NOT an error, and NEVER a reason to recycle players — copy it as "nobody new this round" (come
back), never "you've learned them all" / "done for the season".
The eligible pool GROWS all season (first-time starters, subs crossing 100', tournament call-ups like
WAFCON forcing unusual XIs, late signings, post-injury returns), so a static "we'll run out" count is
misleading — never argue from one. **General trap: this is a DYNAMIC set; a point-in-time snapshot of it
supports no conclusion about the future.** (I made that error twice on 2026-07-27 — first "thin teams are
short by 1 for the season", then "an exhausted club has finished". Both read a moving number as fixed.)
Season: **2026-03-13 → November**; app-side rounds began ~June, 4 rounds done as of 2026-07-27.

## NWSL Trivia

✅ **REBUILT 2026-07-23 — BIWEEKLY ROUNDS** (community family; Know Her Game is the template, and the two now
share the whole grammar: landing page → round session → live community results). 10 questions per round; a
round runs TWO weeks; drops alternate with KHG on `FanZoneCadence` (KHG even week-offsets, Trivia odd —
staggered, so BOTH stay playable and one community game refreshes every week). One scored play per round
(`TriviaStore` round-gate); the streak counts consecutive ROUNDS. Retention = current + previous round only
(store prunes on write; `quiz_answers` prunes via pg_cron). Flow: `TriviaLandingView` (This round / Last
round / How it works) → `TriviaRoundView` (`Entry .play/.review(round:)`); results via the shared
`CommunityResultsView` (indigo `dsGameTrivia`), live from the first responder. The question POOL still rides
the original stocked set with a deterministic per-round slice (wraps after ~4 rounds) until the annual
content-generation pipeline lands (roadmap) — structure first, content pipeline second (owner rule).
The old league-wide best-streak board (`TriviaLeaderboardService`) is DELETED.

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
- **COMPETITIVE** (Predict the XI + The Bracket) = the ARENA look: `Color.dsBgPrimary` (black) page +
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
