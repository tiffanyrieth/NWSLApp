# Roster source research — ESPN vs the NWSL SDP API

> **Status (2026-07-30):** research COMPLETE, verified against live data (three real matches on
> 2026-07-29, including a weather suspension). **Decided:** live games stay on ESPN. **Open:** whether
> and how to use the NWSL SDP API for ROSTER IDENTITY (squad membership, position, jersey). The
> recommended design (§8) is invariants-first + cross-check, not migration. Every claim in this doc was
> verified by direct fetch on 2026-07-29/30 — nothing is schema-read or assumed. Related:
> `docs/roadmap.md` (🛡️ ESPN ROSTER RELIABILITY item), `Reference/Sessions/2026-07-29_live-games-logging-and-roster-sources.md`
> (gitignored session narrative with the raw timeline).

---

## 1. Why this research exists

ESPN is the app's most fragile dependency, and the roster specifically fails as
**wrong-but-plausible data served confidently, then self-healing** — not outages. ESPN covers a
million sports (mostly men's) and has no commercial incentive to fix NWSL data quickly; the league's
own feed covers one league and every incentive aligns. Observed failures, all real:

| Date | Failure | Class |
|---|---|---|
| ~2026-06 | **ACFC roster collapsed to 1 player for ~a week** after a KC transfer; self-healed at the next match | fabrication |
| ~2026-06 | **Spirit showed 5 goalkeepers** (correct count is 3); silently self-healed weeks later | fabrication |
| 2026-07 (3 wks) | **Trinity Rodman listed MIDFIELDER** (career forward); self-healed 2026-07-27 | fabrication |
| 2026-W31 | **Orlando silently dropped from a KHG edition** — ESPN returned an empty/stat-less roster for ~seconds; the fail-open assembler shipped a 15-team pool | fabrication |
| 2026-07-29 | **Two phantom Spirit players** — "Melissa Bethi" (no jersey) and "Monique Ngock" (#8) on ESPN's WAS roster (29 athletes); the official league squad has 27 and neither name | fabrication |
| ongoing | **Croix Bethune jersey** — ESPN #8 (correct, post-trade), official feed #7 (her career-long number, stale) | lagging fact |
| 2026-07-29 | **Ally Sentnor jersey missing** on ESPN (Angel City); official feed has #21 | missing value |

### The two error classes (the frame that shapes the whole design)

- **LAGGING FACT** — the value *was* true; reality moved; nobody keyed it in. **Bounded** (one
  transfer's worth of wrongness) and self-correcting. Bethune's #7 is this: she wore 7 her entire
  career, moved to KC where Elizabeth Ball has 7, took 8. Understandable, finite, forgivable.
- **FABRICATION** — the value was *never* true. **Unbounded**: nothing stops a roster becoming a
  different sport's roster tomorrow (a Google-surfaced NWSL roster once showed men from another
  sport). ESPN's failures above are almost all this class.

**Weight these differently.** Staleness has a ceiling on how wrong it can get; fabrication has none.
And they need **different tools** (§8): invariants catch fabrication with no second source;
cross-sourcing is only needed for staleness.

### Severity, ranked by what the field FEEDS (not how wrong it looks)

1. **Position** — worst. Drives Predict's band bonus, the Bracket's position-filtered pools, and
   whether KHG generates keeper-stat questions. Rodman-as-MID silently corrupted game logic in three
   places for three weeks. A flipped position passes every plausibility check that exists today.
2. **Squad membership** — breaks whole screens (ACFC→1) or invents people (Bethi). Loud, at least.
3. **Jersey** — display-only (pitch markers, roster rows). Annoying, harms nothing downstream.

---

## 2. The NWSL SDP API — everything verified

**Base:** `https://api-sdp.nwslsoccer.com/v1/nwsl/football`
**Auth:** none. No key, no signature. `access-control-allow-origin: *`, `GET, OPTIONS` — built for
public browser reads. Akamai-fronted. Response header `cache-control: private, max-age=86400`.
**Provider:** every record carries `providerId: opta:…` — this is the league's official Opta feed
(NWSL's data partner), i.e. the same upstream ESPN licenses, minus ESPN's entity-mapping layer. The
mapping layer is where ESPN's fabrications live (phantoms, flipped positions are classic re-ingest /
entity-join errors — which also explains the silent self-healing: a later re-ingest re-maps correctly).
**Already integrated:** the proxy's `src/headshots.ts` has consumed this API weekly for months (GUID
matching for player photos) — including a **normalized-name SDP↔ESPN join running at ~98%** with a
shortName/nickname secondary index. That join is a ready-made id bridge for any cross-check.

### Key identifiers (captured live — save these, they're stable)

- NWSL competition: `nwsl::Football_Competition::3293333447504e83986ec13e794b68ea`
- 2026 season: `nwsl::Football_Season::0b6761e4701749f593690c0f338da74c` (2026-03-14 → 2026-11-21;
  seasons exist back to 2013)
- Team GUIDs (from `/seasons/{s}/teams`, field `teamId`, joined to ESPN by `acronymName`):
  - WAS `nwsl::Football_Team::c31d72afc09f42ee86418633aa41390a`
  - LA (Angel City) `nwsl::Football_Team::9587b8ce40624165903b6bc9fd252634`
  - KC `nwsl::Football_Team::2c1699409ff84c9eb491aeaca3d3edde`
- ESPN team ids (from ESPN `/teams`, for the join): LA 21422 · BAY 22187 · BOS 131562 · CHI 15360 ·
  DEN 131563 · GFC 15364 · HOU 17346 · KC 20907 · NC 15366 · ORL 18206 · POR 15362 · LOU 20905 ·
  SD 21423 · SEA 15363 · UTA 19141 · WAS 15365

### Endpoint map (probed; 200 = live, 404/500 = dead)

| Endpoint | Status | Notes |
|---|---|---|
| `/competitions` | ✅ | 1,658 competitions (full Opta catalog — but see §5: only NWSL is licensed) |
| `/competitions/{id}/seasons` | ✅ | |
| `/seasons/{s}` | ✅ | |
| `/seasons/{s}/teams` | ✅ | teamId, acronymName, officialName, stadium, **official club socials, ticket/shop URLs** (app currently hardcodes socials in `TeamSocialLinksProvider.swift`). ⚠️ Team COLORS unverified — check before any directory swap |
| `/seasons/{s}/standings` | ✅ | stats incl. `form` (last-6 W/L/D objects), `movement` (up/down), `qualification` ("Final Series") — none of which ESPN provides (the app derives Last-5 client-side in `RecentForm`) |
| `/seasons/{s}/stats/teams` | ✅ | season-level team stats (NOT per-match) |
| `/seasons/{s}/matches` | ✅ | all 240; fields: matchId, status, providerStatus, phase, time, additionalTime, matchDateUtc + matchDateLocal + offset, stadiumName, cityName, `editorial.broadcasters` (name + URL), winReason, providerHome/AwayScore |
| `/seasons/{s}/matches/{m}/lineups` | ✅ | see below — the standout endpoint |
| `/seasons/{s}/stats/players?teamId={teamGuid}` | ✅ | **full squad in ONE page** (totalPages:1) incl. zero-minute players; also paginated league-wide (~30/page) without teamId |
| `/seasons/{s}/transfers` | ⚠️ | endpoint exists, returns `[]` — **not populated** for NWSL (2025 also empty). A transfer-log feature needs another source |
| `/seasons/{s}/matches/{m}/events`, `/commentary`, `/stats/players` (per-match) | ❌ 404 | no play-by-play, no per-match player stats |
| `/players`, `/seasons/{s}/players`, `/stadiums`, `/rounds`, `/matchsets`, injuries/suspensions | ❌ 404 | |

### The players payload (`stats/players?teamId=`)

Per player: `playerId` (GUID `nwsl::Football_Player::{32hex}` — same GUID the headshot map resolves),
`providerId` (opta), **`bibNumber`** (jersey, string), **`roleLabel`**
("Goalkeeper"/"Defender"/"Midfielder"/"Forward") + numeric `role` (1–4), `mediaFirstName`/`mediaLastName`,
`shortName` ("T. Rodman"), `shirtName`, `nationality`/`nationalityIsoCode`, `team{teamId,officialName}`,
and a **`stats` array of 171 entries**. Placeholder players exist with `isTeamFake: true` / team "TBC"
— **must be filtered**. Sampled squads: WAS 27/27 complete fields, LA 25/25, KC 30 (with one no-bib GK
and the stale Bethune #7 → a real duplicate-number violation, see §8).

### The lineups payload (`matches/{m}/lineups`) — the standout

`home`/`away`, each with **`fielded[11]`**, **`benched[~7-9]`**, `staff[]`. Per player: everything
above PLUS `isCaptain`, `isGoalkeeper`, **`tacticalXPosition`/`tacticalYPosition`** (0–1 normalized
formation coordinates — populated for all 22 starters; a real pitch layout instead of parsing a
formation string), `averageXPosition/Y` (**always null — see §5**), and **`events[]`**.

- **Publishes PRE-KICKOFF** (verified: 11 fielded + 7 benched at T−30min; empty at T−90min) — exactly
  the window the "Lineups in" push needs.
- **Event objects** (attached to the player they happened to):
  `{type, label, time, additionalTime, relatedPlayerId, phase}`. Types observed live: `goal`,
  `yellow-card`, `substitution-in`, `substitution-out`. For a goal, **`relatedPlayerId` = the
  ASSISTER** (verified against ESPN's participants on two assisted goals); an unassisted goal carries
  a placeholder GUID that resolves to no squad player, while cards use `relatedPlayerId: null` — a
  consumer must treat BOTH null and unresolvable as "none". Assist credit can be revised a few
  minutes after the goal (normal Opta behavior; the scorer — which player carries the event — never
  changed in observation).

### Live-state semantics (from a full evening of 30s polling, 3 matches, ~850 polls)

- `status`: `UPCOMING → LIVE → FINISHED`, with a dedicated **`SUSPENDED`** (better than ESPN's
  overloaded `post`). `phase`: `PRE_MATCH → FIRST_HALF → HALF_TIME_BREAK → SECOND_HALF → FULL_TIME`.
- ⚠️ **`phase` is buggy under suspension** — it reverted to `PRE_MATCH` while `time` stayed 27.
  Trust `status`, not `phase`, for suspension.
- **`time`** = true match minute (holds at 45 during the break, resumes at 46 — never resets).
- **`additionalTime`** = a live **elapsed-stoppage counter** (ticks ~1/min once `time` hits 45/90),
  NOT the fourth official's announced board. Verified on a normal match: 0→1→…→8 across the 90'+
  window, then a **post-match revision to the official figure** (8→13, ~2h after FT). On the
  suspended match it froze at 8 while the real stoppage ran +11.
- `winReason: "RegularTime"`, `winTeamId` on finished matches.

---

## 3. What SDP has that ESPN lacks (the gains, verified)

1. **Correct squads** — no phantoms; the exact rosters the league publishes.
2. **171 season stats/player vs ESPN's 106.** Real additions: **xG + xG efficiency**, big chances
   created/missed/scored, progressive carries, carries, duel splits (aerial/ground, won/lost), key
   passes, touches in opposition box, recoveries, final-third touches, left/right-foot goal splits.
   ⚠️ **xG is season-total-per-player ONLY** — no per-match team stats exist, so the natural home
   (home-vs-away xG comparison bars in Match Detail) is NOT reachable. The realistic home is
   `PlayerDetailView`'s stat sections. Owner's read: most of the 171 are analyst-grade and don't fit
   the app's bar-line stat design; not a migration driver by itself.
3. **Tactical formation coordinates** for all 22 starters (capability the app doesn't have).
4. **Standings `form` / `movement` / `qualification`** — would replace the client-side `RecentForm`
   derivation and add two new signals.
5. **Structured assists** on goals; **paired substitutions** (`relatedPlayerId` = the other player).
6. **`FINISHED` vs `SUSPENDED` as distinct statuses** (ESPN overloads `post` — though ESPN *does*
   disambiguate via `completed:false` + `name`, which the app/watcher now decode; see §6).
7. Official club socials/stadium/ticket URLs on the team record; seasons back to 2013.

## 4. What ESPN has that SDP lacks (why full migration is impossible)

- **National teams + Concacaf W Champions Cup.** The Opta catalog lists 1,658 competitions but the
  license is NWSL-scoped: **WAFCON `/matches` → HTTP 500**; NWSL Challenge Cup's newest season
  returns **1 match**. The 15 NT feeds + `concacaf.w.champions_cup` + `usa.nwsl.cup` stay ESPN,
  permanently. (Owner predicted exactly this.)
- **Play-by-play/commentary** (Match Detail PBP tab), **per-match team box score** (Stats tab:
  possession/shots/corners/etc.), **videos/highlights**, **attendance + officials** — all
  ESPN-`/summary`-only.
- **ESPN athlete ids are load-bearing app-wide**: Predict picks in Supabase key on them, the headshot
  map is `espnAthleteId → NWSL GUID`, `AthleteStatsCache` and every stats fetch key on them. Any
  SDP use must JOIN to ESPN ids (the headshots name-join is the bridge), never replace them.

## 5. Verified ABSENT despite appearing in the SDP schema (checked, not assumed)

- **Heat maps / average positions**: `averageXPosition/Y` = null for **0 of 78 players** across two
  finished matches. `pitchSizeX/Y` null.
- **Physical/tracking data**: total-distance, sprint counts, top/average speed — present as stat keys,
  **all zeros**. (Tracking is a separate, expensive Opta product; NWSL's license is event-data only.)
- **`/transfers`**: `[]` for 2026 (and 2025). The offseason transfer-log feature idea needs club
  announcements / league news / social instead (see the content-acquisition playbook).
- Per-match player stats, PBP, per-match team stats: endpoints 404.

## 6. Live games — SETTLED: stay on ESPN (2026-07-29, owner decision)

Full evening of side-by-side 30s polling (3 staggered kickoffs, 4 goals, HT, 2nd-half restart, FT,
one VAR disallowal, one weather suspension+resume):

| Event | Verdict |
|---|---|
| Kickoff ×3 | simultaneous (≤1s apart, same poll) |
| Goals ×4 | SDP +1s · ESPN +31s · tie · tie — **no systematic winner**; both within one 30s cycle |
| Halftime / 2nd-half restart | ESPN ~31s ahead both times |
| Full time (normal match) | **SDP 31s ahead** |
| Suspension | ESPN ~32s ahead |
| **Abnormal-match handling** | **SDP degraded worse**: `phase` → `PRE_MATCH` mid-suspension; closed the resumed match ~10–15 min AFTER ESPN; `additionalTime` froze |
| VAR disallowed goal | **identical in both**: score 0→1→0, the goal event **vanishes entirely** — no VAR/disallowed marker in either feed. Detection can only ever be inferential (score-decrease + debounce + re-poll), which is exactly what the watcher already does — no improvement available from switching |
| Status-name stability | ESPN flapped `STATUS_FIRST_HALF ↔ STATUS_IN_PROGRESS` ~8×/match (never key logic on status names); SDP `phase` rock-steady in normal play |

**The one live-path exception SDP could help with:** the **fabricated kickoff** (Orlando ~2026-07-10:
pre-kickoff lightning; ESPN auto-started the match ~30 min later with a STATIC placeholder minute; the
app's anchor climbed to 120'; healed only when ESPN keyed the new start time and went **`in → pre`** —
an impossible transition that proves the fabrication). SDP would have said `UPCOMING`. But the chosen
guard is single-source (roadmap 🕐 item): **don't tick until the feed clock is OBSERVED ADVANCING**
(generalizes `TickAnchor.freshAtCap`), plus **backwards-transition detection** (`post→in`, `in→pre` ⇒
prior state was wrong). Still unbuilt as of 2026-07-30.

**Also shipped from this research** (2026-07-30, both deployed): app-side `Event.isFinalResult` /
`isUnfinishedPost` + Predict grade-stamping/re-grading; watcher `isUnfinishedPost` at FT-detection,
LA-teardown, and fixture-index `ended` (the worst one — marking a suspended fixture `ended` stopped
polling and silently cost the real full-time push).

## 7. Legal posture (researched, owner-assessed)

Both providers' ToS forbid automated access: NWSL's Terms prohibit "any robot (bot), spider, scraper
or other unauthorized or automated means" with a personal, **non-commercial** license and
written-permission language; Disney/ESPN's prohibit automated access "**whether or not for profit**".
So switching does NOT improve the legal position — identical posture, and non-commercial use is not a
carve-out for either. Owner has weighed this (fandom-use precedent; deterrent language) and accepted
the risk — **it is not a decision factor**. The one asymmetry: NWSL's terms contemplate "express prior
written permission," so *asking the league* is possible in a way it never is with Disney — and NWSL
has every incentive to say yes to a free fan app. Worth considering if the dependency ever needs to be
load-bearing.

## 8. The recommended design (not yet built): invariants first, cross-check second

**"The official feed always wins" is WRONG — verified both ways:**

| Case | ESPN | SDP | Right | How it's detectable |
|---|---|---|---|---|
| Rodman position | Midfielder ❌ | Forward ✅ | SDP | cross-check only |
| Bethune jersey (KC) | #8 ✅ | #7 ❌ (stale) | **ESPN** | **invariant: SDP lists TWO #7s** (Ball + Bethune) — physically impossible |
| Sentnor jersey (LA) | missing ❌ | #21 ✅ | **SDP** | missing value |
| Bethi/Ngock membership | present ❌ | absent ✅ | SDP | cross-check (squad diff) |

### Layer 1 — INVARIANTS (build first; no second source; pure logic; unit-testable)

Catch **fabrication** from a single payload:
- **Unique shirt numbers within a squad** (would have flagged SDP's Bethune #7 dupe)
- **Position-group counts**: 0 GK impossible, 5 GK implausible (the real Spirit incident), ~15 in one
  band impossible
- **Plausible squad size** (existing `ROSTER_GOOD_MIN = 16` floor generalized; ~22–30 is normal)
- **A player on exactly one club** (league-wide sweep)

### Layer 2 — CROSS-CHECK (SDP as auditor, ESPN stays primary)

Catches **staleness** and squad diffs. Correction policy (owner-agreed):
1. **Auto-correct ONLY on a missing value or a violated invariant.** (Sentnor's blank jersey ← SDP
   #21; a duplicate-number side loses that field.)
2. **Both self-consistent but disagreeing → diag only, change NOTHING.** Never guess (a blanket
   "SDP wins" would have broken Bethune while fixing Rodman).
3. **Owner overrides KV** (`roster-truth:overrides`, mirroring `headshots:overrides`) adjudicates
   named cases — fronted by the planned **admin portal** (owner wants one portal merging the existing
   Bracket admin + KHG admin/paste + this; see roadmap).
4. **Fail-open everywhere**: SDP unreachable/changed ⇒ `/roster` behaves exactly as today.
5. Never drop, never inject players (no ESPN id ⇒ breaks Predict/headshots/stats). ESPN-only players
   get diag + optional inert `proxyUnverified: true` (Swift ignores unknown keys).

### Implementation sketch (from the planning pass; not started)

- New proxy module `src/roster-truth.ts`; KV snapshot **`sdp-squads-v1`** (single league-wide key,
  ~70KB, all 16 squads via 16 one-page fetches + 3 setup calls), refreshed by the existing weekly
  headshots cron + admin `POST /roster-truth/run` + lazy `ctx.waitUntil` when >24h stale; 30d TTL as
  the kill switch (delete the key ⇒ pure pass-through).
- Export the existing helpers from `headshots.ts` (`normalizeName`, `currentNwslSeasonId`,
  `fetchNwslTeamAbbrs`, `fetchEspnTeams`, `guidOf`, `SDP` const) — the join is already proven.
- Pure `correctRoster(espnBody, sdpSquad) → {body, report}` applied in `/roster` before serve AND
  before the last-known-good KV write (else a fix regresses exactly when ESPN wobbles); name-join
  team-scoped, ambiguity (duplicate normalized names) skips.
- ⚠️ **Route the raw-ESPN bypasses through it too**: `bracket-engine.ts fetchRoster` (feeds Bracket
  pools AND `knowher.ts computeEligiblePlayers`) hits ESPN directly today with NO guard at all — the
  Orlando KHG dropout went through that hole. The 2026-W31 empty-roster case also argues the KHG
  assembler should retry before shipping a short pool (separate roadmap note).
- Position mapping: `roleLabel` → ESPN `{name, displayName, abbreviation}` (G/D/M/F) — all three
  fields so `PositionGroup` banding + `isGoalkeeper` work unchanged; compare at GROUP level only
  (keep ESPN's richer "Attacking Midfielder" labels when the group agrees).
- Diags (sig-deduped against KV to respect the free-tier 1k writes/day): `rosterPosCorrected`,
  `rosterJerseyCorrected`, `rosterSquadMismatch`, `rosterInvariantViolation`, `rosterJoinAmbiguous`,
  `sdpSquadsRefreshFail`. Tests in the watcher's `node --test` style (workerd broken on local Node
  26); fixtures = the four real specimens above. Extend `health_check_roster.mjs` to warn (not fail)
  on a stale snapshot.
- **Name-join hazards (real, observed):** ESPN "Tamara Bolt" = SDP "Tamara Paranaguá do Carmo"
  (same #16 FWD, different name form) — an unmatched pair on the same team is the signature of a name
  variance, NOT a phantom; diag-only, adjudicate via overrides.

## 9. Open questions / not yet verified

- SDP team **colors** (app leans on ESPN `color`/`alternateColor` for the whole team-tint system).
- SDP squad completeness across all 16 clubs (spot-checked WAS/LA/KC only).
- Rate limits / abuse thresholds (none hit during a full evening of 30s polling + bursts).
- Whether SDP's stale-jersey lag (Bethune) self-corrects and on what timescale.
- `red-card` event type in the lineups feed — never observed live yet (only goal / yellow-card /
  substitution-in/out confirmed). Shape almost certainly matches.
- SDP GUIDs are already the headshot-map values — reuse as the stable join, but the ~2% name-join
  misses need the overrides path before any correction (not display) use.
