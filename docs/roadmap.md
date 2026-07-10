# Roadmap / What's Next

> ### 🧹 CLEANUP — remove the DEBUG postseason simulator's baked-in 2025 data (owner-parked)
> **Kept ON PURPOSE (owner, 2026-07-07):** `PostseasonSimulator.swift` carries real 2025 bracket +
> clinch data so the owner can exercise the Playoffs feature in-sim over the next few days before the
> real Nov postseason. It is 100% `#if DEBUG` + launch-arg-gated (`-simulatePostseason2025…`) → compiles
> out of Release/TestFlight and shows NOTHING in normal builds (scheme flag is off), so it is harmless to
> ship as-is. **When the owner says they're satisfied:** strip the fake 2025 seeding data from
> `PostseasonSimulator.swift` (or delete the sim harness) so no hard-coded 2025 bracket lingers in the
> app source. The unit tests that reference `PostseasonSimulator.clinchTable` (`PlayoffClinchTests`) move
> to inline fixtures at that point. Nothing auto-reminds — this note is the reminder.

> ### 🎯 POLISH — lineup-push crest shows the WRONG team for away-team fans
> **Observed (owner, 2026-07-05, live Boston vs Bay game):** the "Lineups in" V1 push attaches the
> **home** club's crest (`crestAbbr()` defaults to home for lineup events, watcher `events.ts`). A fan
> who follows the AWAY team (Bay) sees the HOME crest (Boston) → reads as "Boston's lineup dropped" to a
> Bay fan. Everything else about it works (deep-link → match detail → XI renders correctly).
> **Why:** the lineup push is ONE payload fanned out to followers of BOTH teams
> (`tokensForEvent([homeId, awayId], "lineup_posted")`), so a single crest can't be per-recipient without
> splitting the fan-out.
> **Two fixes (owner to pick):** (A) IDEAL — split the fan-out by team so each fan gets THEIR team's
> crest (two token queries + two payloads; a both-teams follower gets two pushes). (B) SIMPLER + arguably
> more correct — a **both-crests matchup tile** (BAY + BOS side-by-side) via a new card-worker `/thumb`
> variant, one push, honest that it's a both-teams event. (SF Symbols can't be used — thumbnail is
> server-rendered.) Owner leaned neutral/both-crests as the easy win. Backend-only (proxy/card worker +
> watcher) → no app build.

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
  card footer/title (carry the comp label through the pipeline). (Verify: crest rendering moved to the
  `nwslapp-card` worker — the old `card.ts crestDataUri` self-hosted-404 note may be obsolete.)
- **Competitions follow-ups:** Challenge Cup (`usa.nwsl.cup`, single annual match) + Champions Cup + followed NTs fold into Schedule "My teams" (NT coverage now 16 feeds, shipped). WWC/Olympics whole-tournament UI DEFERRED; foreign-club color DB grows as Champions Cup opponents appear (`DesignTeamColors.international`).
- **Feed** — user-added sources; richer filtering. **Weather** — kickoff-temp header slot.
