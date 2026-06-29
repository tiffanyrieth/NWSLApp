# Roadmap / What's Next

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
- **Push: match-watcher is NOT competition-aware** — it polls only the `usa.nwsl` scoreboard and hard-codes the "NWSL" card footer (`card.ts`), so NON-LEAGUE competitions get no push at all: Concacaf W Champions Cup today, NWSL Challenge Cup (`usa.nwsl.cup`) tomorrow. Fix = poll the additional competition slugs + make the card footer/title competition-aware (carry the comp label through the watcher's event pipeline).
- **Competitions follow-ups:** Challenge Cup (`usa.nwsl.cup`, single annual match) + Champions Cup + followed NTs all fold into Schedule "My teams". WWC/Olympics whole-tournament UI DEFERRED; foreign-club color DB grows as Champions Cup opponents appear (`DesignTeamColors.international`); broaden NT coverage via `NationalTeamFeed.all` + proxy `WOMENS_NT_FEEDS`.
- **Feed** — user-added sources; richer filtering. **Weather** — kickoff-temp header slot.
