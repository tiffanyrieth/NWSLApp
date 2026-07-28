# Roadmap / What's Next

> ### 🔐 MULTI-DEVICE / DUPLICATE-ACCOUNT INTEGRITY (owner 2026-07-27) — no false numbers, ever
> Trigger: the simulator signed in with the owner's Apple ID appeared to disturb her real Superfan data.
> Owner's (correct) instinct: **this matters far beyond the sim.** A real user gets a new phone, signs in
> with the same Apple ID, maybe opens the app once on the old phone — that must never double a Superfan
> score or report false Predict numbers.
>
> **✅ VERIFIED SAFE — doubling is structurally impossible.** Both write paths are max-merges, not adds:
> - `SuperfanService.submit` stores per-game **correct/attempted COUNTS** (not an opaque additive total)
>   and GREATEST-merges local with server before writing; the 0–100 total + tier are DERIVED from the
>   merged counts (`local.merged(with: server)`).
> - `PredictLeaderboardService.upsertScore` does `max(points, server.points)` and
>   `max(matches, server.matches)`, deriving `avg_points` from the merged pair.
>
> `max(a,b)` is idempotent and commutative, so two devices converge — they can never sum. Re-running,
> re-syncing, or syncing from a stale device cannot inflate anything.
>
> **⚠️ BUT — two OPEN issues the max-merge does not cover:**
> 1. **Lost progress, not doubled progress.** Two genuinely-active devices each holding unique local
>    history converge to the max, so the *smaller* device's unique matches are silently dropped rather
>    than merged. CLAUDE.md's documented stance is "last writer wins, fine at current scale" — worth
>    re-confirming that's still the intent once real users have two devices.
> 2. **Independently-maxed correlated pair can yield an average neither device ever had.** `points` and
>    `matches` are maxed *separately*: device A at 100 pts / 5 matches and device B at 80 pts / 6 matches
>    merge to 100 pts / 6 matches → avg 16.7, which is neither A's 20.0 nor B's 13.3. Small, but it is a
>    number shown to the user that no device actually produced. Fix would be to merge the pair atomically
>    (take the row with the greater `matches`, or store per-match rows).
>
> **⚠️ SEPARATE, UNDIAGNOSED — duplicate identities on the leaderboard.** The owner's Predict board shows
> **two "Tiffany" rows** (ranks 4 and 5, both 33 pts); the simulator shows the same shape (a "Tiffany" at
> rank 9 with 1 match, plus the sim's own account at rank 28 with 0). Rows are keyed
> `(user_id, team, season)`, so two rows = **two distinct `user_id`s sharing a display name** — NOT a
> doubled score. Whether that's a second real Apple account, a leftover from an account delete + recreate,
> or a seeded fan that happens to be named Tiffany is unknown. Diagnose before launch — a user who cannot
> tell which row is theirs is exactly the "connected feeling" failure the Fan Zone work is chasing.
> Owner-gated query (needs the service key):
> `select user_id, display_name, points, matches from prediction_scores where team_abbreviation='WAS' and season='2026' order by points desc;`
> Also worth deciding whether display names should be unique per season.

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

> ### 🩹 SMALL PREDICT FOLLOW-UPS (from the reset-button incident, 2026-07-27)
> - **The season card reads LOCAL-only state** (`store.points(forTeam:)` / `scoredMatchCount`) even though
>   `prediction_scores` holds the authoritative numbers. So a local wipe makes the card say "Predict …'s XI
>   to join the board" while the leaderboard directly below still ranks the user. Reading the server row
>   would make the card honest and self-healing. (This also means `docs/fan-zone.md` §3's local-vs-server
>   table is right about *storage* but doesn't flag that a local-only READ can contradict the server.)
> - **Account delete does not clear local Predict state.** `PredictionStore.reset()` now has no caller;
>   `AuthStore.deleteAccount` tears down the session and identity but leaves predictions/scores in
>   UserDefaults on the device. Probably wants wiring up — a deleted account shouldn't leave game history
>   behind locally.

> ### 🛡️ ESPN ROSTER RELIABILITY — reduce the single-source risk (owner 2026-07-27)
> ESPN is the app's most vulnerable dependency. For a solo indie app that's an accepted trade — but the
> **roster** specifically has been flaky enough to warrant a better guard. Not aiming for perfect; aiming
> for *better than one unverified source*.
>
> **The failure mode is WRONG-BUT-PLAUSIBLE DATA, served confidently, then self-healing** — not outages.
> Three observed cases:
> - **ACFC roster collapsed to 1 player for ~a week** after a KC Current transfer; self-healed at the next
>   match. Bandaid shipped: `/roster` keeps a last-known-good KV copy and serves it with a
>   `proxyCachedAsOf` marker when live looks implausibly small.
> - **Orlando silently dropped from KHG edition 2026-W31** (`knowherTodoEmpty`, 06:02:44Z) — ESPN returned
>   an empty/stat-less roster for ~seconds. The assembler is fail-open, so it logged a GAP and shipped a
>   15-team pool. Pride fans opened the game to nothing.
> - **Trinity Rodman listed as MIDFIELDER instead of FORWARD for ~3 weeks**; self-healed 2026-07-27
>   (owner-confirmed in-app; all ESPN surfaces — site roster, athlete endpoint, proxy `/roster`, and the KV
>   last-known-good — now agree on Forward).
>
> **The gap:** every existing bandaid catches *missing* or *implausibly small* data. Nothing catches data
> that is wrong but well-formed — a flipped position passes every plausibility check we have, which is why
> it survived three weeks.
>
> **Scope (owner):** ESPN is FINE for minutes, stats, fixtures, scores. The problem is **roster identity** —
> who is on the squad, their position, their number. Options to explore, none chosen:
> 1. **Cross-check** ESPN against nwslsoccer.com and flag/prefer the other source on mismatch
> 2. **Failover** — a second source promoted when ESPN looks wrong
> 3. **Replace** the roster source entirely, keeping ESPN for stats/fixtures (hybrid)
>
> Worth pricing the sources first (availability, licensing, shape) before designing. Related:
> `docs/backend.md` (roster § last-known-good), and the KHG assembler's fail-open behaviour, which should
> probably also grow a retry before it ships a short pool.

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

> ### 🎚️ STILL OPEN — halve Predict per-match scoring (flag only; verified NOT yet applied 2026-07-27)
> ⚠️ Not to be confused with the **Superfan 0–100 accuracy economy**, which WAS redesigned 2026-07-24 —
> this is a different knob and is still untouched (`XIPrediction.swift` today: formation 5, exact score 10,
> result 3, perfect XI 15 → max 88).
> The Predict-the-XI per-match max is **88** (+3/starter ×11, +2/position ×11, +5 formation, +10 exact
> score, +3 result, +15 perfect XI). The owner flagged this as oversized for a low-scoring sport — consider
> **halving every value → max 44** pre-launch (relative weights unchanged, so rankings don't move). The
> Batch-3 switch to an **average-per-match** leaderboard (users never see cumulative totals) made this
> non-urgent. `+5 formation` is the specific worry (near-free for attentive fans — most clubs run a stable
> shape). **No code change yet** — this is a deliberate pre-launch decision. Values live in
> `Models/XIPrediction.swift` (`PredictionScore.*Points`); if halved, the `predictPointRow` rules text +
> the season card's `/88` ring denominator + `RECENT_RESULTS` breakdown must move to `/44` in lockstep.


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

> ### ♿ PRE-RELEASE GATE — accessibility (owner 2026-07-21; must ship BEFORE launch)
> Accessibility is a release gate, not a nice-to-have — in an inclusive space like NWSL it must not be
> overlooked. NOT yet built; this is a scoped workstream to audit + complete before launch. Two parts:
> - **Blind / low-vision (VoiceOver + Dynamic Type):** systematic pass. Custom-DRAWN elements need
>   explicit `.accessibilityLabel` (formation-pitch dots, `StatComparisonBar`, score header, live clock,
>   image-only crests/headshots); GROUP compound units so a match card reads as one element ("Chicago 0,
>   Angel City 2, Full Time") not fragments; revisit the Dynamic Type **AX1 cap** per-screen (density vs
>   larger AX sizes — trade-off).
> - **Color-blind:** never rely on color ALONE — redundant encoding (letter/shape/icon) + respond to
>   `@Environment(\.accessibilityDifferentiateWithoutColor)`, usually better than a custom mode.
> Current state = PARTIAL, not zero (FormBadge shows W/D/L letter+color = color-blind safe; text uses
> `.dsFont`/@ScaledMetric; scattered labels exist) → the work is systematic completion + an audit, then a
> punch-list. First step when picked up: run the audit (read + VoiceOver in sim). Detail in the
> accessibility-pre-release-gate memory. (Dark-only is NOT an a11y issue — the app's color balances it.)
> Also still pending here: profanity-filter the editable leaderboard display name before public launch.

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
