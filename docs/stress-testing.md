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
- [ ] **Supabase** — DB size, monthly egress, auth MAU, connection limits, RLS query cost;
      `device_tokens` / `*_preferences` read volume per tick. Likely the *second* paid lever (~Pro tier)
      around ~30–50k users. **Verify current free-tier + Pro numbers against primary docs.**
- [ ] **APNs pacing / connection reuse** — HTTP/2 throughput of raw sends at hundreds/batch (relevant to
      the Queues consumer's per-invocation batch size).
- [ ] **iOS local-notification 64 pending cap** — day-before is already windowed to the next 2 fixtures
      per alerting team; re-verify at many multi-team follows.
- [ ] **Live Activity update volume** — per-match push cadence × concurrent Activities. Broadcast
      channels make this flat per match; re-check Apple's (undocumented) broadcast throttle in practice.
      ⚠️ Now especially relevant: the stoppage `+N` clock broadcasts EACH MINUTE in added time (2026-07-11)
      — device-verify that iOS doesn't throttle a ~1/min broadcast cadence (build 26, fake-match harness).
- [ ] (expand as subsystems are examined)

## 7. Status ledger

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
- **Supabase sizing:** ⏳ not yet run through §5 (numbers to verify).
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
- **Per-feature proxy-request LEDGER (seed, 2026-07-16 — extend as features land):** the shared
  100k/day budget each feature draws from. Fixed daily: watcher ~64 (discovery) + per-match windows
  ~300-600/match (+ double-poll during live); bracket `*/5` cron 288; social-refresh + KHG crons <10.
  Per-user-session: launch ~5-6 (config/season/feed/videos); live heartbeat 2-3 per 30s (club) /
  ~7-8 (one-confed NT follower), foreground-only; Match Detail +1 per 30s while open; tap-driven
  (roster/weather/game content) ~1 each. Fan Zone gameplay = Supabase (NOT this budget). ⚠️ Any NEW
  proxy-backed feature adds a row here + re-checks the 1k matchday sum.
- **Involuntary sign-out fix (2026-07-16):** ✅ load-neutral — no new load path (an auth-state
  listener + one foreground `auth.session` revalidation per app-open, on Supabase's unlimited-API
  free tier; no new polling/DB/cron). No §5 run required.
- (append as items resolve)
