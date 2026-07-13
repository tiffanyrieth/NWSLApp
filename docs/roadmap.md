# Roadmap / What's Next

> ### ✅ BUILT (proxy) + ⏳ first-Monday verify — Know Her Game weekly automation (2026-07-13)
> The full no-human weekly loop is BUILT (proxy branch `feature/knowher-weekly-automation`): deterministic
> prompt assembly (`assemble_knowher_prompt.mjs` fills the Rodman-faithful `knowher-weekly-TEMPLATE.md`
> from `/knowher/todo`, which now serves age/country + keeper stats), a dedicated-key
> **`POST /knowher/ingest`** (validate → KV → markFeatured, diag on every outcome), a `knowherStaleWeek`
> serving watchdog (in-season, 1/day), and the committed cloud-routine runbook
> (`knowher-weekly-routine.md`). Proxy DEPLOYED + prod-probed; `node --test` 14/14. The scheduled Claude
> Routine (Sonnet, Mon 09:00 UTC ≈ 5am ET) is configured but **pending the owner's one-time GitHub
> connect** on claude.ai. Monday user nudge = the existing local 10 AM notification (unchanged). **Verify
> on the first automated Monday:** routine report SUCCESS, new weekKey serves, ledger advanced, app shows
> the new week. Engine question CLOSED (owner): the Rodman-WORKING prompt is final;
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

> ### ✅ SHIPPED (server) + ⏳ build 26 device-verify — live-clock / staleness / Match-Detail (2026-07-11)
> **Root cause of the app "stuck clock/score all game":** ESPN's full-season `dates=` scoreboard serves
> live state **25–47 min STALE** during live games (not an app bug — details `docs/backend.md`).
> **DEPLOYED, no build (all live):** proxy busts the ESPN upstream on `/scoreboard` MISS (`_cb`, fixes
> staleness for ALL installed builds); watcher **30s double-poll** in live windows (owner "much improved");
> watcher **drift-triggered LA resync** (≥30s anchor jump → card snaps at each half start, not 10 min late);
> watcher **stoppage `+N` broadcast** (per-minute in added time). Watcher PR #26, proxy PR #44.
> **BUILT (app, build 26, sim-verified only — DEVICE-VERIFY PENDING):** widget `showsHours:false` (68:12
> not 1:08); widget renders `stoppageDisplay` "90'+2'"; app live poll → windowed query merged over the
> season (was ~2MB/30s); Match-Detail **horizontal-drift** fix (`.containerRelativeFrame(.horizontal)`).
> **On the next TestFlight, verify on device:** Fix C past 60', Fix D stoppage `90'+N'` on the lock screen
> (fake-match harness into a frozen-cap window; WATCH Apple's broadcast throttle at 1/min), Fix G no-pan.

> ### ✅ RESOLVED — lineup-push crest showed the WRONG team for away-team fans
> **Was (owner, 2026-07-05):** the "Lineups in" V1 push attached the **home** club's crest, so an
> AWAY-team follower saw the HOME crest → read as the wrong team's lineup. Same latent issue on
> kickoff/HT/FT (a single crest on a both-teams moment).
> **Fixed 2026-07-10 (owner rule — a THIRD option, simpler than the A/B originally weighed):** a crest
> attaches **ONLY to a team-attributable event — a GOAL (scorer's club) or a RED CARD (carded club)**.
> Every match-level moment (kickoff, lineup, halftime, full-time) and VAR corrections are **NEUTRAL** —
> no image, no `mutable-content` (the NSE stays asleep), clean title+subtitle text; the tap still
> deep-links. Watcher `events.ts` (`eventCarriesCrest` + conditional `toPayload`); pure-logic tested,
> `tsc` clean, **deployed** (version `e11ae04f`). **DEVICE-VERIFIED 2026-07-10, 7:12pm** on the exact bug
> case: BAY (AWAY follow) received the LOUvBAY "Lineups in" push — delivered, tap deep-links correctly,
> no crest issue. Still to observe (not failures, just not yet posted): KC away lineup (ORLvKC) + the
> crest-KEPT path (a GOAL should still carry the scorer's crest).

> ### ⚠️ OPEN — follows restore fix: MERGED, device-verify pending on build 25
> **Status:** MERGED to main (app PR #97), headless-verified (clean build, green tests, destructive
> launch-prune removed structurally); **device-verification pending on build 25.**
> **Why pending:** the reinstall-restore path hasn't been confirmed on real hardware yet — verify on the
> build 25 TestFlight cut.
> **Test fixture already in place — DO NOT DELETE:** the owner's account has 3 server follows
> (Bay `22187`, `131562`, `131563`); these ARE the reinstall test fixture.
> **Pass criteria (run on the next TestFlight build, for any reason):** clean reinstall → the TEMP trace
> reads `local=0[] remote=3[…] onboarded=false → authoritative=remote`, all 3 follows restore, **zero
> prune lines**, and `select count(*) from follows` stays at 3.
> **TEMP instrumentation stays on purpose:** the `Diagnostics.debugTrace` case + the reconcile trace in
> `FollowSyncCoordinator` remain in the code until this test passes — then remove them (Step C) and mark
> this done.

Pending work only (ALIVE > core > hardening); shipped work lives in git history + the File Map.
- **Bracket Battle v2 — built, awaiting owner deploy:** run the 4 SQL files (`migration_bracket_v2`
  → `migration_bracket_qualifying` → `seed_bracket_stats_editions` → `seed_bracket_creative_editions`)
  + `npm run deploy` (proxy) + the first-launch flow (`Reference/Bracket Battle/first-launch-checklist.md`).
  Optional later: more stat/creative themes; full bracket-TREE graphic.
- **First-launch perf** — Tier 1+2 shipped; onboarding quick-tips screen DEFERRED (build only if wanted).
- **YouTube Shorts thumbnail pillarbox** — DEFERRED; fix is proxy-side.
- **Pull-to-refresh polish** — keep the list visible during refresh (spinner only on first load).
- **Home follow-ups:** spotlight no-repeat-per-season + opt-in weekly notif.
- **Player headshots Phase B2 banners** — DEFERRED (licensing).
- **Accessibility:** Dynamic Type shipped (AX1 cap); profanity-filter the editable leaderboard display name before public launch.

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
