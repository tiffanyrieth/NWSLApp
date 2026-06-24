---
paths:
  - "**/Bracket*.swift"
  - "**/*bracket*.sql"
---

# Bracket Battle — operating rules

A **live community-voting elimination bracket** for the whole NWSL. Players are seeded into a
themed bracket; each round the **community votes** who advances, and **you score by predicting the
crowd** (not who you want). Points accumulate (later rounds worth more); per-edition leaderboard +
lifetime stats; ranked via Game Center + Supabase `bracket_scores`.

## Engine (sibling repo — `~/Projects/nwslapp-proxy`, NOT this app)

`src/bracket.ts` (pure math, unit-tested) + `src/bracket-engine.ts` (I/O, service-role). One job:
`runBracketTick`, driven by the `*/5` cron + admin `POST /bracket/run`. Idempotent.

- **Manual/Auto mode** read from `bracket_config.mode` every tick. **Manual** (launch default): acts
  only on a queued `manual_action` (`advance_round` | `close_edition` | `start_edition` | `pause` |
  `resume`), then clears it. **Auto**: full lifecycle on schedule (advance when `round_closes_at`
  passes; generate after `break_days`). Flip with one SQL update — no deploy.
- **Qualifying / byes** for pools >64: sizes 64/96/128/160/192 (default 128; >192 snaps to 192). Top
  32 seeds bye into the Round of 64; the other 32 are qualifiers. **Round codes**: main = entrant
  count (64→2); qualifying = **negative** (`q1=-4 … q4=-1`) — this is the cross-repo contract, identical
  to the app's `BracketRound`. Same-team protection through qualifying + Round of 64 + Round of 32.
  **Round of 64 (main-bracket entry) is SEEDED** (`roundOf64Entrants` → `buildSeededRound`, NCAA
  `seedOrder`): byes keep seeds 1–32, qualifier winners get effective seeds 33–64 by rank → seeds 1 &
  2 in opposite halves (quadrant structure). Qualifying rounds pair sequentially (`buildMergedRound`).
- **Seeding by real ESPN season stats** (budget-aware, `bracket_config.stat_fetch_budget` default 20):
  `goals_assists` (Best Forward) via the 1-call league-leaders endpoint; `save_pct` (compute
  `saves/shotsFaced` — ESPN's field is buggy) / `chances_tackles` / `tackles_interceptions` / `minutes`
  via per-athlete Core API. Candidates with no stat fall to roster-depth order; `bracketStatSeed*` diag
  records real-vs-fallback. Creative editions seed by `minutes` (all positions).
- **Creative editions are theme-only** — no per-player content/entries; the Worker pulls the
  whole-league ESPN pool, like stats, differing only by theme label. Rotation alternates creative↔stats.
- **Streak** (written by the tally): consecutive correct picks across rounds within an edition, picks
  folded in **slot order**; current resets to 0 on any miss; longest = per-edition best.
- **Scoring** 1·1·2·2·3·3 (qualifying = 1); max is rule-derived (`matchupCount · points`).
- **NO SILENT FAILURES:** `emitDiag` on any partial state + `scripts/health_check_bracket.mjs`
  (`npm run healthcheck`, exits non-zero on a stuck/unsound edition).

## iOS

`BracketEdition.swift` (`BracketRound` main 64→2 + qualifying q1–q4 negative codes; flat Codable) ·
`BracketScoring.swift` (pure, rule-derived max; unit-tested) · `BracketService.swift`
(`currentEdition`/`results`/`leaderboard`/`submit` + `standings`/`myEditionStats`; throw or
honest-empty) · `BracketStore.swift` (durable picks/submit/scores, `bracket.v2.*`) ·
`BracketViewModel.swift` · `BracketBattleView.swift` (5 screens: Intro·Voting·Submit·Results·Overview) ·
`BracketLeaderboardView.swift` (Rankings + Your Stats — totals/accuracy/streaks/edition history).

## Supabase tables

`bracket_editions` / `_entrants` / `_matchups` / `_votes` / `_scores` + v2 `bracket_config` /
`bracket_stats_editions` / `bracket_creative_editions` (theme-only, no `entries`) /
`bracket_user_edition_stats` (accuracy + streak backing). World-readable + service_role writes (the
`42501` grant gotcha). Migrations/seeds: `supabase/migration_bracket_*.sql` + `seed_bracket_*.sql`.

## Hard rules

ZERO fabricated data (real vote splits / counts / leaderboard only — 2 players → board shows 2).
Hide the game when no active/upcoming edition. Sign-in gate at **submit**, not entry. Submit is
permanent (save-draft is the escape valve). **No emoji in game UI** — teal `dsGameBracket` accent +
team colors + `PlayerDot` (team-ringed player headshot, jersey-monogram fallback) only. Edition intro
is mandatory; **play is gated** behind no-skip sign-in + display name (`.fanZoneGate`, at "Make your picks").

## Launch / operate

Runbook: `Reference/Bracket Battle/first-launch-checklist.md`. Deploy = run the 4 SQL files
(`migration_bracket_v2` → `migration_bracket_qualifying` → `seed_bracket_stats_editions` →
`seed_bracket_creative_editions`) → `npm run deploy` (proxy) → `manual_action='start_edition'`.
Advance: `update bracket_config set value='"advance_round"' where key='manual_action';`. Go auto:
`update bracket_config set value='"auto"' where key='mode';`.
