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
- ⚠️ **`state == "post"` does NOT mean the match finished** (live-proven 2026-07-29, UTA v WAS held
  for wind at 27'): a suspended/abandoned/postponed match reports `post` with **`completed: false`**
  and **`name: "STATUS_SUSPENDED"`** — and REVERTS to `in` on resume (`post→in` is otherwise
  impossible; any backwards state transition proves the prior state was wrong). Anything meaning
  "the result is settled" must use `Event.isFinalResult`/`isUnfinishedPost` (app) or
  `isUnfinishedPost` (watcher `src/events.ts`, mirrored set in `src/fixtures.ts`), all FAIL-OPEN:
  only positive evidence of non-completion blocks. Trusting bare `post` showed FT 0–0 mid-match,
  graded a Predict entry against the fake final, and made the watcher kill the Live Activity, mark
  the fixture `ended` (which stops polling), and miss the real full time.
- ⚠️ **`goalKeeping.savePct` is NOT a save percentage — it is `saves ÷ 100`** (live-verified
  2026-07-31 in BOTH leagues, 4 keepers). Angelina Anderson: 48 saves / 16 conceded, true rate
  **75%**, ESPN sends `0.48`. Hazel Nali: 3 saves / **0** conceded, true rate **100%**, ESPN sends
  `0.03`. The tell is the FORMAT — ESPN prints it batting-average style (`.360`, `.030`) while every
  genuine rate in the same payload comes back as `0.7`. Save % is therefore **COMPUTED** app-side
  from `saves / (saves + goalsConceded)` (`PlayerStats.seasonSections`, regression-tested with these
  specimens); never read the field. It shipped for weeks reading plausible-but-wrong on every keeper
  page — the archetypal failure-that-looks-like-success, and unlike a missing value nothing about it
  looked broken. **Sibling `*Pct` fields are fine** (`general.passPct` 0.707 = 147/208 accurate ✓);
  the defect is isolated to `savePct`, so don't generalize the distrust — or the fix.
- ⚠️ **Athlete names are not "First Last"** — for national teams ESPN carries whatever the federation
  registers, including full patronymic chains ("Yassmin Mohamed Abdelaziz Hassanin") and genuine
  in-payload repeats ("Maha Eldemerdash Eldemerdash Shehata", `lastName` = "Eldemerdash Eldemerdash
  Shehata"). Any surface rendering a name needs a horizontal bound and must WRAP, never truncate.
- Endpoints can change shape, break, or rate-limit without notice. Fail gracefully.

**Proxy (Cloudflare Worker `nwslapp-proxy`)** — sibling repo `~/Projects/nwslapp-proxy`
(GitHub `tiffanyrieth/nwslapp-proxy`), live at `https://nwslapp-proxy.tiffany-rieth.workers.dev`.
- **Pass-through caching:** `GET /scoreboard`, `GET /summary?event={id}` forward to ESPN
  and return bytes **unchanged** (app decoders untouched); match-state-aware TTL.
  - **The `/summary` payload carries far more than the app originally parsed** — as of 2026-07-18 the
    app also decodes `commentary` (the FULL play-by-play: shots/saves/fouls/corners/offsides/VAR),
    `leaders` (per-team match top performers), and `videos` (highlight clips, deep-link-out only;
    thumbnails load direct from `a.espncdn.com`, NOT via the proxy). Still unparsed: `news` (the
    GENERAL NWSL feed, not match-scoped — deliberately skipped, overlaps Club News),
    `lastFiveGames`/`headToHeadGames`, `odds` (skipped — values). The scoreboard similarly carries
    unused `competitor.form` ("WDLWL"), `competitor.records` ("5-4-5"), and embedded per-team
    `competitor.statistics`. Lesson (3-for-3 in one session): before adding a data source, check
    what the already-fetched feeds carry unparsed.
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
- **⚠️ Continuity guard on the CACHE WRITE (2026-07-30).** The size floor cannot tell a real squad
  from a well-formed WRONG one — a substituted roster is plausibly sized, so it used to overwrite
  last-known-good on the first request, i.e. the fallback destroyed itself exactly when needed.
  `rosterCacheRefreshDecision` now requires a new payload to retain **≥`ROSTER_CONTINUITY_MIN` (50%)**
  of the cached squad's normalized names before it may REPLACE the cache. Measured baseline: normal
  week-to-week churn ≥90%, cross-sport contamination ~0% — 50% sits in that empty middle. It gates the
  **write only**: the live payload is still served honestly either way (refusing to serve on a
  heuristic risks hiding a real roster), and a refusal emits `rosterContinuityRefused`, which **pages**.
  🔓 **Escape hatch** — if the CACHED copy is ever the bad one, a refusal would block healing: it
  self-expires at the 90d TTL, or force a re-bootstrap with
  `wrangler kv key delete --binding FEED_TAGS "roster:{espnTeamId}" --remote`.
- **⚠️ The engine/KHG path used to bypass all of this.** `bracket-engine.fetchRoster` hit ESPN raw, so
  Bracket pools and Know Her Game eligibility had NO fallback. Live-proven 2026-07-30: ESPN served
  Portland as 1 athlete and `/knowher/eligible?team=POR` returned **0** — a KHG edition generated that
  day would have shipped 15 teams, the same failure that dropped Orlando at W31. Both now call
  **`fetchRosterResilient(env, teamId, abbr)`**, which reuses the SAME `roster:{id}` record (no second
  cache, no extra ESPN traffic) and touches KV only when the live squad is implausible — the 5-minute
  bracket tick has a 50-subrequest budget. It also swallows a per-team fetch failure that previously
  rejected the whole `Promise.all` and emptied the entire pool. Diags: `rosterEngineFallback` /
  `rosterEngineFetchFail` / `rosterEngineSmallNoCache` (⚠️ these use bracket-engine's module-local
  emitter → `diag:` prefix, which the pager deliberately does not scan; the paging signal for the same
  event is `rosterContinuityRefused` / the nightly verification gate).
- **🛡️ Nightly roster verification (`src/roster-truth.ts`, 2026-07-31).** Cron `0 8 * * *` compares
  all 16 ESPN rosters against the league's own SDP feed and writes a report. **OBSERVE ONLY — it
  changes nothing users see.** Verification runs at BUILD time by design: no user request ever waits
  on a cross-check, and a cross-check can never be why a roster fails to load. SDP unreachable ⇒ the
  run records less; nothing degrades.
  - **Gate A — team identity:** 16 clubs, ESPN's set == SDP's (ESPN briefly deleted Orlando 2026-07-27).
  - **Gate B — shape:** size 16–34, GK 1–4 (**WAS legitimately carries 4**; the Spirit's bad "5" is the
    floor of implausible), no duplicate ESPN jerseys.
  - **Gate C — continuity:** ESPN↔SDP name overlap ≥80% (measured normal 93–100%; contamination ~0%)
    and ≥50% of last night's ESPN squad still present. **The only detector for a plausible squad of
    the wrong humans** — 24 players from another sport passes every size/shape check.
  - **Gate D — per-player diffs (never a gate failure, never pages):** position mismatches (Rodman
    class) · missing jerseys (Sentnor) · ESPN-only additions (Ngock/Bethi — new-signing lane, NEVER
    removed) · **SDP-only-with-minutes = the ESPN-ERASURE signal** (Fuller/Heaps/Spaanstra) ·
    likely name variances.
  - ⚠️ **Two join traps, both cost a wrong first run — do not reintroduce.** (1) A player collides
    with HERSELF when two of her own name forms normalize alike (Temwa Chawinga's shortName IS her
    full name; Lorena's shortName and shirtName are both "Lorena"). Only a collision between two
    different `guid`s is ambiguous. (2) One person spelled differently on each side was counted
    TWICE — as an addition and as an erasure. `pairNameVariances` pairs leftovers **by shirt number**
    (unique within a squad); it pairs every known variance and mis-pairs none, because a genuinely
    erased player has no same-numbered ESPN counterpart. A numberless signing (Bethi) can't be paired
    away. Together these took a live run from 66 bogus "erasures" to 8 variances + 29 erasures (22 =
    Portland's real collapse) + 4 real signings.
  - **KV:** `sdp-squads-v1` (league snapshot, 30d TTL = kill switch) · `roster-truth-report-v1`
    (report + per-club ESPN names for the next night's continuity) · `sdp-season-v1` (7d; saves two
    setup fetches) · `roster-truth:overrides`.
  - ⚠️ **Subrequest budget is the governing constraint** (~39 of the free plan's 50; KV ops count).
    Hence **no retries** (a failed club is `verified:false`, skipped not judged) and **one batched
    diag write** (`emitDiagBatch`). Adding a retry or a per-finding put will silently break runs.
  - **Diags:** `rosterTruthGateFail` + `rosterTruthRunFail` **page**; `rosterTruthSummary` never does.
    Severity scales with blast radius for free — one club is 1–2 events (under the 8-event threshold),
    a contamination or deleted club fails many gates in one batch and crosses it.
- **🛑 Serving from verified state (tweak 2, owner-approved + shipped 2026-07-31).** Two distrust
  signals can DEMOTE a plausibly-sized live payload to the trusted last-known-good copy (honest
  "Roster as of" marker) — closing the "paged but still on screen" gap:
  1. **Real-time — continuity refusal now changes what is SERVED**, not just what is cached: a live
     payload sharing <50% of its players with the trusted copy serves the trusted copy instead.
     Before, contamination was refused the cache but still shown to users until it healed.
  2. **Nightly — the verdict hold**: `runRosterTruth` writes `roster-truth-verdicts-v1`
     (`{at, clubs:{[espnTeamId]:{abbr, ok}}}`, **48h TTL = kill switch**); `/roster` holds a club
     whose last verification FAILED on its last-known-good until it passes. Only the broken club
     goes stale (≤ ~24h — owner accepted this over serving wrong data); the other 15 stay live.
  Pure decision = `goodPathPlan` (index.ts, unit-tested). **Fail-open by construction:** no cache,
  no verdict key, expired verdicts, or a KV error ⇒ the old live-first behavior exactly; an
  UNVERIFIED club (fetch blip during the run) is marked ok — unverified ≠ failed, so a blip can
  never hold a club stale. The cache is never refreshed from a payload either signal distrusts,
  and a no-cache + distrusted payload serves live but is NOT archived (never seed the fallback with
  suspect data). Diag: `rosterVerdictHold` (deliberately not paged — the nightly gate failure that
  caused it already did). ⚠️ Residual gap, documented not hidden: a 50–80%-overlap partial
  substitution passes the real-time check and is only caught (and held) after the next nightly run.
- **🔧 Owner overrides (`roster-truth:overrides`, 90-day TTL).** Applied in `/roster` to whatever is
  served (live or cached), AFTER the cache write — so the stored last-known-good stays raw ESPN and an
  override is a presentation-time correction, never baked into the archive. Marks the athlete
  `proxyOverridden: true` (inert; Swift ignores unknown keys).
  **Deliberately narrow: it can only correct `position`/`jersey` on a player ESPN already lists — it
  can never add or remove anyone**, so a stale ruling can't make a real player vanish.
  **Why they expire:** a permanent pin becomes an invisible lie the day the fact genuinely changes
  (Rodman really could convert to midfield). Expiry is safe *because* the nightly verifier keeps
  running — a lapsed ruling means the mismatch simply reappears in the next report. Entries are kept
  past expiry (1y TTL) so the portal can still show and renew them; a vanished row would hide the
  regression. Neither feed may auto-win a position disagreement (SDP right on Rodman/Girelli/Sanchez,
  **ESPN right on Sonis**) — the machine reports, the owner rules.
- **🤖 Weekly auto-adjudication (shipped 2026-07-31, proxy #66).** A Claude cloud routine (Mondays
  12:00 UTC, `trig_01TDf4WZRsRT2MnFfczvqtXV`, model set in the TRIGGER RECORD per the KHG lesson)
  reads `GET /roster-truth/todo` (open position/jersey mismatches), checks each player on **her
  club's own roster site** (⚠️ Wikipedia = fallback ONLY — it carries CAREER position and says
  "forward" for Janine Sonis, whom her club lists Defender; check married/maiden name forms:
  Sonis=Beckie, Cronin=Monaghan, Heaps=Horan), and posts cited rulings to
  `POST /roster-truth/rulings`. Auth = dedicated `ROSTER_ADJUDICATE_KEY` (blast radius = this one
  feature). Hard rules SERVER-side in `applyAutoRulings`, never trusted to the prompt: no source
  URL → rejected · an owner pin is NEVER overwritten (auto replaces only auto/expired) · positions
  + jerseys only (membership structurally untouchable) · declining = not posting (free). Auto pins
  show in `/admin` with an `auto` pill + clickable source, expire in 90d, and an expired ruling
  puts the item back on the todo (self-closing loop). Script: `scripts/roster-adjudicate-routine.md`
  (the key lives only in the trigger config, never the repo).
  ⚠️ **THE TRANSFER RULE (added after the first live run).** A mismatch needs the two feeds to
  DISAGREE — so when both are stale *together* nothing is flagged. That happens on a specific,
  predictable cohort: a transfer moves a player's NUMBER and her ROLE at the same moment (new number
  if the old is taken; new coach may play her differently) and neither feed re-keys her.
  **A blank ESPN jersey is the free signal that marks it** — a missing number is what a
  half-processed arrival looks like. So the routine reads BOTH number and position for anyone on the
  `jerseys` list and rules on position even though the todo didn't ask (~3 players league-wide).
  Proven case: Ally Sentnor, KC→Angel City July 2026 — ESPN blank, league feed her old #21, both
  feeds "Forward"; angelcity.com said **"midfielder #17"**, right on both counts.
- **🗂️ One admin portal: `GET /admin`** (`src/admin-portal.ts`) — one URL, one password, three tabs
  (Roster · The Bracket · Know Her Game), same HTTP Basic realm so the browser authenticates once for
  the origin. Ops at `POST /admin/roster` (`state` / `run` / `setOverride` / `renewOverride` /
  `removeOverride`); every op returns the same `{report, overrides, ttlDays}` shape so the page
  re-renders from the response instead of keeping client state that can drift from KV.
  ⚠️ **The Bracket + KHG tabs are IFRAMED, not rewritten** — both are complete working documents and
  one drives a live game; their own URLs still work, so the shell is additive and reversible.
- **Know Her Game club completeness:** a published edition must cover **all 16 clubs**
  (`KNOWN_CLUB_ABBRS` in `src/knowher.ts`, twinned in `scripts/load_knowher.mjs`). Both validators
  checked for DUPLICATE clubs but never for MISSING ones — which is why W31 shipped 15 teams silently.
  Opt-in via `validateKnowHerPool(raw, { requireAllClubs: true })` so the admin `upsertPlayer` op can
  keep validating a legitimately-incomplete ONE-player frame. Expansion = update both constants.
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
  club OG news + club IG), `/feed` (Feed: Bluesky reporters/clubs + news RSS + player IG), `/spotlight`
  (app-side retired for Know Her Game — the proxy route + its Haiku builder are retained but currently unused),
  `/trivia` (KV pool), `/quiz-results` (community splits for BOTH quiz games — **always revealed since
  2026-07-23**: Trivia's biweekly round keys ("2026-R08") retired the old wait-for-the-day-to-close rule,
  so both games serve KHG's live model — counts grow from the first responder, `%` at N≥25; every edition
  now serves at the 15-min live TTL, since an edition's end of life is the retention cron, not a
  serve-time rule), `/national-teams` (data-driven NT Browse-all, deduped by FIFA, 24h), `/telemetry`
  (POST sink → KV), `/analytics` (POST sink, 2026-07-17: ANONYMOUS Level-3 usage counters — whitelisted
  `{event,param,n}` batches, one per app session, NO IDs/IP → `increment_counters` RPC → Supabase
  `analytics_counters` daily rollups; unknown event names dropped; RPC failure emits `analyticsRpcFail`).
  **Ops alerting (2026-07-17):** the `*/5` cron also runs an error-spike check over recent `diag:` keys
  (age from the reverse-time KEY = zero reads on quiet ticks) → **Resend** email at ≥8 error events/15min,
  1/hr throttle (`RESEND_API_KEY`+`ALERT_EMAIL` secrets; unset = no-op). **Excludes `apiFailure` events whose
  detail starts with `image fetch ` from the count** (expected IG-CDN/thumbnail flakiness — honest
  placeholder fallback, not an incident; still visible in `/telemetry/recent` + in-app Diagnostics, just
  doesn't page). The WATCHER pings a
  **healthchecks.io** check per tick (`HEALTHCHECK_URL` secret) so a dead cron gets reported by an
  outside observer; app-side **MetricKit** crash/hang payloads land as `metricKitDiagnostic` crumbs in
  this same telemetry sink (device-only delivery). Server-side Haiku (`claude-haiku-4-5`, KV-cached) gates relevance + team-tags the
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
follows. **Follows sync = UPWARD-ONLY (2026-07-23).** The DEVICE is the source of truth and Supabase is backend
bookkeeping the user never hears about: there is **no restore-down at all**. Signing in never rewrites
local follows, never completes onboarding, and never changes what's on screen.

*Why the previous restore-down was deleted:* it existed so a returning user could skip onboarding — worth
little (16 clubs, seconds to re-pick) — and it assumed "a signed-in user IS a returning user (onboarding
precedes sign-in)". The Tier-2 alert-bell intercept made that false: signing in MID-onboarding hijacked
the picker, jumped to Home, and (because `hasOnboarded` was still false) overwrote the clubs already
tapped. What sign-in restores now is **game progress**, not follows (`fanzone_progress` — see
`docs/fan-zone.md` §5).

The decision is a pure, unit-tested function, `FollowSyncCoordinator.resolveFollowOps(local:remote:hasOnboarded:)`:
- `hasOnboarded == false` (picker on screen, or a fresh/wiped install) → **add local-only rows, delete
  NOTHING.** A partial set the user is still building must never look authoritative — pruning against it
  is exactly the "only the oldest follow survives" data-loss bug.
- `hasOnboarded == true` → the device is authoritative **both ways**: adds AND deletes, so
  follow-16-then-unfollow-back-to-2 leaves the server holding 2.

It runs on sign-in and once more when onboarding completes while signed in (via the
`FollowingStore.onOnboardingCompleted` hook — the same optional-callback pattern as `onFollowsChanged`,
so the store stays dependency-free). Live toggles still mirror through `handleLocalChange`
(add/remove per change). The root gate is now simply `hasOnboarded` — the "Restoring…" state is gone,
because with no restore there is no race to wait on. Coordinators: `FollowSyncCoordinator`
(+ competition follows, same rule), `ProgressSyncCoordinator` (game progress),
`TeamAlertSyncCoordinator` (alerts keep their own mirror; alerts ⊆ follows).
**Trade-off (unchanged):** an unfollow made signed-out/offline never reaches the server; it now simply
sits as a stale row until the next signed-in toggle corrects it, instead of reappearing in the UI.
Trade-off: two devices on one account diverging offline → last writer wins (acceptable at current scale;
upgrade to per-item `updated_at` last-write-wins if heavy multi-device curation appears). Schema at
`supabase/schema.sql`. **Gotcha:** RLS alone isn't enough — a new per-user table needs
`grant … to authenticated` or signed-in queries silently fail with `42501`. **Fan Zone scores (v2,
applied 2026-07-22):** `superfan_scores` (`migration_superfan_scores.sql`, PK `(user_id, season)`) holds
each fan's cross-game season total + `games_played` (the ≥2-game qualifier for the client-computed
tier/percentile); world-readable `select` (`grant … to anon, authenticated`) so the rank is browsable,
own-row `insert`/`update` only — the app (`SuperfanService`) reads/writes it DIRECTLY with **no
proxy/service_role path** (contrast the watcher/proxy tables above, no Postgres function). Client built
from gitignored `Secrets` (`Services/SupabaseManager.swift`).

**Fan Zone v3 tables (applied 2026-07-23)** — full system doc: `docs/fan-zone.md`.
- **`fanzone_progress`** (`migration_fanzone_progress.sql`, PK `(user_id, season)`) — the game-progress
  SUMMARY row that makes a reinstall / replacement phone non-destructive. Owner-only RLS both ways (no
  anon read, no service_role — progress is personal). Deliberately a summary, NOT history: `quiz_answers`
  are pruned, so restore must not depend on them. ~150 B/row ⇒ ~20 MB at 100k users. Written by per-game
  PARTIAL upserts (PostgREST merge-duplicates touches only supplied columns, so Trivia can't clobber KHG);
  read + merged once at sign-in by `ProgressSyncCoordinator`.
- **`predict_round_scores`** (`migration_predict_round_scores.sql`, PK `(user_id, team_abbreviation,
  season, week)`) — the comp arena's ROUND clock: one row per club per soccer week (a 2-game week sums
  into one round). Same public-read / own-row-write model and non-decreasing clamp as `prediction_scores`,
  which keeps the season totals. `week` is CALENDAR-derived (`FanZoneCadence.soccerWeek`) on purpose —
  it's a primary key, and counting only fixture weeks would renumber banked rows when a match is postponed.
- **`bracket_user_edition_stats` + `final_rank`/`field_size`** (`migration_bracket_final_rank.sql`) —
  stamped by the engine at edition close so "Finished #12 of 340" survives forever. Same migration adds
  `grant select, delete on bracket_votes to service_role` — the prune is a NEW operation and the grant
  must match the operation (the 42501 gotcha).
- **Retention (`migration_retention_cron.sql`)** — pg_cron daily deletes: `quiz_answers` > 35 days,
  `predict_round_scores` > 28 days (the owner's current-round + previous-round rule; 2-week rounds ⇒ ≤4
  weeks of life). Runs INSIDE Postgres: Cloudflare requests are the metered resource, Supabase API calls
  are unlimited, a database cron uses neither. Age-based rather than round-math so no anchor arithmetic is
  duplicated into SQL and a key-format change can't break it (it also swept the legacy day-keyed Trivia
  editions for free). **Bracket votes are the exception** — pruned by the engine at the NEXT edition's START
  (`pruneCompletedEditionVotes` in `writeEdition`, not at close), so a finished edition stays fully
  browsable round-by-round through the between-editions review window (owner rule 2026-07-24); an edition's
  lifetime isn't calendar-shaped. The record book (`*_scores`, `*_stats`, `fanzone_progress`)
  is never pruned: one tiny row per user.

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
so goal/HT/FT latency is ~30 s (shipped 2026-07-11). **Fixture-window polling (2026-07-16,
`src/fixtures.ts`):** the tick no longer fetches every feed every minute — a ~6h discovery sweep builds
a KV fixture index and the tick polls ONLY feeds with a fixture in `[KO−75m … KO+4h]` (closed at
observed FT; zero fixtures near ⇒ zero proxy fetches; was 16 feeds/min ≈ 23k invocations/day at zero
users). A partial sweep never replaces a good index; a live match discovery didn't know logs a
`DIAG missed-window` line. App-side twin: NT scoreboard fan-out is **confederation-scoped**
(`ConfederationMap.swift` — ZAM polls ~7 feeds not 15). Full system doc: `docs/national-teams.md`. **Clock:** the widget self-advances the minute
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
opt-in; Tier-2 toggles are sign-in-gated (`tier2Binding`) and **display-gated on auth** (2026-07-16
involuntary-sign-out fix: stored intent is PRESERVED across sign-out and reads OFF while signed out —
restored exactly on re-sign-in; `resetServerPushTypes` survives only in account-delete teardown; an
involuntary sign-out with intent stored auto-presents the sign-in sheet + emits `tier2SignedOutDesync`).
The watcher gates each V1 event on its per-event column (`tokensForEvent`) and V2 on `live_activities_enabled`.
