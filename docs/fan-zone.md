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
| Games | Know Her Game, NWSL Trivia | Predict the XI, The Bracket |
| The question it answers | "How did I do **compared to everyone**?" | "**Where do I rank**?" |
| Ranked? | No | Yes — leaderboards + Game Center |
| Payoff screen | `CommunityResultsView` (per-question splits) | Standings tables (top-100 + your true rank) |
| Look | `dsBgGrouped` page + `dsBgCard` | `dsBgPrimary` (black) + `dsMdCard` (navy) |
| Feeds Superfan | Yes | Yes |

**Anti-drift rule (learned the hard way):** the two community games must feel like the *same game in two
flavors*, not two different products. They share the whole grammar — landing page → round session →
live community results — and the same shared components. Trivia diverging from this was a real,
repeatedly-rediscovered defect, closed 2026-07-23.

**⚠️ The payoff screen must answer BOTH questions — "how did everyone do" AND "how did *I* do."**
Until 2026-07-29 the panel showed only the community split with a green ✓ on the correct option, and
nothing at all about the reader's own answer. Owner-reported after playing a real round: on a 97/1/1/1
question you pick B, see the ✓ on the row above your bar, and read it as *your* answer being right.
A results screen that can be misread as the opposite of your result is worse than no results screen.
The fix (shared, so both games get it): your own option carries a red ✗ and a "your pick" tag, against
the correct option's green ✓. **Marks differ by SHAPE and TEXT, not just color** (✓ / ✗ / ○ + "your
pick"), which is the color-blind requirement met at build time rather than retrofitted.

**The per-question header is TWO lines — prompt + "47 out of 50 fans nailed this" — and should stay
there.** Three things were built into that header the same day and then cut; the reasons generalise:
- **A verdict line** ("You said Green — the answer was Blue"). Load-bearing only while option labels
  truncated to one line. Once the options went full-width, it restated what the ✗/✓ marks already show.
- **The leading percentage** ("94% · 47 of 50…"). `correctCount` IS the count of fans who picked the
  correct option, so that percentage was the same statistic as the correct option's own bar, printed
  twice per question, ten questions per recap. ⚠️ Removing it is NOT a return of the pre-2026-07-22
  low-N gate: that gate WITHHELD the percentage below 25 responders, whereas the raw count shows at
  every N and is the harder number to overstate ("2 out of 3 fans" can't mislead the way a bare 67%
  can). Per-option percentages are untouched. Nothing hides at low scale.
- **A flavor line on a rare correct answer** ("only 12% got this"). On a screen already dense with bars,
  per-question commentary is noise, not delight.

The rule underneath all three: on a recap of 10–15 questions, anything printed per-question is printed
ten-plus times. Redundancy that reads as harmless once becomes the texture of the whole screen.

Two layout calls that go with it:
- **Options stack: full label on its own line, bar beneath.** Options in these games are sentences, so
  a side-by-side label column truncated them ("Sitting on the fi…") — and on a review of a round you
  DIDN'T play there's no other place the correct answer appears. Stacking also roughly doubles the bar,
  since it no longer competes with a label column for width. Costs ~90pt per question; accepted. ⚠️ The
  spacing ratio carries it — 5pt from a label to its own bar, 14pt between options. Flatten that and the
  bars stop reading as belonging to their labels.
- **Bars, not a donut** (the Swift Alert Mastermind comparison, weighed and declined). A donut can't
  label its own slices, so it needs a legend — which is the bar list again, minus the bars. It's also
  ~340pt per question against the stacked bars' ~190pt, and these recaps run 10–15 questions where
  Mastermind shows one per screen. The Bracket keeps its donut precisely because it's a *binary* vote,
  one per screen, where the shape IS the story. Same reasoning that cut the Predict GK donut (2026-07-28).

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
| Predict lineups (the 11 picks) | `PredictionStore` | **never uploaded PRE-DEADLINE**; the graded XI + breakdown upload POST-MATCH to `predict_match_results` (own-row RLS, 2026-08-10) | The pre-deadline half is the deliberate rule (the community aggregate needs COUNTS, not lineups — see the note under this table, whose protections are untouched). The post-grading upload exists so a reinstall restores Recent Results / the round board / the predicted-vs-actual detail — owner decision after a real reinstall lost hers |
| Predict community pick counts | — | `predict_pick_counts` / `predict_match_submissions` (NO `user_id`) | Aggregate only; flat in user count; pruned >28d |
| Predict submission dedupe mark | — | `predict_submission_marks` (user, event) | Records THAT you submitted, never WHAT; pruned >28d |
| Predict results-seen flags | `PredictionStore` (`predict.v2.*`) | — | Pure presentation state; a reinstall re-shows one reveal, which is a non-event |
| Predict season bests | `PredictionStore` | `predict_season_bests` (user, season) | The superlative ladder's thresholds; `GREATEST`-merged, never pruned |
| Predict season points + scored-match count | `PredictionStore` | `prediction_scores` (user, team, season) — `points`, `matches`, `avg_points` | Board ranks by `avg_points`; see §4 |
| Predict round points | derived from `PredictionScore.soccerWeek` | `predict_round_scores` (+week) | Pruned >28d |

> **⚠️ How the community percentages exist without uploading anyone's XI (2026-07-28).** The share
> bars, consensus XI, standout picks and contrarian panel all need *how many of a club's predictors
> picked each player*. The obvious implementation — upload every lineup — is forbidden twice over:
> it reverses the row above, and at 100k users it is exactly the per-user-per-round growth the
> storage budget can't absorb. So the app calls `predict_record_picks`, a SECURITY DEFINER RPC that
> increments counters and **discards the lineup**. Size is bounded by *squad × slots × matches*
> (~150 rows/match), identical whether 100 people play or 100,000.
>
> Two properties are worth knowing before touching any of it:
> - **Idempotency is a server-side primary key**, `(user_id, event_id)` in `predict_submission_marks`
>   — not a local flag, which would fail on a reinstall or a lost response.
> - **Reads are deadline-gated by the PROXY, not by Postgres or the app.** Percentages readable while
>   people are still picking would let users copy the consensus and flatten the distribution every
>   other feature depends on. Postgres has no idea when kickoff is; the device clock is the user's.
>   `GET /predict/community` knows kickoff from its own cached `/summary`, serves only a submission
>   count before kickoff − 2h, and **fails closed**. A `closes_at` written solely by the proxy also
>   stops a modified client slipping a post-lineup XI into a pre-summed counter.
| Bracket picks | `BracketStore` (per edition+round) | `bracket_votes` | Votes ARE the game mechanic |
| Bracket points / stats / final rank | small cache | `bracket_scores`, `bracket_user_edition_stats` | Record book, kept forever |
| Superfan counts + tier | — | `superfan_scores` (per-game correct/attempted counts + tier) | 0–100 economy; see §6 |
| Season history (peak tier) | — | `season_history` (user, season_year) | Record book, kept forever |
| Achievements | — | `user_achievements` (user, key, season) | Idempotent INSERT-only; see §6a |

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
- **This round** — that soccer week's raw points, ranked among fans of the same club.
- **Season** — ranked by **AVERAGE points per match** (`avg_points = points / scored matches`), NOT
  cumulative total. Cumulative points inflate to four digits mid-season and can't compare players with
  different match counts (500 over 20 matches is worse than 400 over 6). The average stays in the 0–88
  per-match range all season — the batting-average model. The board shows "52.3 avg · 12 matches"; the
  season card leads with the average (ring = avg/88). Server ranks by `avg_points` (indexed) + a HEAD-count
  rank; the round board stays raw points (a round is only 1–2 matches, so averaging there is noise).

**Results (redesigned 2026-07-28).** The per-match screen shows the REAL starting XI on the picker's own
field, marked green (you called her) / red (you missed her), revealed line by line, and led by "8 of 11
starters" rather than points — points are the accounting, never the headline. Your picks who sat are one
quiet line; there is no separate "you missed" section, because a missed starter is simply a red node.
Community percentages appear ONLY inside the per-band "How <club> fans picked" panels, each carrying its
own explanation — no number floats unlabeled. A submitted prediction also has a destination now
(`PredictLockedView`): the sealed aggregate before the close, the crowd revealed after it, plus a share
card. Routing: 0 unseen results → the landing, 1 → straight into it, 2+ → the landing's round rollup with
NEW pills. ⚠️ Seen-tracking is PER FIXTURE, never per user — one flag would mark all of a weekend's
results seen the moment you opened one of them.

**Recent results + per-match detail** (`PredictXIView` "Recent results" section, windowed to the current +
previous soccer week). Each compact card (crests + FT + total + one-line summary) opens
`PredictMatchResultView`: your predicted XI vs the ACTUAL XI (re-fetched from `/summary` on demand — never
persisted, edge-cached), per-player ✓/✗ + "also started — you missed", formation + scoreline calls, the
full point breakdown, and the fixture's round-week rank (Predict has no per-single-match board; a match
sits inside a round).

**Break weeks show a PAUSED state** ("No NWSL matches this week — predictions for X's next match open
<date>"), with the boards still browsable. The card is only hidden in a true offseason (no future
fixture at all).

### The Bracket (comp arena)
> Renamed from "Bracket Battle" (2026-07-24) — user-facing copy says **The Bracket**; internal ids stay
> `.bracket`/`dsGameBracket`/GC-ids/keys.

A community-voting elimination bracket; you score by **predicting the crowd**, not by picking who you
like. Multi-round, one edition at a time; the engine (proxy `src/bracket-engine.ts`) runs the lifecycle.
Scoring 1·1·2·2·3·3 by round. **Round names are POSITIONAL** — "Round 1–5", Quarterfinals, Semifinals,
Final (no "Round of X" / "Qualifying" in UI; internal raw round codes unchanged). Full ops detail:
`.claude/rules/bracket-battle.md`.

**Returning-player landing** = rank card + active-round CTA + neighborhood board + a **stepping-stones
timeline** (one node per round: completed → tap to review that round's per-matchup results; active → tap to
vote, or re-enter a locked-in round as a read-only review; upcoming → not tappable). A **post-round results
screen** shows once per tally (margin-only verdicts — "Solid — J. Campbell took it · +2 pts", the exact
vote split lives only in the expandable donut; your pick gets the teal border regardless of outcome).

**At edition close** the engine stamps `final_rank` + `field_size` onto each player's stats row → "Finished
#12 of 340" survives forever. **Per-user votes are pruned at the NEXT edition's START** (not at close — owner
rule 2026-07-24), so a finished edition stays fully browsable round-by-round through the between-editions
review window (§7). The Rankings tab can reopen the **previous completed edition** (the World Cup rule).

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
- **Trivia's SEASON accuracy pair (`seasonCorrect`/`seasonAnswered`) is NOT restored here** (2026-07-25,
  the accuracy-pair invariant §6): the table has no season-answered twin, and restoring the lone
  numerator inflated accuracy to a false 100%. Lifetime pair + streak pair still restore (both travel
  whole); season accuracy durability rides `superfan_scores`, exactly like KHG. The
  `trivia_season_correct` column is still uploaded (older builds read it) but ignored on restore.
- Per-completion uploads are **per-game PARTIAL upserts** (PostgREST merge-duplicates touches only the
  supplied columns), so Trivia's write can't clobber KHG's. Only the sign-in restore goes through
  `ProgressSyncCoordinator`.

Bracket needs nothing here — its numbers live in its own server tables and flow back through the
leaderboard reads. **Predict DOES restore here as of 2026-08-10** (`ProgressSyncCoordinator.
restorePredict`, run BEFORE the Superfan merge and outside the `fanzone_progress` guard): season
bests read down into `mergeSeasonBests`, and the season's graded results read down from
`predict_match_results` into `PredictionStore.restoreGradedResults` (skip-if-local merge; restored
rows arrive pre-seen so no reveal re-fires, and pre-marked-uploaded so the backfill never round-trips
them). The board You-row doesn't even wait for this — it renders from the user's own
`prediction_scores` row via `effectiveStanding`. (The previous claim that Predict "needed nothing
here" was the reinstall-erasure bug: the boards were local-gated, so nothing actually flowed back.)

---

## 6. Superfan Zone (the 0–100 accuracy economy)

> **REBUILT 2026-08-05 (owner: "blow it up").** The prior model (a static per-game `accuracy × 25` stat
> sheet) is GONE — it PUNISHED playing (accuracy is a ratio, so a bad game dragged you down) and read as a
> boring spreadsheet nobody opened. Now: a forgiving economy that stays meaningful ALL season, and a detail
> screen led by ALIVE content. `SuperfanScoring` / `SuperfanSpotlight` / `PlayersLearned` / `SuperfanMomentum`.
> ⚠️ EVERY economy constant is a TUNABLE code constant (the score is derived from raw inputs) — the whole
> curve re-tunes with NO migration (owner: build + tune live).

**The score.** Each of the four games is a channel worth **0–25 = 20 accuracy + 5 engagement**, summed 0–100:
- **Accuracy (0–20):** `ratio^gamma × 20` — a TOP-WEIGHTED curve (`SuperfanScoring.accuracyGamma`, per-game
  by luck vs skill: KHG/Trivia steep 1.30, Predict ~75%-luck / Bracket ~70%-vibes gentle 1.05) so the top is
  EARNED, not handed out ([[feedback_superfan_points_philosophy]] — low floor, high HARD ceiling; perfect
  accuracy still earns the full 20, the curve only taxes the middle). Ratio = correct/attempted per game
  (Predict Σ correct XI / Σ 11×matches; Bracket correct / structure matchups; KHG/Trivia Σ correct / Σ attempted).
- **Engagement (0–5): forgiving DECAYING momentum** (`SuperfanMomentum`): +1 each cycle you play, −1 per
  MISSED cycle, floored/capped, NEVER a reset, and it DECAYS if you stop — so it's never a permanent free 5
  (the anti-handout property), yet a single miss costs one point and recovers on return (busy fans safe).
  Per-game cadence in weeks (Predict/Bracket 1, KHG/Trivia 2); recorded at each game's play/submit hook;
  device-local store, the `superfan_scores` momentum column max-merged as a reinstall floor.
- **Tier-floor lock:** the DISPLAYED score never drops below a tier you've earned this season
  (`displayScore = max(total, tierFloor(season_history.peak_score))`) — a rough round can't knock you down.

Playing only one game caps you at 25 — **breadth is the point**; the top takes accuracy AND consistency
across all four (pure 100% accuracy with zero engagement caps at 80).

**Source of truth = per-game correct/attempted COUNTS** (`SuperfanCounts`, mirrored to `superfan_scores`
columns), NOT the derived score. Accuracy/contribution/total are DERIVED, because accuracy legitimately
*falls* (a bad game lowers it) while counts only grow. `SuperfanCounts.merged(with:)` takes the GREATEST
of every count — that's what makes it reinstall-safe (a wiped device can't lower the server) while still
letting a genuinely-changed accuracy recompute. (The old `max(total)` clamped the wrong thing.)

**⚠️ THE ACCURACY-PAIR INVARIANT (owner rule, 2026-07-25 — run it for every game, and for any FIFTH
game via §9's checklist):** an accuracy's numerator and denominator must be **persisted and restored
TOGETHER, or derived from the same source** — never one without its twin. The bug that minted this rule:
`fanzone_progress` carried `trivia_season_correct` but no season-ANSWERED twin (the column was designed
for #167's points model, one day before #173 redefined the metric as accuracy), so sign-in restore
inflated the numerator against a fresh device's denominator and the `min(1,·)` clamp laundered a 0/10
round into "100% · 25/25". Fix: Trivia's season pair is now NEVER restored from `fanzone_progress`
(the column is still uploaded for older builds, ignored on restore) — reinstall durability rides
`superfan_scores`, exactly like KHG. **KHG is the GOLDEN CHILD for community stat games (owner):
paired local writes (`scores`/`attempts` dicts written together), restore never touches the accuracy
pair, durability via the `superfan_scores` GREATEST-merge. Trivia and KHG are SIBLINGS — the one real
difference is calendar (Trivia runs all year; KHG runs the soccer season) — so their state machinery
must stay structurally identical; any divergence is drift, not design.** Enforcement: an impossible
pair (`correct > answered`) emits `.fanZoneAccuracyInvariant` to Diagnostics at counts assembly
(`SuperfanCounts.fromStores`) and is sanitized at `TriviaStore` load — it must never pass silently
as a clamped "100%" (the banned failure-that-looks-like-success).

**ABSOLUTE tiers** (`SuperfanTier.forScore`, even quartiles — NOT percentile): **Fan 0–24 → Rising 25–49
→ All-Star 50–74 → MVP 75–100.** Each has a dedicated tier color (not a game color) + SF Symbol. The
detail screen shows a progress bar to the next tier ("13 points to All-Star"). Tiers show from the FIRST
player — nothing hides at low scale (§8).

**Season reset at MARCH.** The season key is `AppConfig.currentSeasonYear` (`month < 3 ? year-1 : year`),
so the season rolls at NWSL season start, not Jan 1 — offseason Trivia/Bracket play counts toward the
current (just-ended) season until March, when the peak locks into `season_history` and a fresh 0–100 opens.
(A Jan 1 reset would strand users at ≤25–50 through the Feb dead zone when KHG/Predict aren't active.)

**Detail screen** (`SuperfanDetailView`) — REBUILT 2026-08-05 to LEAD WITH ALIVE CONTENT, stats demoted:
1. **Tier hero** — score + tier NAME + a 4-rung LADDER (Fan→Rising→All-Star→MVP) with the current rung lit,
   so where you stand reads at a glance (fixes the old "58 but All-Star looks like the floor" confusion);
   floor-locked score.
2. **Spotlight** (`SuperfanSpotlight`, pure) — ONE rotating "what we noticed" item per visit from a pool of
   CHEAP real signals (next-tier nudge, untapped/weakest channel, players-learned count, personal best,
   achievement, playful zero-state floor). It is the SuperfanDetailView reason-to-open hook, not deep-history
   mining. ZERO fabrication (real item or honest floor).
3. **Players Learned** (`PlayersLearned`) — the on-brand COLLECTION anchor: a grid of headshot stamps for
   every KHG player learned this season (recorded on KHG finish, deduped keeping best score), grows as you
   play. Local for now; a server mirror can layer on without changing the read path.
4. **By the numbers** — the per-game accuracy + engagement breakdown, DEMOTED below the hook.
5. **"How Superfan works"** (published-contract copy — gate #7, kept in sync with the 20+5/floor model),
   **Best Moments** (§6a), **Season History** (`season_history`, peak tier kept forever).
The **Home `SuperfanCard`** shows the COMPACT form (badge · Superfan · score · progress bar) — the rotating
teaser was REVERTED 2026-08-05 (#243): on a `minHeight:128` card its 2-line height grew the whole carousel
and pushed Club News down, losing the next-card peek (owner). The spotlight still feeds SuperfanDetailView;
the card's `teaser` param stays dormant (nil) for an easy re-add. All reads on-demand + bounded. (The percentile "Top N% of N fans" line stays removed — plumbed but unused.)

## 6a. Achievements ("Your Best Moments")

Nine badges (`Achievement.swift`), detected **client-side at game completion** (no Edge Functions), written
to `user_achievements` (UNIQUE `(user, key, season)` → award is idempotent, INSERT-only — a badge is
permanent). `AchievementDetector` runs `checkCumulative` (from the four stores on Superfan load) +
`checkBracket` (from the loaded edition). The set: Perfect Round, **Dark Horse** (3+ upset calls in one
bracket round), Streak Master, Lineup Oracle (9/11 in a Predict match), First Blood, Well-Rounded,
**Upset Royalty** (≥1 upset call), Know It All, Iron Fan. ⚠️ **Upset badges are VOTE-MARGIN based** — an
"upset" = a called winner the crowd advanced with **≤55% of the vote** (a ≤10-pt nail-biter), NOT seed-based
(the handoff's "<40% vote" is impossible in a majority-wins 2-way bracket). "Your Best Moments" renders the
earned set on the Superfan detail (hidden entirely when none — never an empty grid).

---

## 7. Retention — "current + previous, then prune"

The app can't render anything older, so the database holding it is storage with no reader.

| Data | Kept | Pruned by |
|---|---|---|
| `quiz_answers` | ~35 days (current + previous round + margin) | pg_cron, daily |
| `predict_round_scores` | ~28 days | pg_cron, daily |
| `predict_pick_counts` / `predict_match_submissions` | ~28 days | pg_cron, daily |
| `predict_submission_marks` | ~28 days | pg_cron, daily (submit is one-way, so an old mark has nothing left to dedupe) |
| `predict_match_results` | ~400 days (current season restores all season; last season's age out) | pg_cron, daily |
| `bracket_votes` | current + finished edition (through the review window) | the engine, at the NEXT edition's START |
| Record book (`*_scores`, `*_stats`, `fanzone_progress`, `superfan_scores`, `season_history`, `user_achievements`) | **forever** | never — one tiny row per user |

**Why pg_cron:** it runs inside Postgres. Cloudflare requests are the metered resource; Supabase API
calls are unlimited; a cron in the database uses neither. **Why age-based** rather than round math: no
anchor arithmetic duplicated into SQL, and it's robust to key-format changes (it also swept the legacy
day-keyed Trivia editions for free). Bracket is the exception because an edition's life isn't
calendar-shaped — its votes prune when the NEXT edition starts (`pruneCompletedEditionVotes` in the engine's
`writeEdition`), so a finished bracket stays fully browsable through the between-editions review window.

---

## 8. Sign-in, honesty, and Game Center

**Games are browsable signed-out; PLAYING is gated** at the first ranked action (`FanZoneGate`): a
no-skip sign-in step, then a REQUIRED display name (the leaderboard identity), then the action runs.
Because entry is gated, every downstream write is already authenticated.

**ZERO fabricated data** is a hard rule: honest empty/loading states, never padded counts or invented
rivals. A board with one real person shows one person and says so.

**What the rule targets — and what it doesn't.** It forbids the APP inventing rivals client-side. It
does NOT forbid a backend test population: `nwslapp-proxy/scripts/seed_test_fans.mjs` creates real
`auth.users` accounts (`@seed.nwslapp.test`) that own real rows, so the app renders them exactly as it
will render launch traffic and cannot tell the difference. Bracket seeds **votes only** — the real
engine derives the winners, splits, scores and ranks, so a tally bug surfaces instead of hiding behind
hand-written scores. Two guardrails make this safe: nothing seeding-related ships in the app binary
(the `-signInAsTestFan` path is `#if DEBUG`), and `health_check_seed_accounts.mjs` FAILS the proxy
healthcheck while any seed account exists. Purge with `--purge` — every per-user table cascades off
`auth.users`, so deleting the accounts removes everything they own.

**Nothing hides itself at low scale (owner ruling 2026-07-22).** Surfaces show their real shape from the
first player, because the first players are the ones we need to come back. Superfan's **absolute** tier +
0–100 score render from play #1 (the redesign's absolute quartile tiers removed the old percentile gate
entirely — §6), and quiz percentages no longer wait for 25 responders (they render alongside their raw
counts, so a small-N number can't overstate). This is the same call that lifted the Trivia reveal gate —
hiding a feature until a crowd arrives is how the crowd never arrives.

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
8. **Honor the ACCURACY-PAIR INVARIANT (§6):** if the game feeds the Superfan economy, its
   correct/attempted pair is written together and restored together (or not at all — durability via
   `superfan_scores`), never one scalar without its twin. Community stat games copy the KHG pattern
   exactly (the golden child); `correct > answered` must emit `.fanZoneAccuracyInvariant`, never
   clamp silently.
