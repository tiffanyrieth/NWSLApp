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
- Endpoints can change shape, break, or rate-limit without notice. Fail gracefully.

**Proxy (Cloudflare Worker `nwslapp-proxy`)** — sibling repo `~/Projects/nwslapp-proxy`
(GitHub `tiffanyrieth/nwslapp-proxy`), live at `https://nwslapp-proxy.tiffany-rieth.workers.dev`.
- **Pass-through caching:** `GET /scoreboard`, `GET /summary?event={id}` forward to ESPN
  and return bytes **unchanged** (app decoders untouched); match-state-aware TTL.
- **Content routes** (build + normalize to `[ContentCard]`/models): `/team-videos` (Home: YouTube +
  club OG news + club IG), `/feed` (Feed: Bluesky reporters/clubs + news RSS + player IG), `/spotlight`,
  `/trivia` (KV pool), `/national-teams` (data-driven NT Browse-all, deduped by FIFA, 24h), `/telemetry`
  (POST sink → KV). Server-side Haiku (`claude-haiku-4-5`, KV-cached) gates relevance + team-tags the
  third-party buckets (reporter/league Bluesky + news RSS: isNWSL strict; fail-DROP for social /
  fail-open for news); club + player accounts are trusted fast paths. Every card carries a `sourceType`
  (club·reporter·player·league·news) for Feed chips. Plus a flood cap + dedupe.
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
- Teams/roster/standings still hit ESPN directly. Base URLs in `Config/AppConfig.swift`;
  DEBUG `-useESPNDirect` bypasses the proxy.

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
