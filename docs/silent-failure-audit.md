# Silent-failure audit — 2026-06

App-wide sweep against the **NO SILENT FAILURES** rule (every unexpected condition emits to
the Diagnostics spine; fail LOUD to the engineer, HONEST to the user). Run alongside the
match-alert / account-deletion fix because the owner hit a third silent-failure surprise and
asked for a dedicated sweep.

## Method

- Enumerated all `catch` blocks (65), `try?` sites (17), and empty-catch patterns (0) across
  `NWSLApp/`.
- Flagged any block whose body lacked telemetry (`Diagnostics.shared.record` / `emitDiag`),
  a rethrow, or `os_log`.
- Established the telemetry convention: sync-services emit at their **coordinators** (already
  covered); the **ESPN / content / trivia READ path** emitted telemetry inconsistently — the
  ViewModels/Stores caught failures into honest `.error` UI states but **did not** emit
  engineer telemetry. So a load failure showed the user "tap to retry" while the owner watching
  Diagnostics (dev/TestFlight) got **nothing** — the exact "I'd have known weeks ago" gap.

## Systemic finding & fix

**Read-path catches set an honest UI error but emitted no engineer telemetry.** Added
`Diagnostics.shared.record(.apiFailure, …)` at each (the services are thin and don't self-emit;
the catch is the single handling point). 15 sites:

| File | Site | What now telemeters |
|---|---|---|
| `ViewModels/StandingsViewModel` | `load` | standings load failure |
| `ViewModels/BracketViewModel` | `load` | bracket edition load failure |
| `ViewModels/BracketViewModel` | `submit` | bracket submit failure |
| `ViewModels/MatchDetailViewModel` | `loadSummary` | match summary load failure |
| `ViewModels/TeamDetailViewModel` | `load` | team roster load failure |
| `ViewModels/TriviaViewModel` | `loadDaily` | trivia load failure |
| `ViewModels/PredictXIViewModel` | scoring loop | per-fixture scoring fetch failure (was a bare swallow) |
| `ViewModels/PredictXIViewModel` | `roster(forTeam:)` | roster fetch failure (was a silent `return []`) |
| `Stores/FeedStore` | `load` | feed load failure |
| `Stores/ClubStore` | `load` | clubs load failure |
| `Stores/HomeContentStore` | content catch | Home Module-1 content load failure |
| `Stores/HomeContentStore` | spotlight catch | Home Module-2 spotlight load failure |
| `Stores/MatchStore` | top-level | schedule load failure |
| `Stores/MatchStore` | per-national-team-feed | **each dropped feed** — the degraded-but-looks-fine partial-failure class (the same shape as the Google-News-only-Bluesky bug) |
| `Stores/MatchStore` | Champions Cup feed | Champions Cup feed failure |

`HomeContentStore` already telemetered the *unexpected-empty* case (`.unexpectedEmpty` + a
self-healing retry); only its *throw* paths were missing — now covered.

## `try?` sites — reviewed, OK by design

- Task-sleep `try?` (HomeContentStore, TeamsView, MatchDetailView) — only catches cancellation.
- `AuthStore.restoreSession` `try?` — no stored session simply means signed-out (documented).
- `AuthStore.signOut` `try?` — best-effort; the new `deleteAccount` path checks the token
  explicitly and emits diag on the no-session branch.
- `MatchDetailViewModel` live-poll `try? fetchSummary` — a transient poll miss keeps showing the
  real (slightly older) summary and retries on the next 30s tick; expected, not a failure.
- `NotificationsView` `requestAuthorization` `try?` — denial is reflected by the separately-read
  authorization status.
- `AssetRefreshService` FileManager `try?` (`?? []`) — listing an absent cache dir → empty is
  normal; AssetRefreshService has its own diag spine (`assetBundleMiss`/override events).

## Proxy

Added `emitDiag` on every failure path of the new `POST /account/delete` route, plus a
deploy-time health check (`scripts/health_check_account_delete.mjs`, wired into `npm run
healthcheck`) that fails non-zero if the route is undeployed (404) or its Supabase secrets are
missing (500).

## Result

Every read-path failure now reaches the Diagnostics ring + os_log (and the remote `/telemetry`
sink), so a degraded surface surfaces to the engineer without depending on a user report. No
empty catches remain; `try?` swallows are all expected-condition or self-telemetering.
