---
paths:
  - "**/FanZone*.swift"
  - "**/Predict*.swift"
  - "**/XI*.swift"
  - "**/*Prediction*.swift"
  - "**/Trivia*.swift"
  - "**/HomeView*.swift"
---

# Fan Zone & game visibility rules

The Fan Zone is Home's **Module 3** — the three games (Predict the XI, Bracket Battle, Daily Trivia)
plus a cross-game Superfan summary. (Bracket Battle's own engine/ops live in
`.claude/rules/bracket-battle.md`.)

## Home M3 layout (`HomeView.swift` + `Components/FanZoneCard.swift`)

Equal-weight, full-width **stacked** game cards (no featured/tile split) — `FanZoneGameCard` driven
by a flat `FanZoneCardModel` built in HomeView: accent-tinted icon + context line + badge + status +
`CountdownPill` + optional `MiniProgressBar` + green-check submitted/done state. Above them, a
**Superfan banner** (`GameCenterScores.superfanTotal`, **display-only** — the actual Game Center
submit already happens in `GameCenterManager.syncAll`), gated to **≥2 games played AND total > 0**
(never a meaningless "0"). Countdowns via the pure `compactCountdown(to:from:)`. Each game keeps its
accent: predict `dsGamePredict` (pink), bracket `dsGameBracket` (teal), trivia `dsGameTrivia` (indigo).

## Visibility gates (do NOT break these)

| Game | Visible when | Hidden when |
|---|---|---|
| Predict the XI | a followed team has a fixture within `PredictionFixture.activeWindow` (28 days) | no upcoming fixture for any followed team |
| Bracket Battle | `BracketStore.hasActiveEdition` | no active edition |
| Daily Trivia | always | never |
| Fan Zone section | ≥1 game visible | all three hidden (offseason) |

A game with nothing active/upcoming is hidden **everywhere** (card + screen) — no dead links.

## Predict the XI

`PredictionFixture` (`opponentAbbreviation`, `kickoff`, `deadline` = kickoff − 2h; `activeWindow`
28d) · `XIPrediction` (`slots` [Int:String], 11 to be `isComplete`; `draft → submitted`, one-way
lock) · `PredictionStore` (`predict.v2.*`, `seasonPoints`, `points(forTeam:)`) · `PredictionScoring`
(Mastermind partial, max 88; unit-tested) · per-team leaderboards (`PredictLeaderboardService` — a
read failure shows only your real local score). The open-fixtures slate + scoring (via `/summary`)
live in `PredictXIViewModel`; the in-flight picker is `XIPickerViewModel` / `XIPickerView`.

## Daily Trivia

5 questions/day, one scored play per local day (Wordle-style gate); `TriviaStore`
(streak/bestStreak/totalCorrect/accuracy); `TriviaService` throws on failure OR empty pool
(online-only, no seed); league-wide best-streak board (`TriviaLeaderboardService`).

## Sign-in & honesty

Games are **browsable signed-out**; the gate appears **at submit** (`SignInPromptView`). First-entry
one-time invite via `.fanZoneIntro()` (`FanZoneIntroView`, skippable, gated `!introSeen && !isSignedIn`).
ZERO fabricated data: honest empty/loading states, never fake rivals or padded counts; a read failure
shows only the user's real local value. Game Center (`GameCenterManager`) is additive on top of the
Supabase boards.
