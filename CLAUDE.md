# NWSLApp — Project Context for Claude

A one-page cheat sheet of rules/conventions/commands/gotchas for every session. Detailed and
feature-specific context lives in `docs/` + `.claude/rules/` and loads **on demand** (see
**Deeper context** at the bottom) — keep this file lean.

## ⚠️ What this app is — read first

A women's soccer (NWSL) **fandom** app: follow your clubs, keep up with soccer voices (reporters,
club + player social), play/share Fan Zone games (Bracket Battle, Predict the XI, Know Her Game, NWSL Trivia),
and check scores/schedule/standings. The **fandom** — community, the games, social sharing,
live/"alive" content, personal connection — **is the product.** Scores/schedule/standings are
table stakes that must work but are **not** the differentiator.

- **Anti-pattern (matters):** don't shrink the fandom side into a stats-app (ESPN/March-Madness)
  mold. When a design emphasizes fandom/social/playful content, **build it that way** — don't trim it.
- **Litmus test:** "Would I open this today if I opened it yesterday?" A surface that looks identical
  because the data is static is a bug — the app is built to feel alive.
- **Priority order:** (1) **ALIVE** features (live content pipelines + fan engagement) → (2) **core**
  (scores/schedule/standings/stats — must work, not the differentiator) → (3) **hardening**
  (bugs/tests/robustness). Never put 3 above 1.
- **Owner:** Tiffany Rieth. Personal project → production-quality iOS skills + a real App Store app.
- **Sizing calibration (not enterprise, not toy):** solo indie dev, **free** app, **tip-jar-only**
  revenue. Size for **~1k active users at launch** (mandatory — a few hundred one-team fans enabling
  alerts must all get pushes) and architect for **100k over years**. Fixed monthly cost that triggers
  at small scale is disqualifying; prefer flat tiers over metered billing. Full method + the two
  stress tests (1k mandatory / 100k headroom) in **`docs/stress-testing.md`** — read before any
  scaling/sizing/publish-readiness work.
  **⚠️ THE BANNED LENS:** never reason from CURRENT usage ("only 2 users → plenty of headroom /
  that can wait until launch") — every load/reliability question is asked **as if the app ships
  tomorrow** (hundreds of one-club fans from one subreddit post). It produced the APNs 50-device
  near-miss AND two wrong calls on 2026-07-16 (watcher polling burned 23% of the request cap at
  zero users; error alerting misjudged as deferrable). Defer only when the 1k test PASSES or the
  lever is a flip-anytime config — never because today's traffic is small (stress-testing.md §0).
- **Privacy/monetization stance (owner, 2026-07-16 — values vs mechanics):** VALUES are promises —
  no ads, no data sold, no third-party/cross-app tracking, no dark patterns. MECHANICS stay flexible —
  say "free, tip-supported," never vow "free forever"/"no paywalls ever" (Swift Alert precedent), and
  anonymous FIRST-PARTY aggregate usage/diagnostics counters are ALLOWED (target App Store label: Data
  Not Linked to You; the Diagnostics spine already ships this way). Don't write absolutist product
  vows into public copy or docs; don't read the old "no tracking" line as banning anonymous counters.

## State

Production-quality **v0.4.4**, used daily. **Online-only: NO demo/seed/fake data in the running app**
— every surface shows live data or an honest "Couldn't load — tap to retry" (seed/fixtures live only
in previews + tests). Treat it as a real product; never suggest a demo/placeholder mode.

## Stack

Swift 5.9+ / SwiftUI (not UIKit), min iOS 17.2 (`@Observable`; 17.2 = Live Activity push-to-start), Xcode 27.0 beta 2. `URLSession` + async/await,
no third-party HTTP. UserDefaults (small local state) + **Supabase** (Postgres, durable per-user once
signed in); SwiftData nowhere. Sign in with Apple → Supabase (Apple auth + RLS). The **only**
third-party dep is `supabase-swift` (SPM) — a deliberate minimal-dependency stance, but a PREFERENCE to
weigh, not an absolute (revisit on merits if a feature genuinely justifies one). The 2026-07-09 push
fan-out review weighed + DECLINED Firebase and the chosen fix (Cloudflare Queues + APNs Broadcast
Channels) adds **no** app dependency, so the line stays true. Testing = **Swift Testing** (`@Test`/`#expect`), not XCTest.
Secrets in gitignored `Config/Secrets.swift` (anon key is public — RLS is the real boundary).

## Commands

```bash
# Build (Debug) for a booted simulator
xcodebuild build -scheme NWSLApp -destination 'platform=iOS Simulator,id=<SIM_ID>' -configuration Debug
# Unit tests
xcodebuild test -scheme NWSLApp -destination 'platform=iOS Simulator,id=<SIM_ID>' -only-testing:NWSLAppTests
xcrun simctl list devices booted                                   # find the booted sim id
xcrun simctl install <SIM_ID> <NWSLApp.app>
xcrun simctl launch  <SIM_ID> com.tiffanyrieth.nwslapp.NWSLApp
```
DEBUG args: `-resetOnboarding`, `-useESPNDirect`, `-startTab <home|schedule|standings|teams|feed>`,
`-debugOpenMatch <espnEventID>` (deep-links a match detail tap-free — for in-sim verification; Xcode 27 killed idb HID).
Decode-only tests read `NWSLAppTests/Fixtures/*.json` via `#filePath`. **Driving the sim:** `idb` is
installed — start `idb_companion --udid <SIM>`, then `idb ui tap <x> <y>` (DEVICE points) + `idb ui
describe-all` (element frames + a11y labels — exact for locating/measuring UI) are the reliable way to
tap SwiftUI and verify layout. cliclick is fine for SCROLL drags + UIKit hit targets, but its synthetic
clicks get SWALLOWED by SwiftUI buttons inside a nested horizontal-scroll (e.g. a chip in the pinned
Club News header) — don't trust it there. DEBUG deep-link/launch-arg scaffolds remain a fallback.

## Architecture (MVVM, strict separation)

`Models/` (Codable, no UI/net) · `Services/` (API clients, no UI) · `ViewModels/` (`@Observable`,
state-enum `idle`/`loading`/`loaded`/`error`) · `Stores/` (`@Observable` shared state → UserDefaults,
injected via `.environment`, one-fetch-many-readers) · `Views/` (one screen per file, minimal logic) ·
`Components/` (reusable) · `DesignSystem/` (`DSColor`/`DSMetrics`/`DSText` tokens, dark-only). Prefer
`@Observable` over `ObservableObject`. Folders are created when their first real file lands.
**`Packages/`** (repo root, outside every target's synced folder) — local SPM packages that make key
seams **compiler-enforced** (risk-driven: isolate fragile/high-blast-radius code, not what's easiest):
`LiveActivityContract` (the app↔widget ActivityKit data contract, linked by both targets) +
`MatchClockKit` (live-clock engine + the consolidated display guard). ActivityKit code needs `#if
os(iOS)` (unavailable off-iOS breaks host indexing). Add more only when a seam earns it.

## Data sources (essentials — full detail in `docs/backend.md`)

ESPN's unofficial NWSL endpoints (base in `Config/AppConfig.swift`) — **decode defensively**: scores
are `String` not `Int`, scoreboard needs `&limit=500` for a full season **but the full-season `dates=`
query serves live state 25–47 min STALE mid-game** (ESPN-side cache — the app's whole-game "stuck clock",
2026-07-11; windowed/default queries stay fresh, `_cb` forces ESPN to recompute → the proxy busts the ESPN
upstream on every `/scoreboard` MISS, and the app's live poll rides the windowed query), standings sit on a different
base, endpoints break/rate-limit without notice, and **`status.clock` FREEZES at 45:00/90:00 through
stoppage time** — any live clock must anchor MONOTONICALLY (re-anchor only when the clock advances or
the period changes; naive `now − clock` re-anchoring pins the display at +1'/snaps the widget to 45:00).
ESPN also keeps `state=="in"` THROUGH halftime (clock frozen, `description`/shortDetail says "Halftime"/"HT")
**and advances `period` to 2 at the START of the break** (so a period change alone ≠ the second-half
restart — the watcher's widget-clock anchor reconciles only while `clockRunning`, else the ~15-min break
leaked into the clock and the second half read 1:01+), and flips a match "live" ~5–10 min LATE with the
clock reset — so surfaces show a STATIC "HT" (never a
ticking clock) when `Event.isHalftime`, and a first sighting already at the 45:00/90:00 cap is UNKNOWABLE
(don't fabricate +1' — defer to ESPN's string; anchors persist to UserDefaults so a relaunch doesn't reset
the stoppage count). The **watcher** fetches only a yesterday→tomorrow scoreboard window (not the full
season) so a per-minute cron tick isn't parsing ~240 events (CPU), and (2026-07-16) polls on a
**FIXTURE WINDOW** (`src/fixtures.ts`): a ~6h discovery sweep indexes kickoffs in KV; the tick fetches
ONLY feeds with a fixture in [KO−75m…KO+4h] (zero fixtures near ⇒ ZERO fetches — the old 16-feeds-every-
minute burned ~23k proxy invocations/day at zero users, ~23% of the Workers-free 100k/day request cap;
NOTE a proxy cache HIT still counts as a Worker request). App-side twin: the NT scoreboard fan-out is
**CONFEDERATION-SCOPED** (`ConfederationMap.swift` — ZAM polls ~7 feeds not 15; unmapped code fails OPEN
to all + diag; system doc `docs/national-teams.md`). Most traffic routes through the **`nwslapp-proxy`
Cloudflare Worker** (sibling repo `~/Projects/nwslapp-proxy`); DEBUG `-useESPNDirect` bypasses it.
**Roster** routes through the proxy's `/roster` too (last-known-good KV: ESPN intermittently serves an
implausibly small squad — e.g. 1 player — so the proxy caches a plausible roster and serves it with a
`proxyCachedAsOf` marker → app shows a "Roster as of …" note; teams/standings still hit ESPN directly).
**Kickoff weather** routes through the proxy's `/weather?event={id}` too — a PAST match's kickoff-hour
temperature + sky condition from **Open-Meteo** (free, no key; ESPN carries NO NWSL weather). Keyed by a
static **ESPN-venue-id**→lat/lon table (id-keyed so a rename can't silently break it), the exact kickoff
HOUR (not the daily high), **cached write-once in KV** (a finished match's weather is immutable → lazy
backfill covers all history, no cron/watcher); night-aware via `is_day` (sun/moon icon). PAST-ONLY;
envelope versioned for a later forecast mode. Shows as a quiet stamp under the MatchDetail header.
**Tier-2 server push** (live match alerts) is a SECOND sibling Worker, **`nwslapp-match-watcher`**
(`~/Projects/nwslapp-match-watcher`): a `* * * * *` cron that diffs the proxy scoreboard (reached via a
**service binding** — same-account Worker→Worker over `*.workers.dev` 404s with CF **error 1042**, so a
public fetch silently fails) for
kickoff/goal/halftime/full-time + **lineup-posted** (polls `/summary` in a 75-min pre-kickoff window) +
**RED CARD** (reds ONLY — yellows are per-game noise; keys on ESPN's explicit `redCard` boolean on the
scoreboard `details` entry, NEVER text; rides the **`goals`** pref column = zero schema change, precedent
= VAR corrections; per-side `StoredState.redCards` fire-once ledger, a pre-existing KV row baselines
rather than late-firing) +
**VAR goal-correction** (a debounced score *decrease* — re-poll a
cache-busted scoreboard before firing, so an ESPN glitch never sends a false "Goal Disallowed"), looks
up `device_tokens` of users with that alert on, and sends APNs (ES256 `.p8` JWT). **Delivery (SHIPPED
2026-07-09, `docs/push-fanout-scaling.md`): V1 buzz + Live Activity push-to-start fan out via Cloudflare
Queues** (cron enqueues chunked tokens → a consumer drains each batch with its own fresh subrequest
budget → no launch-scale cap; `apns-collapse-id` dedupes); **V2 in-match Live Activity updates ride APNs
Broadcast Channels** (channel-per-match, one POST/event, iOS 18+; iOS 17 = V1-only). **V1 push shape (copy v4, 2026-07-07 — device-tested): title = subject-first with a
COLON (`GOAL: Seattle Reign FC`, never an em-dash), subtitle = scan-ordered detail — goal = SCORER
first then scoreboard (`S. Menti 19' · NC 0–1 SEA`); red card = minute-first player, NO scoreline
(`23' E. Wheeler`); halftime + full-time = scoreline ONLY (no last-scorer at HT, no "…win" tail at FT).
Caps only on GOAL/NO GOAL. NO body; a square crest TILE attaches **ONLY to a GOAL (scorer's club) or
RED CARD (carded club)** — kickoff/lineup/halftime/full-time + VAR corrections are **NEUTRAL (no image,
no `mutable-content`)**: a single crest misreads for the OTHER team's fans (owner rule 2026-07-10; the
away-team "Lineups in" showed the HOME crest). The tile comes from the THIRD sibling Worker
`nwslapp-card`** (`/thumb/{ABBR}`, team-color wash, crest
overscanned past the source PNGs' 41px baked-in border; same repo as the watcher, own
`wrangler.card.jsonc`). The card/thumb renderer lives in that separate fetch-only worker because
satori+resvg (~3.4MB) in the CRON's module graph blew the cold-start CPU budget (Exceeded CPU kills on
idle ticks; lazy `import()` is impossible — Workers forbids runtime WASM instantiation). The watcher
302s `/card/*` → nwslapp-card permanently (APNs can deliver stored pushes hours late). Deployed;
`POST /test-push` (`x-trigger-secret`) sends a synthetic push for
on-device E2E (`APNS_HOST` is production — ⚠️ a USB/Xcode DEBUG build registers a SANDBOX token → prod
gateway 400 `BadDeviceToken`; the test endpoints take an optional `sandbox:true` → `testApnsConfig`
routes THAT call to the sandbox host WITHOUT flipping the global host, which would make the cron prune
real prod tokens. `/replay-tick` + `scripts/replay-realtime.mjs` push a synthetic ESPN scoreboard
through the REAL pipeline for on-device V1/V2 tests). A **V2 Live Activity** layer (lock-screen + Dynamic
Island live score) rides the SAME watcher + `.p8`, ADDITIVE to V1 — but the roles split: **V1 is the
interrupt (buzzes kickoff/goal/HT/FT per the user's toggles); V2 is a QUIET glance.** V2 content-state
carries **per-side scorers** (`homeScorers`/`awayScorers`, capped 4 +N) + `homeRedCards`/`awayRedCards`
(all additive-optional — old app builds ignore unknown keys) → the card stacks each team's scorers under
its crest + a red-card rect. ⚠️ The V2 widget clock is Apple's **mm:ss** during regular play (deliberate —
`showsHours:false` so it reads `68:12` not `1:08`; the football-minute `45'+2'` clock is **IN-APP ONLY**,
`MatchClock`, Match Detail / Schedule cards). **EXCEPTION (build 26): in ADDED TIME the widget shows the
football stoppage `90'+2'`** — the watcher broadcasts a `stoppageDisplay` string each minute (cheap via
Broadcast Channels; the "never push per-minute" rule yields for stoppage only). Don't mistake the widget's
mm:ss for a regression. The watcher **30s-double-polls** live windows (goal/HT/FT latency ~30s) and
resyncs the widget clock the instant the anchor jumps ≥30s (each half's late live-flip). ⚠️ Gotcha (device-proven 2026-07-04,
contradicts Apple's docs): the push-to-start **`alert` is REQUIRED to render** — omit it and APNs 200s but
iOS NEVER presents the card. ⚠️ **START-PAYLOAD LAW (device-proven 2026-07-11 — THE §0 of
`docs/live-activity-v2.md`; read it before touching any V2 payload).** TWO INDEPENDENT things, never
conflate them (doing so cost weeks): **(1) RENDER** needs BOTH an `alert` object AND the payload wrapped
in `{ aps: {…} }` on the wire (`buildStartAps` returns the CONTENTS — the sender must wrap; the 7/9 Queues
redesign stored it UNWRAPPED in `enqueueLaStart`, so every queued start went out with no `aps` envelope →
APNs `1 sent` but iOS silently dropped it → the 7/10 total no-show on three real games; fixed by
`payload: { aps: buildStartAps(...) }`). **(2) BUZZ** is purely the `sound`: `"default"` = one arrival
buzz (SHIPPED), `""` = renders but SILENT. The old "`sound:""` is flaky / never presents" claim was
**WRONG — that was the missing envelope, not the sound.** 🔒 **CHANGE-RULE:** NEVER change the start
payload's envelope/alert/sound on Apple-docs or theory — only a REAL-DEVICE test (real game OR the
**fake-match harness** `POST /debug/fake-match`, watcher) counts; `1 sent` ≠ rendered. Also: iOS shows a one-time per-app "Allow Live Activities?" prompt with the
app's FIRST presented Activity (a reinstall resets it). Push-to-
start fires **≤20 min pre-kickoff** (a device can take minutes to register its per-Activity token) + a
catch-up push for late tokens. `POST /test-activity` + `scripts/replay.mjs` drive it; app `LiveActivityManager`
mirrors push-to-start/per-Activity tokens under a UIKit background-task assertion (background-launch upload);
detail in `docs/backend.md`. The app side: `registerForRemoteNotifications` → AppDelegate →
`PushBridge` → `DeviceTokenService` upserts `device_tokens` (per-team toggles in `team_alert_preferences`).
**Register on EVERY open (canonical Apple pattern — NOT gated on a toggle):** `registerForRemoteNotifications`
fires on cold launch + every foreground (`scenePhase .active`); a signed-in user whose iOS permission was
reset (reinstall) but who has any alert on is auto-re-prompted then registered (denied → honest surface, never
a silent "alerts on but no token"). The OLD gate — register only if already `.authorized`, permission requested
only by a bell toggle — left opt-in/reinstalled users with an EMPTY `device_tokens` (no token ⇒ no pushes at
all). Upsert is guarded (writes only on token change); `didFailToRegister` → Diagnostics (never a bare print).
**Token lifecycle = PER-DEVICE, replace-not-accumulate:** every APNs token table (`device_tokens`,
`live_activity_start_tokens`) keys on **`(user_id, device_id)`**, `device_id` = a Keychain-stable per-device
UUID (`DeviceIdentity.swift`, survives reinstall). So each device keeps ONE current token (a rotation
replaces it in place; the same user on two devices = two rows), instead of piling up a dead token per
reinstall/rotation. The watcher ALSO self-prunes — a send returning `410 Unregistered`/`400 BadDeviceToken`
deletes that token (`pruneDeadTokens`). This accumulation of zombie tokens (the old `(user_id, token)`
keying) was the V2 Live-Activity "delivered-but-never-renders" bug; per-device + prune fixed it (build 23).
**Notifications = OPT-IN (owner rule — no dark patterns):** nothing auto-enables at onboarding/launch;
the user turns on exactly what they want. **Nuance (owner, match-alerts):** an EXPLICIT match-alert
bell tap IS the opt-in, so it CASCADES the full default bundle the first time (day-before + kickoff +
goals + halftime + full-time + lineups + Live Activities via `applyMatchAlertDefaultsIfFirstTime`) — a complete
feature makes the best first impression; a bell-on-nothing-fires state is the banned "silent failure
that looks like success." First-time only (a sentinel respects later manual edits; the sentinel resets
on account-delete only — since 2026-07-16 a plain sign-out PRESERVES prefs + this sentinel and restores
the exact prior toggles on re-sign-in, so no re-cascade).
Because the bundle is mostly Tier-2, a signed-out bell tap presents Sign in with Apple FIRST
(intercept: success → enable+cascade+toast, cancel → bell stays off). **Tier 1** = deliverable without
an account (local: day-before, Player Spotlight — ⚠️ iOS caps PENDING local notifications at 64/app:
day-before is WINDOWED to the next 2 fixtures per alerting team, never the whole season); **Tier 2** = watcher-triggered ⇒ needs an account ⇒
sign-in-gated (`tier2Binding` / the bell intercept) + **display-gated on auth** (involuntary-sign-out fix
2026-07-16: stored Tier-2 intent SURVIVES sign-out and merely READS off while signed out — exact prior
toggles restore on re-sign-in; `resetServerPushTypes` = account-delete teardown ONLY; a LAPSED session
with intent stored auto-presents the sign-in sheet app-wide + emits `tier2SignedOutDesync`, while a
DELIBERATE sign-out never nags — `SignOutSentinels`, `AuthStore.startAuthStateListener` +
`revalidateSession`; DEBUG repro `-simulateLostSession`). **Lineup-posted (Stage D, done):** the watcher polls
`/summary` (cache-busted via the proxy binding) in a 75-min pre-kickoff window and pushes "Lineups in" the tick
BOTH XIs are posted (≥11 starters/side; dedup = **retry-until-SENT**, two KV markers — `lineup-pub` latches
"XIs posted" to stop the /summary re-poll, `lineup:` marks fired only once ≥1 recipient is actually reached, so
a 0-recipient tick RETRIES next tick and logs the gate breakdown / SUSPICIOUS flag — the old mark-fired-at-0
silently dropped a real user's alert, 2026-07-18); the app shows the pre-match XI in `MatchDetailView`'s
future layout. UI groups kickoff+HT+FT under one "Match updates" toggle (grouping only — each still gates its
own column server-side). NEVER auto-enable a notification WITHOUT an explicit user
action. National-team alerts: bell keyed by FIFA code → `competition_alert_preferences` (separate from
the club-id `team_alert_preferences`); the watcher polls the women's-international competition feeds
(friendlies + confederation championships + WC/Olympic qualifying — the SAME slug set kept in sync across
app `NationalTeamFeed.all`, proxy `WOMENS_NT_FEEDS`+allowlist, and watcher `NT_LEAGUES`) + fans out by code.
⚠️ Display + alerts must stay aligned (the ESPN `all/teams/{id}/schedule` endpoint is HISTORY-only, so the
schedule's UPCOMING fixtures come only from these per-competition scoreboards — a new competition = add the
slug to all three lists AND tag its `scope` in `ConfederationMap.swift`; untagged defaults to global/polled-
for-everyone, fail-open). Full NT system doc: `docs/national-teams.md`.
Per-user state in **Supabase**, offline-first (UserDefaults cache). **Follows sync = RESTORE-ONLY launch
reconcile:** launch `reconcile` NEVER deletes a server row — a wiped/un-onboarded device restores the full
server set, and only local-only follows upload. **Unfollows propagate solely via the explicit per-toggle
`removeFollow`** (a signed-in unfollow), so no launch-time race can prune. (This replaced an earlier
device-authoritative mirror whose launch prune deleted rows under the reinstall onboarding race — the
"only the oldest follow survives" data-loss bug. A returning signed-in user is restored + skips onboarding;
`RootTabView` shows a brief "Restoring…" until reconcile resolves, never the picker.) **Trade-off:** a
signed-out/offline unfollow won't reach the server and reappears on reinstall — recoverable, and harmless
to alerts (alerts are a separate table + coordinator; follows ≠ alerts). Two devices diverging offline →
last writer wins (fine at current scale). **Gotcha (grants):** a new per-user table needs `grant … to
authenticated` or signed-in queries fail silently with `42501` (RLS ≠ privilege); **AND** any table a
**Worker reads/writes as `service_role`** — the watcher (`device_tokens`, `*_preferences`,
`team_alert_preferences`, `live_activity_*`) OR the proxy (`profiles`, for the SIWA `apple_refresh_token`)
— needs an explicit `grant … to service_role` too: default privileges don't cover it, and bypassing RLS
is NOT table privilege (this latent gap 42501'd the first real service_role read). The grant must match
the **operation**: the watcher's `pruneDeadTokens` DELETEs `device_tokens`, so a `select`-only grant
strands dead tokens — grant `select, delete`. And any secret the proxy signs into a JWT **raw** (SIWA
`APPLE_TEAM_ID`/`SIWA_KEY_ID`) must be whitespace-clean — a trailing newline signs a JWT Apple rejects
as `invalid_client`; set via **stdin, never copy-paste** (`printf '%s' … | wrangler secret put`).
**Know Her Game content = fully-automated BIWEEKLY (proxy):** a **Claude cloud Routine**
(claude.ai/code/routines, on the OWNER's subscription — $0 metered API) runs `scripts/knowher-weekly-
routine.md` overnight → assembles the Rodman-faithful prompt (`assemble_knowher_prompt.mjs`
from `/knowher/todo`) → generates the 16-player pool → `POST /knowher/ingest` (dedicated
`KNOWHER_INGEST_KEY`, validate→KV→featured-ledger). **Cadence: BIWEEKLY — alternates the Fan Zone quiz slot
with NWSL Trivia (Week 1 = KHG); gated on a COMMITTED `SEASON_ANCHOR` constant in `assemble_knowher_prompt.mjs`
(the routine UI has NO env-var field, so the constant is the source; `KHG_SEASON_ANCHOR` env var = test
override only). Content-quality lints gate the routine's dry-run (`load_knowher.mjs` `validatePool`: ≥10 Qs/
player, ≥6 human/≤5 stat, ≤65% "True" across T/F) + the pool is built in ~4-player batches (beats the 32k
output cap).** Prompt template wording is **owner-owned — never
edit without an explicit decision.** ⚠️ **Cloud routines egress-allowlist by default ("Trusted") →
`*.workers.dev` 403s `host_not_allowed`; the routine environment MUST be set to FULL network access**
(the sourcing needs the open web anyway). Don't fan out per-player sub-agents (16× the session cost).
Detail: `docs/know-her-game.md` §5d.
**Feeds carry more than we parse — check there FIRST** before proposing any new data source/fetch: the
already-fetched ESPN responses have repeatedly held whole features unparsed (2026-07-18, 3-for-3: `/summary`
`commentary`→full play-by-play, `leaders`→top performers, `videos`→highlights; athlete `/statistics` ~100
stats). Current parsed-vs-unparsed inventory: `docs/backend.md` (proxy § pass-through caching).

## Workflow & engineering practices (requirements — flag the trade-off before bypassing)

- **Branch first, never `main`:** `feature/<desc>`; `git status` clean before starting; state what
  you'll touch. Local hooks (`hooks/`): `pre-commit` blocks commits to main, `pre-push` blocks
  force/delete of main (`--no-verify` bypasses; fresh clone runs `git config core.hooksPath hooks`).
- **Build to spec, not to minimum.** Design-doc numbers are requirements, not suggestions — no
  scaled-down versions. A feature isn't "shipped" until EVERY sub-item is automated + verified (no
  partial credit; a scaffold needing manual steps ≠ the feature). Don't reclassify work as "deferred."
- **Prove it live.** Verify with evidence (curl the proxy/REST, screenshot the sim, trace the code
  path) — never reason from an unverified assumption.
- **Debug bottom-up; pull logs before blaming a third party.** Start at the SIMPLEST/nearest causes
  (our own code, config, a typo, stale creds, does-it-repro-elsewhere/other-device/other-account,
  cache/DNS) and work outward — NEVER jump to an external culprit (Cloudflare/ISP/Apple/APNs/DNS/a
  regional outage) before ruling those out. Track record: the root cause has been US every time (stale
  APNs tokens; an `aps` field Apple rejected) and NEVER the third party. When a log would pinpoint it —
  ESPECIALLY the in-app `Diagnostics`/telemetry, or `wrangler tail`/KV — but running it is GATED to the
  owner, don't reason past the missing data toward a worst-case guess: say so plainly and hand the owner
  the EXACT command to run (in the terminal) or step to check, and ask them to paste the output back.
  Missing logs = ask for them, not a license to speculate.
- **NO SILENT FAILURES (app-wide):** every unexpected condition (fallback/API-fail/stale/parse/retry/
  unexpected-empty) emits telemetry to the `Diagnostics` spine (os_log + `@Observable` ring, visible in
  dev/TestFlight). Fail LOUD to the engineer; fail HONESTLY to the user (degraded → subtle truthful
  indicator; blocked → clear message + retry). Banned: blank screens, infinite spinners, silent
  fallbacks indistinguishable from success — a failure must never look like success. Spans the proxy
  (`emitDiag` + a deploy-time health check that exits non-zero on any gap). The spine also carries
  **MetricKit** crash/hang crumbs (`metricKitDiagnostic`, device-only delivery) and is watched by PUSH
  alerting (2026-07-17): proxy error-spike → **Resend** email (≥8 error events/15min, 1/hr throttle;
  EXCLUDES `image fetch …` apiFailures — expected IG-CDN/thumbnail flakiness, still in Diagnostics but doesn't page);
  watcher tick → **healthchecks.io** heartbeat (dead cron ⇒ external email) — both no-op until the
  owner's secrets are set (roadmap). SEPARATE quiet channel: **anonymous Level-3 usage counters**
  (`Analytics.swift` → proxy `/analytics` → Supabase `analytics_counters` daily rollups; six events,
  NO ids/IP ever, one batch per session — measures the product, never the person).
- **Plan for scope:** a change touching 3+ files or a new pattern → present a plan + get approval first.
  No new dependency without explaining why the built-in won't work + approval.
- **⚠️ CLOSE-OUT ROLL CALL (mandatory on any multi-item plan, design handoff, or numbered spec).** Before
  claiming done, list EVERY deliverable the spec asked for BY NAME with a status: **built / skipped /
  blocked**. Not a summary of what you built — a roll call of what was ASKED FOR. If an item is skipped
  or blocked, say so in that list and why, in the same message. **Nothing may be silently omitted, and
  no scoped item may be deferred on your own judgment — if you think something should be deferred, STOP
  and ask.**
  **Why this exists (the failure it targets):** the model rarely *decides* to defer. It sees a dependency
  that isn't ready, silently reclassifies the item as "not yet actionable," and reports done on the rest
  — believing it finished. So "don't defer" rules keep failing; they aim at a decision that never
  consciously happens. A roll call makes omission impossible to do quietly: you must type "SKIPPED" next
  to the item, which the owner can overrule in the same message instead of rediscovering it in the sim
  three sessions later. Track record: a detailed Fan Zone design handoff had 4 of 5 items silently
  dropped across three sessions; Trivia's round backbone was dropped a 4th time on 2026-07-23.
- **BACKBONE IS NEVER DEFERRED FOR A MISSING FRONT END.** Build the structure AS IF the generator /
  content pipeline / data source already works — the app should be waiting on the pipeline, never the
  reverse. "The questions aren't generated biweekly yet" is NOT a reason to skip the round model, the
  landing page, or the retention rule. (Owner's fiber analogy: you don't defer the main feeder lines
  because no customers have signed up and the neighborhood nodes aren't placed — that reasoning can
  never fire in favor of building backbone, so the backbone never gets built.) Deferral doesn't save
  work either; it multiplies it — each skipped item costs a sim run to discover, a turn to report, and
  a context rebuild, and still has to be written.
- **Nothing stays pending past the day it's decided** — deploys especially. A merged-but-undeployed
  change becomes a phantom bug the owner burns hours on weeks later. Merge and deploy same-day; if a
  step can't happen today, say so explicitly in the roll call.
- **No force-unwraps (`!`)** unless a comment explains why it's safe. Temp architecture-bending code
  carries a `TEMP` comment (what/why/when-removed).
- **Before "done":** builds AND runs in the sim with no errors, **manually verified in-sim**
  (compiling ≠ working); update `docs/FILEMAP.md`; commit message `<Area>: <what changed>` (specific,
  present-tense); confirm before pushing (don't auto-push).
- **Stress-test gate = part of "done" for load-bearing features.** Any NEW or REBUILT feature/subsystem
  that adds or changes a **load path** (DB reads/writes, network, push fan-out, KV/storage, cron) must be
  run through the **`docs/stress-testing.md` §5** method and shown to **pass the 1k SIZE test** (+ note the
  100k lever) BEFORE it's done — never ship/rebuild a section (e.g. the Trivia weekly redesign) that
  silently fails 1k/100k because we never re-tested it. Record the result in that doc's §6/§7. Pure
  UI/cosmetic changes with no new load path are exempt (the gate is about load, not pixels).
- **Build bump ⇒ consider the update gate (don't auto-couple).** On a TestFlight/App Store build bump,
  the forced-update gate's `minBuild` (proxy `/config`, `MIN_APP_BUILD`) is a manual FLOOR decoupled from
  the build number — it does NOT auto-track "latest". NEVER raise it on every bump (that force-updates
  every user) and NEVER to a build that isn't live+installable yet (walls users with nowhere to go).
  Raise it + redeploy ONLY to retire a broken/incompatible build, and ONLY after the newer build is
  available. Detail: `docs/versioning.md`.
- **Git:** **squash-merge** PRs (one commit on main; OK to combine related branches). Never commit
  secrets. Commits use the owner's GitHub no-reply email
  `286203575+tiffanyrieth@users.noreply.github.com`. CLAUDE.md / commits / PRs / comments stay
  neutral/professional — never reveal owner preferences; use arbitrary teams for examples.
- **`gh` auth expires mid-session:** `git push` keeps working but `gh` API calls (PR create/merge,
  `gh api`) fail `HTTP 401` → owner runs `gh auth refresh -h github.com`. A push that succeeds but a
  PR-merge that 401s is this, not a permissions problem.

## Collaboration

Doubles as a way to build durable iOS/SWE skills — understanding each change matters as much as
shipping it. Explain non-obvious decisions/trade-offs as you go; note why a new file/folder is
organized that way; briefly explain a pattern (MVVM, state enums, async/await, Codable) the first time
it appears. **If a request reflects a misunderstanding or would introduce bad practice, say so and
propose the better approach.** **Decision split:** the owner owns design/UX/product calls and defers
fine engineering logistics to Claude AFTER a reasoned explanation — explain-then-recommend, don't
over-ask on low-level forks, never guess product/cost calls. **Nothing is impossible:** never answer
"can we do X?" with "not possible / no API" — research the menu of paths + costs, let the owner decide.

## UI rules

- **Dark appearance app-wide**, no toggle (page `#1C1C1E`, cards `#2C2C2E`).
- **Reuse the shared component library — don't re-roll** (pre-launch design pass, 2026-07-17): buttons →
  `DSButton`; error/empty → `RetryStateView`; team colors → `Color.teamColor(…)`; team-color card washes →
  `TeamWashBackground` (`TeamColorWash.swift`); player avatars →
  `PlayerHeadshot`; voice pills → `CategoryPill`; broadcast/platform colors → `BroadcastBrand`/`PlatformBrand`.
  Style via `ds*` tokens ONLY — no UIKit `Color(.systemGray*/.systemGroupedBackground/.separator)`, no raw
  `.white` (→ `dsFgPrimary`), no raw `.font` for readable text (→ `.dsFont`; fixed-size monograms/badges/
  numeric columns exempt), correct/wrong = `dsSuccess`/`dsError`. **Fan Zone = two visual families**
  (competitive arena vs community cards) — the full contract auto-loads from `.claude/rules/fan-zone.md`
  (Design consistency §). Build future games WITH this, not around it — the Superfan Zone + team-color
  washes already do; the NWSL Trivia weekly-engine rebuild is next.
- Persistent UI (tab/nav bars) never obscures scrollable content (respect safe areas); every drilled-in
  view has an explicit back affordance (don't rely on edge-swipe alone). Tabs keep their OWN nav stack
  across switches (**The Athletic model, owner-confirmed 2026-07**); re-tapping the ALREADY-active tab
  pops it to root (intended affordance, PENDING). Do NOT reset on every tab tap — that's ESPN's jarring
  model (owner rejected), and `.id()` on a TabView child desyncs selection from content (tried, reverted).
- **Back button = bare ‹ chevron** (native iOS, MLS/Athletic-style), screen name as a centered inline
  title, via `nativeBackButton(title:)` (`DSText.swift` — full mechanism in its doc comment);
  identity-header screens (MatchDetail/TeamDetail/PlayerDetail) pass no title. Don't use
  `.toolbarRole(.editor)` or hide the bar (breaks edge-swipe).
- **Dynamic Type:** size text via `.dsFont(...)` (`@ScaledMetric`), NOT raw `.font(.system(size:))`;
  crests/flags scale on the same `.body` axis; **capped at AX1** at the root so dense tables don't break.
- **Team naming:** one team as subject → full club name (Gotham FC); **two-team contexts (match cards,
  match detail, comparisons, standings rows) → CREST + ABBREVIATION (e.g. WAS), never crest-less text or
  full names.** ESPN has no nickname field.
- **Crest rule:** bare crests via `TeamLogo`, no ring (only player monograms get a ring). **Crests are
  PROMINENT — render them LARGE, never shrunk toward an icon/spec size; the crest is the team's identity
  (players/fans lift it to their chest) and outranks the abbreviation/name text. AI keeps shrinking them;
  don't — err larger** (à la The Athletic; owner directive, e.g. the LA card crest is 48pt). **Team
  colors:** `DesignTeamColors` by abbreviation; use each club's default brand colors — no manual
  overrides without a documented rendering conflict.
- Clarity over density (~4–5 schedule cards/screen; avoid oversized cards); schedule shows the full
  season. Placeholders only as deliberate "Coming soon" (flagged in the File Map), never blank/broken.

## Deeper context (read on demand — NOT loaded every turn)

- **`docs/FILEMAP.md`** — every file + one-liner. Read to locate code. **Update it after every feature.**
- **`docs/backend.md`** — ESPN quirks, the proxy (routes / headshots / crests / bracket engine),
  Supabase schema + migrations.
- **`docs/live-activity-v2.md`** — ⚠️ THE V2 MANUAL. Read BEFORE touching/testing/troubleshooting
  anything Live Activity: the render law (alert REQUIRED, `sound:""` = quiet), two-token system +
  20-min lead, testing runbook (replay.mjs / test-activity / telemetry), AI-misconception traps
  (V2 is NOT text-only; app does NOT need to be open; "1/1 ok" ≠ rendered; 8pm listing ≠ 8pm kickoff).
- **`docs/notifications.md`** — the WHOLE notification pipeline (V1 + V2) end-to-end: match event → proxy →
  watcher cron → detect → APNs (Queues / Broadcast Channels) → device → render. A **PERMANENT** reference —
  this connective sports-app knowledge (channels, clock anchoring, the fragile V2 wiring) is **NOT
  reconstructable from training**, so read it before ANY notification / Live-Activity / watcher / clock change.
- **`docs/fan-zone.md`** — ⚠️ THE FAN ZONE SYSTEM DOC. How the four games actually work end-to-end: the
  two families, the **cadence engine** (biweekly rounds are STAGGERED — both community games stay
  playable; the anchor is a cross-repo contract with the proxy), state ownership (what's local vs
  Supabase and why), progress restore, retention, scoring/Superfan, and an add-a-fifth-game checklist.
  Read before touching any game. The BUILD RULES stay in `.claude/rules/fan-zone.md` (auto-loads).
- **`docs/navigation.md`** — each tab's lens + adjacency rules (read when adding/redesigning a screen).
- **`docs/versioning.md`** — the (non-semver) version model + distribution.
- **`docs/roadmap.md`** — What's Next (pending work).
- **`docs/stress-testing.md`** — the launch-readiness charter: indie-sizing calibration, the two stress
  tests (1k mandatory / 100k headroom), the efficiency-first rule, and the 8-step method for stress-testing
  any subsystem + a checklist of what still needs it. Read before any scaling/sizing/publish-readiness work.
- **`docs/push-fanout-scaling.md`** — the launch-scale APNs fan-out fix — **BUILT + deployed + device-
  proven 2026-07-09**: **V1 buzz + LA push-to-start → Cloudflare Queues** ($0); **V2 in-match updates →
  APNs Broadcast Channels** (channel-per-match, iOS 18+; iOS 17 = V1-only graceful degradation); Firebase
  declined; Workers Paid $5/mo = the ~10–15k-user expansion slot. Read before push-scale/launch work.
- **`.claude/rules/bracket-battle.md`** + **`.claude/rules/fan-zone.md`** + **`.claude/rules/live-activity-
  notifications.md`** — feature rules that **auto-load** (path-scoped): the first two when you touch Bracket /
  Predict-the-XI / Fan-Zone / Trivia / Home-games files (the Fan-Zone one carries the **build/change LOGIC
  GATE** — six invariants to run before any game or scoring change); the last on any Live-Activity / MatchClock /
  push-token / NSE / widget file — it FORCES the notification+LA source-of-truth docs into context, because that
  fragile subsystem must never be edited from first principles. You don't need to open them manually.
