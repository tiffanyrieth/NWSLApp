# Roadmap / What's Next

> ### ⚠️ OPEN — follows restore fix: committed but NOT device-verified
> **Status:** committed on `feature/display-name-hydration-auth`, headless-verified (clean build, green
> tests, destructive launch-prune removed structurally); **device-verification pending.**
> **Why pending:** the new build has never run on the owner's device — every prior reinstall test ran the
> OLD build (TestFlight not re-cut to avoid spamming testers for one fix; USB-from-Xcode blocked by an
> iOS 27 / Xcode 26.5 mismatch). So the reinstall-restore path is unverified on real hardware.
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
- **Push — Tier 2 (SERVER push)** — code-complete through Stage C (`~/Projects/nwslapp-match-watcher`: cron + KV diff + APNs JWT; per-team targeting live). Remaining: flip `APNS_HOST` sandbox→production at TestFlight; on-device E2E; Stage D (subs + lineup-posted).
- **Competitions follow-ups:** WWC/Olympics whole-tournament UI DEFERRED (followed-team matches already fold into Schedule); foreign-club color DB grows as Champions Cup opponents appear (`DesignTeamColors.international`); broaden NT coverage via `NationalTeamFeed.all` + proxy `WOMENS_NT_FEEDS`.
- **Feed** — user-added sources; richer filtering. **Weather** — kickoff-temp header slot.
