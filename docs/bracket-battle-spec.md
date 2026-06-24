# Bracket Battle — Combined Spec: Quadrant Seeding Fix + Rules Copy

Two changes, one doc. Part 1 is the technical spec for fixing bracket structure in the
Worker engine. Part 2 is the finalized onboarding rules copy for first-time players.

---

## Part 1: Quadrant Seeding Fix

### The Problem

When a 128-player edition runs, the Round of 64 (main bracket start) loses its bracket
structure. The code uses `buildMergedRound` (sequential pairing after interleaving) instead
of `buildSeededRound` (NCAA-style `seedOrder` placement). Result: top seeds can land in the
same quadrant, Cinderella runs are suppressed, and the bracket lacks the left/right half
tension that makes tournament draws compelling.

Qualifying rounds (Q1, Q2) pair sequentially — that's fine; they're feeders. The structure
only matters once we enter the 64-player main bracket.

### What's Already Built

`bracket.ts` already has every function needed:

- **`seedOrder(64)`** → produces the 64-slot placement array where seed 1 plays seed 64,
  seed 2 plays seed 63, and seeds 1/2 can only meet in the Final.
- **`buildSeededRound(participants, roundCode)`** (line 322-344) → takes an `Entrant[]`,
  applies `seedOrder`, spreads by seed, runs `avoidSameTeam`. Returns `{ matchups, byeIds }`.
  Already used for Q1. **This is the function the Round of 64 should call.**
- **`buildMergedRound(winners, newEntrants, roundCode)`** (line 352-360) → sequential
  pairing after `interleaveByes`. Correct for Q2+ qualifying. **Wrong for Round of 64.**

### Where to Change

**File:** `nwslapp-proxy/src/bracket-engine.ts`, lines 750-765

**Current code (line 760):**
```typescript
const next = buildMergedRound(winners, newEntrants, nextCode);
```

This is called for every round in the large-pool path — qualifying AND main bracket.

**Fix:** Branch on `nextCode`. When `nextCode === 64` (entering the main bracket), build
the full 64-entrant list with effective seeds and call `buildSeededRound` instead.

### Pseudocode

```typescript
if (poolSize > 64) {
  const structure = planStructure(poolSize);
  const nextCode = nextCodeIn(structure, round);
  if (nextCode === null) return await finish("champion crowned");
  const newSeeds = new Set(structure.entrySeeds[nextCode] ?? []);
  const newEntrants: Entrant[] = entrantRows
    .filter((e) => newSeeds.has(e.seed))
    .map((e) => ({ id: e.entrant_id, name: "", jersey: null, team: e.team_abbreviation, seed: e.seed }));

  let next: Matchup[];

  if (nextCode === 64) {
    // ── MAIN BRACKET: use seedOrder for proper quadrant structure ──
    // 32 qualifier winners + 32 bye holders = 64 entrants.
    // Assign effective seeds 1-64: bye holders keep their original seeds (1-32),
    // qualifier winners get seeds 33-64 based on their original seed ranking.
    const byeEntrants = newEntrants; // seeds 1-32 entering now
    const qualifierWinners = winners.map((wId) => {
      const row = entrantRows.find((e) => e.entrant_id === wId);
      return {
        id: wId,
        name: "",
        jersey: null,
        team: row?.team_abbreviation ?? "",
        seed: row?.seed ?? 999,
      } as Entrant;
    });
    // Sort qualifier winners by original seed, assign effective seeds 33-64
    qualifierWinners.sort((a, b) => a.seed - b.seed);
    qualifierWinners.forEach((e, i) => { e.seed = 33 + i; });

    const allEntrants = [...byeEntrants, ...qualifierWinners];
    const result = buildSeededRound(allEntrants, 64);
    next = result.matchups;
    // byeIds from buildSeededRound should be empty (64 entrants → 64-slot bracket → 0 byes)
  } else {
    // ── QUALIFYING: sequential pairing is fine ──
    next = buildMergedRound(winners, newEntrants, nextCode);
  }

  // Same-team protection through qualifying + Round of 64 + Round of 32.
  if (isQualifying(nextCode) || nextCode >= 32) {
    avoidSameTeam(next, entrantRows.map((e) => ({
      id: e.entrant_id, name: "", jersey: null,
      team: e.team_abbreviation, seed: e.seed
    })));
  }
  return await writeNextRound(env, ed.id, next, nextCode, now, config, round, matchups.length);
}
```

### What This Produces (128-player, Round of 64)

With `seedOrder(64)`, the bracket draws:

**Top half (left side):**
- Seed 1 (bye) vs Seed 64 (qualifier survivor)
- Seed 32 (bye) vs Seed 33 (qualifier survivor)
- Seed 17 (bye) vs Seed 48 (qualifier)
- Seed 16 (bye) vs Seed 49 (qualifier)
- ... etc

**Bottom half (right side):**
- Seed 2 (bye) vs Seed 63
- Seed 31 vs Seed 34
- ... etc

**Quadrant isolation:** Seeds 1 and 2 are in opposite halves. Seeds 1-4 are in separate
quarters. The #1 overall seed can only meet #2 in the Final, only meet #3 or #4 in the
Semifinals. This is the NCAA tournament structure.

### Edge Cases

- **Qualifier winner whose original seed was higher than expected** (e.g., an upset where
  seed 97 beats seed 40 in qualifying): They still get an effective seed of 33-64 based on
  their original seed rank among the 32 survivors. Their original high seed means they land
  closer to 64 (bottom of the effective range), which correctly puts them against a top bye
  holder — rewarding the bye holder's seed position.

- **Same-team protection still applies.** `avoidSameTeam` runs after `buildSeededRound`
  already did its own pass, so the engine's second pass catches any residual collisions
  created by the effective-seed reassignment. The swap is greedy and won't break quadrant
  structure meaningfully (it only swaps B-side entrants within their half).

- **Pool size 96** (1 qualifying round): Same logic. Q1 produces 32 winners, 32 bye holders
  enter at Round of 64, `buildSeededRound` places all 64.

- **Pool size 64** (no qualifying): Hits the classic ≤64 path (line 768+), which already uses
  `buildFirstRound` with `seedOrder`. No change needed.

### Testing

Add to `test/bracket.spec.ts`:

1. **Quadrant isolation test:** Build a 128-pool structure, simulate Q1 + Q2 → 32 winners,
   call the fixed Round of 64 builder, verify seed 1 and seed 2 are in opposite halves
   (their matchup slots are in different 16-slot ranges).

2. **Effective seed mapping:** Verify that 32 qualifier winners with original seeds 33-128
   get effective seeds 33-64 sorted by original seed (best qualifier survivor = seed 33,
   worst = seed 64).

3. **Same-team protection post-seeding:** Feed in entrants where seeds 1 and 64 are on the
   same team, confirm the swap moves seed 64 to a different matchup.

---

## Part 2: Rules / Onboarding Copy

### Structure

Single scrollable page, accessed from the Edition Intro screen ("How It Works" tap target).
Dark background (#1C1C1E), teal accents (Bracket Battle's identity color). Four steps, each
with one job. Points table below steps. CTA button. "Good to Know" section below the CTA.

### The Copy

---

**BRACKET BATTLE**

**128 players. One bracket. You call the winner.**

Every month, the full NWSL goes head-to-head in a community elimination bracket. A new
theme each edition — stats-based, creative, chaotic. Your job: predict who advances.

---

**Step 1 — See the matchups**

Each round shows you every head-to-head. Two players, one question. Read the theme and
decide: who wins this one?

**Step 2 — Vote the question, not the jersey**

This isn't "who's your favorite." If the theme is *Best Goal Celebration*, vote the better
celebration — even if the other player is on your team. The question is the question.

**Step 3 — Predict the crowd**

The community decides who advances. You score points when your pick matches the majority.
Think a lesser-known player actually wins the matchup? Trust that read — the crowd might
agree with you.

**Step 4 — Lock it in**

Submit your picks for the round. Once submitted, they're locked — no edits, no undo.
Results drop when voting closes, with vote percentages and your score.

---

**Points**

| Round | Per correct pick |
|---|---|
| Early rounds | 1 |
| Round of 16 & Quarterfinals | 2 |
| Semifinals & Final | 3 |

Climb the leaderboard. Track your accuracy in Your Stats.

---

**[ Let's Go ]**

---

**Good to Know**

- New edition every month with a fresh theme
- Top-seeded players get byes — they enter later in the bracket
- Miss a round? You can still play the rest (you just won't earn points for the ones you missed)
- No same-team matchups early — this is about the whole league

---

### Copy Decisions Explained

**"Vote the question, not the jersey"** replaces the earlier "this is not a popularity
contest" + "go with the crowd" messaging, which was contradictory. The new framing:

- Steps 2 AND 3 both hit the prediction twist, from different angles
- Step 2 = answer the actual question honestly (creative editions: who wins the stare-down?)
- Step 3 = your score depends on the crowd agreeing (so read the room too)
- Neither step tells you to ignore your opinion OR blindly follow popularity
- The tension between "answer honestly" and "predict the majority" IS the game — the copy
  surfaces it without resolving it, which is correct

**"The question is the question"** is the one-line version of the hotdog eating contest
analogy from our conversation — in a stare-down bracket, a player who cracks easily loses
regardless of how popular they are. The question has a real answer.

**No theme-specific copy in the rules.** The Edition Intro screen already shows the theme,
the question framing, and the bracket structure. The rules page teaches the game mechanic,
not the current theme. This keeps it reusable across editions without conditional copy.

**Scoring table simplified to three tiers.** The full 8-round breakdown (QR1, QR2, R64,
R32, R16, QF, SF, F) lives in a "?" expandable or the Bracket Overview screen. Onboarding
says "early / middle / late = 1 / 2 / 3" and moves on. Power users will find the detail.

**"Good to Know" is BELOW the CTA.** The player can start without reading it. Byes, missed
rounds, and same-team protection are FAQ material, not prerequisites. Putting them below
the CTA means curious players find them but casual players aren't blocked by fine print.

---

## Implementation Notes for Claude Code

### Seeding fix (nwslapp-proxy)

1. Open `src/bracket-engine.ts`, find the `if (poolSize > 64)` block (~line 750)
2. Add the `nextCode === 64` branch per the pseudocode above
3. The `entrantRows` variable (already in scope) has every entrant's `entrant_id`,
   `team_abbreviation`, and `seed` — that's all `buildSeededRound` needs
4. Add tests in `test/bracket.spec.ts`
5. Deploy to Cloudflare Workers after tests pass

### Rules copy (NWSLApp)

1. The rules screen is in `BracketBattleView.swift` (Edition Intro section)
2. Replace the current "How it works" copy with the Step 1-4 structure above
3. The points table can be a simple `VStack` with `DSText` — no need for a SwiftUI `Table`
4. "Good to Know" section below the CTA button, same dark card styling
5. Use `DSColor.dsGameBracket` (#30B0C7 teal) for accent elements (step numbers, CTA button)

### No active edition impact

The seeding fix only affects **future editions** (it changes how the Round of 64 is built
at tally time). The current "Who Would Win a Stare-Down?" edition is already in qualifying —
if it's past Q2, the Round of 64 matchups are already written. If it hasn't reached the
Round of 64 yet, deploying the fix before that tally will apply proper seeding to the
current edition. Either way, no data migration needed.
