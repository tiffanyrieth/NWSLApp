# Roadmap / What's Next

> **Open blockers only.** This is the owner's personal punch-list — meant to go DOWN. When an item is
> done or dropped it's removed (git history keeps the record); durable lessons live in the system docs
> (`docs/backend.md`, `live-activity-v2.md`, `notifications.md`, `decisions.md`, …), not here. Order
> follows the app's priority: ALIVE > core > hardening.

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

> ### 🎡 NWSL Trivia — content pipeline ONLY (structure SHIPPED 2026-07-23)
> The biweekly-round STRUCTURE (rounds, landing page, retention, community model) is built — the app
> already treats Trivia as biweekly 10-Q rounds alternating with KHG. What remains is CONTENT: the
> annual ~530-question generation (tuned prompt + evergreen/season-bound tagging + difficulty
> stratification per `docs/nwsl-trivia-weekly-redesign.md` content rules) and its Claude-Routine
> loader. Until then the current stocked pool serves rounds with a deterministic slice (repeats
> after ~4 rounds — acceptable interim, owner-approved).
> 📄 The design doc is on the parked branch: `git show docs/nwsl-trivia-weekly-redesign:docs/nwsl-trivia-weekly-redesign.md`.
> ⚠️ Read it for the CONTENT rules only (530-pool → 53 slots, evergreen tagging, difficulty mix, annual
> regen). Its UI/cadence half is SUPERSEDED — the app shipped BIWEEKLY rounds + the landing page on
> 2026-07-23. Current truth: `docs/fan-zone.md`.

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

> ### 🎯 PREDICT "VS THE BOARD" on the LOCKED screen — implement the thin-population rule (owner 2026-08-06)
> **Rule (decided):** if only ONE vote was cast before the fixture locked (i.e. just you), **SKIP the
> community-stats reveal entirely** — don't render the 100%-everything bars or the empty contrarian
> panel. Show a simple "in progress" / sealed-until-results state instead. Once more than one fan has
> voted, show the reveal as normal.
> ⏳ **To implement (small):** gate the locked-screen community section on submission-count > 1.

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

> ### 📜 NT LIST SCROLL JUMP — 🔴 CONFIRMED ON DEVICE (owner 2026-08-06). Real bug; does NOT repro in sim.
> **Device repro (owner):** cold-start → National Teams → scroll to roughly halfway OR near the bottom →
> **STOP** → tap follow on a country → the list jumps **UP 3–4 rows**. The follow DOES register (scroll
> back down and that country reads followed), but the tap yanks the scroll position up 3–4 rows every
> time. It happens with the list **fully stopped**, so it is NOT scroll momentum.
> ⚠️ **Two structural hypotheses measured 0.0pt in the SIM — but the sim doesn't reproduce the bug at
> all, so treat these as "not the sim-harness cause," NOT "ruled out on device," and still do NOT
> re-propose either as the fix:**
> (a) *"the card grows when followed"* — the bell sits in a fixed 32pt row; gradient/stroke are
> background layers; (b) *"the in-cell NavigationLink(destination:) causes it"* — the fix that would
> imply **reverses a documented fix**: `CombinedPitchView.swift:74-80` records that registering
> `.navigationDestination(for:)` on a PUSHED child mis-scoped the destination and double-pushed
> MatchDetail (2026-07-18); `CompetitionsView` is also pushed. Don't move the destination registration.
> **Mechanism to chase:** tapping follow mutates the followed-set, which re-identifies/re-lays-out the
> row and SwiftUI loses scroll anchoring in the `List`/`ScrollView`. Investigate stable row `.id` +
> scroll-position preservation on the NT list — not navigation.
> **Why sim can't see it:** measured 0.0pt shift signed-out/in, first-follow/repeat, at the very bottom
> (URU → VEN → VIE → WAL → ZAM). idb swipes are discrete; the device's real scroll state is what exposes
> it. This one needs on-device iteration.
> ✅ Fixed anyway while in there: `NationalTeamCard` had no `.contentShape(Rectangle())`, so only the
> flag/code/name glyphs were tappable rather than the whole card (regression from `0141876`).

> ### 🕐 LIVE STATE — trust the SEQUENCE, never a single snapshot (fabricated kickoff PARKED)
> Live match state has broken three times, each a different mechanism, each from trusting ONE field.
> Three are fixed (see git history + `docs/backend.md` / `live-activity-v2.md`); the **fabricated
> kickoff** variant is the one still open:
> | Variant | ESPN says | Reality | Status |
> |---|---|---|---|
> | **Stale cache — ESPN's** (2026-07-11) | old-but-valid | clock stuck all game; read `pre` 47min after KO | ✅ fixed build 26 |
> | **Stale cache — OURS** (2026-07-31) | frozen mid-suspension | resumed + finished | ✅ fixed proxy #70 |
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
> an *inferred* mechanism, and we would have no way to tell whether it worked. The July match also
> self-healed.
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

> ### 🔐 MULTI-DEVICE INTEGRITY — atomic-pair merge (🅿️ PARKED, owner 2026-08-04)
> _(The render-bug that doubled a row was fixed in #195. The "Superfan doubling" investigation was
> removed 2026-08-06 — Superfan has been reworked past its original cause; owner re-raises only if seen again.)_
> **⚠️ STILL OPEN — correlated pairs are max-merged INDEPENDENTLY.** `prediction_scores` maxes `points`
> and `matches` as separate scalars, and `SuperfanCounts.merged` maxes each game's `correct` and `total`
> separately. Device A at 100 pts / 5 matches and device B at 80 / 6 merge to 100 / 6 → avg 16.7, a
> number **neither device produced**. Fix: merge each pair ATOMICALLY — take the side with more progress
> (the greater denominator) whole, never a numerator from one and a denominator from the other.
> **🅿️ PARKED for now (owner 2026-08-04) — revisit AFTER Fan Zone if it recurs.**
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

> ### 🪪 DISPLAY-NAME UNIQUENESS + PROFANITY — 🟡 BUILT 2026-08-06, pending owner migration apply
> **Decisions (owner 2026-08-06):** global, case-insensitive, first-come uniqueness (renaming frees your
> old name); profanity/slur filter only for v1 (no club/player impersonation lists yet); enforced
> client-side AND server-side; a rename AUTO-UPDATES the leaderboards (no rank reset). Was: `profiles.
> display_name` had no unique constraint (10 collisions across ~120 seeded fans) and no content filter.
>
> **Built on `feature/display-name-uniqueness`:**
> - `supabase/migration_display_name_uniqueness.sql` — `blocked_names` table + seed, `display_name_
>   rejection()` fn, a BEFORE-write trigger on `profiles` (unbypassable profanity guard), `check_display_
>   name()` advisory RPC (RLS blocks a client from reading others' profiles), `set_display_name()` RPC
>   (atomic: writes profiles + CASCADES the new name to `prediction_scores` / `predict_round_scores` /
>   `superfan_scores` / `bracket_scores`), seed-dedup + `unique index on lower(display_name)`.
> - App: `AuthStore.updateDisplayName` → server-first + **throwing** (was optimistic + swallowed errors —
>   the banned looks-like-success shape); `checkDisplayName`; `DisplayNameError`; `DisplayNameEntry` now
>   does a debounced live availability/filter check + inline errors and only advances on a real save.
> - `nwslapp-proxy/scripts/seed_test_fans.mjs` → generates unique names so re-seed survives the index.
>
> **🔴 REMAINING (owner):** apply the migration in the Supabase SQL editor (it self-dedupes seed names, so
> it applies today). Then verify with two `-signInAsTestFan` accounts (take a taken name → blocked; rename
> → boards update; profane name → blocked). Verification queries + apply steps are in the session handoff.
> Load: one indexed lookup per name entry; rename = a few indexed UPDATEs — both rare, pass 1k/100k.

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
>   simulation, `cvd.py` method) found **no failures**. Thinnest margin = Standings form chips (W and L
>   are the same colour under deuteranopia; only the W/L/D letters distinguish them, so never swap those
>   letters for coloured dots).
> - NOT done, deliberately: the Teams grid's uneven tile borders when club names wrap (cosmetic).
> **First step when picked up:** run the VoiceOver audit in the sim screen by screen, then work the
> punch-list. Dynamic Type and colour-blind are closed — do NOT re-audit them.
> (Dark-only is NOT an a11y issue — the app's colour balances it.)
> (The display-name profanity filter that used to be parked here is now BUILT — see the display-name
> uniqueness item above.)

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

> ### 🧹 CLEANUP — remove the DEBUG postseason simulator's baked-in 2025 data (owner-parked)
> **Kept ON PURPOSE (owner, 2026-07-07):** `PostseasonSimulator.swift` carries real 2025 bracket +
> clinch data so the owner can exercise the Playoffs feature in-sim over the next few days before the
> real Nov postseason. It is 100% `#if DEBUG` + launch-arg-gated (`-simulatePostseason2025…`) → compiles
> out of Release/TestFlight and shows NOTHING in normal builds (scheme flag is off), so it is harmless to
> ship as-is. **When the owner says they're satisfied:** strip the fake 2025 seeding data from
> `PostseasonSimulator.swift` (or delete the sim harness) so no hard-coded 2025 bracket lingers in the
> app source. The unit tests that reference `PostseasonSimulator.clinchTable` (`PlayoffClinchTests`) move
> to inline fixtures at that point. Nothing auto-reminds — this note is the reminder.

> ### 📏 TYPE AUDIT — ✅ 12pt floor DONE 2026-08-06 · 🕰️ 13-14 secondary tier = a FEW-WEEKS VIBE CHECK
> **✅ DONE (this PR):** a **12pt hard readable-font floor** — every `.dsFont(9…11.5)` bumped to 12 (160
> sites). No floor existed before (119 uses at 11pt); the trigger was the owner's mom (70s) not being able
> to read the app, and the Sim renders desktop-scale so small type "looked fine" but wasn't on a phone
> ([[feedback_size_for_phone_not_desktop]]). Owner research + the AX1 engineering point both land on 12
> ("below 10-11 stays illegible even after accessibility scaling"). Verified default + AX1 on Standings +
> Schedule (no overflow). Exceptions kept: the 5pt bullet-dot icon, `trackedCaps` eyebrows, monograms.
>
> **🕰️ FOLLOW-UP — do NOT do this now (owner 2026-08-06): the 13-14pt "must-read secondary" tier.** Per
> the research, must-read secondary text (Match Detail stat labels, standings secondary numbers) ideally
> wants 13-14, not just the 12 floor. But whether it's *needed* is a **VIBE reaction after living with
> today's change for a few weeks on-device**, NOT a gut call now — and it should be done SURGICALLY per
> screen where the owner's eye says it still reads small, never another blanket bump (that flattens
> hierarchy). Revisit ~late Aug after the 12 floor has been felt on real use.

> ### ⛔ V2 LIVE ACTIVITY WORK — DEDICATED, ISOLATED SESSION ONLY (owner 2026-08-06)
> **Both items below touch the V2 Live Activity system: device-proven, fragile, easy to break (weeks to
> get right — read `docs/live-activity-v2.md` §0 FIRST, never edit from first principles). 🔒 RULE (owner):
> do V2 LA work in its OWN session with NO other tasks in flight — never bundled with unrelated work.**
> (This item was scoped + verified on 2026-08-06 but deliberately NOT built, because that session had
> other work in it — the owner's call, exactly right.)
>
> **1. CLUB-COMPETITION PUSH + V2 LA — 🔴 CONFIRMED GAP (verified 2026-08-06).** Following an NWSL club
> (e.g. Orlando Pride) gets you NOTHING when they play a **Challenge Cup** or **Concacaf Champions Cup**
> match — no goal/FT/red-card/lineup push AND no lock-screen Live Activity — even though the club is live
> and scoring right now. **Owner ruling: this MUST be built** — a followed NWSL club needs push + V2 LA for
> ALL its matches, cups included; alerts vanishing the moment the competition changes makes no sense.
> **Evidence:** the app fetches the cups on their OWN slugs (`usa.nwsl.cup`, `concacaf.w.champions_cup`;
> `Competition.swift:121,130`) so they show in the calendar, but the watcher polls only
> `[NWSL_FEED, ...NT_LEAGUES]` (`nwslapp-match-watcher/src/index.ts:521`) — neither cup slug is in it, and
> they're not in the default NWSL board either. WAFCON pushes only because it's an NT competition IN
> `NT_LEAGUES`. **Scope:** add the two cup slugs to the watcher's CLUB fan-out (by team, like NWSL — NOT
> the NT path) + a competition label on the push card ("NWSL Challenge Cup" / "Concacaf Champions Cup") +
> V2 LA for cup matches + foreign-club card rendering for Champions Cup opponents (crest + name; colors =
> the `DesignTeamColors.international` growth item). ⚠️ The watcher runs Tier 2 AND V2 LA off the SAME event
> list (`index.ts:579` + `startUpcomingActivities` :737) — which is exactly why this is V2-LA-touching.
>
> **2. NT V2 LA — extend the lock-screen Live Activity to national teams (owner 2026-08-06).** Today NTs
> get Tier-2 push (goals etc.) but NO V2 LA card — only **USWNT** was wired for V2 LA ("for now", the
> per-match-channel economics note at `index.ts:141`). Owner wants NTs on V2 LA too, **GATED on passing the
> 1k/100k stress test** (`docs/stress-testing.md §5`): the per-match broadcast-channel economics are the
> open question the stress test answers (channel-per-match × concurrent NT matches × audience). Revisit the
> USWNT-only gate against that result.

---

**Pending work only (ALIVE > core > hardening); shipped/decided/dropped work lives in git history + the File Map.**
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
- **Competitions follow-ups:** national-team coverage is DONE (16 NT feeds, WAFCON live + Tier-2 pushing).
  Residual (NOT the cup PUSH — that's the ⛔ V2 LA block above): the CLUB cups folding into Schedule
  "My teams", and foreign-club colors as Champions Cup opponents appear (`DesignTeamColors.international`).
  WWC/Olympics whole-tournament UI stays DEFERRED.
- **Weather** — kickoff-temp header slot (nice-to-have, stays). _(User-added feed sources SHIPPED in the
  Social Phase-3 "make it yours" pass — Bluesky reporters + player follows; that line is retired.)_
