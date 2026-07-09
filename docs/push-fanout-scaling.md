# Push fan-out scalability — the launch-scale problem & the DECIDED architecture

> **Status: DECIDED 2026-07-09** (4 parallel research agents, every hard number verified against primary
> docs — Cloudflare/Apple/Firebase — with source URLs below). Supersedes the earlier RESEARCH/option-menu
> version. Two facts in that version were **stale in our favor**: Cloudflare Queues is now **free** and
> the subrequest budget was split external/internal. **Build pending** (Part A fan-out redesign + Part B
> USWNT V2). Read this with `docs/stress-testing.md` (the charter that frames the sizing rules) and
> `docs/live-activity-v2.md` (the V2 manual).

## The problem (a launch blocker, not a "100k someday" problem)

Every alert fans out **one APNs request per follower token, all inside a single cron invocation**. APNs
has no multicast — each device is its own POST to `/3/device/<token>`, which Cloudflare counts as an
**external subrequest**.

- **Free plan cap = 50 external subrequests per invocation.** But the watcher also spends ~16 on feed
  polls + 3 Supabase selects per fired event before any push goes out, so real APNs headroom today is
  **~31 tokens/event**, and simultaneous events (two goals in a tick, concurrent matches) share and
  compound the same budget.
- **V1 (buzz) and V2 (Live Activity) fan-outs share the same per-tick budget.** A dual-opted user costs
  **2 POSTs/event** today.
- **Failure mode is ugly and self-worsening:** on cap, the runtime throws `Too many subrequests`
  mid-loop. Because the watcher's **KV state write happens AFTER the sends** (`src/index.ts:347`), a tick
  that dies mid-fan-out **never persists state** → the next tick re-detects the same goal and **re-fires
  it: the first ~31 followers buzz twice, the tail still gets nothing.** Non-deterministic, and a direct
  NO-SILENT-FAILURES violation.

### The killer scenario (why this is day-one)
Launch into a club subreddit (e.g. Washington Spirit, ~7.7k weekly). ~100 fans install, all follow the
**same team**, all enable match alerts. The club scores → **~40 get the push, ~60 get nothing**, live,
in front of the exact audience you're trying to win. 100 users *concentrated on one team* (the realistic
launch pattern) already breaks the free tier. This must be solved **before** publishing into a fanbase.

### Why the watcher write-guard did NOT fix this
The write-guard reduces **KV writes**, which scale with **match volume**. The fan-out ceiling scales with
**user volume** (followers per team). Different axis — see the charter's §5 "identify the load axis."

---

## The decided architecture

**Two rails, split by push type — because Apple's broadcast only carries Live Activities:**

### V2 in-match Live Activity updates → APNs Broadcast Channels (iOS 18+)
Apple-native, purpose-built for sports Live Activities, and Apple's own WWDC24 blueprint (session 10069).
- **Channel per MATCH** (not per team). The watcher creates a channel shortly before kickoff via the
  channel-management REST API, stores its id, and every in-match update (goal/card/HT/FT/end) is **one**
  POST to `/4/broadcasts/apps/{bundleId}` with the `apns-channel-id` header — **Apple fans out to every
  subscribed Activity, any audience size, one subrequest.** Channel deleted post-match.
- **Team-following stays 100% in Supabase.** There is no "subscribe to a team" concept and **no topics
  anywhere** — a user's follow + alert prefs are a Supabase row, exactly as today. The channel is a
  per-match delivery pipe, not a subscription store.
- **Push-to-start stays per-device** (broadcast *cannot start* an Activity). But the iOS 18 start payload
  carries `input-push-channel`, so the system-created Activity **auto-subscribes to the match channel**
  for all later updates. Net: **one per-device fan-out per match (the start), then $0 broadcasts for every
  event.** That start fan-out rides the same Queues pipeline as V1.
- **Same ES256 `.p8` JWT** we already sign (no new key). Channel-management hosts:
  `api-manage-broadcast.push.apple.com:2196` (prod), `…sandbox…:2195`. Sends go to the standard hosts,
  path `/4/broadcasts/...`. No-Storage message policy (Apple's rec for frequent sports updates). 10,000
  channels/app/env (vs ~7 matches/day — trivial); 5KB payload.
- **One-time portal step:** enable **Broadcast Capability** on the App ID. ⚠️ **Never DELETE** the
  capability — it irreversibly wipes all channels/config for the topic.

### Everything per-device (V1 buzz club+NT, lineups, LA push-to-start) → Cloudflare Queues ($0)
- **Producer** (the detecting cron tick): look up tokens (Supabase), **chunk ~40 tokens/message**,
  `sendBatch` to the queue (a Cloudflare-service call = *internal* budget, not the 50-external cap), then
  **persist KV state**. Detection and delivery are now separate jobs.
- **Consumer Worker:** takes 1 message/invocation → ≤40 APNs POSTs against **its own fresh 50-external
  budget** → `pruneDeadTokens` on 410/BadDeviceToken (receipt loop preserved) → failed batch retries
  alone; exhausted → dead-letter queue.
- **Keeps the entire hardened stack:** raw APNs, Supabase preferences, Tier-2 sign-in gating, per-device
  `(user_id, device_id)` token lifecycle, `pruneDeadTokens`, the FIFA-code NT fan-out. **Zero app-side
  change, zero targeting-model change.**
- **Design invariant:** `(tokens per message) × (max_batch_size) ≤ ~45`. Don't enqueue one message per
  device (10 goals × 1,000 tokens = 10k messages ≈ 30k ops/day, 3× over the free cap) — chunk.

### The correctness bonus
Moving delivery off the detecting tick **structurally kills the duplicate-refire bug**: the tick enqueues
(durable) and persists state regardless of send outcome; a send failure retries just that batch instead
of poisoning the whole match's state. This was a NO-SILENT-FAILURES defect, fixed for free by the redesign.

### iOS 17 = graceful degradation (decided)
Min target stays **17.2**. iOS 17.x devices get **full V1 forever** (V1 is plain APNs tokens, unaffected
by the iOS 18 broadcast floor) but **no Live Activities** — the app registers an LA start token only on
iOS 18+, and the Live Activities setting shows an honest "Requires iOS 18." The watcher keeps **one clean
channels-only V2 path** (no per-token V2 fallback to maintain). App is unpublished, so this strands nobody.

---

## Rejected / deferred options (why)

- **Firebase / FCM Topics — DECLINED.** $0 on delivery, but: Google's own docs say topics are
  *"optimized for throughput rather than latency… for fast delivery target registration tokens instead"*
  — the vendor telling you topics are the wrong tool for goal alerts (community tail-reports of
  hours-late sends; no SLA, no per-device receipts → collides with NO SILENT FAILURES). **Cannot broadcast
  Live Activities** (per-device `live_activity_token` required) — zero help for V2. Cost is *engineering,
  not dollars*: pulls ~7 SPM packages (~2–4MB) + APNs-callback swizzling, needs GoogleService-Info.plist +
  privacy-label additions (Google device-ID collection), and moves targeting client-side (topic subs =
  app-instance state → sync drift, no server-side Tier-2 gating, a failed unsubscribe = invisible ghost
  pushes). Industry check: **no major sports app found using FCM Topics for goal alerts** (FotMob =
  in-house direct-token on AWS after providers crashed at peak; theScore = Airship ~$25k/yr).
- **Full Firebase (move the DB to Firestore) — DECLINED.** A total rewrite of the auth + data layer (SIWA
  re-integration, RLS → security rules, watcher data layer), delivery math **unchanged** vs FCM-Topics,
  and it is the **only option with metered billing** (a bug or viral day → surprise bill) — rejected on the
  charter's own criteria (least headache, no overruns).
- **Amazon SNS — documented plan-B, not chosen.** Keeps raw APNs payloads with **no client SDK** (endpoints
  from your existing tokens, one Publish fans out), $0 at both scales (≤1M pushes/mo free, then $0.50/M).
  Real fallback if Queues is ever outgrown, but adds an AWS account + endpoint-mirroring for no capability
  gain over Queues today; LA `liveactivity` support undocumented.
- **Workers Paid ($5/mo) — the expansion slot, not a rewrite.** Raises the external cap 50→10,000
  (configurable to 10M) and Queues to 1M ops/mo. Pulled only when matchday Queues-ops or account-wide
  request volume demand it (~10–15k users) — donation-justified scale. Same queue, same code, bigger quota.

---

## Stress-test verdict & cost curve

**Full-match cost model** (spicy match = 4–1, a red card, a VAR reversal; yellows never push): ≈ **11 V1
fan-outs + 1 per-device LA start + ~10 flat V2 broadcasts.** V2 broadcasts are **flat regardless of
audience** (Apple fans out). V1 (+ start) cost per event = `ceil(F/40)` messages × 3 ops, F = followers.

**Test 1 — 1k users** (1,000 followers of one team, one goal): 25 messages → 25 parallel consumer
invocations (each its own fresh budget) → **~5–10s to full delivery**, ~0.75% of the 10k/day ops cap.
Worst-case NWSL decision day (7 matches / all 14 clubs) ≈ 8% of cap; NT international break day (~20–30 of
the 88 followed codes) ≈ ~1,000 ops (~10%). **Passes with ~10x headroom.**

**Test 2 — 100k users** (~7k followers of the biggest team): delivery still ~5–15s (autoscales ≤250
concurrent consumers); a full matchday's ops (~40–75k) exceeds the 10k/day free cap ~6–7× → **pull Workers
Paid ($5/mo).** No re-architecture — same queue, same code, bigger quota. **Passes via the documented lever.**

```
  USERS →   0 ──── 1k ──── 10k ──┬── 15k ──── 30k ──── 50k ──┬──── 100k
                                 │                           │
  COST  →   $0 ──────────────────┤                           │
            (free tier)          ▼                           ▼
                          $5/mo ─────────────────────► ~$30/mo
                       (Workers Paid)              (+ Supabase Pro ~$25)
```

| Stage | Users | Cloudflare | Supabase | Total/mo | Trigger |
|---|---|---|---|---|---|
| Launch | 0–1k | Free | Free | **$0** | — (decision day ≈ 8% of ops cap) |
| Growth | 1k–10k | Free | Free | **$0** | — (ops usage grows ~8% → ~75%) |
| First $ | ~10–15k | **$5/mo** | Free | **$5** | worst-case matchday ops cross 10k/day (observable → planned) |
| Mid | ~30–50k | $5 | **~$25/mo Pro** | **~$30** | Supabase free tier outgrown (numbers to verify) |
| 100k | 100k | $5 | ~$25 | **~$30 (~$360/yr)** | — (sits inside Paid tiers; ~2% of ~$20k/yr tips) |

- **"Users" = total actives**, modeled worst-case (launch-concentrated follows, most users alert-enabled).
  If only ~half enable alerts, every threshold ≈ doubles in our favor (first $ ~20–30k).
- **No metered component anywhere** — worst failure on both flat tiers is throttling, never a surprise bill.
  Fixed regardless: $99/yr Apple Dev Program.

**Future USWNT V2 (Part B, being built now)** free-rides: one channel per USWNT match + ~10 flat broadcasts
+ one Queues start fan-out. @1k ≈ +39 ops/match; @100k ≈ +1.5k ops on a break day already needing Paid. No
tier threshold moves. Other NT codes remain V1-only for now (V2 machinery is code-agnostic → later config change).

---

## Residual unknowns (flagged, not blockers — verify at build time)

1. **Broadcast rate limits are undocumented** by Apple ("publishing budget" unquantified; forum reports of
   throttling exist with no numbers). Our ≤1/min cadence is gentle; watch Console metrics in production.
2. **Capital-letter bundle-ID → `TopicMismatch`** on the channel API (secondary source). Ours is
   `com.tiffanyrieth.nwslapp.NWSLApp` (capitals) → **sandbox channel-create is build test #1.**
3. **Supabase Pro tier numbers** (~$25/mo, egress/MAU) — verify against primary docs during the charter's
   Supabase sweep before relying on the ~30–50k threshold.
4. **Queues free-plan availability** — verify live with a `wrangler queues create` on the free account
   before building the producer/consumer.

## Primary sources (verified 2026-07-09)

- Cloudflare: Queues-now-free changelog (2026-02-04); subrequest split changelog (2026-02-11);
  `/workers/platform/limits/`, `/queues/platform/{pricing,limits}/`, `/queues/configuration/{batching-retries,consumer-concurrency}/`, `/workers/platform/pricing/`, `/kv/platform/limits/`.
- Apple: `/documentation/usernotifications/setting-up-broadcast-push-notifications`,
  `…/sending-broadcast-push-notification-requests-to-apns`, `…/sending-channel-management-requests-to-apns`,
  `/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications`,
  WWDC24 session 10069 "Broadcast updates to your Live Activities."
- Firebase: `/docs/cloud-messaging/{topic-messaging,throttling-and-quotas,customize-messages/live-activity,ios/client}`,
  `/docs/ios/app-store-data-collection`, `/pricing`; FotMob-on-AWS + Airship case studies.

## Related note — CLAUDE.md "one dependency"
The "only third-party dep = supabase-swift" line is a **currently-true fact + an early (pre-0.1)
preference**, not a hard rule. The chosen architecture **keeps it true** (Queues + Broadcast Channels add
no app dependency — they're server-side + native APNs). It was the right call to weigh Firebase against it
and decline; the line stays as a factor-to-weigh, not a blocker.
