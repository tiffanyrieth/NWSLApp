# Stress Testing & Launch-Readiness Charter

> Read this **before** any "is the app ready to publish?" / scaling / infrastructure-sizing work. It
> sets the mental model, the two tests, and the method. It is deliberately **app-specific** — general
> "best practices" get filtered through *these* constraints. When a subsystem is examined, record the
> result in §7.

---

## 0. Who this app actually is (calibration — read first)

Not an enterprise with a team; not a 10-download toy. A **solo indie developer** shipping a **free**
women's-soccer fandom app whose **only revenue is a tip jar**. The two default assumptions coding tools
make are *both* wrong, and both are expensive:

- **"Enterprise" failure** — proposing infra with fixed monthly cost, a heavy SDK, or a big ops surface
  "to be safe." The owner cannot run that on tip-jar money, and it adds maintenance the owner carries
  alone. (The pre-0.1 "hard limits" in CLAUDE.md came from over-correcting toward this.)
- **"Toy" failure** — sizing for *current* usage (owner + one tester) because the app isn't published
  yet. At launch this is **not** a 10-download app. It should be sized for **~1k active users within
  the first few months** and architected to reach **100k over years**.
  **⚠️ THE BANNED LENS (made explicit 2026-07-16 after it produced two wrong calls in one day):**
  never reason from "we only have N users right now, so…" — not to defer, not to skip, not to
  soft-pedal. EVERY load/reliability question is asked **as if the app ships to the App Store
  tomorrow** (the launch scenario: hundreds of one-club fans arriving from a single subreddit post).
  "Only 2 users → plenty of headroom" and "only 2 users → alerting can wait until launch" are the
  SAME mistake; both were made and both reversed on the publish-tomorrow test (the watcher was
  burning 23% of the request cap at zero users; error alerting turned out launch-gated because every
  existing channel is pull and the 7/15 CPU burst was found a day late). The ONLY valid reasons to
  defer are: the 1k test PASSES, or the lever is a reversible config knob — never today's user count.
- The owner is the **decision-maker on product/cost trade-offs.** Present the menu + real numbers with
  a recommendation; never silently pick the enterprise option or quietly under-size.

## 1. The cost reality (the governing constraint)

Free app, tip-jar only. Worked example at the launch target: 1k users, ~2% donate $10 = **$200/yr**;
Apple Dev Program takes **$99/yr** → **~$100/yr of real headroom.** Consequences:

- A fixed monthly charge that triggers at the ~51st user is **disqualifying at launch scale.**
- Paid infra is acceptable **only far out**, when donation volume actually justifies it (≈tens of
  thousands of users and up) — as a **bridge to a bigger tier**, never as the day-one plan.
- **Prefer flat tiers over metered billing.** A flat tier's worst failure mode is throttling; a metered
  service's worst failure mode is a surprise bill from a bug or a viral day. For an indie, "no invoice
  can ever spike" is worth more than a slightly lower nominal price.
- **Cost is a pass/fail axis**, alongside the two tests below — not a footnote.

Revenue vs. cost stays in the black at every stage (2% × $10 donation model, incl. $99/yr Apple):

| Users | Tips in /yr | Infra + Apple /yr | Net /yr |
|---|---|---|---|
| 1k | ~$200 | ~$99 | **+~$100** |
| 10k | ~$2,000 | ~$99 | **+~$1,900** |
| ~15k | ~$3,000 | ~$159 (first CF $5/mo) | **+~$2,840** |
| 100k | ~$20,000 | ~$459 (~$30/mo) | **+~$19,540** |

The gap widens with growth and never closes — costs step up in small flat jumps while revenue climbs
continuously. At 100k, infra is ~2% of donations.

## 2. The two tests (distinct — do not conflate)

**Test 1 — SCALE (mandatory at launch): 1,000 active users.**
This is *sizing*, not scalability. If the app breaks when a few hundred fans of one club enable alerts,
it was **improperly sized for the day it shipped** — a launch blocker, not a "someday" problem.
Canonical failure: publish into a club subreddit (e.g. Washington Spirit, ~7.7k weekly), several
hundred install + enable that club's alerts, the club scores → only ~50 get pushed, the rest get
nothing → "this app is broken" as a first impression, in front of the exact audience being courted.
**The app MUST pass 1k before publishing.**

**Test 2 — SCALABILITY (headroom): 100,000 users.**
Not the same as sizing for launch. Scalability = the lever **exists and is ready**, but organic growth
reaches for it over **months/years**, not week one. **If you have to pull a scalability lever in the
first weeks, that wasn't scalability — it was under-sizing showing up late.**

Server analogy (the owner's, and the canonical mental model): you have 400GB of data.
- a **250GB** drive can't even hold it → **today's under-sized design**;
- a **512GB** drive fits with **zero breathing room**;
- a **1TB** drive = **breathing room** (absorbs organic growth without a fire drill);
- **empty expansion slots** = **true scalability** (add capacity as you grow, not overnight).

## 3. Efficiency first, scalability second (never scale to cover waste)

Before adding any scaling lever, ask: **is the current approach wasteful or naive in a way a
best-practice pattern fixes for free?**

Proof case — the watcher KV write-guard: the watcher wrote KV **every 60s tick** (~1,440 writes/day
against a 1,000/day free cap). The tempting "fix" was to accept the near-limit and burn a scalability
option in the first weeks. But those writes were **waste, not load** — 1,439/day changed nothing.
Gating writes on **actual status change** cut it ~10x; the scalability lever is now unused, waiting for
real growth. Rule: **stop writing garbage before you buy a bigger drive.** (This is also almost
certainly the best-practice pattern — a sports watcher is a diff engine; persist state *transitions*,
not unchanged snapshots.)

## 4. Three bars, not one

"**Works today**" ≠ "**properly sized**" ≠ "**efficient / best-practice**." The app can work for 2 users
and still be mis-sized, wasteful, and non-standard. A stress test clears **all three**, in order:
1. is it wasteful/naive → fix for free (§3);
2. is the *properly-sized* version OK at 1k (mandatory, §2 Test 1);
3. is there a ready lever for 100k (headroom, §2 Test 2).

## 5. How to stress-test a subsystem (the method)

For each subsystem, walk it explicitly:

1. **Identify the unit of load** and what it scales with — users? followers-per-team? concurrent
   matches? match-events? requests/min? Different axes are easy to confuse: the watcher's *write* volume
   scales with **matches**; the push *fan-out* scales with **followers/team**. A fix on one axis (the
   write-guard) does nothing for the other (fan-out).
2. **Find the hard ceiling** on the free tier — subrequests/invocation, writes/day, rate limits, APNs
   pacing, KV/DB size + egress, iOS pending-notification caps, etc. **Verify against current primary
   docs** — never reason from an unverified remembered number (limits change; e.g. Cloudflare Queues
   went free 2026-02-04 and the subrequest budget was restructured 2026-02-11).
3. **Plug in 1k and 100k** and compute where it breaks — including the realistic *concentrated* pattern
   (100 users all on one team on launch weekend), not just a uniform spread. Worst-case is the correct
   sizing basis.
4. **Efficiency pass first** — is there waste inflating the number? Fix it before adding infra (§3).
5. **Then size** — does the correct version pass 1k? If no → launch blocker, must fix now.
6. **Then headroom** — is there a ready, $0-at-small-scale lever to 100k? Document it; don't build it
   prematurely.
7. **Cost check** — does any option add fixed monthly cost at small scale, or (worse) metered billing?
   If yes, it's a bridge, not the plan (§1).
8. **Failure-mode honesty** — how does it fail *at* the ceiling? Cleanly degrade, or silently drop /
   duplicate / corrupt state? (Ties to the app-wide **NO SILENT FAILURES** rule. The fan-out's
   duplicate-refire-on-mid-loop-death was a §8 failure caught this way.)

## 6. Subsystems to stress-test before publish (living checklist)

- [x] **Push fan-out (APNs)** — the known launch blocker. Scales with followers/team. **DECIDED &
      specced** → see `docs/push-fanout-scaling.md` (V1 = Cloudflare Queues, V2 = APNs Broadcast
      Channels). BUILT + deployed + device-proven 2026-07-09.
- [x] **Watcher KV writes** — fixed (write-on-change). Re-confirm under many concurrent matches
      (international windows): ~10 writes/match × ~30 matches ≈ 300/day, under the 1,000/day cap.
- [ ] **Watcher subrequests per tick** — feed polls vs the 50-*external* cap. Note the 2026-02-11 split:
      proxy service-binding calls are now *internal* (1,000 budget), so ~16 feed polls no longer compete
      with APNs. Re-confirm Supabase REST (external) + APNs counts under worst-case simultaneous events.
      NB (2026-07-11): during a live window the tick **double-polls** (30s cadence) → the scoreboard feed
      fetches run twice; still internal (proxy binding), so no pressure on the external cap.
- [x] **ESPN / proxy rate limits & Cloudflare account-wide request cap** — **EXAMINED + FIXED
      2026-07-16 (the "requests cap" pass — APNs-class finding).** Free = 100k requests/day and **a
      cache HIT still invokes the Worker** (caching is `caches.default` INSIDE the fetch handler), so
      polling scales requests linearly regardless of hit rate. Found: watcher polled 16 feeds/min
      24/7 (≈23k/day at ZERO users, ~23% of the cap — the owner's ~28k/day Observability graph); any
      NT-follower app fanned to all 15 feeds/tick (~17 calls/30s live → cap-day at a few dozen
      country-followers; club watchers ~700). Fixed: watcher fixture-window polling (§7) + app
      confederation scoping (§7). Residual open item: model a FULL-SLATE matchday (6-7 NWSL games)
      against the per-user costs in the §7 ledger before launch.
- [x] **Nightly roster verification (`roster-truth`, shipped 2026-07-31)** — ✅ **passes 1k and 100k
      unchanged: the load is FIXED, not per-user.** One cron run/night: ~36 upstream fetches + ~5 KV
      ops + **one** batched diag write, regardless of whether the app has 2 users or 100,000. Adds
      ~30 Worker requests/day against the 100k/day free cap (~0.03%). The per-user path is untouched —
      `/roster` gains a single KV read for overrides, absorbed by the existing 6h edge cache.
      ⚠️ **The binding constraint is per-invocation, not per-day:** the free plan allows 50
      subrequests and KV ops count, so the run budgets ~39. That is why it does **no retries** and
      batches diags into one write; adding either would silently start failing runs. A 17th club
      would cost 2 more (~41) — still fine, but the margin is the thing to watch on expansion.
- [x] **Matchday jersey source (`resolveJerseysFromMatchday`, shipped 2026-08-03)** — ✅ **passes 1k
      and 100k unchanged: per-LEAGUE load, not per-user.** Runs inside the SAME nightly cron
      invocation, so it spends from that run's budget rather than adding one. **Zero subrequests on a
      night with nothing pending** (the normal case); otherwise 1 scoreboard + summaries newest-first,
      stopping the moment every open question is answered — both live 2026-08-03 specimens took 2.
      ⚠️ **The cap is the budget, and it is tight.** The verification run already spends ~39 of the
      free plan's 50 per-invocation subrequests, so the ceiling is 50 − 39 − 1 = 10; taking all 10
      would sit exactly ON the limit, where one extra KV op fails the whole run. Capped at **6** for
      margin. Raising it, or adding a 17th club, means redoing that arithmetic FIRST.
      No user request touches this path; failure is best-effort and degrades to the weekly routine.
- [ ] ⚠️ **Team-page athlete-stats burst (CLIENT→ESPN DIRECT, never stress-tested)** — found
      2026-07-30. `TeamDetailViewModel.load` fetches the roster and then fans out **one ESPN Core-API
      call PER ATHLETE (~25–30) in parallel, straight from the device** — no proxy, no edge cache, no
      last-known-good, no cross-user dedupe. `AthleteStatsCache` is in-memory + session-scoped, so a
      relaunch refetches all of it. **The trigger is opening a team page, NOT tapping a player** (the
      team-leaders board is derived from the whole squad's stat lines) — so the common "who is Portland's
      #7" gameday glance pays the full burst, and app-side lazy-loading canNOT fix it.
      **1k sizing:** ~800 team-page opens ⇒ **~21.6k direct ESPN calls/day**, bunched around matches;
      ~27 per residential IP, so a global block is unlikely — the realistic failure is **per-device burst
      throttling**, which degrades to a stats card with players silently missing rows (a no-silent-failures
      smell). At 100k: ~2.1M/day.
      **Fix (deferred by owner 2026-07-30, rosters prioritised):** a BUNDLED `/team-stats?team={id}`
      proxy route — whole squad in one edge-cached response, ~27 requests → 1, shared across all users
      (~800 Worker req/day instead of 21.6k). ⚠️ Naively proxying the existing 27-call fan-out would burn
      **~22% of the free 100k/day cap at 1k users** — the same trap as the watcher-polling finding above.
      Build needs Queues (16 clubs × ~28 athletes ≈ 450 calls exceeds the 50-subrequest budget per tick).
- [~] **Supabase** — DB size, monthly egress, auth MAU, connection limits, RLS query cost;
      `device_tokens` / `*_preferences` read volume per tick. Likely the *second* paid lever (~Pro tier)
      around ~30–50k users. **Verify current free-tier + Pro numbers against primary docs.**
      **[x] DB SIZE + egress modelled 2026-07-24 (§7): free 500 MB HOLDS at 15k/7k (~170-280 MB year-1);
      first wall ≈ year 3-4 record-book accumulation → Pro $25/mo; archival lever noted.** Still open:
      connection limits + `device_tokens`/`*_preferences` per-tick read volume at watcher scale.
      - **[x] Fan Zone leaderboard reads — FIXED.** Bracket/Predict/Trivia boards fetched the whole scored
        set (no `.limit()`) and rendered eagerly — a 1k-scale global board = thousands of rows → hang +
        multi-MB fetch. Now capped at `LeaderboardRanking.visibleLimit` (top-100) + a COUNT-based true rank,
        so a board is O(100) regardless of scale. Passes the 1k gate. (Open headroom, not a 1k blocker:
        `quiz_answers` grows unbounded — materialize each closed edition's aggregate + prune when it matters.)
      - **[x] Superfan Zone (`superfan_scores`) — PASSES 1k.** ONE row per user per season (PK
        (user_id, season)); a detail-screen open does exactly **1 upsert + 2 `count: .exact, head: true`
        reads** (zero rows transferred — the tier/percentile is a HEAD count, never a table scan) + 1 tiny
        own-row select. No per-tick load (opened on demand, not polled), no fan-out, no leaderboard render
        (the client shows only the count, not a rows list). Same read shape as the Predict/Bracket boards,
        which already pass 1k. **100k lever:** the two count queries ride the same pattern as the existing
        boards — no new bottleneck; the season-partition PK keeps each count scoped to the current year.
      - **[ ] Bracket tally's own reads — UNBOUNDED, pre-existing.** `accumulateScores` /
        `accumulateUserStats` / `stampFinalRanks` each `select` EVERY row for the edition with no
        `.limit()` (`bracket_scores?edition_id=eq.…`, `bracket_user_edition_stats?…`). That's one row per
        PLAYER, so a 100k-player edition pulls 100k rows into a Worker on a round close — inside the CPU/
        memory budget of a cron tick. Not a 1k blocker (1k rows is trivial) and NOT introduced by the
        2026-07-22 display_name change (which is chunked); logged here so it isn't rediscovered as a
        surprise. Fix when it matters: paginate, or move the accumulate to a Postgres function.
- [ ] **APNs pacing / connection reuse** — HTTP/2 throughput of raw sends at hundreds/batch (relevant to
      the Queues consumer's per-invocation batch size).
- [ ] **iOS local-notification 64 pending cap** — day-before is already windowed to the next 2 fixtures
      per alerting team; re-verify at many multi-team follows.
- [ ] **Live Activity update volume** — per-match push cadence × concurrent Activities. Broadcast
      channels make this flat per match; re-check Apple's (undocumented) broadcast throttle in practice.
      ⚠️ Now especially relevant: the stoppage `+N` clock broadcasts EACH MINUTE in added time (2026-07-11)
      — device-verify that iOS doesn't throttle a ~1/min broadcast cadence (build 26, fake-match harness).
- [ ] (expand as subsystems are examined)

- [x] **Predict the XI community aggregate + `/predict/community`** — PASSES 1k (2026-07-28). Flat-in-user-count
      counter table; the only per-user growth is a 28-day-pruned dedupe mark. See §7.

## 7. Status ledger

- **Predict the XI community aggregate + results redesign (2026-07-28): ✅ passes 1k; 100k needs only
  the pre-existing levers.**
  **Units of load — four, easy to conflate:** (a) aggregate WRITES scale with *submissions*, one
  idempotent RPC each; (b) season-best merges scale with *scored matches per user*; (c) `/predict/community`
  ORIGIN work scales with *fixtures × TTL buckets*, edge-collapsed across every reader of a match;
  (d) `/predict/community` REQUEST count scales with *screen opens* — ⚠️ this is the axis that matters,
  because a cache HIT still counts as a Worker invocation, so it stays user-linear even though the
  origin work does not. Plus DB size, which is dominated by one table only (see below).
  **Efficiency pass first (before any sizing):** the route is BATCHED by fixture from day one (a
  multi-club round is one request, capped at 6) — cheap now, an ugly retrofit later; the round rollup
  fetches NO community data, only the per-match screen does; a sealed fixture calls a count-only RPC
  rather than the distribution; the kickoff lookup rides the worker's own cached `/summary` and adds
  zero ESPN load; drafts are never uploaded.
  **1k, concentrated (a Saturday, 300 one-club fans):** ~300 submit RPCs and ~300–600 result opens ⇒
  **≲1.5k Worker requests on the worst matchday**, against a 100k/day cap already carrying the existing
  fixed traffic. Writes land on Supabase's unlimited-request tier. **PASSES.**
  **Size:** `predict_pick_counts` is **flat in user count** — squad × slots × matches, ~150 rows/match,
  ~27k rows/season whether 100 people play or 100,000. The only per-user growth is
  `predict_submission_marks` (one row per user per match), ~12k rows live at 1k users on the 28-day
  window; `predict_season_bests` is one tiny row per user per season. All three pruned by pg_cron.
  **100k lever:** Workers Paid ($5/mo) — the already-documented expansion slot, nothing new invented.
  A second, cheaper lever exists if ever needed: materialize each closed fixture's distribution into a
  userless row on first post-close read so the RPC runs once per fixture forever. Documented, NOT built.
  **Cost:** $0 new at small scale, no metered service, no new dependency.
  **Failure modes (NO SILENT FAILURES):** an unresolvable kickoff ⇒ the route SEALS (fails closed) and
  emits `predictCommunityNoKickoff` — failing open would leak the crowd's XI before the deadline, the
  one thing the gate exists to prevent; a failed distribution read ⇒ the app hides every community
  section rather than rendering 0% as fact; a failed submit RPC ⇒ the local submit stands untouched and
  a `Diagnostics.apiFailure` fires; a repeat RPC ⇒ a server-side no-op, never a double count. Gated by
  `health_check_predict_community.mjs`, which fails the deploy if a pre-close fixture ever ships picks.

- **Bracket `display_name` stamp (2026-07-22): ✅ passes 1k + 100k by construction.** One new READ path
  in the tally (`accumulateScores` → `profiles?id=in.(…)&select=id,display_name`), added because nothing
  had EVER written `bracket_scores.display_name`, so every rival rendered as the `?? "Fan"` fallback.
  Chunked at 200 ids (`PROFILE_LOOKUP_CHUNK`) — the filter travels in the URL, so the unchunked version
  would have been an unbounded URL and a hard failure at exactly the scale we're sizing for. Frequency
  is **per edition-round, not per user request**: it runs inside the 5-min cron tick only when a round
  actually closes. 1k voters ⇒ 5 chunked selects per round; 100k ⇒ 500, still bounded, still off the
  user-facing path, against Supabase's unlimited-API-request tier. No lever needed. NOTE the pre-existing
  unbounded `bracket_scores?edition_id=eq.…` select in the same function is untouched by this change —
  logged in §6 as its own item rather than silently widened here.

- **Pre-launch seed population (2026-07-22): not a production load path.** `seed_test_fans.mjs` is an
  operator script, never invoked by the app or a cron, and the accounts it creates are purged before
  launch (guarded by `health_check_seed_accounts.mjs`). It DOES exercise the real read paths at ~120
  users, which is the first time the top-100 cap, the below-fold rank splice and the community
  aggregates have run against a non-trivial field — a cheap partial rehearsal of the 1k test, not a
  substitute for it.

- **Alert-type reinstall restore (2026-07-22): ✅ passes 1k + 100k by construction.** (Still shipped — TYPES restore; the per-team BELL restore was removed 2026-08-03 and only ever cost fewer reads.) One new READ
  path: a single-row `select` on `notification_preferences`, gated on a device that has never made a
  notification choice — so it fires **once per install per identity**, not per launch and not per
  foreground (`NotificationSyncCoordinator.needsRestore`). A failed fetch retries on the next
  foreground but is still bounded by that same gate. 1k: ≤1k one-time single-row selects, against
  Supabase's unlimited-API-requests tier; adds no rows and no egress of note. 100k: identical shape,
  linear in installs, no lever needed. The companion team-alert reconcile retry (follows arriving
  after a restored session) reuses the existing per-identity reconcile — bounded to one extra run.

- **Fan Zone v3 (rounds/retention/restore, 2026-07-23): ✅ passes 1k + 100k by construction.**
  Verified first against primary docs (supabase.com/pricing): Supabase has **UNLIMITED API requests**
  on every tier — the binding constraints are **DB size (free 500 MB / Pro 8 GB), MAU (50k/100k),
  egress (5/250 GB)**, the OPPOSITE shape of Workers (where request count is the cap). New load paths:
  • `fanzone_progress` — 1 row/(user,season) ≈150 B ⇒ ~20 MB at 100k; writes = 1 partial upsert per
    quiz completion + 1 fetch/merge per sign-in. Flat, unmetered.
  • `predict_round_scores` — users × followed-clubs × 2 retained weeks (cron prunes >28d) ⇒ ~a few
    thousand rows at 1k users, bounded forever. Round boards reuse the top-100 + HEAD-count-rank
    pattern that already passed 1k.
  • **Retention crons run INSIDE Postgres (pg_cron)** — zero Worker requests, zero API calls; and they
    CAP `quiz_answers`, the one table §6 flagged unbounded (~85 MB/season at 1k engaged under weekly
    cadence): with the 35-day prune it plateaus at a few MB regardless of season length. The prune is
    safe because restore reads the SUMMARY row, never raw answers.
  • Bracket close adds two service-role calls per EDITION (rank stamp + old-vote delete) — per-edition,
    not per-user; noise.
  100k lever: all of the above scale linearly in rows, none in request rate; first paid wall stays the
  ~30–50k-user Supabase Pro size/MAU line already forecast in §6.
- **Push fan-out:** ✅ **DECIDED 2026-07-09** (4-agent primary-doc research). V1 buzz + LA push-to-start
  → Cloudflare Queues fan-out ($0, free since 2026-02-04). V2 in-match updates → APNs Broadcast
  Channels (channel-per-match, one POST/event). Firebase declined. iOS 17 = graceful degradation (V1
  only, no Live Activities). Workers Paid $5/mo = the documented expansion slot at ~10–15k users. Full
  spec + cost curve in `docs/push-fanout-scaling.md`. **BUILT + deployed 2026-07-09** (fan-out redesign +
  Part B USWNT V2).
- **Watcher write-guard:** ✅ shipped/deployed (write-on-change).
- **Proxy scoreboard upstream cache-bust (2026-07-11):** ✅ **no new load path.** On a `/scoreboard`
  MISS the proxy appends `_cb` to the ESPN upstream so ESPN can't serve its 25–47-min-stale full-season
  cache. Edge-cache key unchanged → ESPN hit COUNT is identical (still ≤2/min collapsed across all app
  traffic); ESPN just recomputes instead of serving its cache. Zero added CPU. (The rejected alternative
  — parse+overlay the 2 MB season in the proxy — measured ~9 ms on a laptop, over the free-plan **10 ms
  CPU cap**; do not ship it.) Passes 1k trivially.
- **Watcher 30s live double-poll (2026-07-11):** ✅ during a live window the cron tick polls twice (poll
  → 30s → poll cache-busted). Orthogonal to nearly every axis — KV writes (write-on-change), push
  fan-out (per-event, collapse-id), APNs are all UNCHANGED; the ONLY axis that ~doubles is ESPN
  scoreboard hits, and only during the ~2h live window (one small windowed fetch/poll). Passes 1k.
- **V2 stoppage `+N` broadcast (2026-07-11):** ✅ **decided in §5.** Per-minute broadcast ONLY in added
  time (~2–8 min/match), ONE POST per channel = **follower-independent** → flat at 1k and 100k. The one
  unknown = Apple's undocumented broadcast throttle at minute cadence (§6 open item) — **device-verify
  pending build 26** on a real stoppage window before calling it done.
- **Supabase DB SIZING (2026-07-24): ✅ run through §5 — free tier (500 MB) HOLDS at the 15k/7k target
  with room; the first wall is multi-year record-book accumulation, ~year 3-4, lever = Pro $25/mo.**
  Modelled 15k total users / 7k semi-regular players across Predict+KHG+Trivia+Bracket, mid-season year 1,
  during a MATURE bracket edition (worst case), at ~150-180 B/row incl. indexes:
  | Table | Retention | Rows @ 15k/7k | ~Size |
  |---|---|---|---|
  | `bracket_votes` | pruned at **next edition START** (2026-07-24 rule) | ~4k voters × ~60 matchups = 240k | ~36 MB (up to ~130 MB if all 7k vote every matchup) |
  | `quiz_answers` (KHG+Trivia) | pruned **>35d** → plateaus | ~7k × ~20 × ~2.5 rounds = 350k | ~53 MB |
  | `predict_round_scores` | pruned **>28d** → plateaus | ~7k × 2 teams × ~4 weeks = 56k | ~10 MB |
  | `prediction_scores` (season avg) | **kept**/season | ~7k × 2 = 14k | ~2.5 MB |
  | `bracket_scores` + `_stats` | **kept forever** (+~6 MB/yr) | ~4k × ~6 editions = 24k×2 | ~7 MB |
  | `superfan_scores` / `fanzone_progress` / `season_history` / `trivia_scores` | **kept**/season | 7k each | ~4.7 MB |
  | `user_achievements` | **kept**/season | ~7k × ~5 | ~5 MB |
  | `profiles` + `device_tokens` + prefs | kept | 15k + tokens | ~11 MB |
  | `auth.users` | kept | 15k | ~30 MB |
  | **Total, year-1 peak** | | | **~170 MB typical · ~280 MB worst-case bracket** |
  **Verdict:** solidly under 500 MB with ~220-330 MB headroom in year 1; MAU (free 50k) fine at 15k; egress
  (free 5 GB/mo) is the other axis but most heavy reads (feeds/images) go through the PROXY not Supabase, so
  Fan Zone egress is ~1-3 GB/mo — under cap. **Pruning never touches season-average data** — averages live in
  the KEPT aggregate rows (`prediction_scores`/`superfan_scores`); only raw per-question answers (>35d) + old
  round boards (>28d) are pruned, which the app can't render past current+previous round anyway. **Watch-items
  (none is a year-1 blocker):** (1) `bracket_votes` peak scales with voters×matchups — transient (pruned each
  edition start), the largest single table; (2) the kept record book grows ~15-25 MB/season FOREVER, so at a
  steady 15k the cumulative record book (~60-100 MB by year 3-4) + transient peaks approach the 500 MB line
  around **year 3-4**, or sooner past ~20k users; (3) prune windows are already as tight as the current+prev
  display allows — can't prune more without breaking the "last round" views. **100k / headroom lever:**
  Supabase Pro (8 GB DB / 250 GB egress, **$25/mo**) — the documented ~30-50k line; at 15k, donation revenue
  (~$3k/yr) covers it many times over, so it's a clean bridge, not a day-one cost.
- **Record-book archival (year 3-4 headroom option, noted 2026-07-24):** the ONLY thing that grows unbounded
  is the kept record book (`prediction_scores`/`bracket_scores`/`bracket_user_edition_stats`/`superfan_scores`/
  `season_history`/`user_achievements`), ~15-25 MB/season forever by design (the permanent record). Before it
  matters (~year 3-4 at 15k, or on Pro), archive seasons older than N (e.g. keep 2 live + the `season_history`
  peak row, move older per-season rows to a cold table or an exported snapshot). This is a HEADROOM lever, not
  a 1k/launch need — do NOT build it prematurely; `season_history` already preserves each past season's peak
  tier/score, so archiving the bulky per-team/per-edition rows loses nothing a user can see.
- **Bracket-votes prune timing (2026-07-24): ✅ moved close → next-edition-START, load-neutral.** Owner rule:
  a finished edition stays fully browsable (full bracket, your picks, per-matchup results) through the
  between-editions review window; votes prune when the NEXT edition begins (`writeEdition` →
  `pruneCompletedEditionVotes`, best-effort, idempotent). Record book (scores/stats/final ranks) untouched.
  Same number of DELETEs, just later in the lifecycle — no new load path, no 1k/100k impact.
- **Know Her Game weekly automation (2026-07-13):** ✅ **passes 1k + 100k by construction — content is
  LEAGUE-WIDE, not per-user,** so load is user-count-independent. New load paths, all once-weekly: the
  routine's 16× `/knowher/todo` calls (each its OWN invocation ≈30 ESPN subrequests — under the 50/
  invocation cap; results edge-cached 1h) + one `/knowher/ingest` POST (validate + 1 KV write + ledger
  mark) + the `knowherStaleWeek` watchdog (one KV read per `/knowher` cache-miss ≈ every 5 min, diag
  throttled to 1/day via KV). Weekly ESPN burst ≈480 requests — the watcher exceeds that every ~20 min
  on game days. $0 at every tier; generation runs on the owner's subscription (Claude Routine), not the
  metered API.
- **Fixture-window polling + confederation scoping (2026-07-16):** ✅ **the requests-cap fix (§6),
  both halves shipped.** (a) **Watcher** (`src/fixtures.ts`): a ~6h discovery sweep builds a KV
  fixture index; the per-minute tick polls ONLY feeds with a fixture in `[KO−75m … KO+4h]` (window
  closes at observed FT; partial discovery never replaces a good index; `/debug/fake-match` injects
  outside the gate so the harness still works). Baseline 23,040 → ~64/day idle + ~1.5-3k/matchday.
  (b) **App** (`ConfederationMap.swift`): NT fan-out scoped to globals + followed countries'
  confederations (ZAM 15→7 feeds/tick; unmapped fails OPEN + diag). Live-verified via `wrangler
  tail`: cold-cache ZAM launch requests exactly NWSL + caf.w.nations + 6 globals. **1k test:** one
  live NWSL match, 150 concurrent club watchers ≈ 150 × 2-3 calls/30s ≈ ~1,100/min peak — bounded by
  the ~2h window ≈ ~40-60k that day INCLUDING the fixed costs — passes; pre-fix the same day was
  ~23k fixed + the same user load + NT waste. **100k lever:** Workers Paid ($5/mo, 10M req/mo) — the
  documented ~10-15k-user slot — plus the app-side push-not-poll redesign (broadcast the in-app live
  score the way the LA card already works) held as the architectural lever before ~100k.
- **Post-match Predict-results push (Change 8, 2026-08-04):** ✅ **passes.** A once-daily cron pass, NOT
  per-minute — for each of the prior day's settled finals it runs ~4 capped Supabase reads
  (`predict_submission_marks` → anti-join `predict_result_seen` → gate `predict_results` → `device_tokens`)
  then rides the EXISTING V1 Queues fan-out (chunk ~40/msg → consumer). **1k:** recipients are the unseen
  predictors of one club's fixture — a subset SMALLER than a goal push's both-fanbase alert set, which is
  already device-proven; a handful of finals/matchday × one pass. **100k lever:** an index on
  `predict_submission_marks(event_id)` (built in `migration_predict_result_push.sql`) so the recipient
  query isn't a table scan, + the same Queues rail (flat, Workers Paid slot). Only net-new write =
  one small `predict_result_seen` upsert per result-view (bounded by views). No cost cliff.
- **Per-feature proxy-request LEDGER (seed, 2026-07-16 — extend as features land):** the shared
  100k/day budget each feature draws from. Fixed daily: watcher ~64 (discovery) + per-match windows
  ~300-600/match (+ double-poll during live); bracket `*/5` cron 288; social-refresh + KHG crons <10.
  Per-user-session (post-Part-D): launch ~5-6 (config/season/feed/videos); live heartbeat ~1 per
  60s (aux feeds join only when their own fixture is within ±36h; NT adds its scoped feeds only in
  international windows), foreground-only; Match Detail +1 per 60s while open; +1 per foreground
  V1 push received (event-driven refresh); tap-driven (roster/weather/game content) ~1 each. Fan
  Zone gameplay = Supabase (NOT this budget). ⚠️ Any NEW proxy-backed feature adds a row here +
  re-checks the 1k matchday sum.
  **Predict community (added 2026-07-28):** `/predict/community` ≈ **1 call per results-screen or
  locked-card open**, batched across every fixture in a round (cap 6), so a 3-club weekend is one
  request not three. Post-close responses are frozen and cache 24h; pre-close cache ≤5 min. ⚠️ Counted
  as user-linear anyway, because a cache HIT is still a Worker invocation. 1k concentrated matchday
  ≈ **≲1.5k/day** on top of the fixed costs above — the ~40-60k live-match day becomes ~42-62k, still
  inside 100k. Predict's WRITES stay on Supabase and draw nothing from this budget.
- **Involuntary sign-out fix (2026-07-16):** ✅ load-neutral — no new load path (an auth-state
  listener + one foreground `auth.session` revalidation per app-open, on Supabase's unlimited-API
  free tier; no new polling/DB/cron). No §5 run required.
- **In-app live-poll efficiency, Part D (2026-07-16):** ✅ owner decision: the ≤30s-fresh surface is
  the **V2 card** (watcher-driven, one broadcast POST per event, user-count-FREE — untouched); the
  in-app screens don't need to match it. Shipped: (a) aux-feed gate — the live tick re-fetches
  NT/Champions-Cup/Challenge-Cup feeds only when the loaded season has one of THEIR fixtures within
  ±36h (fail-open on unparseable dates; the Challenge Cup was fetched every 30s all season for one
  match/year); (b) live cadence 60s (heartbeat + Match Detail; idle/pre unchanged); (c) a V1 push
  arriving FOREGROUND triggers an instant `matches.refresh()` (event-driven — opted-in users see
  goals at push latency, FASTER than the old 30s poll). **New per-watcher cost ≈ 1 call/60s ≈ 120
  req per full match (was ~600) → ~750 concurrent full-match watchers** (~1,500 at typical ~1h
  sessions) on Workers Free. Passes 1k with real margin.
- **In-app pub/sub (Supabase Realtime vs Durable Object sockets) — evaluated 2026-07-16, DEFERRED
  to the ~5-10k-user lever.** With Part D it is no longer a 1k necessity. Decision recorded:
  Realtime free tier ≈200 concurrent (verify vs current docs) with a $25/mo Pro wall (disqualified
  at launch scale per §1); a Durable-Object WebSocket layer rides the SAME $5/mo Workers Paid plan
  the watcher's CPU ceiling already points at → **DO-on-$5 is the presumptive rail when built**,
  with today's polling as the permanent fallback (a dropped socket degrades to poll, never a frozen
  score). Watcher cron CPU is user-count-INDEPENDENT (median 9.56ms vs the 10ms free cap — the
  2026-07-15 exceededCpu burst was the live double-poll parsing 16 feeds ×2; B1 removes most of
  that parsing; Workers Paid $5/mo = the 30s-CPU backstop if live ticks still spike).
- **Anonymous Level-3 usage analytics (2026-07-17):** ✅ **passes 1k + 100k by construction.** New
  load path = ONE pre-summed batch POST per app session (`Analytics.swift` aggregates in memory,
  flushes on background) → proxy `POST /analytics` (whitelist, no IP/IDs) → one Supabase RPC
  (`increment_counters`, atomic daily rollups; table grows ~40-60 rows/day ≈ ~2MB/yr). 1k (~500
  DAU): ~1k req/day ≈ 1% of the request budget. 100k: ~60k req+RPC/day — on Workers Paid by then;
  trivial for Postgres. No identifiers ⇒ no GDPR/consent surface; label = Usage Data, Not Linked.
- **Ops alerting (2026-07-17):** ✅ **scales with INCIDENTS, not users — flat $0 at every tier.**
  (a) Error-spike email: the proxy's existing `*/5` cron scans recent `diag:` keys (age filtered
  from the reverse-time KEY, so a quiet tick = 1 KV list + 0 reads) → Resend email at ≥8
  error-kind events/15min, throttled 1/hr. (b) Dead-cron watchdog: the watcher pings a
  healthchecks.io check each tick; missed pings ⇒ THEY email (the failure class a dead worker
  can't self-report). (c) MetricKit → Diagnostics: Apple's on-device crash/hang payloads surface
  as `metricKitDiagnostic` crumbs in the same telemetry sink (device-only delivery; TestFlight ✓).
  Both (a)+(b) no-op until the owner sets the secrets (RESEND_API_KEY + ALERT_EMAIL;
  HEALTHCHECK_URL).
- **Fan Zone comp-arena redesign + Batch 1-3 (2026-07-24): ✅ passes 1k + 100k by construction.** Full
  §5 sweep of every Fan Zone load path touched this session:
  • **Predict AVERAGE leaderboard (Batch 3, the one genuinely new DB load path).** Unit of load = predictors
    per team; the board is `standings` capped at `visibleLimit` (top-100), now `order(avg_points desc)` +
    a new **btree index** `prediction_scores(team_abbreviation, season, avg_points desc)`; `rank`/`totalPredictors`/
    the new `roundTotal` are all `head:true, count:.exact` HEAD counts (ZERO rows transferred). Same O(100)
    shape as the points board that already passed — the switch to average moved the ORDER BY / COUNT onto an
    indexed column, no new scan. `upsertScore` still = 1 own-row read + 1 write per scored team per screen
    load (the `matches`/`avg_points` columns ride the SAME upsert; ~12 B/row added ⇒ negligible DB growth).
    Reinstall-safe: `max(points)`/`max(matches)`, avg derived from the merged pair — never clobbers down.
    **1k concentrated:** 300 one-club fans opening Predict post-match ≈ ~5 Supabase calls each (all capped/
    HEAD) ≈ ~1.5k API calls — noise on Supabase's UNLIMITED-API tier. **Round board stays raw points** (a
    round is 1-2 matches) — unchanged, already passed.
  • **Match-result "See details" detail (Batch 3) — TAP-DRIVEN, not polled.** Per open: 1 proxy `/summary`
    (a finished match is immutable ⇒ **edge-cached**, so repeat opens are cache HITs) + roster (session-cached)
    + `roundTotal` + `roundRank` (2 HEAD counts). The ACTUAL XI is re-fetched, never persisted (online-only,
    zero storage growth). Adds a row to the per-feature proxy ledger: **Predict match detail ≈ 1 proxy call
    per unique detail open, edge-cached, user-tap-driven** (same class as roster/weather taps). 1k: bounded by
    user taps, cache-collapsed per match. Fails honestly → `RetryStateView`.
  • **Bracket Batch 1-3 (stepping-stone review, margin verdicts, voting re-entry, points-table copy) — ZERO
    new server load:** every one reads the ALREADY-LOADED edition in memory or is pure UI. The voting-screen
    re-entry for a submitted round renders local picks; no fetch.
  • **Superfan detail — LOAD REDUCED.** Batch 2 removed the percentile `standing` call, so a detail open now
    does 1 counts upsert (read-back + GREATEST merge) + 1 season-history upsert + 1 bounded history read +
    1 earned-achievements read (≤9 rows) — two HEAD counts FEWER than before. On-demand, bounded.
  • **Achievements (PR4) — on-demand, bounded.** Detection reads local stores + the loaded edition (no
    server load); awards are idempotent INSERT-only upserts on a UNIQUE(user,key,season); `earned` = 1 read
    of ≤9 rows. Per Superfan-open, not polled.
  • **KHG / Trivia Batch 1-3 (streak display, rules copy) — ZERO new load** (UI/copy only; quiz_answers +
    community aggregates unchanged, already pruned via pg_cron per the v3 entry above).
  **Efficiency:** avg_points is STORED (indexed ORDER BY/COUNT, no per-query scan); the detail re-fetches an
  edge-cached immutable summary instead of persisting history — no waste. **Cost:** no fixed monthly cost at
  small scale; DB delta is ~bytes/row + one small index; the detail rides the existing proxy Free budget.
  **100k levers (all pre-existing, unchanged):** Supabase Pro at the ~30-50k size/MAU line; Workers Paid
  ($5/mo) at the ~10-15k proxy-request line for the /summary taps. **Failure modes:** board query fails
  (incl. pre-migration missing column) → empty rivals + Diagnostics (own local score still shown); rank/total
  COUNT fails → nil → inline splice; detail fails → retry; reinstall → max-clamp. NO SILENT FAILURES.
  ⚠️ **Owner action for the board to populate:** apply `migration_predict_avg_leaderboard.sql` (roadmap) —
  until then the season board's rivals degrade to empty (honest), the rest works.
- (append as items resolve)

- **Summary cache TTL rework (2026-07-31): ✅ passes 1k; nothing new needed at 100k.**
  Two new load paths, both tiny and both bounded. (a) An **unsettled** `post` summary now polls at
  live cadence instead of being frozen — but that is the same 30s tier a live match already sits in,
  edge-collapsed across every viewer, and it applies only while a match is actually suspended (rare,
  and self-terminating). Non-resumable statuses drop to hourly precisely so a canceled fixture can't
  hold a permanent 30s hot path. (b) A **settled-but-incomplete** summary re-checks every 6h until
  attendance lands, bounded at 14 days — so the population is "finals from the last fortnight still
  missing a crowd figure", typically 0–3 matches, ⇒ **≤12 origin fetches/day worst case**, independent
  of user count.
  ⚠️ The axis that actually moves is **client revalidation**: capping the client-facing `max-age` at
  1h means a device re-asks for a past match it re-opens later, and a cache HIT still counts as a
  Worker request. That is user-linear — but it is bounded by *screen opens*, not by matches: 1k users
  re-opening a handful of past matches a day is ~low thousands of requests against the 100k/day cap,
  next to the existing fixed traffic. Accepted deliberately: the alternative is unreachable devices
  pinning wrong data for a year, which no server-side fix can correct. **PASSES.**
  **100k lever:** Workers Paid ($5/mo) — the same already-documented slot; no new mechanism.
