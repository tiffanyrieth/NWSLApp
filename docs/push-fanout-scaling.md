# Push fan-out scalability — the launch-scale problem & the option menu

> **Status: RESEARCH / DECISION PENDING.** This is the reference doc for the "Part D" work, deferred to its
> own dedicated planning + build session (hybrid Claude Code + Gemini research). Captured 2026-07-08.
> Nothing here is built yet. Tonight's build (Know Her eligibility, watcher write-guard, NT feed expansion)
> is separate and does **not** address this — it's a different axis (match-volume, not user-volume).

## The problem (a launch blocker, not a "100k someday" problem)

Every alert fans out **one APNs request per follower token, all inside a single cron invocation**. APNs has
no multicast — each device is its own POST to `/3/device/<token>`. Cloudflare counts each as a **subrequest**.

- **Free plan cap = 50 subrequests per invocation.**
- So once a single team has more than **~40–45 alert-followers**, a goal **drops the overflow** — the ~46th
  follower onward gets no push.
- **V1 (buzz) and V2 (Live Activity) fan-outs share the same per-tick budget.**
- **Failure mode is ugly:** partial delivery, and because hitting the cap can error the tick *before it saves
  match state*, the next tick may **re-detect the same goal and re-fire** to a random subset → some users get
  **duplicate** buzzes while others get **nothing**. Non-deterministic and bad.

### The killer scenario (why this is a day-one blocker)
Launch into the Washington Spirit community (subreddit ~7.7k weekly visitors). ~100 fans install day one, all
follow **the same team**, all enable match alerts. Spirit scores Saturday → **~40 get the push, ~60 get
nothing** — live, in front of the exact audience you're trying to win. 100 users *concentrated on one team*
(the realistic launch pattern) already breaks the free tier. A few hundred installs is normal for any
published app; this must be solved **before** publishing into a fanbase.

### Why the watcher write-guard (tonight's Part B) does NOT fix this
The write-guard reduces **KV writes**, which scale with **match volume** (many concurrent matches / an
international window). The fan-out ceiling scales with **user volume** (followers per team). Different axis —
Part B is real and valuable, but it does nothing for this.

## The option menu (decide in the dedicated session — keep all on the table)

### 1. APNs Broadcast Channels (iOS 18+) — the native fix for **V2 Live Activities**
Apple-native, purpose-built for sports Live Activities. Create a **channel per match**; clients subscribe to
the channel (instead of requesting a per-Activity push token); the Worker sends **one** request with an
`apns-channel-id` header and **Apple** fans out to every subscribed Activity.
- **One subrequest, infinite fan-out, free, keeps raw APNs — no Firebase, no $/mo.** This is how Apple
  intended sports live scores to work.
- **Verify:** exact iOS floor (app min is **17.2** → need a per-Activity-token fallback for <18 users, or bump
  min iOS to 18); the channel create/manage APIs; store channel-per-match in Supabase; client subscription flow.
- **Note:** FCM **cannot** broadcast Live Activities — they require session-specific per-Activity tokens
  declared in the payload, so FCM Topics don't apply (confirmed via Gemini research).

### 2. Cloudflare Queues — the fix for **V1 push** (keeps your entire stack)
Producer (the detecting tick) enqueues **one** job (a binding call, *not* an external subrequest); a separate
**consumer Worker** drains the queue in ~40-token batches, each consumer invocation getting its **own fresh
50-subrequest budget**. Effectively unlimited fan-out.
- Keeps **raw APNs + your Supabase preferences + your token lifecycle** (per-device tokens, `pruneDeadTokens`,
  the build-23 register-on-open fix). The consumer reuses existing `sendApns` / `tokensForEvent`.
- **Verify:** Gemini says Queues is now on the **free** plan (10k ops/day, 2026) — confirm; earlier belief was
  Paid-only. If free, this is the durable V1 fix at $0.

### 3. Cloudflare Paid ($5/mo) — zero-code stopgap
Raises the per-invocation subrequest cap (**Gemini: 50→10,000, configurable via `limits.subrequests`;
earlier figure was 1,000 — verify the current number**). Handles hundreds to ~900+ followers/team/tick with
**no code change** — the "I'm launching this weekend and haven't built the real fix" insurance.
- Owner stance: fine paying **later at real scale** (≈100k users, donation-justified), **not** at ~50 users.
  So Paid is a bridge, not the plan.

### 4. Firebase / FCM Topics — considered, likely NOT for this app
Works for **V1** (Worker sends one call to a topic, FCM fans out, $0), but **cannot** do **V2** Live
Activities. For *this* app the real cost is **engineering, not dollars**:
- forces moving server-side preferences (Supabase, Tier-1/2 sign-in gating, FIFA-code NT fan-out) to
  **client-side topic subscriptions**,
- **rips out the just-hardened token system** (build-23 register-on-open, per-device tokens, prune),
- adds a **heavy SDK + Google data surface**, against the app's minimal-dependency design.
- Cloudflare would remain the watcher either way (FCM = delivery rail only).
- Keep on the table, but weigh hard against Queues.

## Current leaning (to validate, NOT locked)
**V2 → APNs Broadcast Channels. V1 → Cloudflare Queues. Paid = emergency stopgap only. Firebase = weigh but
likely decline.** This keeps small-scale cost at **$0**, stays native, and removes the ceiling — matching the
indie-cost goal (don't add a fixed charge at the ~51st user). **Verify all figures against current docs
first** (iOS floor for channels, Queues free-tier limits, the Paid subrequest number).

## Open questions for the dedicated session
- Min-iOS decision for Broadcast Channels: bump the floor to 18, or run a hybrid (channels for 18+, per-Activity
  push fallback for 17.x)?
- Is there any broadcast mechanism for **V1** standard alerts? (No native APNs broadcast for non-LA pushes —
  V1 still needs Queues/FCM/Paid.)
- Cloudflare Queues exact free-tier limits + consumer batching shape.
- On-device migration + testing plan (channels subscription, fallback path).

## Related note — CLAUDE.md "one dependency"
The "only third-party dep = supabase-swift" line is a **currently-true fact + an early (pre-0.1) preference**,
not a hard rule (it dates to the "hello world" era before the app had a real layout). Treat it as a **factor
to weigh**, not a blocker, when evaluating Firebase. Consider softening the wording in CLAUDE.md.
