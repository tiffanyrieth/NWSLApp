# Fan Zone — how the whole thing works

> **What this doc is:** the SYSTEM reference for the Fan Zone — the four games, the two families, the
> cadence engine, where every piece of state lives, retention, restore, and the scoring/leaderboard
> model. Read it before touching any game, and especially before adding a fifth.
>
> **What it is NOT:** the build rules. Those live in **`.claude/rules/fan-zone.md`** (auto-loads when you
> touch Fan Zone files) — Home layout, visibility gates, the six-item LOGIC GATE, the shared-component
> contract. That file says *what you must do*; this one says *how it works*. Bracket's engine/ops detail
> is in `.claude/rules/bracket-battle.md`; Know Her Game's design/decision record is
> `docs/know-her-game.md`.
>
> Much of the connective tissue below (the stagger, what's local vs server, why restore reads a summary)
> is NOT reconstructable from the code without reading five files at once. That's why this exists.

---

## 1. Two families — the organising idea

The Fan Zone is deliberately **two kinds of game**, and the surface signals which before the copy does.
A new game picks a family; it never invents a third.

| | **COMMUNITY STATS** | **COMP ARENA** |
|---|---|---|
| Games | Know Her Game, NWSL Trivia | Predict the XI, Bracket Battle |
| The question it answers | "How did I do **compared to everyone**?" | "**Where do I rank**?" |
| Ranked? | No | Yes — leaderboards + Game Center |
| Payoff screen | `CommunityResultsView` (per-question splits) | Standings tables (top-100 + your true rank) |
| Look | `dsBgGrouped` page + `dsBgCard` | `dsBgPrimary` (black) + `dsMdCard` (navy) |
| Feeds Superfan | Yes | Yes |

**Anti-drift rule (learned the hard way):** the two community games must feel like the *same game in two
flavors*, not two different products. They share the whole grammar — landing page → round session →
live community results — and the same shared components. Trivia diverging from this was a real,
repeatedly-rediscovered defect, closed 2026-07-23.

---

## 2. The cadence engine (`Models/FanZoneCadence.swift`)

One pure, date-injected type owns the Fan Zone calendar. Everything round-shaped derives from it.

**The stagger — the single most misunderstood part.** Community rounds are **two weeks long** and the
drops are **offset by one week**:

```
season week:   1        2        3        4        5        6
KHG:          [round 1        ][round 2        ][round 3        ]
Trivia:                [round 1        ][round 2        ][round 3   ]
drop week:     KHG      Trivia   KHG      Trivia   KHG      Trivia
```

So **both games are almost always playable** — in a Trivia drop week, KHG is in its second week. What
alternates is which game drops something NEW.

- `quizSlot(for:)` → which game drops this week (even offsets = KHG, odd = Trivia).
- `roundNumber(for:at:)` → what's LIVE for a game (nil before that game's first round).
- `isDropWeek(for:at:)` → the "fresh content" signal (Home's unseen dot).
- `roundCloses(for:at:)` → two weeks from that round's own opening Monday, so "closes in N days" doesn't
  reset halfway through.

**The anchor is a cross-repo contract.** `seasonAnchor = "2026-03-09"` (the Monday of the week containing
the Fri 3/13 opener) must equal `SEASON_ANCHOR` in the proxy's `scripts/assemble_knowher_prompt.mjs` —
the app decides what to SHOW, the proxy decides what to GENERATE. Drift = a fan opens a game whose
content was never generated. `FanZoneCadenceTests.anchorMatchesTheProxysCommittedAnchor` pins it.
**Bump both each season.**

**Predict is different: its round is the SOCCER WEEK**, not a two-week edition, because its content is
the fixture list. `soccerWeek(for:)` is Week 1 = the anchor week. A club playing Wednesday *and*
Saturday has both matches in one round.

⚠️ **Why the week number is calendar-derived and not "the Nth week with fixtures":** it's a leaderboard
primary key. Counting only fixture weeks means one postponed match renumbers every later week and
silently corrupts already-banked round scores. A calendar grid can't be renumbered by a schedule change
— a break week simply has no rows.

⚠️ **The 2026 season has 7 fixture-free weeks** (incl. a four-week June block). Predict therefore shows a
PAUSED state, never a phantom round — see §4.

⚠️ **Epoch gotcha:** the Unix epoch was a **Thursday**. Reconstructing a Monday from `ordinal × 7 days`
lands 3 days off. Week *differences* are unaffected — which is why the proxy's identical subtraction is
correct, and why only one test caught this. Use the calendar for absolute dates (`weekStart`).

---

## 3. State ownership — what lives where

The governing principle: **the device leads during play; the server is for ranking, community
aggregates, and restore.** Local writes always succeed first; every network step is best-effort.

| Data | Local (UserDefaults) | Supabase | Notes |
|---|---|---|---|
| Trivia round scores + picks | `TriviaStore` — **current + previous round only** | — | Pruned on write |
| Trivia counters (lifetime/season/streak) | `TriviaStore` | `fanzone_progress` | Aggregates, not history |
| KHG per-edition scores | `KnowHerGameStore.scores` (all season) | `fanzone_progress` (season totals) | + `previousPool` for last-round review |
| Quiz per-question answers | — | `quiz_answers` | Feeds community splits; pruned >35d |
| Predict lineups (the 11 picks) | `PredictionStore` | **never uploaded** | Deliberate — no value server-side |
| Predict season points | `PredictionStore` | `prediction_scores` (user, team, season) | |
| Predict round points | derived from `PredictionScore.soccerWeek` | `predict_round_scores` (+week) | Pruned >28d |
| Bracket picks | `BracketStore` (per edition+round) | `bracket_votes` | Votes ARE the game mechanic |
| Bracket points / stats / final rank | small cache | `bracket_scores`, `bracket_user_edition_stats` | Record book, kept forever |
| Superfan total | **computed client-side** | `superfan_scores` (for ranking only) | See §6 |

**Nothing syncs DOWN except progress restore (§5).** Follows sync is upward-only for the same reason —
see the header of `Stores/FollowSyncCoordinator.swift`.

---

## 4. Per-game lifecycle

### Know Her Game (community)
One featured player per followed club per round. `KnowHerLandingView` (This round / Last round / How
players are chosen) → `KnowHerGameView` (`.play` or `.review`). Content is fully automated: a Claude
Routine generates the pool biweekly and POSTs `/knowher/ingest`. Player selection is server-side
(`starts ≥ 1 || minutes ≥ 100`, once per season). Scoring: 1 point per correct.

### NWSL Trivia (community)
One 10-question slate per round, league-wide (no per-team split). `TriviaLandingView` →
`TriviaRoundView` (`.play` / `.review(round:)`). Scoring: 1 per correct. One scored play per round; the
streak counts consecutive ROUNDS.

**Round slates are DETERMINISTIC** (`TriviaViewModel.roundSelection`): the pool is id-sorted, shuffled
once with a fixed seed, then paged by round number. That's what lets a past round be reviewed with **zero
stored questions** — only the user's score and picks persist. ⚠️ Currently 41 questions in the pool ⇒ 4
unique rounds, then it wraps. The annual ~530-question generation is a **parked roadmap item**; the
structure is already waiting for it.

### Predict the XI (comp arena)
Per-club. Each followed club's next fixture inside a 28-day window; submissions close at **kickoff − 2h**;
submit is one-way. ESPN's real lineup auto-scores it Mastermind-style (`PredictionScoring`, max 88:
players ×3, positions ×2, formation 5, exact scoreline 10, result 3, perfect XI 15).

**Two clocks** (owner's Overwatch framing — a season rank alone isn't competitive; you need a fresh
weekly chance that *moves* your season position):
- **This round** — that soccer week's points, ranked among fans of the same club.
- **Season** — the running total.

**Break weeks show a PAUSED state** ("No NWSL matches this week — predictions for X's next match open
<date>"), with the boards still browsable. The card is only hidden in a true offseason (no future
fixture at all).

### Bracket Battle (comp arena)
A community-voting elimination bracket; you score by **predicting the crowd**, not by picking who you
like. Multi-round, one edition at a time; the engine (proxy `src/bracket-engine.ts`) runs the lifecycle.
Scoring 1·1·2·2·3·3 by round. Full ops detail: `.claude/rules/bracket-battle.md`.

**At edition close** the engine stamps `final_rank` + `field_size` onto each player's stats row → "Finished
#12 of 340" survives forever, and older editions' per-user votes are pruned (see §7). The Rankings tab can
reopen the **previous completed edition** (the World Cup rule: a finished tournament's table stays
inspectable).

---

## 5. Progress restore (`fanzone_progress`)

**What sign-in restores: game progress. Not follows.** (Follows were removed as a restore target —
16 clubs take seconds to re-pick, and restoring them while a fan's season vanished was inverted.)

- One summary row per **(user_id, season)**. **Keyed on `user_id`, NEVER `device_id`** — a replacement
  phone gets a new Keychain UUID but the same Apple ID.
- **A SUMMARY, never history.** Raw `quiz_answers` are pruned (§7), so restore must not depend on them —
  and nobody wants question 7 of round 30 back. They want their streak and their season total.
- **Merge is MONOTONIC** (`ProgressSnapshot.merge`): counters take the max side, so a stale server row
  can never lower a fresher device.
- **Streaks travel as a PAIR with their last-completed marker.** Max-ing the fields separately would
  graft an old long streak onto a recent play and resurrect a dead streak.
- **KHG restores via a season BASELINE floor**, not synthetic score rows: season reads take
  `max(local-derived, baseline)`. A floor, not an addend — local play that already fed the server total
  can't double-count.
- Per-completion uploads are **per-game PARTIAL upserts** (PostgREST merge-duplicates touches only the
  supplied columns), so Trivia's write can't clobber KHG's. Only the sign-in restore goes through
  `ProgressSyncCoordinator`.

Predict and Bracket need nothing here — their numbers already live in their own server tables and flow
back through the leaderboard reads.

---

## 6. Superfan Zone

The cross-game total, **computed client-side** (`GameCenterScores.superfanTotal`) as the sum of four
season-scoped numbers: Trivia correct + Predict season points + Bracket points + KHG banked points.

The server (`superfan_scores`) exists only so you can be **ranked**: one row per (user, season), upserted
with a monotonic `max(total, serverTotal)` clamp — that clamp is precisely why a reinstall can't destroy
a leaderboard standing. Tier comes from a percentile over qualifying fans (≥2 games): Fan → Rising (top
50%) → All-Star (top 20%) → MVP (top 5%), and is **hidden below 5 qualifying fans** (no "top 50% of 3
fans"). Rank/percentile are two `count: .exact, head: true` reads — zero rows transferred.

---

## 7. Retention — "current + previous, then prune"

The app can't render anything older, so the database holding it is storage with no reader.

| Data | Kept | Pruned by |
|---|---|---|
| `quiz_answers` | ~35 days (current + previous round + margin) | pg_cron, daily |
| `predict_round_scores` | ~28 days | pg_cron, daily |
| `bracket_votes` | active + previous edition | the engine, at edition close |
| Record book (`*_scores`, `*_stats`, `fanzone_progress`) | **forever** | never — one tiny row per user |

**Why pg_cron:** it runs inside Postgres. Cloudflare requests are the metered resource; Supabase API
calls are unlimited; a cron in the database uses neither. **Why age-based** rather than round math: no
anchor arithmetic duplicated into SQL, and it's robust to key-format changes (it also swept the legacy
day-keyed Trivia editions for free). Bracket is the exception because an edition's life isn't
calendar-shaped.

---

## 8. Sign-in, honesty, and Game Center

**Games are browsable signed-out; PLAYING is gated** at the first ranked action (`FanZoneGate`): a
no-skip sign-in step, then a REQUIRED display name (the leaderboard identity), then the action runs.
Because entry is gated, every downstream write is already authenticated.

**ZERO fabricated data** is a hard rule: honest empty/loading states, never padded counts or invented
rivals. A board with one real person shows one person and says so.

**Game Center is purely additive** on top of the Supabase boards — every call no-ops silently when the
player isn't authenticated. It is NOT a source of truth, and it works pre-publish (sandbox) — nothing
about the ranked experience waits on App Store approval. ⚠️ The trivia achievement identifiers still say
"day" (`trivia_perfect_day`, `trivia_streak_7/30`) — published GC ids are forever, so they were kept and
**reinterpreted as ROUNDS**.

---

## 9. Adding a fifth game — the checklist

1. **Pick a family** (§1) and a `dsGame*` accent token — add a token, never hardcode a hex.
2. **Reuse the shared components** — `DSButton`, `RetryStateView`, `CommunityResultsView`,
   `PlayerHeadshot`, `Color.teamColor`, `FanZoneGate`. Do not re-roll.
3. **Derive cadence from `FanZoneCadence`** — don't invent a second calendar. If it needs a new rhythm,
   add it there.
4. **Decide state ownership up front** (§3) and **cap every leaderboard at design time** (top-N + your
   own row).
5. **Run the six-item LOGIC GATE** in `.claude/rules/fan-zone.md` before calling it done — scoring
   idempotency, double-tap guard, deadline/lifecycle, list scale, reinstall/offline, partial-failure
   atomicity. Each maps to a bug this codebase actually shipped.
6. **Run the load stress test** (`docs/stress-testing.md` §5) and record it in §7 there.
7. **Add its retention rule** — what's the unit, what's kept, what prunes it, and who does the pruning.
