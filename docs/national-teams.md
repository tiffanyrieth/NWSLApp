# National teams — how the system works

The reference for everything women's-international: how ~200 followable countries map onto ESPN's
~16 competition feeds, which component polls what (and when), and what to touch when adding a
country or a competition. Written 2026-07-16 alongside the fixture-window/confederation polling fix.

## 0. ⭐ WHY national teams exist — and what tier they occupy (owner, 2026-07-31)

**Read this before deciding whether any new feature should extend to national teams. The default
answer is NO, and that is a product decision, not a resourcing one.**

**This is an NWSL app first and foremost, above everything else.** National teams are here because of
who NWSL fans actually are — the fanbase comes from every background: people born here, people who
immigrated here, and people abroad who found the league through a player. The owner's example: someone
in Zambia who grew up watching **Barbra Banda** and now wants to follow the Orlando Pride *and* Zambia's
national team. This app lets her do both, in one place. That is the whole reason the NT side exists.

**But "supported" is not "feature-matched."** Precisely what a followed country DOES get
(owner-specified 2026-07-31):
- its fixtures in **My Calendar**, alongside club matches
- the **lineup on match day** when it's announced
- the **score**, updating live as the match progresses
- **goal + match alerts**

And what it deliberately does NOT get:
- ⚠️ **No team page at all — and this is STRUCTURAL, not a missing link.** There is no
  `NationalTeamView` in the codebase; a national-team card is not tappable because the destination
  was never built. **This is intentional — do not "fix" it with a `NavigationLink`.** Club cards go to
  `TeamDetailView`; countries have no equivalent, *including the USWNT*.
- therefore **no roster page and no per-player stats** for any country.
- no Fan Zone games, no roster identity verification, no Match Detail enrichment, and (the case that
  prompted writing this) **no weather radar during a delay**.

**The owner's reason, verbatim in substance: "just too much data to monitor, and my focus is NWSL."**
Roster + stats for ~100 countries is a second app's worth of surface area, monitoring and failure
modes — for the *secondary* half of the product.

⚠️ **The followable-country count is DYNAMIC — never pin a number.** The curated grid is 16
(`NationalTeam.all`); Browse-all is data-driven from proxy `/national-teams` (the union of every
feed's `/teams`), which returned **106** on 2026-07-31 and moves with ESPN's coverage. Earlier drafts
of this doc said "~200"; that was wrong. Say "~100, data-driven" and let the endpoint be the truth.

**Practical decision rule for a new feature:** if it deepens the *club* experience, build it NWSL-only
and don't apologise for the asymmetry. If it is core scheduling/scores/alerts, it must cover NT too.
When unsure, ask — don't quietly build parity, and don't quietly drop NT from something core.
(This also keeps the cost side honest: NT polling is already the most expensive fan-out in the
app, which is why §3's confederation scoping exists.)

## 1. The core shape: countries ≠ feeds

- The app lets users follow **countries** (FIFA code — "USA", "ZAM"). The curated grid is 16 teams
  (`NationalTeam.all`), but Browse-all is **data-driven** from the proxy `/national-teams` (the union
  of every feed's `/teams`), so any country ESPN covers can be followed.
- ESPN organizes women's international soccer as **competition scoreboards** (~16 feeds), NOT
  per-country schedules: friendlies, World Cup, Olympics, plus each confederation's championship and
  qualifying. One feed carries many countries; a country appears across several feeds.
- **⚠️ The load-bearing ESPN quirk:** the per-team schedule endpoint (`all/teams/{id}/schedule`) is
  **HISTORY-only** — a followed country's UPCOMING fixtures exist ONLY in these competition
  scoreboards. That's why display and alerts must both ride the same feed list, and why a feed
  missing from any of the three slug lists (§4) silently loses both fixtures and alerts for it.

## 2. Confederations + feed scoping (the app's fetch rule)

FIFA's six confederations partition the countries; a country can only ever appear in:

- **Global feeds (fetched for every NT follower):** `fifa.friendly.w` (also where invitationals like
  the SheBelieves Cup field cross-confederation teams), `fifa.shebelieves`, `fifa.wwc`,
  `fifa.w.olympics`, `fifa.wwcq.ply` (inter-confederation playoff), `global.pinatar_cup`.
- **Its own confederation's feeds:** UEFA → `uefa.weuro` + `uefa.w.nations` + `fifa.wworldq.uefa`;
  Concacaf → `concacaf.w.gold` + `concacaf.womens.championship` + `fifa.w.concacaf.olympicsq`;
  CAF → `caf.w.nations` (WAFCON); AFC → `afc.w.asian.cup`; CONMEBOL → `conmebol.america.femenina`;
  OFC → no ESPN feed today (globals only).

`Models/ConfederationMap.swift` holds the full FIFA-membership map + the feed `scope` tags +
`NationalTeamFeed.scopedFeeds(forFollowedCodes:)`. Worked example (owner's, 2026-07-16): following
**ZAM** fetches the 6 globals + `caf.w.nations` = **7 feeds** — covering Zambia's WAFCON games
(EGY/NGA/MWI) and friendlies (CAN/BRA/NOR) — instead of the old all-15 fan-out that polled the
UEFA Euro for a Zambia fan every 30 seconds.

**Fail-open rule (NO SILENT FAILURES):** an unmapped country code → ALL feeds + a Diagnostics
breadcrumb (`NT confederation map miss`); an untagged future slug → `.global` (polled for everyone).
Efficiency may degrade to the old cost; a fixture is never silently missed.

## 3. Who polls what, when

| Component | What it polls | Cadence |
|---|---|---|
| **App — season load** (`MatchStore.load`) | NWSL season + scoped NT feeds (full-year window) | launch / follows change |
| **App — live heartbeat** (`RootTabView` → `performWindowedRefresh`) | same scoped set, 3-day window | 30s when a match is live, 5 min otherwise, foreground only |
| **Watcher — discovery** (`src/fixtures.ts`) | ALL feeds once → KV fixture index | every ~6h (~64 fetches/day) |
| **Watcher — per-minute tick** | ONLY feeds with a fixture in `[KO−75m … KO+4h]` (window closes at observed FT); zero fixtures near ⇒ zero fetches | every minute (+30s double-poll in live windows) |

The watcher's alert coverage is deliberately **unscoped by follows** (it must detect events for
*any* user's followed country — per-user scoping happens at the fan-out lookup), so its lever is
the **fixture window**, not the confederation map. The app's lever is the **confederation scope**,
because each installed app polls on behalf of one user's follows.

Known, accepted trade-off (owner 2026-07-16): a fixture announced **<6h before kickoff** waits for
the watcher's next discovery pass (alerts only — the app's schedule still shows it on next launch).
Fixtures are announced weeks out; if it ever happens, the watcher logs
`DIAG missed-window LIVE match at discovery` rather than staying silent.

## 4. The three synced slug lists (keep identical)

| Repo | Constant |
|---|---|
| App | `NationalTeamFeed.all` (`Models/Competition.swift`) |
| Proxy | `WOMENS_NT_FEEDS` + the `?league=` allowlist |
| Watcher | `NT_LEAGUES` (`src/index.ts`) |

Adding a feed to one list but not the others = fixtures without alerts (or vice-versa). §1's quirk
makes this the alignment that matters most.

## 5. Maintenance recipes

- **New followable country:** one code in its confederation's list in `ConfederationMap.byCode`
  (+ optionally the curated `NationalTeam.all` entry for a flag/color). The completeness unit test
  (`ConfederationMapTests.everyCuratedCountryMaps`) guards curated entries; data-driven codes are
  covered by the fail-open path until mapped.
- **New competition feed:** add to ALL THREE slug lists (§4) **and** tag its `scope` in
  `ConfederationMap.swift` (untagged = global = polled for everyone — safe but unscoped). No watcher
  change needed beyond the list: discovery indexes any listed feed automatically.
- **Confederation change (rare):** move the code between lists; nothing else.
- **V1 alerts** fan out by FIFA code → `competition_alert_preferences` ("nt:ZAM"); **V2 Live
  Activities are USWNT-only** today (`USWNT_CODE` in the watcher) — extending is a config change.

## 6. Cost model (why this shape — see stress-testing §7 for the ledger)

- Watcher baseline: was 16 feeds × 1440 min ≈ **23,040 proxy invocations/day at zero users** (~23%
  of the Workers-free 100k/day cap); now ~64/day discovery + per-match windows (~1.5–3k on a
  matchday).
- App worst case: was ~17 calls/tick for any NT follower (~2,040/hr live); now ~7-8 for a
  single-confederation follower. Club-only followers were always cheap (2-3/tick — per-competition,
  not per-team) and are unchanged.
