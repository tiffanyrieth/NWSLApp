# Backend & Data Sources

_ESPN endpoints, the Cloudflare-Worker proxy, and the Supabase backend. Read when touching networking, the proxy, or persistence._

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
- ⚠️ **The full-season `dates=` scoreboard query serves STALE live state for 25–47 min during live
  games** (ESPN's own CDN/app-tier cache — load-proven 2026-07-11: a match read `pre` 47 min after
  kickoff, then stuck `HT`/`70'` while reality was 90'+). The **windowed** (`dates=yesterday-tomorrow`)
  and default scoreboards stay fresh; only the whole-year query lags. A `_cb=<ts>` param forces ESPN to
  recompute (the app-facing fix is the proxy busting the upstream on MISS, below; the app also moved its
  live poll onto the windowed query, build 26). The app's stuck clock all game was THIS, not an app bug.
- Endpoints can change shape, break, or rate-limit without notice. Fail gracefully.

**Proxy (Cloudflare Worker `nwslapp-proxy`)** — sibling repo `~/Projects/nwslapp-proxy`
(GitHub `tiffanyrieth/nwslapp-proxy`), live at `https://nwslapp-proxy.tiffany-rieth.workers.dev`.
- **Pass-through caching:** `GET /scoreboard`, `GET /summary?event={id}` forward to ESPN
  and return bytes **unchanged** (app decoders untouched); match-state-aware TTL.
  - ⚠️ **`/scoreboard` busts the ESPN UPSTREAM on every cache MISS** (`proxyAndCache(..., bustUpstream)`):
    appends a `_cb=<ts>` to the ESPN fetch so ESPN can't serve its 25–47-min-stale full-season cache
    (see quirks above). The proxy's OWN edge-cache key stays the clean incoming URL, so app traffic still
    collapses to ≤2 ESPN hits/min — hit COUNT unchanged, just uncacheable ESPN-side. Zero added CPU
    (device-proven fix, 2026-07-11). The abandoned alternative (parse+overlay the 2MB season) blew the
    free-plan 10 ms CPU limit.
- **Roster resilience:** `GET /roster?team={espnTeamId}` passes ESPN's roster through when it's a
  plausible squad (≥`ROSTER_GOOD_MIN`=16) and caches it as **last-known-good** in KV (`roster:{id}`,
  90d); when ESPN comes back implausibly small (the recurring "one player" gap, e.g. ACFC) or fails,
  it serves the cached roster with an injected top-level **`proxyCachedAsOf`** marker → app shows an
  honest "Roster as of …" label (`ClubSquad.cachedAsOf`). Never silent (emits `rosterStaleServe` /
  `rosterImplausibleNoCache` / `rosterUnavailable` diag); deploy gate `health_check_roster.mjs`. ACFC
  was seeded once from the official club site (`scripts/seed_acfc_roster.mjs`).
- **Playoff override** (`src/playoff-override.ts`): the roster last-known-good philosophy applied to
  the postseason bracket — an operator escape hatch for when ESPN corrupts playoff data (wrong
  winner/score, a dropped game) or the format surprises us. `GET /playoff-override?season=YYYY` →
  `{ version, season, override }` (public; `override:null` = dormant, the app derives purely from
  ESPN). The app (`PlayoffStore`) layers it over the derived bracket AT THE EVENT LEVEL before
  derivation, so a corrected winner propagates to later rounds. Set/clear with the `BRACKET_ADMIN_KEY`:
  `curl -X POST ".../playoff-override?season=2026" -H "x-admin-key: $KEY" -d '{JSON}'` (clear:
  `&clear=1`). KV key `playoff-override:{season}` in `FEED_TAGS`, no TTL. Override JSON: `note` /
  `hideBracket` (kill switch) / `teamCount` / `seeds{abbr:seed}` / `matchups[{round,home,away,
  homeScore,awayScore,winner,state,kickoff,broadcast,venue}]` — all optional. Fix = live for every
  user in minutes, no App Store release.
- **Kickoff weather** (`src/weather.ts`): `GET /weather?event={espnEventId}` serves a PAST match's
  kickoff-hour temperature + WMO sky condition from **Open-Meteo** (free, no key — ESPN has no NWSL
  weather). Resolves venue/kickoff/state via the worker's OWN edge-cached `/summary` (the byte-identical
  URL the app already requests → warm hit, no extra ESPN calls), maps venue→lat/lon by a static
  **ESPN venue-id** table (`VENUE_COORDS`, 22 venues incl. alt/neutral sites — id-keyed so a stadium
  rename can't silently break it), and indexes Open-Meteo's **HOURLY** array at the exact kickoff hour
  (not the daily high; `timezone=UTC` so a UTC instant indexes a UTC-labelled array — no per-venue tz
  table). Source by age: forecast API `past_days` for matches <7d old (the archive API lags ~days),
  archive API for older; one fallback to the other if the hour is missing. **Cached write-once in KV**
  (`weather:{eventId}`, NO TTL — a finished match's weather is immutable → first open backfills, everyone
  after is instant; lazy so it covers ALL history, no cron). Night-aware via `is_day` (sun vs. moon icon
  app-side). Guarded to state `post`; future/live → `{mode:"unavailable",reason:"not-finished"}`; unknown
  venue → `unknown-venue` + `weatherVenueUnknown` diag (no KV write). Versioned envelope
  (`{v,mode,tempF,weatherCode,isDay,condition,asOf}`) leaves room for a later `mode:"forecast"` (upcoming
  matches). Strict `?event` validation (writes KV) unlike `/summary`'s pass-through. Deploy gate
  `health_check_weather.mjs` (FAILS on an NWSL `unknown-venue` = a new/renamed stadium needs coords). App
  side: `MatchWeather` model (WMO→SF-Symbol day/night map) + `MatchDetailView` header stamp
  (`MatchDetailViewModel.loadWeather`, additive/non-blocking, past-only).
- **Content routes** (build + normalize to `[ContentCard]`/models): `/team-videos` (Home: YouTube +
  club OG news + club IG), `/feed` (Feed: Bluesky reporters/clubs + news RSS + player IG), `/spotlight`,
  `/trivia` (KV pool), `/national-teams` (data-driven NT Browse-all, deduped by FIFA, 24h), `/telemetry`
  (POST sink → KV). Server-side Haiku (`claude-haiku-4-5`, KV-cached) gates relevance + team-tags the
  third-party buckets (reporter/league Bluesky + news RSS: isNWSL strict; fail-DROP for social /
  fail-open for news); club + player accounts are trusted fast paths. Every card carries a `sourceType`
  (club·reporter·player·league·news) for Feed chips. Plus a flood cap + dedupe.
- **IG scrape = LOAD-BALANCED across two free tiers** (2026-07-05, after Apify's free $5/mo ran dry
  mid-cycle): **clubs (16 handles → Home) via Apify** (~192 items/run ≈ $0.86/mo — Home serves the club
  pool UNCAPPED and pages its ~12/profile depth on refresh, so the cheap actor ignoring per-post limits
  is a feature) and **players (34 handles → Feed) via Bright Data's Web Scraper API** (recurring free 5k
  records/mo; `num_of_posts=6` honored ≈ 3,060/mo; players serve-cap at 3/handle anyway). BD is ASYNC:
  the every-2-day cron triggers, BD POSTs results to the proxy's `/brightdata-webhook` ~1–3 min later
  (auth = `BD_WEBHOOK_SECRET` echoed in the Authorization header). SPLIT KV keys
  (`social-cards-club-v1` / `social-cards-player-v1`, per-side keep-last-good — two writers, so a shared
  key would race). Admin `POST /refresh-social` (`x-admin-key`) forces an immediate refresh (token swap /
  aborted run). Gotcha: BD bills a record even for an EMPTY handle (renamed/dead account) — quota drains
  silently, hence the `bdHandleEmpty` diag; keep the player handle list clean.
- **Headshots** (`src/headshots.ts`): `GET /headshots` serves an `{espnAthleteId: nwslGuid}` map (NWSL
  SDP JSON name-matched to ESPN rosters, ~98%; weekly cron + admin `POST /headshots/run`; union-merged
  in KV with an unmatched/overrides audit). App builds the Cloudinary URL on-device — no image bytes.
- **Crests/flags BUNDLED in-app** (first-launch asset strategy — durable rules): the 16 NWSL crests
  (11 vector SVG + 5 raster PNG: CHI/KC/BOS/DEN/GFC) + the **8 FEATURED** NT flags ship in the asset
  catalog (`Crests/<ABBR>`, `Flags/<FIFA>`) as vector/lossless, so `TeamLogo`/`NationalTeamCard` render
  frame-one with ZERO network. **Rules:** bundle anything release-cadence (reserve network for live data);
  **bundle = featured, browse-all = download+cache**; bundled is authoritative (live never fetched when a
  bundle exists). `GET /crest?team=WAS` (`scripts/load_crests.mjs`) = FALLBACK for non-NWSL sides +
  rebrand-override; `GET /crest/manifest` (`scripts/build_asset_manifest.mjs`) = per-asset hashes + `v`
  (vector?) flag for the cadenced refresh (`AssetRefreshService`, >30d/March), which **never downgrades
  vector→raster**. Re-run both on a rebrand.
- **Bracket engine:** `src/bracket.ts` (pure) + `bracket-engine.ts` — generate editions from ESPN,
  tally votes + advance rounds on the `*/5` cron. **Manual/Auto** mode via `bracket_config`
  (operator drives the live game by one value change); **qualifying rounds** for 96–192 pools
  (negative round codes shared with the app's `BracketRound`); **real season-stat seeding** (leaders
  + per-athlete, budget-aware via `stat_fetch_budget`); per-edition **streak**; **theme-only**
  creative editions (pool from ESPN, like stats); `bracketStatSeed*`/diag + `npm run healthcheck`
  (`health_check_bracket.mjs`). Runbook: `Reference/Bracket Battle/first-launch-checklist.md`.
- Teams/standings still hit ESPN directly; **roster now routes through the proxy** (`/roster`, see
  above). Base URLs in `Config/AppConfig.swift`; DEBUG `-useESPNDirect` bypasses the proxy (roster
  included → ESPN's `teams/{id}/roster` direct, no cache/marker).

**Per-user backend (Supabase):** boundary = Workers (stateless/global) vs Supabase (stateful/per-user).
Sign in with Apple → a Supabase user; `profiles` + `follows` (RLS'd to the owner) persist per account.
**Display name** lives on `profiles` (`display_name` + `name_is_custom`) and is the leaderboard identity —
`AuthStore.hydrateProfile()` reads it back on BOTH auth paths (session restore AND fresh sign-in) so it
survives reinstall (UserDefaults is wiped, the server row is not; this is the fix for the old "reverts to
Member" bug). `name_is_custom` marks a CONFIRMED name vs. a merely-present (Apple-supplied) one; the Fan
Zone gate (`hasChosenName`) makes the user confirm before it hits a public board. Added via
`migration_profile_name_is_custom.sql` (defaults false, **no backfill** — existing testers confirm once).
**Offline-first:** UserDefaults is the immediate cache; the app never blocks on the network to show
follows. **Follows sync = RESTORE-ONLY launch reconcile + explicit per-toggle propagation.** Launch
`reconcile` (`FollowSyncCoordinator`) NEVER deletes a server row: it restores the full server set to a
wiped/un-onboarded device (`authoritative = (hasOnboarded && !local.isEmpty) ? local : remote`) and only
UPLOADS local-only follows. **Unfollows propagate solely through `handleLocalChange.removeFollow`** — an
explicit signed-in unfollow — so no launch-time race can prune. (This replaced the earlier
"device-authoritative mirror" whose launch prune could delete server rows under the reinstall onboarding
race: on reinstall the picker showed concurrently and its immediate `toggle` writes made `local` partial,
so the launch prune wiped the rest. Removing the launch prune makes a destructive launch delete
*impossible*, the hard invariant.) **Trade-off:** an unfollow made while signed-out/offline won't reach
the server (the only thing the launch prune used to catch) and will reappear on the next reinstall —
recoverable, and harmless to alerts (alerts live in `team_alert_preferences` with their OWN coordinator/
prune; follows ≠ alerts). A returning signed-in user is restored + skips onboarding (`RootTabView` shows a
brief "Restoring…" until `restoreResolved`, never the picker). Coordinators: `FollowSyncCoordinator`
(+ competition follows), `TeamAlertSyncCoordinator` (alerts keep their own mirror; alerts ⊆ follows).
Trade-off: two devices on one account diverging offline → last writer wins (acceptable at current scale;
upgrade to per-item `updated_at` last-write-wins if heavy multi-device curation appears). Schema at
`supabase/schema.sql`. **Gotcha:** RLS alone isn't enough — a new per-user table needs
`grant … to authenticated` or signed-in queries silently fail with `42501`. Client built from gitignored
`Secrets` (`Services/SupabaseManager.swift`).

**Account deletion (right-to-be-forgotten / App Store requirement):** the client can't delete an
`auth.users` row (needs the service-role key), so Profile → Delete Account calls the proxy
`POST /account/delete`, which verifies the caller's JWT then service-role hard-deletes the auth user.
All per-user FKs are `on delete cascade` (see `supabase/migration_account_deletion_cascade.sql` — five
were missing it: profiles/follows/device_tokens/notification_preferences/bracket_votes), so one admin
delete removes everything. `AuthStore.deleteAccount()` throws on any failure (never claims success
silently); ProfileView then wipes all local state. Deploy-gated by
`scripts/health_check_account_delete.mjs` (fails on a 404 route or 500 missing-secret).

**SIWA credential revocation (App Store guideline 5.1.1(v)) — deleting our data isn't enough; we must
also tell Apple the relationship is over, else a re-signup returns "existing user".** At sign-in the app
captures Apple's short-lived `authorizationCode` (~5-min TTL) and fire-and-forgets it to the proxy
(`POST /auth/apple-token-exchange`, via `AppleTokenExchangeService`) — never blocking sign-in; a miss
just means "no token until next sign-in". The proxy (`src/apple-auth.ts`) builds an **ES256 `client_secret`
JWT** signed with the SIWA `.p8` (same Web Crypto pattern as the watcher's APNs JWT — header carries
`kid`, payload `iss`=Team ID / `sub`=bundle / `aud`=appleid / 180-day `exp`), exchanges the code at
Apple's `/auth/token` for a `refresh_token`, and **upserts** it onto `profiles.apple_refresh_token`. On
account deletion, `handleAccountDelete` reads that token and calls Apple's `/auth/revoke` **before** the
Supabase cascade — best-effort and fully non-fatal (Apple down / no token / unconfigured secrets all just
emit a diag and proceed; a delete must never be stranded). **New Worker secrets** (set via `wrangler
secret put`, distinct from the APNs key): `SIWA_PRIVATE_KEY` / `SIWA_KEY_ID` / `APPLE_TEAM_ID`. The proxy
reads/writes `profiles` as service_role for the first time, so `migration_apple_refresh_token.sql` adds
both the column **and** `grant … to service_role` (the 42501 gotcha). Deploy-gated by
`scripts/health_check_apple_auth.mjs`. No backfill: existing users get a token on their next sign-in.

**Forced-update gate (`GET /config`).** Returns `{ minVersion, minBuild }` from two hardcoded constants
(`MIN_APP_VERSION` / `MIN_APP_BUILD` in `src/index.ts` — no KV/DB). The app checks it at launch
(`AppGateView` → `ForceUpdateService`) and walls itself off if `CFBundleVersion < minBuild`; the app fails
OPEN (a down `/config` never blocks). `minBuild` is a deliberate FLOOR raised by hand to retire a broken
build — see `docs/versioning.md` for the raise-only-after-the-build-is-live rule.

**V2 Live Activity (lock screen + Dynamic Island) — additive to V1 push.** Same `nwslapp-match-watcher`
Worker, same ES256 `.p8` JWT signer, SECOND APNs channel: `apns-topic: <bundle>.push-type.liveactivity`,
`apns-push-type: liveactivity`, payload `aps:{event:start|update|end, content-state, attributes-type,
attributes, stale-date, dismissal-date}` (`src/activitykit.ts`). **Two token types** mirrored to Supabase
by the app (`Services/LiveActivityManager.swift`, RLS-scoped + `grant…to authenticated`): a per-device
**push-to-start** token (`live_activity_start_tokens`) lets the watcher remote-create the Activity **≤20 min
pre-kickoff**. The per-Activity `live_activities` token table is retained but the cron **no longer uses it
for updates** (see the Broadcast Channels change below). **ROLE SPLIT: V1 is the interrupt, V2 is a quiet
glance.** ⚠️ **ARRIVAL-BUZZ LAW (device-proven, corrected 2026-07-09):** the start `aps` MUST carry an
`alert` (omit it and iOS silently never presents the card), and it **BUZZES ONCE** on arrival (`sound:
"default"`) — a fully-silent `sound:""` start is FLAKY and often never presents on real games; every UPDATE/
END stays silent (`docs/live-activity-v2.md` §3). The 20-min lead is deliberate (a device can take minutes to
register after push-to-start), under a UIKit background-task assertion (`withBackgroundTime`). **V2 in-match
updates ride APNs BROADCAST CHANNELS (SHIPPED 2026-07-09, `docs/push-fanout-scaling.md`):** the watcher
creates a channel per MATCH, the iOS 18 `input-push-channel` in the start payload auto-subscribes each
Activity, and every update/end is **ONE broadcast POST** (Apple fans out) — killing the old per-Activity-token
lag. `syncLiveActivity` broadcasts on an event, on **anchor drift** (`clockStartEpoch` jumps ≥30 s —
each half's late live-flip, so the card snaps within a tick instead of coasting behind to the 10-min
floor), on **stoppage rollover** (see Clock), or on the 10-min resync floor; and ends + deletes the
channel at FT; `startUpcomingActivities` (NOT folded into `detectEvents`) KV-dedups + creates the channel + sends the
per-device `event:start` (via the Queues rail) ≤20 min pre-kickoff. **Poll cadence:** the cron floor is
1 min, but during a live window the tick **double-polls** (poll → sleep 30 s → poll again cache-busted)
so goal/HT/FT latency is ~30 s (shipped 2026-07-11). **Clock:** the widget self-advances the minute
locally from `clockStartEpoch` (mm:ss, `showsHours:false` so it never rolls to `1:08`) — no per-minute
push during regular play; **BUT in added time the watcher broadcasts a `stoppageDisplay` string
("90'+2'") each minute** (Apple's timer can't format football stoppage; the anchor is frozen so drift
won't fire) — bounded ~2–8 min/match, one broadcast per channel. Widget render is build 26 —
device-verify pending. **Activation gate:**
`team_alert_preferences.alerts_enabled` AND the Tier-2 opt-in `notification_preferences.live_activities_enabled
= true` (`startTokensForTeams`), NOT follow. **V2 requires iOS 18** (Broadcast Channels) — the app registers a
start token only on iOS 18+; 17.x gets full V1 with an honest "Requires iOS 18" (graceful degradation). `POST /test-activity` (secret-gated) + `scripts/replay.mjs`
(compressed real-match replay, `--team`/`--start-only`/`--updates-only`) drive on-device E2E. **Sim caveat:**
push-to-start + the Dynamic Island don't work/composite in the sim — surface render is device-verified.

**Notification model = PURE OPT-IN.** Every `notification_preferences` toggle defaults OFF; nothing
auto-enables (there is no hub-visit auto-enable — removed). **Tier 1** (local, no account: day-before, Player
Spotlight) and **Tier 2** (watcher-triggered ⇒ account: kickoff/goals/HT/FT + the V2 Live Activity) are all
opt-in; Tier-2 toggles are sign-in-gated (`tier2Binding`) and reset on sign-out (`resetServerPushTypes`). The
watcher gates each V1 event on its per-event column (`tokensForEvent`) and V2 on `live_activities_enabled`.
