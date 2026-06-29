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
- **Push: match-watcher is NOT competition-aware** — it polls only the `usa.nwsl` scoreboard and hard-codes the "NWSL" card footer (`card.ts`), so NON-LEAGUE competitions get no push at all: Concacaf W Champions Cup today, NWSL Challenge Cup (`usa.nwsl.cup`) tomorrow. Fix = poll the additional competition slugs + make the card footer/title competition-aware (carry the comp label through the watcher's event pipeline). The footer `comp` param is a ~3-line add in `card.ts crestDataUri`'s file — could ride the crest-cache fix below.
- **Push: self-hosted crest primary is dead (rich card falls back to ESPN)** — the watcher's `/card` crest fetch (`card.ts crestDataUri`, `cf:{cacheEverything:true,cacheTtl:86400}`) is pinned to a STALE 404 cached during the 2026‑06‑24 deploy-before-crest-load window. All 16 crests ARE in the proxy KV and serve 200 externally; step‑1 (self-hosted) returns a cached 404 so prod silently uses step‑2 (ESPN). Cards still show real crests (ESPN works), but the "never-missing" safety net isn't live — an ESPN hiccup → rings. Fix: `cf:{cacheTtlByStatus:{"200-299":86400,"404":0,"500-599":0}}` + a one-char cache-version bump, redeploy. ~15 min.
- **V2 — Live Activity (lock screen + Dynamic Island live score)** — ships immediately after V1 push is verified (NOT post-launch). The premium glance layer. Top-tier apps run Live Activities ALONGSIDE rich push — push buzzes on events (interrupt), the Live Activity silently updates the score in place (glance); both fire simultaneously on a goal. Requires: ActivityKit widget extension (new Xcode target), push-to-update token lifecycle, SwiftUI widget UI for lock screen + Dynamic Island. Separate from the NSE — shares NO code with V1 push. Key consideration: a Live Activity needs CONTINUOUS updates, not just on events, so the watcher's cron model may need more frequent state pushes between goals. Sequence: verify V1 push → Design specs the Live Activity → Code builds → verify → ship. Both layers ship before launch.
- **Competitions follow-ups:** Challenge Cup (`usa.nwsl.cup`, single annual match) + Champions Cup + followed NTs all fold into Schedule "My teams". WWC/Olympics whole-tournament UI DEFERRED; foreign-club color DB grows as Champions Cup opponents appear (`DesignTeamColors.international`); broaden NT coverage via `NationalTeamFeed.all` + proxy `WOMENS_NT_FEEDS`.
- **Feed** — user-added sources; richer filtering. **Weather** — kickoff-temp header slot.
