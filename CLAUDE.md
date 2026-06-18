# NWSLApp — Project Context for Claude

## ⚠️ WHAT THIS APP IS — READ FIRST

**A women's soccer (NWSL) fandom app.** It's a lively hangout for fans: follow your
clubs, keep up with your favorite soccer voices (reporters, club + player social),
play and share Fan Zone mini-games (Bracket Battle, Predict the XI, Daily Trivia),
and check scores, schedule, and standings. The **fandom** — community, the games,
social sharing, live/"alive" content, and a personal connection to your teams — **is
the product.** Scores/schedule/standings are table stakes that must work, but they are
**not** the differentiator.

**Anti-pattern to avoid (this matters):** do NOT treat this like a traditional
sports/stats app (an ESPN/March-Madness clone) and shrink the fandom side. When a
design plan (e.g. from Claude Design) emphasizes fandom, social, or playful content,
**build it that way** — don't slot it into a stats-app mold or trim the fandom content
down. The fandom half and the sports half are equally core; the fandom half is what
makes the app worth opening.

**The litmus test:** "Would I open this app today if I opened it yesterday?" If a
surface looks identical because the data is static, that's a bug — the app is built to
feel alive (fresh content every open, fan engagement, personal connection).

**Priority order when deciding what to work on:**
1. **ALIVE features** — live content pipelines (YouTube/club news/Bluesky → Home & Feed,
   Player Spotlight rotation, Fan Zone games) and fan engagement.
2. **Core functionality** — scores, schedule, standings, stats (must work; not the differentiator).
3. **Hardening** — bug fixes, tests, robustness. Never above category 1.

**Owner:** Tiffany Rieth. Personal project to build production-quality iOS skills and
ship a real consumer app; long-term goal is App Store distribution.

---

## State of the app

The app is **fully live and in production-quality state** (v0.4.0) — real data
everywhere, used daily by the owner + testers as their primary NWSL app. **Online-only:
there is no demo/fake/seed data in the running app** — every surface shows live data or an
honest "Couldn't load — tap to retry" (seed/fixtures live only in previews + tests). Treat
the app as a real, working product when building — never suggest a "demo" mode or placeholder.

Every surface pulls live: ESPN (scores/schedule/standings/teams/rosters/match detail
via a caching proxy), the content pipeline (Home + Feed: YouTube · club-site news ·
Bluesky · news RSS · Instagram · Player Spotlight, all via the proxy), the three Fan
Zone games (real Supabase leaderboards), and Sign-in-with-Apple accounts (Supabase).

---

## Tech Stack

- **Language/UI:** Swift 5.9+, SwiftUI (not UIKit). Min iOS 17 (for `@Observable`). Xcode 26.5.
- **State:** `@Observable` (modern) over `ObservableObject`.
- **Networking:** `URLSession` + `async/await`. No third-party HTTP libraries.
- **Persistence:** UserDefaults for small local state (follows, game stats); **Supabase**
  (Postgres) as the durable per-user source of truth once signed in. SwiftData used nowhere.
- **Auth / per-user backend:** Sign in with Apple → **Supabase** (Postgres + native Apple
  auth + Row-Level Security). The project's **only** third-party dependency is the
  **Supabase Swift SDK** (`supabase-swift`, SPM) — justified vs raw URLSession (JWT refresh,
  RLS headers, keychain session). Credentials live in gitignored `Config/Secrets.swift`
  (template `Secrets.example`); the anon key is a public client key — RLS is the real boundary.
- **Testing:** Swift Testing (`@Test` + `#expect()`), not XCTest.

---

## Commands

```bash
# Build (Debug) for a booted simulator
xcodebuild build -scheme NWSLApp \
  -destination 'platform=iOS Simulator,id=<BOOTED_SIM_ID>' -configuration Debug

# Run the unit tests
xcodebuild test -scheme NWSLApp \
  -destination 'platform=iOS Simulator,id=<BOOTED_SIM_ID>' -only-testing:NWSLAppTests

xcrun simctl list devices booted                 # find the booted sim id
xcrun simctl install <SIM_ID> <NWSLApp.app>      # install a built .app
xcrun simctl launch  <SIM_ID> com.tiffanyrieth.nwslapp.NWSLApp
```

DEBUG launch args: `-resetOnboarding`, `-useESPNDirect`,
`-startTab <home|schedule|standings|teams|feed>`. Decode-only tests read
`NWSLAppTests/Fixtures/*.json` off disk via `#filePath` (no bundle membership).
**Driving the sim:** cliclick hits the UIKit tab bar but not SwiftUI NavigationLinks/Buttons
reliably — use DEBUG deep-link/launch-arg scaffolds (then remove). `idb ui tap` is more robust if installed.

---

## Architecture

**MVVM** with strict separation:
- `Models/` — `Codable` structs matching API responses; no UI or networking.
- `Services/` — API clients (ESPN, Supabase, content); no UI logic.
- `ViewModels/` — `@Observable` classes owning view state; state-enum pattern
  (`idle`/`loading`/`loaded`/`error`).
- `Stores/` — `@Observable` shared app state → UserDefaults, injected via `.environment`
  (one fetch, many readers).
- `Views/` — one screen per file; minimal logic. `Components/` — reusable pieces.
- `DesignSystem/` — `DSColor`/`DSMetrics`/`DSText` token layer (dark-only). Team colors
  stay dynamic via `Color+Hex`.

Folders are created when their first real file lands, not preemptively.

---

## Data Source

**Primary:** ESPN's unofficial NWSL endpoints (community reverse-engineered, unsupported).
- Base: `https://site.api.espn.com/apis/site/v2/sports/soccer/usa.nwsl/`
- Scoreboard (full season): `scoreboard?dates=YYYY0101-YYYY1231&limit=500`

**Known quirks (decode defensively):**
- Scores decode as `String` (`"0"`), not `Int`.
- Event timestamps sometimes lack seconds — custom parsing in `Event.kickoff`.
- Default scoreboard caps ~100 events; `&limit=500` returns the full season.
- Standings lives at `apis/v2/…` NOT the `apis/site/v2/…` base.
- ESPN's headshots are null for every NWSL athlete; the app instead sources real photos via
  the proxy `/headshots` map (espnAthleteId→NWSL GUID → Cloudinary), monogram fallback on a miss.
- Feed articles are legal-limited to headline + summary + link — never the article body.
- Endpoints can change shape, break, or rate-limit without notice. Fail gracefully.

**Proxy (Cloudflare Worker `nwslapp-proxy`)** — sibling repo `~/Projects/nwslapp-proxy`
(GitHub `tiffanyrieth/nwslapp-proxy`), live at `https://nwslapp-proxy.tiffany-rieth.workers.dev`.
- **Pass-through caching:** `GET /scoreboard`, `GET /summary?event={id}` forward to ESPN
  and return bytes **unchanged** (app decoders untouched); match-state-aware TTL.
- **Content routes** (build + normalize to JSON `[ContentCard]` / models): `/team-videos`
  (Home: YouTube + club OG news + club Instagram), `/feed` (Feed: Bluesky reporters/clubs +
  news RSS + player Instagram), `/spotlight` (Player Spotlight), `/trivia` (Daily Trivia
  KV pool), `/national-teams` (data-driven Browse-all directory: union of ESPN `/teams` across the
  women's NT feeds, deduped by FIFA code, ESPN flag href, 24h cache), `/telemetry` (POST event sink → KV). Server-side Haiku (`claude-haiku-4-5`, KV-cached) does both relevance AND
  team-tagging for the third-party buckets: reporter + league-outlet Bluesky and news
  RSS are gated (isNWSL, strict — national-team/international/foreign/men's dropped),
  team-tagged, and filtered to the requested teams (off-topic + non-followed-team +
  general-chatter dropped; genuine league-wide kept). Fails toward DROP for social
  (fail-open for news). Club-official + player accounts are trusted fast paths (own
  abbr, no Haiku). Every card carries a `sourceType` (club·reporter·player·league·news)
  for the app's Feed chips. Plus a flood cap + dedupe.
- **Headshots** (`src/headshots.ts`): `GET /headshots` serves an `{espnAthleteId: nwslGuid}`
  map (built from the public NWSL SDP JSON API name-matched to ESPN rosters, ~98%; weekly cron
  + admin `POST /headshots/run`; union-merged in KV with an `unmatched`/`overrides`/`meta`
  audit). The app builds the NWSL Cloudinary headshot URL on-device. Pure mapping — no image bytes.
- **Crests/flags BUNDLED in-app** (first-launch asset strategy — durable rules): the 16 NWSL crests
  (11 vector SVG + 5 raster PNG for CHI/KC/BOS/DEN/GFC) and the **8 FEATURED** national-team flags ship
  in the asset catalog (`Crests/<ABBR>`, `Flags/<FIFA>`) as resolution-independent vector, lossless, so
  `TeamLogo`/`NationalTeamCard` render frame-one with ZERO network. **Rules:** bundle anything
  release-cadence (reserve network for live data); **bundle = featured set, browse-all = download+cache**
  (don't chain a growing list to releases); bundled is authoritative — live is never fetched when a bundle
  exists. `GET /crest?team=WAS` (KV `crest:{ABBR}`, `scripts/load_crests.mjs`) = FALLBACK for non-NWSL
  sides + rebrand-override source; `GET /crest/manifest` (KV `asset:manifest`,
  `scripts/build_asset_manifest.mjs`) = per-asset source-master hashes + a `v`(vector?) flag for the
  cadenced refresh (`AssetRefreshService`, >30d/March), which **never downgrades vector→raster**. Re-run
  both on a rebrand.
- **Bracket engine:** `src/bracket.ts` + `bracket-engine.ts` — auto-generate 64-player
  editions from ESPN, tally votes + advance rounds on a cron, rotate creative↔stats editions.
- Teams/roster/standings still hit ESPN directly. Base URLs in `Config/AppConfig.swift`;
  DEBUG `-useESPNDirect` bypasses the proxy.

**Per-user backend (Supabase):** boundary = Workers (stateless/global) vs Supabase
(stateful/per-user). Sign in with Apple → a Supabase user; a `profiles` row + `follows`
row-set (RLS'd to the owner) persist per account. **Offline-first:** UserDefaults is the
immediate local cache; the app never blocks on the network to show follows. On sign-in
local and server follow sets are **merged (union — never delete)**. Schema (tables + RLS +
the required `authenticated` GRANTs) is checked in at `supabase/schema.sql`. **Gotcha:**
RLS alone isn't enough — a new per-user table needs `grant … to authenticated` or signed-in
queries silently fail with `42501`. The Supabase client is built from gitignored `Secrets`
(see `Services/SupabaseManager.swift`).

---

## Workflow & Engineering Practices

Treat these as requirements. If a request would bypass one, pause, flag it, explain the
trade-off before proceeding.

**Build to spec, not to minimum.** Numbers in a design doc are requirements, not
suggestions. Don't ship scaled-down versions that need follow-up to reach spec. A feature
isn't "shipped"/checked off until EVERY sub-item is automated + verified — no partial
credit; a scaffold needing manual steps ≠ the feature. Don't reclassify required work as
"deferred."

**Prove it live.** Verify "it works" with evidence (curl the proxy/REST, screenshot the
sim, trace the code path) — never reason from an unverified assumption.

**NO SILENT FAILURES (app-wide default).** Every unexpected condition (fallback, API failure,
stale serve, parse error, retry, unexpected-empty) ALWAYS emits telemetry — record to the
`Diagnostics` spine (`Services/Diagnostics.swift`: os_log + @Observable ring), visible in
dev/TestFlight via a diagnostics surface (the `-assetAudit` screen seeds it). Fail LOUD to the
engineer always; fail HONESTLY to the user proportionally (degraded → subtle truthful indicator,
never a fake-perfect fallback; blocked → clear message + retry). Banned: blank screens pretending
no content, infinite spinners, silent fallbacks indistinguishable from success. A failure must
never look like a success.

**Before starting a session:** `git status` (resolve uncommitted changes first); never
work on `main` — branch `feature/<desc>` first; state what you'll touch.

**During work:** for a change touching 3+ files or a new pattern, present a plan and get
approval first. Don't add a dependency without explaining why the built-in won't work +
approval. No force-unwraps (`!`) unless a comment explains why it's safe. Temporary code
that bends architecture carries a `TEMP` comment (what/why/when-removed).

**Before "done":** app builds AND runs in the simulator with no errors; the feature is
**manually verified in-sim** (compiling ≠ working); commit messages are specific,
present-tense, `<Area>: <what changed>`; update the **File Map** + **Current State** below;
confirm before pushing (don't auto-push).

**Git:** never commit to `main` — work on a feature branch, merge via **squash-merge** PR
(one commit on main; OK to combine related branches into one PR). Never commit secrets.
Commits use the owner's GitHub no-reply email (`286203575+tiffanyrieth@users.noreply.github.com`).
CLAUDE.md/commits/PRs/comments stay neutral/professional — never reveal owner preferences;
use arbitrary teams for examples.

**Local hooks** (`hooks/`): `pre-commit` blocks commits onto `main`; `pre-push` blocks
deleting/force-pushing `main`. Bypass with `--no-verify`; a fresh clone runs
`git config core.hooksPath hooks` to enable. See `hooks/README.md`.

**`gh` auth expires mid-session:** the token can go stale — `git push` keeps working but
`gh` API calls (`gh pr create`/`merge`, `gh api`) fail `HTTP 401`. Fix: owner runs
`gh auth refresh -h github.com`, then retry. So a push that succeeds but a follow-up PR
merge that 401s is this, not a permissions problem.

---

## Collaboration Preferences

This project doubles as a way to build durable iOS/software-engineering skills —
understanding each change matters as much as shipping it.
- Explain the reasoning behind non-obvious decisions/trade-offs as you go.
- When introducing a new file/folder, note why it's organized that way.
- First time a pattern appears (MVVM, state enums, `async`/`await`, `Codable`), briefly
  explain how it works.
- If a request reflects a misunderstanding or would introduce bad practice, say so and
  propose the better approach.
- **Decision split:** the owner owns design/UX/product calls; defers fine engineering
  logistics to Claude AFTER a reasoned explanation. Explain-then-recommend; don't over-ask
  on low-level forks, but never guess product/cost calls.
- **Nothing is impossible:** never answer "can we do X?" with "not possible / no API."
  Research alternatives, present the menu of paths + costs/tradeoffs, let the owner decide.

---

## UI Requirements

- Persistent UI (tab/nav bars) must never obscure scrollable content — respect safe areas.
- Every drilled-in view has an explicit back affordance; don't rely on edge-swipe alone.
- **Back-button = PARENT, not self.** A drill-in's back chevron must read the screen you came
  FROM ("‹ Schedule", "‹ Home", "‹ Standings"), never the current screen's name. The pushing
  screen passes its own name as an `origin`/label; the child renders it via `navigationContextLabel`.
  (SwiftUI's automatic back-title doesn't propagate here because the tab roots hide their bars for
  custom headers, so the parent name is passed explicitly.) Don't hardcode the current screen's name.
  On full-bleed detail screens the header (crests + score, etc.) carries identity, so there's **no
  centered nav title** — just the parent back button. `TeamDetailView` takes an `origin` and renders
  "‹ {origin}" directly (Teams→"Teams", Standings→"Standings"); `MatchDetailView` does the same.
- Navigation state resets predictably (tapping a tab returns to its root).
- Placeholders allowed only as intentional scaffolding: a clean "Coming soon" state (never
  blank/broken) AND flagged in the File Map. A placeholder must look deliberate, not forgotten.
- The schedule shows the full season, not a rolling window.
- Clarity over density — screens should breathe (~4–5 schedule cards/screen; avoid oversized
  NWSL/MLB-style cards).
- **Dark appearance app-wide**, no toggle (page `#1C1C1E`, cards `#2C2C2E`).
- **Crest rule:** bare crests via `TeamLogo`, no ring (only player monograms get a ring).
- **Team colors:** `DesignTeamColors` by abbreviation so ESPN near-black primaries stay legible.
  **Always use each club's default brand colors; do not add manual color overrides (e.g. the
  Portland→gold override) unless there's a documented rendering conflict. Remove existing overrides
  that aren't justified.**
- **Team naming:** one team as subject → full club name (Gotham FC). **Two-team contexts (match
  cards, match detail, head-to-head/season comparisons, standings rows, recent form in a matchup)
  always use CREST + ABBREVIATION (e.g. WAS) — never full club names and never crest-less text. Full
  club names appear only in single-club contexts (club page, Teams directory, following lists). Crests
  are never dropped in favor of text.** ESPN has no nickname field.

---

## Navigation Identity

Each tab has a distinct lens. When adding/redesigning, check the lens matches and neighbors
stay consistent. Full rationale in `Reference/navigation-architecture.md`.
- **Home** — your teams, right now. Personal + temporal. The engagement hub (live content,
  Player Spotlight, Fan Zone games, "Coming up").
- **Schedule** — when do they play / what happened? Full-season calendar.
- **Standings** — where does your team sit?
- **Teams** — the club directory + deep dives.
- **Feed** — the conversation around your teams (reporter/journalist/social voices).

**Adjacency rule:** Home Module 1 (team content) and Feed (reporter/social voices) are
distinct — don't blur them. Schedule cards and MatchDetailView share visual language.

---

## Versioning & Distribution

- **Versioning model (owner's, NOT classic semver — follow this).** A **`minor.0` (e.g.
  `0.4.0`) is a big flagship release**, like Apple shipping iOS **26.0** — it bundles a pile of
  features and can span **several TestFlight builds** under the *same* marketing version (e.g.
  0.4.0 build 9 = QOL, build 10 = headshots). **Do NOT bump the patch digit for a new feature** —
  features stay at `.0`. **Patches (`0.4.1`, `0.4.2`…) are reserved for BUG FIXES** discovered
  after the big release. A **minor bump (`0.4` → `0.5`)** starts the next big release era. Reserve
  **1.0.0** for the first public App Store launch.
- **Releases so far:** `0.1.x` prototype → `0.3.x` backbone (→ fully live, capped 0.3.9) → **`0.4.0`
  flagship** (the "fully-working app", shipping as successive builds — QOL, headshots, etc.; features
  stay `.0`). 0.4.1+ = bug-fix follow-ups.
- **Xcode fields:** "Marketing Version" (`CFBundleShortVersionString`, human-facing — stays `0.4.0`
  across the flagship's builds) + "Build" (`CFBundleVersion`, a monotonic int bumped on every
  TestFlight upload — this is what increments per feature build). Tag releases in git. Proxy-only
  changes don't bump the app version.
- **Distribution:** Simulator + Personal Team sideload now; Dev Program is active (paid);
  TestFlight (OTA) for tester install. App Store deferred until presentable.

---

## File Map (UPDATE THIS AFTER EVERY FEATURE)

Marker: 🔧 = intentional "coming soon" placeholder. Design specs in `Reference/Design/*-spec.md`.
Online-only — no runtime seed/offline fallback (see State of the app); fixtures live only in previews + tests.

```
NWSLApp/
├── NWSLAppApp.swift                   — app entry; launches RootTabView; forces dark; DEBUG `-resetOnboarding`; AppDelegate (APNs token + foreground/tap → PushBridge)
├── NWSLApp.entitlements               — Sign in with Apple + aps-environment (push) + game-center (Game Center)
├── Config/
│   ├── AppConfig.swift                — base URLs; scoreboard/summary → proxy; DEBUG `-useESPNDirect`; content route URLs (teamVideos/feed/spotlight/trivia)
│   ├── Secrets.swift                  — 🔒 GITIGNORED Supabase URL + anon key
│   └── Secrets.example                — checked-in template (non-.swift so it never compiles)
├── DesignSystem/
│   ├── DSColor.swift                  — `Color.ds*` tokens (dark-only hex)
│   ├── DSMetrics.swift                — `enum DS` spacing/radii/avatar/crest/game-card dims
│   └── DSText.swift                   — modifiers: `.trackedCaps()`, `.sectionTitle()`, `.navigationContextLabel("…")`, `Font.dsScore`
├── Models/
│   ├── BracketEdition.swift           — Bracket Battle: BracketRound/Entrant/Matchup/Edition (64→6 rounds, flat Codable)
│   ├── Club.swift                     — flat Club + ESPN /teams decode (brand/alternate color → crests)
│   ├── Competition.swift              — `ScheduledMatch` (Event + `CompetitionType` tag) + `ChampionsCupFeed`/`NationalTeamFeed.all` (7 women's NT feeds incl. uefa.weuro/fifa.wwc/fifa.w.olympics; keep in sync with proxy `WOMENS_NT_FEEDS`); the seam folding non-NWSL feeds into the schedule
│   ├── ContentCard.swift              — unified ALIVE-content model: 7 layouts + `sourceType` (club·reporter·player·league·news, for Feed chips) + StalenessWindow (Home 72h / Feed 7d, 6-card-floored)
│   ├── NationalTeam.swift             — followable women's NT: FIFA code + name + flag + national brand color (followed wash/border/code tint). Curated `featured(8)`/`all(16)` (flagcdn slug + color) + a `discovered` init for data-driven Browse-all teams (ESPN flag by FIFA code; color via DesignTeamColors.displayHex else neutral)
│   ├── AthleteStatistics.swift        — ESPN Core API /statistics → PlayerSeasonStats
│   ├── MatchSummary.swift             — ESPN /summary: lineups+formation, boxscore, key-events timeline
│   ├── PlayerSpotlight.swift          — Home Module-2 player-of-week; `espnAthleteId`+`seasonStatLine` carry live data; `statStrip` is nil when the proxy sent no stats → the view hides "This Season" (never fabricated)
│   ├── PlayerStats.swift              — per-player season stats + team-leaders (real ESPN data)
│   ├── Roster.swift                   — squad + team profile from one roster fetch
│   ├── Scoreboard.swift               — ESPN scoreboard structs + Event helpers
│   ├── Standings.swift                — table rows (rank + Club + GP/W/D/L/PTS)
│   ├── TeamSocialLinks.swift          — per-team social links for TeamDetail (reference data, no live API)
│   ├── TriviaQuestion.swift           — one Daily-Trivia question (4 options)
│   └── XIPrediction.swift             — Predict the XI: PositionGroup · Formation · PredictionFixture · XIPrediction (draft→submitted) · ActualResult · PredictionScore
├── Services/
│   ├── BracketScoring.swift           — pure Bracket scorer (tiered per-round points). Unit-tested
│   ├── ContentRoundRobin.swift        — pure Home Module-1 fair-share: `balanced` (per-team round-robin + content-type interleave + follow-scaled cap) + `advancedOffsets` (pull-refresh rotation). Unit-tested
│   ├── BracketService.swift           — Bracket Supabase client: currentEdition/results/leaderboard/submit; all throw on failure (online-only; no offline fallback; nil currentEdition only = genuinely no active edition)
│   ├── AthleteStatsCache.swift        — actor; session cache of PlayerSeasonStats
│   ├── ContentService.swift           — ALIVE content client: homeCards→/team-videos · feedCards→/feed · spotlightCards→/spotlight; all `throws` on failure (online-only; no seed)
│   ├── ESPNService.swift              — async fetch: scoreboard + summary (proxy)/teams/roster/standings + seasonStats (Core API)
│   ├── FollowSyncService.swift        — Supabase `follows` client (fetch/push/add/remove); RLS-scoped
│   ├── CompetitionFollowSyncService.swift — Supabase `competition_follows` client (national-team + Champions Cup follow keys: "nt:USA"/"concacaf"); the competition twin of FollowSyncService; RLS-scoped
│   ├── DeviceTokenService.swift       — Supabase `device_tokens` client (APNs token); RLS-scoped
│   ├── NotificationPrefsSyncService.swift — Supabase `notification_preferences` upsert
│   ├── NotificationScheduler.swift    — @MainActor; LOCAL (Tier 1) scheduling: day-before reminder (global type ∩ teams with alerts on) + weekly spotlight (global)
│   ├── PushBridge.swift               — @MainActor @Observable `.shared`; UIKit AppDelegate (APNs/tap) → observable world
│   ├── SupabaseManager.swift          — the one shared SupabaseClient (built from Secrets)
│   ├── HeadshotStore.swift            — @MainActor @Observable `.shared`; fetches the `/headshots` map (espnAthleteId→NWSL GUID) once per launch; `guid(forAthleteID:)`; best-effort (failure → monograms)
│   ├── AssetRefreshService.swift      — @MainActor; cadenced (>30d / forced March) best-effort refresh of BUNDLED crests/flags: diff `/crest/manifest` vs BundledAssetManifest, download only a rebranded asset to Caches (cache-override → bundle → network); NEVER downgrades vector→raster (vector→vector waits for re-bundle); never gates cold start
│   ├── BundledAssetManifest.swift     — source-master hashes (sha256[:16]) of every shipped crest + FEATURED flag + the raster-crest set; matches the proxy manifest so a fresh install re-downloads nothing. GENERATED — regen when bundled art changes
│   ├── Diagnostics.swift              — @MainActor @Observable `.shared` NO-SILENT-FAILURES spine: os_log + capped event ring (assetBundleMiss/apiFailure/parseError/staleServe/…), surfaced in dev/TestFlight + flushed (background/burst) to proxy `POST /telemetry` (non-PII: kind+detail+ts+app/os, no identifiers)
│   ├── GameCenterIDs.swift            — GameKit ID constants (4 leaderboards + 6 achievements) + pure cross-game score helpers (GameKit-free, unit-tested)
│   ├── GameCenterManager.swift        — @MainActor @Observable `.shared`; LAZY idempotent `authenticate()` (on-appear from game screens + Profile, not launch) + best-effort submit/report/syncAll/showDashboard. Only file importing GameKit
│   ├── TeamAlertPrefsSyncService.swift— Supabase `team_alert_preferences` client (per-team on/off upsert/fetchAll, composite key); RLS-scoped
│   ├── SupportStore.swift             — @MainActor @Observable StoreKit 2 for Support: 4 tip tiers (one-time + monthly), load/purchase/restore, `purchased` thank-you flag
│   ├── PredictLeaderboardService.swift— Supabase per-team Predict board: upsertScore + standings(team); a read failure shows only your real local score (no fabricated rivals)
│   ├── TriviaLeaderboardService.swift — Supabase league-wide Trivia best-streak board: upsertScore + standings; read failure shows only your real local streak
│   ├── PredictionScoring.swift        — pure Predict-the-XI scorer (Mastermind partial, max 88). Unit-tested
│   ├── RecentForm.swift               — pure last-5 W/D/L per club from the season; feeds Standings "Last 5"; `result(scored:conceded:)` = the shared W/D/L rule (reused by MatchDetailViewModel.form). Unit-tested
│   ├── TeamSocialLinksProvider.swift  — static per-team social-account URLs (reference data, no live API)
│   └── TriviaService.swift            — Daily-Trivia client: triviaQuestions→/trivia; `throws` on failure OR empty pool (online-only; no seed)
├── Stores/                            — @Observable shared state → UserDefaults, injected
│   ├── AppRouter.swift                — tab selection (AppTab); `openMatch(eventID:)` live-push tap; `reselectNonce` (re-tap-active-tab → Schedule snaps to boundary); DEBUG `-startTab`
│   ├── AuthStore.swift                — @MainActor; Sign in with Apple → Supabase user; profile upsert; cached displayName; deleteAccount
│   ├── BracketStore.swift             — Bracket per-edition/round draft + one-way submit (only after server ack) + banked points + edition-summary gate snapshot (`bracket.v2.*`; no offline edition cache)
│   ├── ClubStore.swift                — shared club directory; one fetch, many readers
│   ├── FeedPreferencesStore.swift     — Feed content-type toggles + muted sources + `defaultFeedFilter` (the chip the Feed opens to, raw string)
│   ├── FeedStore.swift                — @Observable shared Feed cards + load state (one fetch, many readers); PREWARMED low-pri from RootTabView so the first Feed switch is instant; honest loading state (isLoadingItems + hasCompletedItemsLoad → never a fake-empty)
│   ├── FollowSyncCoordinator.swift    — @MainActor; the ONLY follows↔Supabase bridge (sign-in union-merge + ongoing sync) — clubs (`follows`) AND competition follows (`competition_follows`: national teams + Champions Cup)
│   ├── NotificationSyncCoordinator.swift — @MainActor; device-token + notif-prefs↔Supabase bridge
│   ├── TeamAlertStore.swift           — @Observable; per-team match-alert ON/OFF (`Set<String>`) → UserDefaults; `migrateFromGlobalIfNeeded`; `onAlertChanged` sync seam
│   ├── TeamAlertSyncCoordinator.swift — @MainActor; per-team on/off↔Supabase bridge + clears a team's alerts when it leaves the followed set (alerts require following)
│   ├── FollowingStore.swift           — followed clubs + national teams + Champions Cup toggle + onboarding gate; offline-first; `competitionFollowKeys`/`mergeCompetitionFollowKeys` for sync; one-time legacy-competition migration; DEBUG `debugResetState`
│   ├── NationalTeamDirectoryStore.swift — @Observable; loads `/national-teams` once (data-driven Browse-all directory); idle/loading/loaded/failed
│   ├── MatchStore.swift               — shared season store; one fetch, many readers
│   ├── NotificationPreferencesStore.swift — Profile's 9 notif toggles; → NotificationScheduler / NotificationSyncCoordinator
│   ├── PredictionStore.swift          — Predict-the-XI durable state: predictions+scores by fixtureID (`predict.v2.*`); `seasonPoints` + `points(forTeam:)` + `scoredTeams`
│   └── TriviaStore.swift              — Daily-Trivia streak/bestStreak/accuracy + one-play/day gate
├── ViewModels/                        — @Observable; one per screen (idle/loading/loaded/error)
│   ├── BracketViewModel.swift         — Bracket session: round phase, progress, results, leaderboard, settled-round scoring (+ Game Center submit)
│   ├── FeedViewModel.swift            — source-class chips (All/News/Clubs/Reporters/Players by `sourceType`; Reporters also = league outlets) + filtered [ContentCard] (follows∩ OR league, 7d staleness); cards ← ContentService; `itemsError` on fetch failure
│   ├── HomeViewModel.swift            — derives Home modules from MatchStore+ClubStore+Following; M1/M2 via ContentService; per-module `contentError`/`spotlightError` + `retryContent`
│   ├── MatchDetailViewModel.swift     — one match: temporalState (past/live/future) + /summary + live refresh + preview
│   ├── PredictXIViewModel.swift       — Predict slate (open fixtures per followed team) + scoring via /summary + real per-team leaderboards (+ Game Center submit)
│   ├── XIPickerViewModel.swift        — in-flight XI picker: formation + slot→athlete + scoreline; read-only once submitted
│   ├── ScheduleViewModel.swift        — day-grouped sections + filters from MatchStore
│   ├── StandingsViewModel.swift       — one-shot fetchStandings
│   ├── TeamsViewModel.swift           — thin reader over the shared ClubStore
│   ├── TeamDetailViewModel.swift      — roster + social links + real season stats/leaders
│   └── TriviaViewModel.swift          — one Daily-Trivia session; questions ← TriviaService (throws→error state); non-repeating daily-5 (unit-tested); best-streak leaderboard (+ GC submit)
├── Views/                             — one screen per file
│   ├── RootTabView.swift              — app root; 5-tab TabView; injects stores; restores session + coordinators; Game Center syncAll (auth deferred to game screens); routes live-push tap
│   ├── HomeView.swift                 — your-teams hub (32pt header + avatar): 4 modules; M1 round-robin + per-team chips (2+ teams) + "See more →" (per-module error+retry card); M2 Spotlight carousel; M3 Fan Zone featured + tiles; refetch on pull + follows-change
│   ├── HomeContentListView.swift      — "See more from your teams" full firehose: ALL followed-team content, no cap, reverse-chron, respects the active team chip (+ `HomeTeamChips` bar: [All] + per-team)
│   ├── ProfileView.swift              — account & settings sheet: identity / Fan Zone stats (🏆 → Game Center) / Settings (Notifications → hub · Support → SupportView) / My Teams / Account
│   ├── NotificationsView.swift        — the ONE notifications hub: §Match alerts (per-team on/off) · §Alert types (global, dimmed when no team on) · §Activity; 3 doors. INVARIANT: Tier-2 ON ⟹ signed in (default OFF, sign-out resets); unfollow clears alerts
│   ├── SupportView.swift              — "Support NWSLApp" (StoreKit tips): hero · one-time/monthly toggle · 4 tip tiers · CTA · Restore · "Where it goes" · thank-you state
│   ├── DailyTriviaView.swift          — Daily Trivia game (indigo); 5/day; results screen w/ best-streak leaderboard
│   ├── BracketBattleView.swift        — Bracket Battle (teal): 5 screens — Edition Intro · Voting · Save/Submit · Results · Bracket Overview
│   ├── PredictXIView.swift            — Predict the XI (pink): open fixtures + Results breakdown + per-team leaderboard cards
│   ├── XIPickerView.swift             — Predict picker sheet: formation chips → pitch-grid slots → scoreline → Save/Submit (+ Game Center first-prediction)
│   ├── OnboardingView.swift           — first-open club picker (+ a quiet pointer to Teams → Follow competitions; the old inert competition toggles are gone)
│   ├── SignInPromptView.swift         — sign-in half-sheet shown ONLY on a genuine sign-in-required action (Bracket submit); never auto-presented post-onboarding
│   ├── NotificationAuthPromptView.swift — contextual "sign in for live alerts" half-sheet (Tier 2)
│   ├── ScheduleView.swift             — full-season cards; filter chips (NWSL · My teams = followed clubs + national teams + Champions Cup); "SAT · MAR 14" headers + TODAY chip; opens at the past/upcoming boundary (ScrollViewReader + opacity gate, no flash, incl. Home-preload); re-tap + filter animate back
│   ├── TeamsView.swift                — all-16 directory: ONE list (followed floated up) + subtitle; follow-competitions row; per-row 🔔 toggles (+ bottom confirmation toast → hub) + "{N} teams · Manage" line + nav-bar 🔔 → NotificationsView; first-visit coach mark (zIndex-lifted above the grid)
│   ├── CompetitionsView.swift         — follow international comps: Champions Cup card+toggle (top) + National Teams = scoped search bar (under header) → SUGGESTED shortcut (8 curated, USA-first, bundled flags) over the full DATA-DRIVEN A-Z list (NationalTeamDirectoryStore; suggested also in A-Z, iOS Frequently-Used pattern); searching hides SUGGESTED; honest loading/error/empty. No Browse-all screen; NT get no detail page
│   ├── TeamDetailView.swift           — club page: header (⭐ follow) + social row + Squad·Stats tabs
│   ├── MatchDetailView.swift          — state-aware match: full-bleed Card-C header (72pt crests, team-color abbr + score per crest, temporal center) + "‹ {origin}" back; past=Play-by-Play/Lineups/Stats (formation pitch + BENCH), live=poll & LIVE pill, future=info grid + How-to-Watch + comparison + form
│   ├── CombinedPitchView.swift        — BOTH teams' XIs on ONE pitch; Lineups default
│   ├── FormationPitchView.swift       — single-team XI on a pitch; per-team list fallback
│   ├── PlayerDetailView.swift         — roster bio + season stat block
│   ├── PlayerSpotlightView.swift      — editorial spotlight: ghosted jersey # + hero, This Season grid, Story (Haiku blurb), Fast Facts + Watch
│   ├── StandingsView.swift            — color-block table (# · TEAM · PTS · GP · W · D · L · LAST 5); crest + color-coded abbr every row; cyan PLAYOFF LINE the only cutoff cue (no dimming); team-color left spine + tint + accent rank = FOLLOW indicator (no ★); Last-5 via RecentForm over `nwslEvents`
│   ├── FeedView.swift                 — Feed tab: header (title+gear+subtitle) + source-class chip bar + chronological ContentCardViews; opens to `defaultFeedFilter`; full-screen error+retry on fetch failure
│   ├── FeedSourcesView.swift          — Feed content preferences: Default-view picker + content-type toggles + mute sources
│   ├── _ColorAuditView.swift          — 🔧 DEBUG-only 16-club color audit (`-colorAudit`); remove once verified
│   └── _AssetAuditView.swift          — 🔧 DEBUG-only bundled-crest/flag fidelity audit (`-assetAudit`); remove once verified
├── Components/
│   ├── BroadcastInfo.swift / BroadcastLink.swift — "How to Watch" DB + broadcast→watch-URL
│   ├── Chip.swift                     — pill filter chip (Schedule + Feed chip bars); optional `compact` (13pt) for the redesigned Schedule bar
│   ├── BroadcastChip.swift            — color-coded broadcast pill (handoff palette, substring-matched); schedule cards now, match detail at #2 (separate from BroadcastInfo's color DB)
│   ├── ContentCardView.swift          — single entry point; routes a ContentCard by layout → the 3 card views; 3px team-color left-edge bar (color-block motif) on all layouts
│   ├── ThumbnailContentCard.swift / AvatarContentCard.swift / ArticleContentCard.swift — the ContentCard layouts
│   ├── SettingsToggleRow.swift        — shared settings primitives: `SettingsToggleRow` + `SettingsGroup` (optional subtitle + optional quieter `note` line) + `SettingsRowDivider` (NotificationsView)
│   ├── PlatformBadge.swift            — platform glyph (YT/Bluesky/TikTok/IG/article/reddit)
│   ├── FormBadge.swift                — W/D/L form badge (optional `size`/`fontSize`, default 22; `MatchResult` convenience init)
│   ├── GameCard.swift                 — Fan Zone game tile (200×160, radial accent-glow corner + emoji + status pill + badge)
│   ├── FeaturedGameCard.swift         — Fan Zone full-width featured lead card (medallion + FEATURED eyebrow + title + tagline + CTA) anchoring M3; rest render as GameCard tiles
│   ├── HowToWatchCard.swift / MDInfoCard.swift / StatComparisonBar.swift — match-detail tiles (HowToWatch = FREE/SUB badge + BroadcastChip + verbatim per-device "Find it" steps; MDInfoCard = label/value)
│   ├── PitchDot.swift / PlayerDot.swift / PlayerCard.swift — player markers/cards (team-color monogram, no headshots)
│   ├── ComingUpRow.swift / EventTimelineRow.swift / FlowLayout.swift — Home/match rows + wrapping layout
│   ├── ImageCache.swift / TeamLogo.swift / CachedThumbnail.swift — cached crests + content thumbnails; TeamLogo resolves cached-override → BUNDLED crest/flag (`Crests/<ABBR>`·`Flags/<FIFA>`, zero-network frame-one) → proxy `/crest`/ESPN; CachedThumbnail sync-seeds from ImageCache so cards don't flash on tab-switch
│   ├── MatchCard.swift                — schedule card (takes a `ScheduledMatch`) → MatchDetailView: team wash, 60pt crests, team-color abbr under each crest (non-NWSL sides via `DesignTeamColors.displayHex`), scores below, temporal center, broadcast+venue rail, competition label for non-NWSL matches, uniform height
│   ├── NationalTeamCard.swift         — shared NT grid card (Competitions hub + Browse-all), mirrors the club card: flag (bundled vector `Flags/<FIFA>` → cached-override → `team.flagURL`) + halo, FIFA code in country color, name, Follow pill + bell; followed → country-color wash + border. Reads FollowingStore + TeamAlertStore from env
│   ├── PlayerHeadshot.swift           — circular player headshot via HeadshotStore→Cloudinary (ImageCache); jersey-monogram fallback on all 6 avatar surfaces (404/unmapped keeps the monogram)
│   ├── PlayerSpotlightCard.swift      — Module-2 hero (~400pt): team-gradient card, headshot fade-masked into the gradient, text in a left zone; ghost# + crest fallback on no-GUID/404 (never empty)
│   └── SocialLinkButton.swift         — circular team-tinted social icon
├── Extensions/
│   ├── Color+Hex.swift                — Color(hex:); teamAccent/teamFillOnDark; resolveMatchColors
│   ├── Date+RelativeAgo.swift         — shared "2h ago" formatter
│   ├── Club+BrandColor.swift          — Club → brandHex/accentColor (design palette → id-override → ESPN)
│   ├── DesignTeamColors.swift         — curated 16-team NWSL palette by abbreviation (authoritative; `hex(for:)` doubles as the NWSL-membership test). `displayHex(for:)` = COLOR-only resolver adding national teams + foreign Champions Cup clubs (kept separate so it never affects the membership test)
│   └── TeamBrandColors.swift          — per-team-id brand-color overrides for clubs ESPN gets wrong
└── Assets.xcassets/                   — app icons, accent; `Crests/` (16 NWSL: 11 vector SVG + 5 raster PNG), `Flags/` (8 FEATURED NT flags, vector SVG; browse-all = download+cache) — bundled for zero-network first launch

supabase/schema.sql                    — Postgres: profiles, follows, competition_follows, device_tokens, notification_preferences, team_alert_preferences, bracket_*, prediction_scores, trivia_scores (+ RLS + authenticated GRANTs)
NWSLApp.storekit                       — local StoreKit 2 config (4 tip consumables + monthly subs) for in-sim Support testing; referenced by the shared scheme. ASC products owner-gated
```

---

## What's Next

Pending work only (ALIVE > core > hardening); shipped work lives in git history + the File Map, not here.
- **First-launch perf** (Reference "First Launch Performance — Asset Strategy") — Tier 1 + 2 shipped (bundling,
  rebrand refresh armed, disk cache, prefetch priority, Feed prewarm, telemetry). DEFERRED: the onboarding
  quick-tips screen — a deliberate design task, not a perf buffer (build only if wanted as UX).
- **YouTube Shorts thumbnail pillarbox** — DEFERRED (owner). Baked-in side bars; fix is proxy-side.
- **Pull-to-refresh polish** — keep the list visible during refresh (spinner only on first load).
- **Bracket follow-ups (optional):** exact stat-edition seeding; more stat templates; full bracket-TREE
  graphic. Owner to curate the Best Goal Celebration creative edition (`scripts/load_creative_edition.mjs`).
- **Home follow-ups:** spotlight no-repeat-per-season + opt-in weekly notif.
- **Player headshots — Phase B2 banners (DEFERRED — licensing):** Team Detail banner on hold pending review.

**Hardening (after ALIVE work):**
- `Fixtures/scoreboard.json` + a decode-only test for `Scoreboard`/Event helpers (date parsing, `dayKey` TZ).
- `MatchStore.matches(for:)` joins club↔game by `abbreviation` (no ESPN id) — a rename silently empties
  a schedule. Fix: a normalized id map.
- Team social links — verify a few subreddit handles (KC `r/KCCurrent`; CHI `r/redstars` vs `r/ChicagoStars`).
- **Club-page links data pass** — add Website · Shop · Tickets (OFFICIAL) + Discord (Fan) to
  `SocialPlatform` + `TeamSocialLinksProvider`, curated per-club (gracefully omitted today).

**Longer-term:**
- **Push — Tier 2 (SERVER push)** — code-complete through Stage C (Worker `~/Projects/nwslapp-match-watcher`:
  cron + KV diff + APNs JWT; kickoff/goal/halftime/full-time; per-team targeting live). Remaining: flip
  `APNS_HOST` sandbox→production at TestFlight; on-device E2E; Stage D (subs + lineup-posted).
- **Competitions follow-ups** (shipped): WWC + Olympics whole-tournament UI (group tables/brackets) DEFERRED
  — but their followed-team MATCHES already fold into Schedule. Foreign-club color DB grows as Champions Cup
  opponents appear (`DesignTeamColors.international`). Broaden NT coverage further by adding confirmed women's
  feeds to `NationalTeamFeed.all` + proxy `WOMENS_NT_FEEDS` (e.g. Copa América Femenina once slug-confirmed).
- **Feed** — user-added sources; richer filtering. **Weather** — kickoff-temp header slot.
