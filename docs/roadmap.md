# Roadmap / What's Next

> **Open blockers only.** This is the owner's personal punch-list — meant to go DOWN. When an item is
> done or dropped it's removed (git history keeps the record); durable lessons live in the system docs
> (`docs/backend.md`, `live-activity-v2.md`, `notifications.md`, `decisions.md`, …), not here. Order
> follows the app's priority: ALIVE > core > hardening.

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

> ### 📺 "FIND THE MATCH" — where/how to actually watch (owner 2026-08-08)
> The broadcast chip already NAMES the network (great — ION games are the hardest to find). Next step: help
> fans actually GET there, especially the tricky networks. **The ION problem specifically:** there is no
> real live ION app on tvOS, and searching "ION" in Apple TV's own TV app finds nothing — so a fan sees
> "ION" and is stuck. **Clever fallback the owner uses (make this the app's advice): Plex** — install the
> free Plex app on Apple TV → Live TV → **ION is a channel there**, free. Other free routes: Tubi / Pluto
> TV live channels; over-the-air antenna. (⚠️ NOT on NWSL+, unlike CBS→Paramount+ / ESPN games.)
> **⏳ RESEARCH BEFORE BUILDING (owner wants more first):** pin down whether the Apple-TV gap is a "Scripps
> vs ION" naming/branding thing (does searching "Scripps" surface it? is there a Scripps Sports app?) or
> whether tvOS genuinely has neither — and confirm the Plex live-TV carriage is stable/national. Then
> design a small **"how to watch" affordance** on the match card / Match Detail: per-network guidance
> (network → the app(s) that carry it + a "free via Plex/Tubi/Pluto" hint for the hard ones). Keep it a
> curated network→apps map (small, owner-maintained), not a live carriage API. US/NWSL scope like the rest.
>
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
>
> **➕ IG SOCIAL REFRESH MUST BE COVERED TOO (owner 2026-08-06).** Same class, different subsystem: the
> every-other-day IG social cron (`0 12 */2 * *`, writes `social-cards-club-v1` + `social-cards-player-v1`)
> **silently missed its 08-05 noon firing** → the 3-day-TTL snapshots expired → the Social **Players chip
> (Bright Data) + Club IG (Apify) went empty**, discovered only by the owner eyeballing the chip + the admin
> Status tab. Root cause (evidenced 2026-08-06): NOT code, NOT a deploy race (all 08-05 deploys were evening,
> ~10h after the noon window), NOT Bright Data (delivered 08-03) — a **free-tier Cloudflare cron skip** (no
> SLA, no retry; the `*/5` engine was proven flawless in the same window, so it was an isolated miss of the
> low-frequency cron). Manual `POST /refresh-social` fully recovered it (150 player + 64 club cards).
> **What's needed:** a **heartbeat / fail-loud** so a missed-or-failed social refresh pages within hours —
> a skipped low-freq cron emits ZERO diags (no code runs), so the error-spike pager can't catch it; needs
> either a healthchecks.io-style dead-man's-switch on the social cron OR wiring the Status-tab's
> snapshot-missing check to page proactively.
>
> **⚠️ DO NOT add a stale fallback to "fix" this (owner 2026-08-06 — this is a VALUES call, not a bug).** The
> empty chip is the INTENDED signal ([[feedback_no_silent_stale_fallback]]); masking a dead pipeline with old
> IG data would have hidden the break for days. Future design SHE may allow: tolerate **exactly ONE** missed
> cycle via fallback (Mon fires → Wed skips → still serve Mon's data), but if the NEXT scheduled one **also**
> misses (now ~4-day-stale = a real scheduling problem), **stop falling back and show nothing** so the outage
> is loud. Only build that once the cron proves reliable on its normal schedule. Until then: leave unchanged,
> empty = the canary. First test of reliability: watch whether 08-07 noon fires on its own.

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

> ### ✅ PRE-PUBLISH — privacy package: BUILT + LIVE (2026-08-18) — 2 owner steps left
> - ✅ **Privacy Policy + Terms page** written accurate to the code audit (SIWA email-only/optional,
>   Supabase per-user data, anon analytics/diagnostics, NO location, tips via Apple), incl. the
>   **affiliation disclaimer** + full **Open-Meteo CC-BY 4.0** credit. **LIVE at `https://crestside.pages.dev/`**
>   — a SEPARATE Cloudflare Pages project (source `~/Projects/crestside-site/index.html`), deliberately NOT
>   the proxy Worker so the backend URL is never exposed. Contact routes to App Store support (no personal
>   email published).
> - ✅ **App Privacy label + Privacy Policy URL** entered + PUBLISHED in ASC (9 data types; Tracking=No).
>   In-app Profile → "Privacy & Terms" row opens the page; `AppConfig.privacyURL` repointed to Pages.
> - ✅ **Support copy** de-absolutised ("free to download + core free, tip-supported"); tips now ONE-TIME
>   round $2/$5/$10/$20 (no monthly — Apple 3.1.1; no Restore — consumables).
> - ⏳ **OWNER STEP 1:** read the privacy statement end-to-end + agree (she's the owner — do it rested).
> - ⏳ **OWNER STEP 2:** send to external testers (Apple Beta App Review, light). All other ASC gates
>   (Age 13+, Accessibility, IAP prices, Game Center) are DONE.
> - ⚠️ These ride **build 36** — build 35 was archived BEFORE tonight's privacy/Support changes.

> ### ♿ PRE-RELEASE GATE — accessibility: **ALL FOUR PARTS DONE** (owner 2026-07-21; VoiceOver 2026-08-17)
> Accessibility is a release gate, not a nice-to-have — in an inclusive space like NWSL it must not be
> overlooked. All four legs are now complete + mechanically gated:
> - ✅ **Dynamic Type / AX1** — cap decided, whole app swept, every screen passes (detail below).
> - ✅ **Colour-blind** — deuter/protan/tritan simulation across the app found **no failures**;
>   existing rules carry it (✓/✗ glyph shapes, crest+abbreviation, text "your pick" labels).
> - ✅ **Contrast (WCAG AA)** — DONE 2026-08-11. `dsFgSecondary` lightened to #AEAEB2, tertiary/quaternary
>   made decoration-only, ~230 sites swept, and a **contrast FLOOR** (`DSColorContrastTests` +
>   `Color.wcagContrastRatio`, CLAUDE.md rule) fails CI on a regression. [[feedback_invisible_dark_on_dark_text]].
> - ✅ **VoiceOver — DONE 2026-08-17.** Systematic pass: shared components fixed once
>   (`PlayerHeadshot` hidden, `StatComparisonBar`/`ScoreRing`/`FormBadge` labelled), match surfaces read
>   as ONE curated sentence built from the model (`MatchCard` + `MatchDetail` header → "Louisville 4,
>   Boston 1, full time" — the live minute spoken, not "51 apostrophe", without touching the fragile
>   `MatchClockKit`), the formation `PitchDot` announces each player's role, and every compound row
>   (Standings, Bracket leaderboard, `PlayoffMatchupRow`, Superfan breakdown, content-feed cards) is
>   grouped with a curated label. Content cards also gained a link trait + activation action (they were
>   tap-to-open but not Buttons). **Mechanically gated by `NWSLAppUITests/AccessibilityAuditUITests`**
>   (`performAccessibilityAudit` walks each screen, fails CI on an unlabeled/mistraited/undescribed
>   element) — the VoiceOver peer of the contrast test. Audit scoped to the VoiceOver-specific checks
>   (`.elementDetection`/`.sufficientElementDescription`/`.trait`); `.dynamicType` + `.contrast`
>   deliberately excluded (owned by the AX1 gate + `DSColorContrastTests`, and they flag the app's
>   intentional fixed-size text + team-color-on-wash design). CLAUDE.md carries the "part of done" rule.
>   ⏳ **Owner's remaining step: a device VoiceOver spot-check** — the audit proves structure; a human
>   should confirm the labels READ naturally (swipe a match card, standings row, the formation pitch).
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
> punch-list. Dynamic Type, colour-blind, and contrast are closed — do NOT re-audit them.
> (⚠️ CORRECTED 2026-08-11: the old note here said "dark-only is NOT an a11y issue — the colour balances
> it." That was WRONG — dark-mode gray-on-gray text was measurably below WCAG AA and shipped invisible.
> Dark-only doesn't excuse contrast; the CONTRAST gate above now enforces it.)
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

> ### 🔒 V2 LA RULE (standing): V2 Live Activity work happens in its OWN session with NO other tasks
> in flight — it's device-proven, fragile, weeks to get right; read `docs/live-activity-v2.md` §0 FIRST,
> never edit from first principles. _(No open V2-LA items — the ⌚ Apple Watch `.small` crest fix merged
> 2026-08-09 (#263, `live-activity-v2.md` §8b); on-watch check rides the next TestFlight build, owner
> re-raises only if it misrenders.)_

> ### 🌍 VERIFY notification LOCAL-TIME on the NEXT TestFlight build (merged 2026-08-14: app #286, watcher #38)
> Global-audience notification timing is on `main` and the watcher is DEPLOYED, but **dormant-safe** until a
> build carries the app half: every device is still null-tz → the legacy 14:00-UTC Predict-results send
> (byte-for-byte the old behaviour). ⚠️ The TestFlight build shipped <24h before this does NOT include it — so
> verify on the NEXT build:
> 1. **tz is populating** — confirm `device_tokens.timezone` is non-null after installing + foregrounding (it
>    writes on token/tz change via `NotificationSyncCoordinator`).
> 2. **Predict-results dry-run per timezone** (with `MANUAL_TRIGGER_SECRET`):
>    `POST https://nwslapp-match-watcher.tiffany-rieth.workers.dev/predict-results-run?dryRun=1&atHourUTC=<h>`
>    — confirm the right cohorts light up (`atHourUTC=0` → Sydney's 10am wave; `=14` → US-Eastern + null-tz
>    legacy). Returns `{predictors, qualifyingTokens, userIdsWouldMark}` per fixture, no send.
> 3. **KHG "new round" nudge** (also in this build) fires at local Mon 10am on a KHG drop week — device-check.
> Deploy-order-safe; do NOT raise the update-gate `minBuild`. Mechanism: `docs/notifications.md` delivery-timing rule.

---

**Pending work only (ALIVE > core > hardening); shipped/decided/dropped work lives in git history + the File Map.**

_(Hardening: none open. Team-link subreddit verification + the club-website data pass shipped 2026-08-13; Discord dropped — no maintained league-wide directory exists to pull from, only one club had a usable public server.)_

---

## 🗂️ ANYTIME — not publishing blockers (address whenever; verified working, or polish/watch items)

> These do NOT block publishing. They are follow-ups on shipped systems (verify the automation
> behaved), or polish that can land in any release.

> ### 🔁 SOCIAL SELF-TUNING — follow-up verification on the automated runs (system SHIPPED 2026-08-17)
> The self-tuning system (players IG + reporters Bluesky + analytics discovery) is LIVE and
> automated — `docs/social-tuning.md` is the system doc. What remains is watching the automation
> prove itself, per the tune-from-real-runs model:
> - **Reporters (monthly, 1st):** review each run's report — did the quality bar hold (adds are
>   distinctive NWSL voices, not link-dumps/recaps)? Did drops follow the two-audit streak rule?
>   Adjust the routine prompt from real outcomes. First automated cycle: Sept 1.
> - **Players IG (Mar/Jul/Oct 15):** verify each run's report — candidates researched under the
>   identity gate, adds within the ceiling, drops verified as real departures.
> - **Near-term watches:** `alozieee` returned 0 cards on the 8/17 scrape (verified account,
>   likely transient) — confirm she returns on a following cron or investigate; the 8/19 + 8/21
>   pool scrapes are the first at ~79 handles each — glance at `apifyHandleEmpty` diags after.
