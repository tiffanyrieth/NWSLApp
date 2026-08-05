# Roadmap / What's Next

> ### 🔄 SOCIAL FEED SELF-TUNING — the maintenance routine (owner-DEFERRED 2026-08-05, do NOT drop)
> The 2026-08-05 Social-tab audit shipped everything EXCEPT this: P1 (club-news fixes + 6 reporters + Clubs-chip
> removal), Phase 2a (ESPN-direct proxy-outage fallback), and **Phase 3 "make it yours"** — the user CAN now add
> Bluesky reporters + follow players beyond their teams (proxy routes `/feed/players`, `/feed/validate-reporter`,
> `/feed?handles=&players=`; app Content Preferences UI). **This item is the AUTOMATION on top of that shipped
> infrastructure** — owner deferred it (her call) because it deserves its own routine-design pass, NOT because
> it's optional. Two independent components:
>
> **1. Curated-feed discovery (which reporters should we ADD to the defaults?).** Keeping up with beat reporters
> for all 16 clubs by hand is a nightmare + risks missed reporters. The signal: the **anonymous discovery
> analytics** — a per-team → added-handle counter (`Analytics.swift` → proxy `/analytics` → `analytics_counters`,
> NO ids/IP). ⚠️ **The threshold is computed over ADDERS, not the whole fanbase.** Example (ACFC fans): of those
> who added ANY handle, count who they added — Fan A→"Tiffany", Fan B→"Tiffany", Fan C→"Kayla", Fan D→"Tiffany"
> ⇒ the common theme is ACFC fans keep adding "Tiffany", a handle we DON'T carry ⇒ surface it as a default
> candidate. It must be `adds-of-X / total-adders`, never `/ total-fans` (most fans add nothing). Threshold TBD.
> Could be a routine OR a manual review of the analytics. **Build needs:** the analytics counter (proxy
> `/analytics` allowlist entry + an app event fired on add) — this counter is NOT yet built; it was scoped with
> Phase 3 but belongs here with its only consumer.
>
> **2. The player-add routine (which national-team players to feature?).** Auto-compute candidates from
> `current-NT-rosters ∩ current-NWSL-rosters − current 34` (the app already fetches both roster sets), with
> `bdHandleEmpty` + off-NWSL-roster → DROP (retired/departed solve themselves). ⚠️ **The hard part is
> BALANCE:** while the list is capped at ~34 (Bright Data free tier), the routine must weigh popularity AGAINST
> **club representation** — don't let the popular-players pick leave some clubs with ZERO featured players.
> That's why it deserves dedicated design time. (If the 34 cap is later lifted — e.g. via the Phase-5 IG
> `business_discovery` API — club-representation becomes far less of a worry and popularity can dominate.)
>
> **Guardrail (both components):** one-tap OWNER APPROVAL, never no-gate — same routine-class that bit KHG
> (wrong-model / ledger-bypass), and a bad IG handle bills Bright Data quota every refresh. The routine does
> 100% of the research and hands over "add these, drop these — approve?". Cloud-activation is owner-gated like
> the KHG routine. Full plan context: the approved Social-tab plan (Phase 4).


> ### ✅ SHIPPED 2026-08-04 — PREDICT post-match "your result is in" push (Change 8)
> Merged: app PR #233, watcher PR #34 (deployed). Generic copy (no score), separate opt-in "Predict
> results" toggle, next-day batched, only to users who haven't viewed their result (server-visible
> `predict_result_seen` mark). ⏳ Real-device push verify is the only thing left (sim can't receive push) —
> confirm the banner renders + the tap opens the result screen at the next finished fixture.

> ### 🚨 ALERTING GAP — a total outage paged NOBODY (owner 2026-08-04, NOT fixed today)
> **What happened:** ESPN began 403'ing the proxy's UA-less scoreboard fetches → `/scoreboard` 502'd
> for hours → **2 of 5 app tabs fully down (Home landing page + Schedule)**. The owner got **zero email
> alerts**. It was caught only by chance (she opened the app while Claude was mid-Predict-build). A
> sudden spike of 502s taking down the landing page MUST email an alert.
>
> **Root cause (verified in code):** the scoreboard/summary failure path — `proxyAndCache`'s
> `if (!espnResponse.ok) { … return upstreamError() }` — **never calls `emitDiag`**. The error-spike
> pager (`checkErrorSpike` → Resend email, ≥8 err/15min) counts **only** `sdiag:` records, so 548
> scoreboard failures produced zero countable events and never fired. The single most critical path in
> the proxy is the one path not wired into alerting. Meanwhile **healthchecks.io** watches the watcher
> CRON's heartbeat (it kept completing fine on 502s → "up"), and **UptimeRobot** pings a static endpoint
> that 200s regardless of ESPN — so none of the three monitors actually asks "does the scoreboard return
> real data?"
>
> **Fix (two parts):** (1) **emit a diagnostic on the ESPN upstream failure** in `proxyAndCache` (a
> distinct kind NOT on the `image fetch` exclusion list) → the existing pager fires within a minute of a
> real spike; (2) a **synthetic scoreboard check** (UptimeRobot keyword monitor or a health route) that
> fetches `/scoreboard` and asserts 200 + non-empty `events` — defense-in-depth so a pager gap can't hide
> a data outage again. See memory `project_espn_403_no_user_agent`.

> ### 📰 CONTENT-SOURCE AUDIT — per club, are we pulling everything we can? (owner 2026-08-03)
> **Goal:** Club News (Home) and Social are the ALIVE surfaces — the whole product thesis. Audit and
> log, **per club**, every source we pull and every one we could: club news/article feed (OG
> fast-path or RSS), YouTube channel, Bluesky handles (club · players · reporters), Instagram, and
> anything else the club actually publishes to. Confirm each is (a) correct, (b) live, (c) complete.
>
> ⚠️ **THE TRAP THAT PROMPTED THIS — a wrong club URL looks identical to a club that publishes
> nothing.** Verified 2026-08-03: `houstondashsoccer.com` is a HOLLOW domain (27KB, zero player
> data); Houston's real site is **`houstondynamofc.com/houstondash/`**. It returns 214KB of
> server-rendered HTML and was readable by plain `curl` all along. A dead URL had been read as
> "unscrapeable JS site." Any club we quietly pull nothing from deserves the same check before it is
> written off.
>
> **Why it will hit more than one club (owner):** several NWSL sides are run by their MLS owner and
> live UNDER the men's team's domain as a sub-path, so the standalone `<club>soccer.com` is legacy or
> parked. Enumerate which clubs are structured this way and fix their URLs together — the pattern is
> the finding, not the single club.
>
> **Deliverable:** a per-club table (16 rows) of source → URL/handle → last successful pull → gaps,
> plus fixes for anything stale. Cross-check against `SOCIAL_HANDLES` + the club-news fast-paths in
> the proxy, and against what each club visibly publishes.

> ### 🧭 SYNC-DIRECTION AUDIT — write down what syncs which way, and why (owner 2026-08-01)
> **Why:** the "reinstall restores your teams" idea has resurfaced ~7 times in a few months. Root cause
> found 2026-08-01 — it was asserted as intended behaviour in **8 places**, two of which auto-load into
> every session (`CLAUDE.md`, memory `MEMORY.md`), and `docs/notifications.md` §1a framed it as the FIX
> for a banned silent-failure, so removing it read as reintroducing a bug. All 8 are now corrected or
> banner-superseded, **but the underlying gap remains: there is no single place that states, per data
> type, which direction it syncs and why.** Until there is, the next plausible-sounding restore idea has
> nothing to be checked against.
>
> **Deliverable:** one table covering every piece of user data, each classified into the owner's three
> categories, with the REASON (the reason is what stops it being re-litigated):
> 1. **UP-ONLY — device is truth.** Supabase needs a current copy to *act* (the watcher must know who
>    follows what, with which alerts, to push at all). Nothing comes back down. *(follows; team +
>    competition alert bells; alert types, pending the sub-question in the sweep below)*
> 2. **BOTH WAYS — server is durable truth.** Things the user EARNED and must never lose on a new phone
>    or a reinstall. *(Fan Zone progress, Superfan counts, leaderboard scores, display name)*
> 3. **LOCAL-ONLY — deliberately not stored.** Fine-grained per-round detail that would cost real
>    database to keep per user, where the server holds only the cheap rollup it needs for leaderboards.
>    *(per-round picks/answers, streak internals, caches)*
>
> **Owner's acceptance bar: a user who gets a NEW PHONE must never start over in the Fan Zone.** The
> audit must prove that end-to-end, not assume it — check each category-2 item actually round-trips.
> Also flag any GAPS (data in the wrong category, or synced in a direction nothing justifies).
> Scope note: category 1 vs 2 is the whole point — 2 is for what was earned, 1 is for what is two taps.

> ### ✅ DONE 2026-08-03 — SYNC-DIRECTION AUDIT CLOSED (item 6)
> The audit itself is `docs/data-sync.md` — every per-user datum, which way it syncs, and WHY, in the
> owner's three categories (up-only choices · both-ways earned progress · local-only detail). It exists
> so the next "restore X on reinstall" idea has something to be checked against, after that idea
> recurred ~7 times for want of one.
> **Acceptance bar met:** a user who replaces their phone does NOT start over in the Fan Zone — traced
> end to end, not assumed.
> All 5 gaps closed: (1) bell restore-down removed · (2) Superfan adopts at sign-in · (3) → the Predict
> dual-source bug, still open as sweep item 3e below · (4) `trivia_scores` retired · (5) Game Center
> never receives a zero.
> ⚠️ **Two lessons worth keeping, both from getting it wrong first:**
> • **Gap 2 was documented ✅ FIXED while only half fixed.** The guard that stopped a junk all-zero row
>   also stopped the READ, because `submit` is read-merge-write-and-return — so the replacement phone,
>   the exact case the fix existed for, still adopted nothing. Separate the read from the write when one
>   call does both, and re-check a guard against the goal it was added to serve.
> • **The Superfan card being always-visible is what would have EXPOSED that**, plus a cache that could
>   be clobbered downward by a failed read. Making something visible is a good way to find out what was
>   quietly wrong behind it.
> 🟡 Owner action outstanding: confirm the three Game Center boards are **"Best Score"** (not "Most
> Recent") in App Store Connect — belt-and-braces on top of the zero-skip.

> ### 🐞 OWNER DEVICE SWEEP 2026-08-01 — 5 findings from a reinstall + live use
> Reported off a real device after a fresh reinstall. Triaged in-session; **only the bar-alignment one
> is fixed.** Each is stated with its VERIFIED cause, not a symptom, so none needs re-diagnosing.
>
> **1. ✅ SHIPPED 2026-08-03 — reinstall no longer restores team bells; alerts are UPWARD-ONLY.**
> Removed the `localOn.isEmpty` restore branch in `TeamAlertSyncCoordinator` (+ the two now-dead
> `fetchAll` reads). ⚠️ **It was NOT a pure deletion — three hazards the deletion alone would have
> created, all fixed:** (a) an empty device would have let the prune loops WIPE every server alert row,
> so both deletes are now gated on `hasOnboarded`; (b) nothing fired when onboarding completed
> (`completeOnboarding` mutates that flag alone and its hook is FollowSyncCoordinator's), so the
> coordinator now observes `hasOnboarded` and only marks an identity done when a prune-eligible pass
> ran; (c) a bell tapped DURING the reconcile could be pruned by the stale snapshot, so the ON set is
> re-read after the awaits and subtracted. **Alert TYPES deliberately still restore** (owner: detailed
> preferences may, choices may not) and land inert until a bell is on. Sim-verified: follow → bell OFF,
> Alert types greyed. 479 tests green. Directions per datum: `docs/data-sync.md`.
>
> <details><summary>Original diagnosis (2026-08-01)</summary>

> Symptom: after a reinstall, tapping follow on a previously-followed club (ACFC/WAS, not BAY) turns its
> bell on with no tap — and the uninstall had revoked iOS notification permission, so the bell read ON
> while nothing could fire (the banned "looks like success" state). Mechanism:
> `TeamAlertSyncCoordinator.swift:203` restores server-side alert rows onto a device with an empty local
> set (2026-07-22), and the Keychain preserves the Supabase session + `device_id` across an uninstall, so
> the user is still signed in.
> ⚠️ **The restore itself is the defect, not the permission mismatch.** Its own comment claims it is
> "mirroring the follows contract" — that comment is STALE: follows went **upward-only on 2026-07-23**,
> the day after this was written, and bells were never brought along. So today follows don't restore but
> bells do, which is precisely the state the owner hit.
> **OWNER RULING (2026-08-01):** restoring alerts was a v0.1 idea that no longer pays for itself — it
> saves ~2 taps out of a flow that still requires finding and following each club. Supabase needs an
> up-to-date copy so the watcher knows who to push to; that is a one-way obligation. **Reinstall
> onboarding is a CLEAN SLATE: not re-selecting a team is a real signal, and the post-onboarding sync
> pushes that reality up.** Fan Zone progress still restores down (it was earned); preferences do not.
> Fix = delete the `if localOn.isEmpty` restore branch + the "bail without marking reconciled" guard above
> it (dead weight once nothing restores), update CLAUDE.md, invert the reinstall-restore tests. This also
> DELETES the permission bug rather than special-casing it: nothing auto-enables ⇒ no bell can sit on
> without permission, and a manual bell tap already prompts correctly (owner-confirmed).
> ✅ RESOLVED 2026-08-03 — alert TYPES **keep restoring**. Owner's line: detailed PREFERENCES may restore,
> the generic "who do I follow" may not. They land inert (the UI disables Alert types until a bell is on),
> so a restored type applies to nothing until the user deliberately enables a team. ⚠️ Do NOT "fix" any of this by signing the user out on uninstall — that session is
> what restores Fan Zone progress and Superfan.
>
> </details>
>
> **2. 📜 NT list scroll jump — ⚠️ NOT REPRODUCIBLE IN THE SIM (2026-08-03). Needs device evidence.**
> Tried signed-out and signed-in, first follow and repeat, at the very bottom of a fully-loaded list
> (URU → VEN → VIE → WAL → ZAM, so "3 rows up" would land on UKR/USA exactly as reported). Measured
> shift: **0.0pt every time.**
> ⚠️ **Two structural hypotheses were tested and BOTH are wrong — do not re-propose them:**
> (a) *"the card grows when followed"* — it doesn't; the bell sits in a fixed 32pt row and the
> gradient/stroke are background layers; (b) *"the in-cell NavigationLink(destination:) causes it"* —
> and the fix that implied would have **reversed a documented fix**: `CombinedPitchView.swift:74-80`
> records that registering `.navigationDestination(for:)` on a PUSHED child mis-scoped the destination
> and double-pushed MatchDetail (2026-07-18). `CompetitionsView` is also pushed.
> **Leading explanation: scroll physics, not re-layout.** `idb` swipes are discrete and carry no
> momentum; a real finger leaves the view decelerating, and at the bottom it is often rubber-banding
> back from an overscroll — tapping mid-settle would look exactly like a 3-row jump. Owner also notes
> it may simply be a device-vs-TestFlight difference.
> **What makes this actionable:** reproduce on device with the list FULLY STOPPED before tapping.
> Still jumps when dead still ⇒ real, and there's something to design against. Doesn't ⇒ momentum.
> ✅ Fixed anyway while in there: `NationalTeamCard` had no `.contentShape(Rectangle())`, so only the
> flag/code/name glyphs were tappable rather than the whole card (regression from `0141876`).
>   instead of truncating (AX1) and each row is one VoiceOver fact.
>   🔴 **OPEN — DEVICE-VERIFY BEFORE BUILD 32 SHIPS. Do not let this ride out unseen.**
>   It is **already ON MAIN** (it rode into #225, which was titled "Docs:" — I branched the docs work
>   off the fix branch by mistake; owner accepted it staying, on condition it isn't lost). Nobody has
>   seen it render: the state needs a submitted XI inside the KO−2h window, and no fixture was in that
>   window when it was built. A preview can't substitute — `community` arrives from the network, so a
>   preview shows the pre-reveal state with no bars, which is the exact half that changed.
>   **Check on the owner's device at the next match:** every bar starts at the same x, long names wrap
>   rather than truncate, and the percentages stay right-aligned down the block.
> - **(c) ✅ DONE 2026-08-04 (PR #233).** Landing now has real lifecycle sections: **Open for predictions
>   → 🔒 Locked in (dimmed) → Results**; a never-submitted fixture is dropped. The open/dimmed-locked
>   ambiguity is gone.
> - **(d) ✅ ADDRESSED (game-feel pass).** The team chips were moved INTO the leaderboard header, so they
>   sit directly above the board they control (one of the owner's own proposed fixes) — the "reads as
>   broken" cause is resolved. Not a text *label*; a device glance can confirm it now reads right.
> - **(e) ✅ GONE 2026-08-04.** The season-average card (game-feel), the chase line / `nextRungText`, and
>   the provisional/rank machinery are all deleted — the two disagreeing sources no longer render anything
>   (verified: no `#N of M`, "behind", or `nextRung` copy remains in the view). The self-contradiction
>   can't occur.
> - **⏳ STILL PENDING from #3 — the fan-picks DATA BARS device-verify.** Rode onto main in #225, never seen
>   rendered (needs a submitted XI in the KO−2h window). 🔴 Verify on device before build 32: bars start at
>   the same x, long names wrap, percentages right-aligned.
> - **🟡 OPEN DESIGN Q (owner 2026-08-04) — the "vs the board" community section on the LOCKED screen.**
>   At 1 submission (only you) every bar is 100% + the contrarian panel is empty, so it reads as broken —
>   but that's the zero-population edge, not the feature. Options: (a) KEEP + fix the thin case (below a
>   small floor, swap the 100%-everything bars for an honest "you're the first fan to predict this" line,
>   keep the pitch; Claude's rec — it's an alive/social payoff at real scale), or (b) DROP the reveal and
>   leave the wait sealed until results. Owner deciding.
>
> **4. 📣 Notification title truncation — MEASURED, owner DECISION: accept (2026-08-03).**
> ⚠️ **A decision, not a closed bug.** Mechanism → ruling → the constraint that keeps it safe.
> **Mechanism:** iOS renders the delivery timestamp on the **title row**, and it widens as the
> notification ages (`4:00 PM` 55px → `Yesterday, 6:30 PM` **129px**). The title that truncated
> ("Angel City play tomorrow", 169px) is **11px NARROWER** than one that fit ("Washington play
> tomorrow", 180px) — the 74px stamp is the whole difference. The confusing part: the fitting row's
> stamp read `4:00 PM`, identical to the time inside its own BODY, so it looked like no stamp existed.
> Corroborated by the fixture timeline (ACFC Sat, Spirit Sun ⇒ screenshot Saturday evening, making the
> ACFC reminder exactly one day old).
> **Owner ruling:** it renders correctly when read within 24h, which is when these are read. Accept on
> BOTH tiers — Tier 1 (day-before) and Tier 2 (server pushes) — until actually OBSERVED on Tier 2.
> Live Activities are structurally immune (a widget; no notification-cell timestamp on the row).
> 🔒 **THE CONSTRAINT — what makes accepting it safe, so treat it as a rule: title lengths must not
> grow.** Several Tier-2 titles ALREADY exceed the specimen that truncated: `GOAL: Kansas City Current`
> 177px · `GOAL: North Carolina Courage` 203px · `RED CARD: North Carolina Courage` 232px (vs 169px).
> They survive only because a goal push is read immediately, when the stamp is `now`. A longer club
> name (expansion, rename) or any copy edit could truncate even when **fresh** — a real bug, not an
> aging artifact. Re-measure if any title grows. Built in one place per tier:
> `DayBeforeContent.swift:57` (Tier 1); the watcher's copy-v4 builder (Tier 2).
>
> **5. ✅ DONE 2026-08-03 — HOW TO WATCH rebuilt on research, not a lookup table.**
> The card no longer vanishes, the advice is accurate, and the two screens finally agree.
> **What was actually wrong** (none of it was just "CBSSN missing"):
> • the resolver was an EXACT-string dictionary, so `CBSSN`, `ABC`, `ESPN2`, `ESPN Deportes` and
>   `ESPN+` all missed — and the card had no else-branch, so it rendered **nothing**;
> • **ABC** — free over the air — was badged SUBSCRIPTION on Match Detail and FREE on Home. Two
>   tables, same match, opposite answers;
> • a bare `contains("ion")` matched **"Univision"**, and the app folds ~15 women's NT feeds into the
>   schedule, so a Mexico fixture would render a purple ION chip with a FREE badge;
> • unknown broadcasters defaulted to `free: false` ⇒ a confident **SUBSCRIPTION** badge for a channel
>   we had never heard of — a fabricated paywall.
> **Fixed:** ordered normalizing resolver (specific-before-general, ION token-exact) · tri-state
> `BroadcastAccess` (free / paid / **unknown → no badge**) shared by both surfaces · an honest unknown
> card + `Diagnostics` instead of silence · `Device.id` keyed on the label, not `UUID()` · dead
> `BroadcastLink` deleted after porting its one real case · **18 tests where there were zero.**
> **⭐ The copy is now research, and two corrections were expensive to learn:**
> • **Paramount+ carries CBS Sports Network on NO tier**, including Premium (which adds the local CBS
>   *station* — a different channel). The old copy told CBSSN viewers to "open the Paramount+ app":
>   pay, and still miss the match. The owner lost an hour to exactly this on a Spirit match.
> • **A fan paid $120/month for Fubo** before learning ION is free on Tubi / Pluto TV / Plex / antenna.
>   ION now leads with those, plus `iontelevision.com/find-us` (ZIP → local channel), the Roku path
>   (Roku Channel → Live TV → ION, *not* an app-store search), and the free-Sling DVR trick.
> • **NWSL+ posts full replays a few days later** — the real answer for anything you can't get live,
>   and it was missing entirely.
> Sources: r/NWSL + cord-cutting guides, 2026-08-03. 2026 split: 240 matches, 160 free / 80 paid;
> CBSSN is the biggest paid block (25) and the only one with no cheap path.
> ### ✅ DONE + DEPLOYED 2026-07-30 — WATCHER: "suspended" is not full time
> **Fixed and deployed** (`isUnfinishedPost` → `Match.unfinishedPost`, consulted at all three sites;
> 87 watcher tests + `test/suspension.test.ts`). The Live Activity path RETURNS EARLY on a suspension
> rather than broadcasting — the content state derives its phase from `state`, so an update would render
> a full-time card mid-match, and the teardown can't be undone. Fail-open polarity throughout: only
> positive evidence of non-completion counts, so a payload missing `completed` behaves exactly as before.
> ⚠️ NOT done (deliberate, owner call): un-marking `ended` when a fixture is seen `in` again. With the
> cause fixed, the 6h discovery sweep already covers recovery, and un-ending on `post→in` risks a
> duplicate full-time push on ESPN's frequent status flapping. Revisit only if a fixture is ever wrongly
> ended by some other route. **The original diagnosis is kept below — it's the reference for the failure
> mode, and the fabricated-kickoff variant in the next item is still unguarded.**
>
> #### Original diagnosis (2026-07-29)
> ESPN reports a suspended/abandoned match as **`state == "post"` with `completed == false` and
> `name == "STATUS_SUSPENDED"`.** The app now guards this (`Event.isFinalResult`, `SuspendedMatchTests`);
> **the watcher does not**, and it trusts bare `post` at THREE sites. Real consequences, all observed on
> UTA v WAS (wind hold at 27', resumed ~70 min later):
> - **`fixtures.ts:105,:126` marks the fixture `ended` → `isActive` (`:82`) drops it → POLLING STOPS.**
>   ⚠️ The worst one, and the least obvious. It was MASKED for 2½h because BAY v GFC was live on the same
>   ESPN feed (one scoreboard response covers every NWSL match, so the Spirit match kept being diffed as a
>   side effect — that's why the resumed-half goal + halftime pushes fired). When BAY finished at 00:10
>   the feed went quiet, and the Spirit's real full time at ~00:27 was **never observed** — KV proved it:
>   `match:401853954` still read `state:"in"`, fixture `ended:true`. **No full-time push was ever sent.**
>   Visibility depends on the schedule, which is the worst property a bug can have.
> - **`events.ts` FT detection** (`prev.state==="in" && state==="post"`) → fires a FALSE full-time push.
> - **`index.ts` ~:781 Live Activity teardown** → `broadcastEnd` + `deleteChannel` + KV deletes. IRREVERSIBLE:
>   push-to-start is gated on `ko >= now`, so an already-kicked-off match can never restart its Activity.
>   The guard must sit BEFORE the delete and bias toward "not ended" when signals conflict.
>
> Fix = the same `isFinalResult` concept at all three. Belt: **un-mark `ended` if a supposedly-ended
> fixture is ever seen `in` again** (see the backwards-transition rule below). Needs a deploy.

> ### ✅ DONE + DEPLOYED 2026-07-31 — PROXY CACHE: the third site of the same `post` bug
> `chooseSummaryTTL` read a bare `state === "post"` as "finished, cache for a year", so WAS @ UTA was
> pinned at the instant it was suspended (23', attendance 0) while ESPN had the full 90'+7' and 9,538.
> **The lesson worth keeping: a cache is the worst place for this bug.** The app and the watcher
> recover on their next read — a cache never gets a second look, which is why the scoreboard healed on
> resume and the summary could not. When a rule like `post`≠final turns out to be wrong, the sweep has
> to cover everywhere the assumption is ENCODED, not just where it was noticed.
> Also fixed alongside: immutable now requires COMPLETE, not merely settled (attendance lands days late
> at some venues, and a 1yr cache meant it was never seen); `CACHE_EPOCH` as the only practical global
> purge (the Cache API is per-colo, `workers.dev` has no zone); and a client-facing `max-age` cap,
> because a device that cached a year-long response is unreachable by ANY server fix. App side: the
> one-time `URLCache.shared` eviction (#223) for devices already holding one — ⚠️ an app UPDATE does
> not clear `Library/Caches`, so build 32 needs that migration to reach them.
>
> ### 🕐 LIVE STATE — trust the SEQUENCE, never a single snapshot (variants of one lesson)
> Live match state has broken three times, each a different mechanism, each from trusting ONE field:
> | Variant | ESPN says | Reality | Status |
> |---|---|---|---|
> | **Stale cache — ESPN's** (2026-07-11) | old-but-valid | clock stuck all game; read `pre` 47min after KO | ✅ fixed build 26 (windowed query + upstream cache-bust) |
> | **Stale cache — OURS** (2026-07-31) | frozen mid-suspension | resumed + finished | ✅ fixed proxy #70 (see below) |
> | **Suspension** (2026-07-29) | `state=post` | in progress | ✅ app + watcher + proxy cache all fixed |
> | **Fabricated kickoff** (Orlando, ~2026-07-10) | `state=in` at 1' | **never kicked off** | 🅿️ **PARKED — observing (owner 2026-07-31)** |
>
> **Fabricated kickoff — PARKED, not solved (owner 2026-07-31).** A pre-KO lightning delay; ESPN
> auto-starts after ~30 min regardless and shows a STATIC placeholder minute, so the anchor climbed to
> 120'. Seen ONCE, and only on a match nothing was logging at the time.
> ⚠️ **Be precise about what changed:** the 2026-07-30 suspended-match work fixed a DIFFERENT mechanism
> (`state=post` while play continues). It does NOT guard this one (`state=in` while play has not started).
>
> **⭐ WHY THIS IS PARKED (owner 2026-07-31) — the reason is EVIDENCE, not priority.** Nothing was
> monitoring that July match. **We have no tick data for it at all** — the account of what ESPN sent is
> observational, from watching the app, not from logs. So any guard built now would be designed against
> an *inferred* mechanism, and we would have no way to tell whether it worked. Contrast the 2026-07-29
> suspension, which WAS being logged: that is why it could be diagnosed precisely and fixed correctly.
> The July match also self-healed.
> **The rule: tweak, watch how the system reacts, then change based on what it shows.** A recurrence
> now runs through the watcher with diags, so next time there will be evidence to design against.
> Revisit only when it happens again WITH logs. The design if it does (do not re-derive it):
> - ⚠️ **Do NOT tighten on status NAMES.** Verified 2026-07-29: a legitimate kickoff arrived as
>   `STATUS_IN_PROGRESS` (not `STATUS_FIRST_HALF`), and ESPN flapped between the two ~8× in one match.
>   Name-matching would MISS real kickoffs.
> - **Tighten on BEHAVIOUR:** require the feed clock to have been OBSERVED ADVANCING before ticking
>   locally; until then render ESPN's string verbatim. Generalises `TickAnchor.freshAtCap`.
> - **Backwards transitions prove the PRIOR state was wrong** — `post→in` and `in→pre` are both
>   impossible in a real match. Cheapest in the watcher, which already persists `prev`.

> ### 🪪 DISPLAY NAMES ARE NOT UNIQUE — decide BEFORE launch (owner 2026-07-29)
> **Today anyone can take a name someone else already has.** `profiles.display_name` is a plain `text`
> column with **no unique constraint** (`supabase/schema.sql:34`), `DisplayNameRules` only trims and
> checks 2–20 characters, and **nothing anywhere queries whether a name is taken** — not on first
> choice, not on rename. Every board row carries a denormalized copy of the name, and nothing joins by it.
>
> **⚠️ It already happens.** Audited 2026-07-29 across the 2026 Predict boards: of 108 distinct names,
> **10 are held by more than one account** — "devontouchline" and "skyoffside" by THREE each. Those are
> seeded fans and purge before launch, but the demonstration stands: a *random name generator* collided
> ten times in ~120 accounts. Real users deliberately choosing desirable names will collide far more.
>
> **Why it matters beyond tidiness.** Club boards are small (a few hundred), so a collision is visible
> and confusing rather than lost in a crowd. Your own row is accent-highlighted, so YOU can find
> yourself — but the board is ambiguous to everyone else, and it directly undermines the recognition
> the Fan Zone is chasing ("why is nwslnoob always two spots above me?" only works if a name is a
> stable identity). It also leaves impersonation wide open: nothing stops a user picking a real
> player's name, or yours.
>
> **⚠️ THE TIMING IS THE WHOLE POINT.** Adding uniqueness before launch costs one index + one lookup.
> Adding it after means forcing existing users to rename — the kind of change that reads as the app
> taking something away. This is a pre-launch decision, not a someday one.
>
> **Recommended: case-insensitive GLOBAL uniqueness, first-come-first-served.**
> - `create unique index on public.profiles (lower(display_name))` — case-insensitive, so "Tiffany" and
>   "tiffany" can't coexist. ⚠️ Check for existing duplicates first; the index creation fails if any
>   remain (the seed purge clears today's).
> - An availability check in `DisplayNameEntry` before submit, plus honest "that name's taken" copy.
> - ⚠️ The UI check is ADVISORY ONLY — two people can submit the same name in the same instant. The
>   unique index is the real guard, so `AuthStore.updateDisplayName` must catch the `23505` unique
>   violation and surface it, not swallow it (NO SILENT FAILURES: a rename that appears to work and
>   didn't is exactly the banned shape).
> - Renaming must free the old name — it does automatically with a single-column index.
> - Load: one indexed lookup per name entry. Passes 1k/100k by construction; no new load path worth a
>   stress-test entry.
>
> **Considered:** per-club uniqueness (messy — users follow several clubs); a Discord-style `#1234`
> discriminator (kills collisions but also kills recognition, which is the thing the names are FOR);
> leaving it and relying on the you-row highlight (fails for everyone reading the board except you).
>
> **Separate but adjacent, worth deciding at the same time:** a reserved/blocked-name list. Nothing
> currently stops impersonating an NWSL player, a club, or the app itself.

> ### 📏 TYPE AUDIT — the DATA-BAR sweep is ✅ DONE; ~125 small-type uses remain (owner, 2026-07-28)
> Caught reviewing Predict's fan-picks bars: they shipped as a **4pt-tall bar in a fixed 70pt slot
> with an 11pt fixed-size percentage**. That reads fine in a design tool on a desktop and is squinty
> in a hand. Fixed for Predict (10pt bar, flexible width, `.dsFont` percentages that scale with
> Dynamic Type).
>
> **✅ KNOW HER GAME + NWSL TRIVIA — DONE 2026-07-29.** `CommunityResultsView` went further than a
> resize: options now STACK (full label on its own line, bar beneath), which killed the truncation AND
> roughly doubled the bar width since it no longer competes with a label column. Same pass added the
> "your pick" marking and cut two duplicate header lines. Both community games share the component, so
> Trivia got it for free as expected.
>
> **The general lesson worth keeping:** an 11pt font and a 4pt bar are a *tool* default, not a
> phone-reading size. When sizing anything a user has to read or compare at arm's length, size it
> for the device — and prefer `.dsFont` over `.font(.system(size:))` so Dynamic Type can rescue it.
>
> **✅ DONE 2026-07-28 — the DATA-BAR sweep.** Every bar the reader is meant to COMPARE is now 10pt
> (7pt in the compact Fan Zone carousel card, where a full-size bar would dominate): Predict's
> fan-picks + locked-XI bars, `CommunityResultsView` (fixes Know Her Game AND NWSL Trivia in one —
> was 60×6 with an 11pt fixed percentage while the LABEL took all the flexible width), Match Detail's
> `StatComparisonBar`, both Superfan bars, the Bracket leaderboard's accuracy bar and its
> picks-made progress. Bars in Predict + the community panel are now `Grid`-aligned so they share a
> common left edge — ragged edges make lengths incomparable, which is the entire job of a bar.
> Deliberately NOT touched: status dots (5–7pt live/bullet indicators), tab underlines (2pt), and the
> `ThumbnailContentCard` team-colour stripe (3pt) — none are data the reader compares.
>
> **⚠️ STILL OPEN — the broader TYPE audit.** 151 uses of `.dsFont(10/10.5/11)` remain app-wide.
> **26 are the deliberate tracked-caps eyebrow motif** (`trackedCaps(size: 11)` — small caps with
> tracking read larger than their point size, and it's a consistent DS motif) and should stay. The
> other ~125 are mostly legitimately-secondary captions, but some are certainly too small. That is a
> screen-by-screen judgement pass across ~40 files, not a find-and-replace — doing it blind would
> risk breaking layouts that were tuned around the current sizes. Worth its own session with the
> AX1-cap revisit in the accessibility workstream.

> ### 🚫 PREDICT STAGE 1 — results at LINEUP DROP — DROPPED (owner 2026-08-04)
> **Dropped from the list (owner, 2026-08-04).** Not this session's community-picks "vs the board"
> screen — that already ships; Stage 1 was *early scoring* (grade your XI against the REAL posted lineup
> ~90 min pre-kickoff, before full time). Kept here as reference only, in case early scoring is ever
> revived. The trap below still applies if so.
> The redesigned results screen ships against FULL TIME only. The handoff also specified a two-stage
> timeline: 75 of the 88 points (players, positions, formation, perfect XI) resolve when the real
> lineup drops ~90 minutes before kickoff, and only the last 13 (exact score, result) wait for full
> time. Opening the screen at lineup drop is the moment the game is *named* for.
>
> Deferred as one pass, not dropped — the current build is structured so it drops in:
> - Per-pick detail is already derived TRANSIENTLY (`PredictResultDerivation`), not persisted, so a
>   pre-full-time render needs no new storage.
> - `PredictionScore` is untouched and still only written at full time.
>
> ⚠️ **THE TRAP TO RESPECT WHEN BUILDING IT.** A partial score must NEVER reach
> `PredictionStore.recordScore`: that increments `scoredMatchCount`, which is the denominator of
> `avg_points`, which is what the season board ranks on. Writing a stage-1 score would silently
> corrupt every user's rank. Stage 1 must be display-only, computed in the VM.
>
> Still to decide (both were open in the handoff):
> - **What triggers it.** Fetch-on-open is simplest and matches the existing on-demand `/summary`
>   pattern; anything more eager costs Cloudflare requests, the metered resource. ⚠️ Whatever fetches
>   inside the pre-kickoff window MUST send `w=near` (the cache-key window bucket), or a stale empty
>   pre-lineup shell can mask a posted XI. The current results fetch deliberately does NOT send it —
>   it only ever reads a finished match, where `w=near` would just cost cache hits.
> - **Whether to push at lineup drop.** The moment with the most pull; the app has matchday push
>   limits to respect, and it would need its own opt-in.
> - `PredictionScore`'s four Bools can't express "pending" (false is indistinguishable from unresolved),
>   so the pending rows need a separate transient type.

> ### ✅ FIXED 2026-07-31 — Bracket rank line (was: "top 94%" reads as praise)
> **The wording was never the problem** — "top 1%" is a well-understood idiom (Spotify Wrapped, class
> rank) and STAYS. Two real defects, both fixed via a new `RankDisplay` (`Models/BracketEdition.swift`)
> that owns the rules so the four call sites can't drift apart (they already had: the leaderboard used
> a ≥5 floor and rounded up, the battle views used no floor and rounded to nearest):
> - **A percentile over a field too small to support one.** `rank/total` renders FIRST PLACE in a
>   12-player edition as "top 8%" and in a 2-player one as "top 50%" — describing the field size, not
>   the fan. Under **50 players** it now states the placing ("1st of 12").
> - **A bad percentile in the PRAISE colour.** Rank 30/32 was styled exactly like rank 1/32. Accent
>   styling now applies only at ≤25%. Stating a weak finish is fine; celebrating it isn't.

> ### 🔐 MULTI-DEVICE INTEGRITY (owner 2026-07-27; diagnosed further 2026-07-29)
> Trigger: the owner runs the app in THREE places under the same Apple ID — TestFlight, an Xcode USB
> build, and the Simulator — each with its own LOCAL stores but all syncing to one server row. She
> reports that after signing into the sim, her phone's Superfan total **doubled** (e.g. 30 → 60) on the
> next refresh. This matters far beyond the sim: it's the same shape as a user getting a new phone.
>
> **✅ FIXED 2026-07-29 (#195, reaches testers in build 31) — the duplicate rows were a RENDER bug, not two accounts.**
> The 2026-07-27 entry concluded "two rows = two distinct `user_id`s". **That was wrong.** Direct query
> of `prediction_scores` (WAS/2026, display_name=Tiffany) returns **exactly ONE row**, while the sim
> renders **two** (confirmed via the accessibility tree, 2026-07-29). One row, drawn twice.
>
> Root cause — `PredictXIViewModel.swift:475`:
> ```swift
> let myID = auth.userID?.uuidString              // Swift UUID → UPPERCASE
> let rivals = standings.filter { $0.userID != myID }   // Postgres uuid → lowercase
> ```
> The compare can never match, so the user's own server row is never removed from `rivals` — and then
> her live "You" row is spliced in beside it. `BracketService.swift:178` already guards exactly this
> (`myUserID?.uuidString.lowercased()`, commented "never double the user"); Predict is the only board
> that forgot. **Fixed by lowercasing both sides**, matching Bracket. Verified in-sim: two rows before,
> one after.
>
> ⚠️ **The seed `--purge` does NOT fix this** (owner asked, 2026-07-29). Purge deletes
> `@seed.nwslapp.test` accounts and cascades their rows; there is no second account here to delete. It
> would remove the seeded rivals and leave both "Tiffany" rows exactly as they are.
>
> **⚠️ STILL OPEN — correlated pairs are max-merged INDEPENDENTLY.** `prediction_scores` maxes `points`
> and `matches` as separate scalars, and `SuperfanCounts.merged` maxes each game's `correct` and `total`
> separately. Device A at 100 pts / 5 matches and device B at 80 / 6 merge to 100 / 6 → avg 16.7, a
> number **neither device produced**. Fix: merge each pair ATOMICALLY — take the side with more progress
> (the greater denominator) whole, never a numerator from one and a denominator from the other.
>
> **🅿️ PARKED for now (owner 2026-08-04) — revisit AFTER Fan Zone if it recurs.** The atomic-pair merge
> fix above is deferred; owner will adjust if the issue comes back.
>
> **⚠️ STILL OPEN + UNREPRODUCED — the Superfan doubling itself.** Ruled out so far: `max()` cannot sum;
> Trivia's restore deliberately skips the season accuracy pair (`TriviaStore.swift:233-239`, guarding the
> earlier "0/10 shows 100%" bug); KHG's baseline is excluded from the accuracy numerator; the Home card
> and Game Center both max-merge. **NEW EVIDENCE (owner 2026-08-04):** her cell shows Superfan **59**, the
> sim shows **46**, and BOTH are signed in as `tiffany.rieth@proton.me` (same Apple ID ⇒ same `user_id`).
> Same user_id means the two SHOULD converge to one score, so 59-vs-46 is the two devices **DIVERGING**
> (each displaying its own local total, not reconciling to the server max) — a different shape than
> doubling. **The mechanism is not yet found — do not "fix" it by guessing.** Owner's planned repro:
> delete the account on her cell, recreate it, then use sim + phone and watch whether the score suddenly
> doubles. The decisive evidence is the `superfan_scores` row captured IMMEDIATELY BEFORE and AFTER the
> sim signs in — that pins which field moves:
> `select * from superfan_scores where user_id = '<id>' and season = '2026';`
>
> **Also worth deciding:** whether display names should be unique per season.

> ### 🧪 SIM IDENTITY ISOLATION — stop the simulator writing to the owner's real data (owner 2026-07-27)
> Signing the simulator in with the owner's Apple ID makes it write to her real Superfan / Predict rows.
> **The mechanism to avoid this already exists and is wired correctly** — it has just never been switched
> on. `-signInAsTestFan <n>` (DEBUG-only, `AuthStore.debugSignInAsTestFan`) signs in as a seeded Fan Zone
> account instead. Verified 2026-07-27:
> - address format matches exactly on both sides (`seed+%04d@seed.nwslapp.test`)
> - every gate keys on `auth.isSignedIn` (= `currentUser != nil`), which the path sets — so Fan Zone entry,
>   Tier-2 alert toggles, NT bells and Profile all unlock
> - the Fan Zone gate additionally needs `hasChosenName`; the seeder writes
>   `profiles.display_name` + `name_is_custom = true`, so a seeded fan arrives already named
>
> **The one prerequisite: enable the Supabase Email provider with signups DISABLED** (so the only
> email/password accounts that can exist are the admin-created seed ones). Then:
> `xcrun simctl launch <SIM> com.tiffanyrieth.nwslapp.NWSLApp -signInAsTestFan 1`
>
> ⚠️ Push DELIVERY still can't be tested in a simulator at all (hardware, not auth) — device + the
> watcher's `/test-push` with `sandbox:true` remains the only real path. And this is the cheap 80% fix for
> Fan Zone contamination only; the broader 3-install cross-talk still wants a test Apple ID + `.debug`
> bundle id (see the signOut/global-scope finding).

> ### ✅ FIXED 2026-07-31 — Predict follow-ups (from the reset-button incident)
> - **Season card read LOCAL-only state** while the leaderboard beneath it read the server, so a wiped
>   or reinstalled device showed "Predict …'s XI to join the board" above a board still ranking the
>   user — exactly what the owner hit on TestFlight. The card now falls back to the SERVER's average
>   for that user (`TeamStanding.serverAvg`, read off the board row already fetched — no extra
>   request). Local stays authoritative when present, since it includes anything scored since the last
>   fetch.
> - **"Account delete leaves local Predict state" was ALREADY FIXED** — verified, not assumed:
>   `resetForAccountDeletion()` is wired into `ProfileView.runDeleteAccount`. What actually existed was
>   a dead `reset()`, byte-identical and uncalled; removed, since two ways to wipe the same state is
>   how one stops matching the other.

> ### ✅ COMPLETE 2026-07-31 — ESPN ROSTER RELIABILITY (opened 2026-07-27)
> ESPN is the app's most fragile dependency and the roster failed as **wrong-but-plausible data served
> confidently** — ACFC→1 player, Orlando deleted as a club, Portland→1, Rodman mislabelled MIDFIELDER for
> three weeks. Closed end-to-end in one arc: research → two live bug fixes → nightly verification →
> owner overrides → one admin portal → serving from verified state → weekly auto-adjudication.
>
> **📖 The reasoning now lives in the system docs — read these, not this entry:**
> `docs/roster-source-research.md` (⭐ **§10 = the 16-club census**: the two error classes, why "the
> official feed always wins" is WRONG in BOTH directions, ESPN erases rather than fabricates, SDP is
> season-cumulative with duplicate numbers on 12/16 clubs, the name-join hazards, and the mixed position
> verdicts) · `docs/backend.md` roster §§ (gates, verdict hold, overrides, the transfer rule, the three
> join traps) · proxy PRs #63–#68.
>
> **What runs unattended now:** nightly 08:00 UTC verification of all 16 clubs (gates A–D) → a
> gate-failing club is held on last-known-good → Monday 12:00 UTC adjudication resolves new
> position/jersey mismatches against the CLUB'S OWN site with a cited 90-day pin. First manual run
> cleared all 15 open mismatches.
>
> **⚠️ Deliberately NOT solved, and not solvable this way:** ESPN **erasures** — Fuller, Heaps
> (a USWNT captain), Spaanstra and Portland's 22 are absent from ESPN league-wide, and an override can
> only correct a player ESPN already lists, never add one. These stay visible-in-report only. Also open:
> a 50–80%-overlap partial substitution is caught at the next nightly run, not in real time.
> ### 🌩️ IDEA (low priority, nice-to-have) — weather radar during a delay (owner 2026-07-31)
> When a match is in a weather delay, show a **radar** on Match Detail — precipitation plus, ideally,
> recent lightning (soccer delays are a LIGHTNING call far more than a rain call). Explicitly a
> "nice to have", not a need. **US / NWSL ONLY** — national teams are a deliberately lighter tier
> (`docs/national-teams.md` §0), so this does not extend to NT matches.
>
> **Source research, all verified live 2026-07-31 — do not re-research:**
> - ❌ **Open-Meteo (what `/weather` uses today) cannot do it.** `lightning_potential` returns **all
>   nulls** in the US (only populated for the Central-European models); `cape` DOES work (storm energy,
>   real values) but is *potential*, not strikes; and it is a JSON forecast API with **no tiles at all**,
>   so it can't render a map.
> - ✅ **Radar — two free no-key options.** **RainViewer** public API (13 past frames ⇒ animates,
>   global, tile fetch verified `200`/PNG, requires attribution) and **NOAA nowCOAST WMS** (US-only,
>   public domain, `GetCapabilities` verified `200`). US-only is fine here by the scope rule above.
> - ⚠️ **Lightning is the hard half.** Observed strike data is commercial (Vaisala/Earth Networks).
>   Free paths: NOAA **GOES-GLM** (satellite; free but NetCDF on S3 — a processing pipeline, not an
>   API) or **Blitzortung** (community, non-commercial licence). **Better idea:** NWS
>   `api.weather.gov/alerts/active?point=lat,lon` — free, no key, GeoJSON polygons, **verified working**.
>   A stadium doesn't suspend for a strike 40 miles away; it suspends because a severe-thunderstorm
>   warning covers the venue — which is the same authority the stadium is acting on. Strike dots look
>   better; the warning is the actual reason.
> - ⚠️ **Tiles must go DEVICE → source directly, never through the Worker.** One radar view is dozens
>   of tile requests; proxying them repeats the team-stats mistake at far worse volume (every tile = one
>   Worker invocation against the 100k/day cap). The proxy would serve only the small JSON (frame list,
>   warning polygons). `MKTileOverlay` renders these natively in MapKit.
> - Venue lat/lon already exists — the ESPN-venue-id table in the proxy's `/weather`.

> ### 📊 TEAM-PAGE STATS BURST — ~27 direct ESPN calls per team-page open (found 2026-07-30, DEFERRED by owner)
> `TeamDetailViewModel.load` fans out **one ESPN Core-API call per athlete, in parallel, from the
> device** — bypassing the proxy entirely (no edge cache, no last-known-good, no cross-user dedupe;
> `AthleteStatsCache` is session-scoped so a relaunch refetches everything).
> ⚠️ **The trigger is opening a TEAM page, not tapping a player** — the team-leaders board needs every
> squad member's stat line, so the ordinary "who's wearing #7" gameday glance pays the whole burst.
> **This rules out app-side lazy-loading as a fix.**
> At 1k users: ~21.6k direct ESPN calls/day. Realistic failure = per-device burst throttling → a stats
> card with players silently missing rows. **Fix = a bundled `/team-stats?team={id}` proxy route**
> (27 requests → 1, edge-cached, shared) built on Queues (450 calls > the 50-subrequest budget).
> Owner deferred 2026-07-30: rosters are the correctness problem, this is a scaling one. Full sizing in
> **`docs/stress-testing.md` §6**.

> ### 🎮 FAN ZONE — a long-horizon iteration loop, NOT a one-session build (owner 2026-07-27)
> Four mini-games plus a Superfan point economy tying them together. The owner's framing, worth holding
> onto: **designing games is far harder than it looks and takes many revisions and trial-and-error.** The
> 2026-07-24 competitive redesign was a big improvement, but a few things still don't feel right — the
> target is that it feels **instantly big and connected**, and getting there is a matter of several more
> passes, not one more change.
>
> **Expected working rhythm:** change → TestFlight → live with it for a few weeks → adjust from real use →
> TestFlight again → repeat. Over months.
>
> **How to work on this (for future sessions):** don't treat a Fan Zone ask as a single-session build, and
> don't propose sweeping rewrites between passes — small, reversible tweaks that can be felt in real use
> beat big swings. Expect the owner to sit with a change before judging it. Instrument what's cheap to
> measure, but weight her lived impression above metrics at this scale. Read `docs/fan-zone.md` and
> `.claude/rules/fan-zone.md` (LOGIC GATE, incl. invariant #7) before touching any of it.

> ### ✅ DECIDED 2026-07-31 — Predict per-match scoring stays AS IS (max 88)
> Flagged 2026-07-27 as possibly oversized for a low-scoring sport (halve every value → max 44).
> **Owner decided against it:** the season view moved to an AVERAGE-based board (2026-07-24 redesign),
> which is what actually made the per-match numbers legible — so the raw magnitude no longer misleads.
> Values stay `XIPrediction.swift`: +3/starter · +2/position · +5 formation · +10 exact score ·
> +3 result · +15 perfect XI. **Don't re-propose halving** without a new reason.

> ### ✅ DONE 2026-07-24 — Predict average-leaderboard migration (Batch 3)
> APPLIED by the owner (confirmed 2026-07-27). `supabase/migration_predict_avg_leaderboard.sql` (idempotent,
> additive: `prediction_scores` gains `matches` + `avg_points` + an index). Until it's applied, the Predict
> SEASON board's rivals degrade to empty (honest — the season CARD, recent results, and round board all use
> other data and keep working); after it's applied + a client sync, the board ranks by average per match.
> The seeder (`nwslapp-proxy/scripts/seed_test_fans.mjs`) now writes the two columns, so `--purge` +
> re-seed makes the seeded average board realistic for the visual pass.

> ### ✅ DONE 2026-07-24 — Fan Zone v3 migrations
> ALL FOUR APPLIED by the owner, and the proxy deploy is done (confirmed 2026-07-27). For the record:
> `migration_fanzone_progress.sql` (game-progress restore), `migration_predict_round_scores.sql`
> (Predict round boards), `migration_bracket_final_rank.sql` (final ranks + the bracket_votes
> service_role DELETE grant), `migration_retention_cron.sql` (pg_cron prunes; needs the pg_cron
> extension toggle on the free tier — Database → Extensions if the CREATE EXTENSION errs).
> Plus one proxy deploy (`wrangler deploy` in ~/Projects/nwslapp-proxy — quiz-results reveal rule +
> bracket rank stamping ride together).

> ### 🎡 NWSL Trivia — content pipeline ONLY (structure SHIPPED 2026-07-23)
> The biweekly-round STRUCTURE (rounds, landing page, retention, community model) is built — the app
> already treats Trivia as biweekly 10-Q rounds alternating with KHG. What remains is CONTENT: the
> annual ~530-question generation (tuned prompt + evergreen/season-bound tagging + difficulty
> stratification per `docs/nwsl-trivia-weekly-redesign.md` content rules) and its Claude-Routine
> loader. Until then the current stocked pool serves rounds with a deterministic slice (repeats
> after ~4 rounds — acceptable interim, owner-approved).

> ### 🏆 The Bracket → offseason-first, semi-automatic (decision LOCKED; the one code change is NOT done)
> **Decision (locked, owner):** stop running The Bracket year-round on a fixed cadence. Make it primarily
> an **offseason** feature, with maybe **1–2 editions during the season**. You stock a library of themes;
> the engine only advances rounds. ("Tentpole" just meant *the anchor feature that carries the offseason* —
> the thing that gives people a reason to open the app when the other three games are quiet.)
>
> ⚠️ **Verified 2026-07-27: the one required code change is still OUTSTANDING.** `handleAuto` in
> `bracket-engine.ts` still calls `generateNext()` once `break_days` elapses, i.e. auto still STARTS
> editions by itself. Until that becomes advance-only, the locked decision isn't actually in force.
>
> **Why — the content-calendar gap.** In season the Fan Zone is already full: KHG and Trivia alternate
> biweekly (a new round every Monday, each playable for two weeks) and Predict the XI runs any week
> with fixtures. That's plenty. But **both KHG and Predict are in-season ONLY** — KHG's featured
> players are picked from season stats, and Predict needs a fixture inside its 28-day window (it hides
> in a true offseason). So the offseason falls back to **Trivia alone**. Bracket is the natural filler:
> it's the one game that needs no live fixtures, no season stats, and no new editorial content per
> round — the engine generates it from the league pool. Offseason is exactly when the app most needs a
> reason to open, and when Bracket has the least competition for attention.
>
> **The model (owner, 2026-07-23) — "semi-automatic":** the operator curates a LIBRARY of themes (jot
> ideas down during the season, drop 3–4 in when the offseason arrives); **auto mode's only job is to
> advance rounds when the timer runs down.** Editions are STARTED by hand from the library, not
> generated on a break timer. Run it ~3–4 times a year, ~3 weeks each.
>
> **⚠️ Most of this already exists — don't rebuild it.** `bracket_creative_editions` /
> `bracket_stats_editions` ARE the library: per-theme `status` (`ready` | `parked` | `used`) + a
> `season` column that gates no-repeats, plus `used_themes_this_season` in `bracket_config` which
> `generateNext` skips against. The admin portal already has Add creative theme, Edit title,
> Park / Set ready, Delete, **Start specific**, Start next (rotation), and Clear used themes.
>
> **So the actual remaining work is a REDUCTION, not a build:**
> - **Stop auto from auto-STARTING editions.** `handleAuto` currently generates a new edition once
>   `break_days` elapses with none active. The wanted behaviour is advance-only: tally + advance while
>   an edition is live, then STOP when it completes and wait for the operator. That also removes the
>   need for any "is it the offseason?" signal — the operator's start IS the signal, which is far
>   cheaper than teaching `FanZoneCadence` an offseason concept it doesn't have.
> - **Re-pick the pacing** for a 3-week offseason edition (today `early_round_days=2`,
>   `late_round_days=3`, `break_days=10` → ~3–4 weeks + a ~10-day break); `break_days` becomes
>   irrelevant once editions are operator-started.
> - **Admin-portal controls** adjusted to match (the start/advance emphasis, less mode-toggling).
> - **💡 Fan-submitted theme ideas** (owner's "maybe have a way for people to recommend things") — a
>   genuinely new piece, and a nice ALIVE/community hook: suggestions land in the library as `parked`
>   for the operator to promote to `ready`. Needs a moderation path before it ships.
>
> **Already fixed (2026-07-23), don't re-diagnose:** the admin portal's AUTO/MANUAL switch wrote only
> the global `bracket_config` key while each edition carries its OWN `mode`, so switching an in-flight
> edition to AUTO silently did nothing (`handleAuto` skips a manual-mode edition). `setMode` now
> carries the mode onto the active edition and stamps `round_opened_at`/`round_closes_at` so the
> countdown starts. The ROUND SCHEDULE itself was never broken and is unit-tested (`bracket.spec.ts`).

> ### ✅ DONE — analytics + alerting go-live (owner-confirmed 2026-07-27)
> All arms are LIVE: analytics migration, Resend error-spike email, healthchecks.io dead-cron watchdog,
> and UptimeRobot route monitors.
>
> ⚠️ **Scope gap worth knowing (verified 2026-07-27): the email pager does NOT cover APP CRASHES.**
> `checkErrorSpike` scans **only** `sdiag:` (proxy server-origin diagnostics) and deliberately skips the
> client `/telemetry` stream, because that endpoint is unauthenticated and spoofable — counting it would
> let anyone trip the alert. So an iOS crash (e.g. the Predict picker crash) can never page; Apple's own
> "report this crash" prompt is currently the only signal. This is by design, NOT a threshold being tuned
> too low. The one deliberate softening is narrow: `apiFailure` events whose detail starts with
> `image fetch ` are excluded from the PAGING count (expired IG/YouTube thumbnail URLs — the false alarm
> you remember); they still land in telemetry and the in-app Diagnostics screen. Thresholds are ≥8 error
> events in 15 min, max one email per hour. For app-crash visibility the cheap path is Apple's own App
> Store Connect / TestFlight crash notifications + Xcode Organizer, not building a second pager.
>
> Historical setup steps, all now complete:
> 1. ✅ **Supabase migration — DONE (2026-07-22):** `supabase/migration_analytics_counters.sql` applied,
>    so counters now record. (No more `analyticsRpcFail: increment_counters 404` in /telemetry/recent.)
> 2. **Resend** (error-spike email): create a free account at resend.com → API key →
>    `wrangler secret put RESEND_API_KEY` + `wrangler secret put ALERT_EMAIL` (your address) in
>    ~/Projects/nwslapp-proxy. Threshold ≥8 error events/15min, max 1 email/hour.
> 3. **healthchecks.io** (dead-cron watchdog): free account → new check, period 2 min / grace
>    3 min → copy the ping URL → `wrangler secret put HEALTHCHECK_URL` in
>    ~/Projects/nwslapp-match-watcher. If the watcher cron ever stops, THEY email you.
> 4. **UptimeRobot** (route uptime): free account → HTTP monitors on the proxy `/config` and the
>    watcher `/` root. No code involved.

> ### ✅ ACTIONED 2026-07-31 — force-update gate raised for the FIRST time (`minBuild` 21 → 31)
> `/config` had served `minBuild 21` since forever, so the gate had never fired for anyone and the
> known-broken **build 28** was still permitted. Build 31 (TestFlight) ships with `MIN_APP_BUILD = 31`,
> retiring everything ≤30.
> ⚠️ **ORDER MATTERS AND IS THE WHOLE RISK.** The proxy deploy must come AFTER build 31 is live and
> installable on TestFlight — deploying the gate first walls every user on 30 (including the owner's own
> device) with nowhere to go. The app bump merged first; the proxy change is committed and deploys on
> confirmation. See `docs/versioning.md`.

> ### 📋 PRE-PUBLISH — privacy package (needed BEFORE App Store submission; target mid-Aug)
> Lower priority than ALIVE work but MUST exist at submission (owner 2026-07-16 — track it here so
> it isn't lost):
> - **App Store privacy label** (filled in App Store Connect): Data Linked to You = Contact Info
>   (Sign in with Apple email/account). Data Not Linked to You = Diagnostics + Usage Data (the
>   anonymous telemetry + counters). Data Used to Track You = **None** (no ATT prompt).
> - **Privacy policy page** (Apple requires a URL at submission): write from the 2026-07-16
>   honest-language work — values as promises (no ads; no data sold; no third-party/cross-app
>   tracking), what IS collected (account basics; anonymous aggregate diagnostics/usage, never
>   linked), retention, delete-account. Host it (GitHub Pages is $0) + paste the URL in ASC.
> - README/showcase copy already reframed to match (PR #152); CLAUDE.md carries the
>   values-vs-mechanics stance so future copy stays consistent.

> ### ♿ PRE-RELEASE GATE — accessibility: **VoiceOver is the only part left** (owner 2026-07-21)
> Accessibility is a release gate, not a nice-to-have — in an inclusive space like NWSL it must not be
> overlooked. **Two of the three parts are now DONE** (owner-confirmed 2026-07-31):
> - ✅ **Dynamic Type / AX1** — cap decided, whole app swept, every screen passes (detail below).
> - ✅ **Colour-blind** — deuter/protan/tritan simulation across the app found **no failures**;
>   existing rules carry it (✓/✗ glyph shapes, crest+abbreviation, text "your pick" labels).
> - ❌ **VoiceOver — THE REMAINING WORK.** Partial today: 16 files carry a11y modifiers, so it is not
>   zero, but there has been no systematic pass. This is what blind users need to use the app at all,
>   and it's the reason the AX1 cap is defensible (users needing >AX1 are served by VoiceOver + Zoom).
>   Scope below.
>
> **VoiceOver scope:** custom-DRAWN elements need
>   explicit `.accessibilityLabel` (formation-pitch dots, `StatComparisonBar`, score header, live clock,
>   image-only crests/headshots); GROUP compound units so a match card reads as one element ("Chicago 0,
>   Angel City 2, Full Time") not fragments; revisit the Dynamic Type **AX1 cap** per-screen (density vs
>   larger AX sizes — trade-off).
> - **Color-blind:** never rely on color ALONE — redundant encoding (letter/shape/icon) + respond to
>   `@Environment(\.accessibilityDifferentiateWithoutColor)`, usually better than a custom mode.
>
> #### ✅ Dynamic Type / AX1 — SETTLED 2026-07-29 (the cap question above is now ANSWERED)
> **The cap STAYS at AX1** (owner decision, after testing MLS / NWSL / MLB / Reddit / Swift Alert on
> device). Consequences, and the standing rule:
> - **AX1 is the largest size the app promises, so it must lose NO data.** AX2–AX5 all resolve to AX1
>   (verified: the maximum system setting renders pixel-identically), so AX1 IS the worst case — there's
>   nothing above it to test.
> - **Don't lift the cap.** At AX5 body text is 53pt on a 402pt screen ≈ 7 characters per line; no
>   layout survives it, which is why every app that permits it breaks (MLB shatters; MLS's club pages
>   overlap; Swift Alert breaks too). A predictable cap is a more honest contract than an uncapped
>   layout that collapses. Users who need >AX1 are served by **VoiceOver + iOS Zoom**, which work
>   regardless of the cap — that's where the remaining effort belongs, not here.
> - **The bar** is *same layout, same information, nothing hidden, nothing overlapping* — NOT "looks
>   identical" (bigger text legitimately means fewer cards per screen).
> - **Severity ladder:** **overlap = always broken** > truncating a value available nowhere else = bug >
>   truncation where the full value is one tap away (a fixed-size carousel card) = fine, leave it.
> - ⚠️ **A fixed-HEIGHT container must CLAMP its text** (`lineLimit`), or the text escapes its bounds
>   and collides — that's exactly how the MLS roster cards break. Clamped truncation is the SAFE
>   failure mode; unclamped overlap is not.
> - ⚠️ **MEASURE before redesigning.** Standings was assumed to need a graduated fix from ~xLarge up;
>   stepping through every size showed it clean across the ENTIRE standard range (xSmall…xxxLarge) and
>   broken only at AX1 — which shrank the work to one threshold. The reflex to redesign for "large text"
>   generally overshoots.
> - **Swept 2026-07-29** (five tabs, both quiz results panels, Bracket, Teams, Schedule, Social,
>   Superfan, Match Detail): PASS everywhere after fixing Superfan tier blurbs, Bracket edition titles,
>   Standings, and the Match Detail tiles + kickoff date. Colour-blind pass (deuter/protan/tritan
>   simulation, `cvd.py` method) found **no failures** — existing rules carry it: ✓/✗ glyph shapes, the
>   crest+abbreviation naming rule, "your pick"/"YOUR PICK" text labels, positional bars. Thinnest
>   margin = Standings form chips (W and L are the same colour under deuteranopia; only the W/L/D
>   letters distinguish them, so never swap those letters for coloured dots).
> - NOT done, deliberately: the Teams grid's uneven tile borders when club names wrap (cosmetic).
> **First step when picked up:** run the VoiceOver audit in the sim screen by screen, then work the
> punch-list. Dynamic Type and colour-blind are closed — do NOT re-audit them.
> (Dark-only is NOT an a11y issue — the app's colour balances it.)
> Also still pending here, unrelated to a11y: profanity-filter the editable leaderboard display name
> before public launch.

> ### ✅ SHIPPED + PROVEN — Know Her Game weekly automation (built 2026-07-13, proven through 2026-07-27)
> The full no-human weekly loop is BUILT (proxy branch `feature/knowher-weekly-automation`): deterministic
> prompt assembly (`assemble_knowher_prompt.mjs` fills the Rodman-faithful `knowher-weekly-TEMPLATE.md`
> from `/knowher/todo`, which now serves age/country + keeper stats), a dedicated-key
> **`POST /knowher/ingest`** (validate → KV → markFeatured, diag on every outcome), a `knowherStaleWeek`
> serving watchdog (in-season, 1/day), and the committed cloud-routine runbook
> (`knowher-weekly-routine.md`). Proxy DEPLOYED + prod-probed; `node --test` 14/14. The scheduled Claude
> Routine runs Mon 06:00 UTC (2am ET) on **Opus 4.6** — GitHub connected, four editions published
> (W27/W29/W30/W31). Monday user nudge = the existing local 10 AM notification (unchanged).
> ⚠️ **Three durable gotchas learned 2026-07-27 — see `docs/know-her-game.md` before touching this:**
> the routine's MODEL lives in the trigger's `job_config`, which the claude.ai UI does NOT write (set it
> via the RemoteTrigger API or every run silently reverts); `scripts/load_knowher.mjs` bypasses the
> featured ledger and is now guarded; and a one-second ESPN blip can silently drop a club from an edition
> (the assembler is fail-open — it logs a GAP and ships short). Engine question CLOSED (owner): the Rodman-WORKING prompt is final;
> `knowher-generation-prompt.md` (untested self-audit variant) deleted. Detail: `docs/know-her-game.md` §5d.

> ### 🧹 CLEANUP — remove the DEBUG postseason simulator's baked-in 2025 data (owner-parked)
> **Kept ON PURPOSE (owner, 2026-07-07):** `PostseasonSimulator.swift` carries real 2025 bracket +
> clinch data so the owner can exercise the Playoffs feature in-sim over the next few days before the
> real Nov postseason. It is 100% `#if DEBUG` + launch-arg-gated (`-simulatePostseason2025…`) → compiles
> out of Release/TestFlight and shows NOTHING in normal builds (scheme flag is off), so it is harmless to
> ship as-is. **When the owner says they're satisfied:** strip the fake 2025 seeding data from
> `PostseasonSimulator.swift` (or delete the sim harness) so no hard-coded 2025 bracket lingers in the
> app source. The unit tests that reference `PostseasonSimulator.clinchTable` (`PlayoffClinchTests`) move
> to inline fixtures at that point. Nothing auto-reminds — this note is the reminder.

> ### 🧹 PRE-LAUNCH GATE — purge the Fan Zone seed test population (owner 2026-07-23)
> The pre-launch seeder (`nwslapp-proxy/scripts/seed_test_fans.mjs`) creates real `@seed.nwslapp.test`
> `auth.users` so the crowd-shaped surfaces (leaderboards, community splits, Superfan ladder) can be
> designed against before there are real players. **Retention does NOT clean these up** — the cron only
> prunes `quiz_answers` (>35d) and `predict_round_scores` (>28d); the record book it writes
> (`prediction_scores`, `superfan_scores`, `profiles`) is kept FOREVER by design, and the `auth.users`
> rows never expire. So the seed fans would rank on real leaderboards and count in real aggregates
> permanently until explicitly torn down. **Before launch:**
> - `node scripts/seed_test_fans.mjs --purge` — deletes the `@seed.nwslapp.test` accounts; `on delete
>   cascade` sweeps all six seeded tables clean.
> - Then run the **REVOKE block** at the bottom of `supabase/migration_seed_grants.sql` — returns the
>   service_role key to exactly the reach it had before seeding.
> Enforced, not remembered: `health_check_seed_accounts.mjs` FAILS the `npm run healthcheck` chain while
> any seed account exists — that gate is why seeding against the prod project is safe at all.

> ### ✅ SHIPPED — Fan Zone v2 (2026-07-22, merged to main)
> The Fan Zone v2 batch is DONE + on main (detail in git + `.claude/rules/fan-zone.md`):
> - **Superfan Zone:** the trailing "Superfan" carousel card is now TAPPABLE → `SuperfanDetailView`, a
>   cross-game season stats hub (season total, competitive tier + percentile, per-game breakdown, "Your
>   best moments"). New backing: `superfan_scores` Supabase table + `SuperfanService`/`SuperfanStats`;
>   season-scoped, passes the 1k stress gate. ✅ **`migration_superfan_scores.sql` applied.**
> - **Know Her Game → BIWEEKLY + landing page:** KHG now alternates the Fan Zone quiz slot with NWSL
>   Trivia (Week 1 = KHG), editions numbered "Round N"; the old `KnowHerPickerView` is now the richer
>   `KnowHerLandingView` (This round · Last round · How players are chosen + "all caught up" state).
> - **NWSL Trivia FACELIFT:** the play screens were rebuilt onto the Know Her Game community-family
>   pattern (intro, progress dots, tap-to-answer, shared `ScoreRing` + `CommunityResultsView`). ⚠️ That
>   pass was PLAY-SCREENS ONLY and left the front door diverged — **superseded 2026-07-23** by the full
>   round rebuild (`TriviaLandingView` + `TriviaRoundView`, biweekly rounds), which closed the remaining
>   community-family drift. Only the question-generation pipeline is still parked (see Pending, below).
> - **Team-color vibrancy (Predict + Player Detail):** new shared `TeamWashBackground`
>   (`Components/TeamColorWash.swift`) on the Predict fixture/result + "Predictors" leaderboard cards,
>   `MatchCard` migrated onto it; "Playing as" now a consistent below-nav strip across all games.

> ### ✅ CLOSED 2026-07-13/16 (kept as one-liners; detail in git/memories)
> - **Live-clock / staleness / Match-Detail (build 26):** DEVICE-VERIFIED 2026-07-13 — count-up past
>   60', stoppage `45+7`/`90+6`, HT/FT, no pan; two display-only wording follow-ups remain (Match
>   Detail live-label form + V2 HT dedupe — see the wording-followups memory/session notes).
> - **Lineup-crest wrong-team:** resolved + device-verified 2026-07-10 (crest only on GOAL/RED CARD).
> - **Follows restore:** closed 2026-07-13 (owner) — restore-on-reinstall behaving across real uses.
> - **Polling efficiency (2026-07-16):** watcher fixture-window + app confederation scoping + 60s
>   in-app cadence + push-triggered refresh — merged (app #152/#153, watcher #27) + deployed; watch
>   the Cloudflare graph fall from ~23-28k/day as the visible proof. `docs/national-teams.md`.
> - **Involuntary sign-out fix (2026-07-16):** merged (app #152). On-device check on the next
>   TestFlight: exact toggles restore on re-sign-in; Notifications rows read OFF signed-out.
> **TEMP instrumentation stays on purpose:** the `Diagnostics.debugTrace` case + the reconcile trace in
> `FollowSyncCoordinator` remain in the code until this test passes — then remove them (Step C) and mark
> this done.

Pending work only (ALIVE > core > hardening); shipped work lives in git history + the File Map.
- **The Bracket v2 — built, awaiting owner deploy:** run the 4 SQL files (`migration_bracket_v2`
  → `migration_bracket_qualifying` → `seed_bracket_stats_editions` → `seed_bracket_creative_editions`)
  + `npm run deploy` (proxy) + the first-launch flow (`Reference/Bracket Battle/first-launch-checklist.md`).
  Optional later: more stat/creative themes; full bracket-TREE graphic.
- **First-launch perf** — Tier 1+2 shipped; onboarding quick-tips screen DEFERRED (build only if wanted).
- **YouTube Shorts thumbnail pillarbox** — DEFERRED; fix is proxy-side.
- **Pull-to-refresh polish** — keep the list visible during refresh (spinner only on first load).
- **Home follow-ups:** spotlight no-repeat-per-season + opt-in weekly notif.
- **Player headshots Phase B2 banners** — DEFERRED (licensing).
- **Accessibility** — now a PRE-RELEASE GATE (see the ♿ callout above): VoiceOver + color-blind pass before launch.
- **NWSL Trivia — question-generation pipeline (PARKED; STRUCTURE SHIPPED 2026-07-23)** — the biweekly
  ROUND model, landing page, retention and cadence are all built and live; the app already asks for
  "round N's 10 questions" and doesn't care where they come from. What remains is CONTENT ONLY: the
  annual ~530-question generation (tuned prompt, evergreen vs season-bound tagging, per-round difficulty
  stratification, fact-check pass) + its loader/routine. Until it lands the stocked 41-question pool
  serves rounds with a deterministic slice — 4 unique rounds, then it repeats (accepted interim).
  📄 The design doc is on the parked branch: `git show docs/nwsl-trivia-weekly-redesign:docs/nwsl-trivia-weekly-redesign.md`.
  ⚠️ Read it for the CONTENT rules only (530-pool → 53 slots, evergreen tagging, difficulty mix,
  annual regen). Its UI/cadence half is SUPERSEDED — it says "weekly / not yet built"; the app shipped
  BIWEEKLY rounds + the landing page on 2026-07-23. Current truth: `docs/fan-zone.md`.
  (community family), but the engine rebuild (`docs/nwsl-trivia-weekly-redesign.md`: weekly cadence,
  10 questions/wk, 530-pool → 53 weeks, annual regen, stat-questions-in-code) is the next Fan Zone build.
- **More team-color vibrancy (owner interested 2026-07-21)** — Predict cards + schedule `MatchCard` +
  player detail now carry the wash (via `TeamWashBackground` / `accentHex`, shipped in Fan Zone v2). STILL
  pending: extend it to more surfaces so club color carries further (candidate surfaces: Home header, Team
  detail, Standings followed-team rows, the Squad grid). Keeps the neutral-canvas philosophy — color comes
  from the TEAMS, not the chrome; the crest/abbreviation identity rules still hold. Design pass, scope
  per-surface with the owner (don't recolor chrome globally). Reference: MatchDetail header wash.

**Hardening (after ALIVE work):**
- `Fixtures/scoreboard.json` + decode-only test for `Scoreboard`/Event helpers (date parsing, `dayKey` TZ).
- `MatchStore.matches(for:)` joins club↔game by `abbreviation` (no ESPN id) — a rename silently empties a schedule. Fix: a normalized id map.
- Team social links — verify a few subreddit handles (KC `r/KCCurrent`; CHI `r/redstars` vs `r/ChicagoStars`).
- **Club-page links data pass** — Website · Shop · Tickets (OFFICIAL) + Discord (Fan) → `SocialPlatform` + `TeamSocialLinksProvider`, per-club.

**Longer-term:**
- **Push — Tier 2 (SERVER push) — SHIPPED** (Stage A–D done: watcher cron + KV diff + APNs JWT, per-team
  targeting, `APNS_HOST=production`, lineups-posted, red-card/VAR; NT alerts by FIFA code). Delivery now
  rides **Cloudflare Queues (V1) + APNs Broadcast Channels (V2)** — `docs/push-fanout-scaling.md`. Still
  open on the CLUB-competition axis: **Champions Cup / Challenge Cup (`usa.nwsl.cup`) push** — the watcher
  polls the NWSL + NT scoreboards but not these club-comp slugs; needs their slugs + a competition-aware
  card footer/title (carry the comp label through the pipeline). (The old "self-hosted crest primary is
  dead" item is RESOLVED — that was CF error 1042 from fetching the proxy over its public URL; `card.ts`
  now uses the PROXY service binding, so self-hosted `/crest` is the working primary, ESPN the fallback.)
- **Competitions follow-ups:** Challenge Cup (`usa.nwsl.cup`, single annual match) + Champions Cup + followed NTs fold into Schedule "My teams" (NT coverage now 16 feeds, shipped). WWC/Olympics whole-tournament UI DEFERRED; foreign-club color DB grows as Champions Cup opponents appear (`DesignTeamColors.international`).
- **Feed** — user-added sources; richer filtering. **Weather** — kickoff-temp header slot.
