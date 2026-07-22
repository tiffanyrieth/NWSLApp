# Roadmap / What's Next

> ### ⏳ OWNER SETUP — analytics + alerting go-live steps (2026-07-17, ~15 min total)
> The anonymous-analytics + ops-alerting code is MERGED + deployed but four one-time owner steps
> arm it (each is a silent no-op until done — nothing breaks meanwhile):
> 1. **Supabase migration** (required for counters to record): paste
>    `supabase/migration_analytics_counters.sql` into the SQL editor + Run. Verify: use the app,
>    background it, then `select * from analytics_counters;` shows session rows. (Until then every
>    flush logs `analyticsRpcFail: increment_counters 404` in /telemetry/recent — expected.)
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
- **Bracket Battle v2 — built, awaiting owner deploy:** run the 4 SQL files (`migration_bracket_v2`
  → `migration_bracket_qualifying` → `seed_bracket_stats_editions` → `seed_bracket_creative_editions`)
  + `npm run deploy` (proxy) + the first-launch flow (`Reference/Bracket Battle/first-launch-checklist.md`).
  Optional later: more stat/creative themes; full bracket-TREE graphic.
- **First-launch perf** — Tier 1+2 shipped; onboarding quick-tips screen DEFERRED (build only if wanted).
- **YouTube Shorts thumbnail pillarbox** — DEFERRED; fix is proxy-side.
- **Pull-to-refresh polish** — keep the list visible during refresh (spinner only on first load).
- **Home follow-ups:** spotlight no-repeat-per-season + opt-in weekly notif.
- **Player headshots Phase B2 banners** — DEFERRED (licensing).
- **Accessibility** — now a PRE-RELEASE GATE (see the ♿ callout above): VoiceOver + color-blind pass before launch.
- **More team-color vibrancy (owner interested 2026-07-21)** — extend the MatchDetail team-color wash to more
  surfaces so club color carries further (candidate surfaces: Home header, Team detail, schedule cards,
  standings followed-team rows, player detail already uses `accentHex`). Keeps the neutral-canvas philosophy
  — color comes from the TEAMS, not the chrome; the crest/abbreviation identity rules still hold. Design pass,
  scope per-surface with the owner (don't recolor chrome globally). Reference: MatchDetail header wash.

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
