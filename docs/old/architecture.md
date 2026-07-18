# Architecture & Coupling Map

_How the codebase is organized, where each feature lives, and where cross-feature coupling risk actually
concentrates. Read before a refactor, a new feature area, or any change to shared infrastructure. Point-in-time
snapshot — **2026-07-12**; re-verify counts against the code before relying on them._

## Top-line

- **Single-target "modular monolith by convention," not a modularized app.** Everything ships in **one app
  target** (`NWSLApp`) plus two thin extensions. **Zero internal Swift packages/modules**; the only SPM
  dependency is `supabase-swift` (external).
- **Feature *logic* is cleanly separated; feature *isolation* is not enforced.** Nothing at the compiler level
  stops one feature reaching into another — separation is discipline (folder/naming conventions), not module
  boundaries.
- **Could one feature (e.g. Know Her Game) break another (Live Activities, the match feed)? Directly, no** —
  they share no types. **Indirectly, yes** — but only via the *shared-infrastructure* layer (the ~16
  environment stores, shared services, models, or the design system). That is where the real coupling risk
  lives, not in feature-to-feature code.

## 1. Target & module structure

| Target | Role | Swift files | Shares with app |
|---|---|---|---|
| **NWSLApp** | the whole app | ~163 | — |
| **NWSLLiveActivity** | lock-screen / Dynamic Island widget | 2 | **1 file** (`Shared/MatchActivityAttributes.swift`, dual target-membership) |
| **NotificationServiceExtension** | renders push-card images (NSE) | 1 | (minimal) |

- **No `Package.swift` anywhere** → no feature is carved into its own module. `Shared/` is a single file with
  dual target membership, not a package.
- **One external dependency:** `supabase-swift`.
- **Consequence:** one target ⇒ any compile error in any file fails the whole-app build; you cannot build/test
  one feature in isolation. (A build-break, caught at compile — not a silent runtime break.)

## 2. Organization — by **layer**, not by feature

```
NWSLApp/
  Models/(20)  Services/(36)  Stores/(22)  ViewModels/(12)
  Views/(33)   Components/(35) DesignSystem/(3) Config/(2)
```

Strict MVVM layering. **A feature is sliced *across* these folders**, not gathered in one place — e.g. Know
Her Game = `KnowHerService` (Services) + `KnowHerGameStore` (Stores) + `KnowHerGameViewModel` (ViewModels) +
`KnowHerGameView` (Views). There is no single folder that is "the Know Her Game module."

## 3. Feature areas & where they live

| Feature area | Primary files |
|---|---|
| **Fan Zone — Know Her Game** | `KnowHerService`, `KnowHerGameStore/ViewModel/View`, `QuizResultsService`\* |
| **Fan Zone — Trivia** | `TriviaService`, `TriviaLeaderboardService`, `TriviaStore/ViewModel`, `QuizResultsService`\* |
| **Fan Zone — Bracket Battle** | `BracketService`, `BracketScoring`, `BracketStore/ViewModel` |
| **Fan Zone — Predict XI** | `PredictionScoring`, `PredictLeaderboardService`, `PredictionStore`, `PredictXI/XIPicker ViewModels+Views` |
| **Match feed / scores** | `ESPNService`, `MatchStore`, `Scoreboard` (model), `Schedule/MatchDetail ViewModels+Views`, `RecentForm`, `PlayoffStore` |
| **Live Activities (V2)** | `LiveActivityManager`, `PushBridge`, `DeviceTokenService`, `MatchActivityAttributes` (Shared), `NWSLLiveActivity` (widget) — content driven by the **watcher** repo, not the app |
| **Feed / social** | `ContentService`, `ContentRoundRobin`, `FeedStore`, `FeedPreferencesStore`, `TeamSocialLinksProvider`, `FeedView/ViewModel` |
| **Notifications / alerts** | `NotificationScheduler`, `NotificationPreferencesStore`, `TeamAlertStore`, sync coordinators, `PushBridge` |

\* `QuizResultsService` is genuinely shared between Trivia and Know Her Game (both render the "how everyone
did" panel).

## 4. Coupling — the actual answer

Cross-feature type references, checked directly against the code. **Feature-owned code is well-isolated:**

- **Know Her Game, Trivia, Bracket → match feed / Live Activities: NONE.** They reference no `MatchStore`,
  `ESPNService`, `Scoreboard`, or Live-Activity types.
- **Live Activities → Fan Zone: NONE.** The widget / `LiveActivityManager` / `PushBridge` / `Shared` path
  references zero Fan Zone types.
- **The one real cross-link: Predict XI depends on the match feed** (`PredictXIViewModel` + `PredictXIView`
  read `MatchStore` + `ESPNService`) — by design (predicting a starting XI needs the fixture + roster). It is a
  **read-only consumer**; it does not mutate match state, so it cannot corrupt the feed.
- *(False positive to ignore: `MatchStore.swift` matches "Predict" — that is a word in a code **comment**, not a
  dependency.)*

**Where coupling risk actually concentrates — the shared-infrastructure layer** (file counts referencing each):

| Shared surface | Files | What it is |
|---|---|---|
| **DesignSystem** (`.dsFont`, `Color.ds*`) | **~44–56** | visual tokens — nearly every view |
| **Diagnostics** | **41** | telemetry / no-silent-failure spine |
| **FollowingStore** / **Club** | **37** each | follows + club identity |
| **AuthStore** | **26** | sign-in state (gates Fan Zone submits, alerts, follows) |
| **ClubStore** | **25** | club directory |
| **Event** (model) | **21** | ESPN match model |
| **AppConfig** | **20** | base URLs / proxy routes |
| **ESPNService** | **16** | match-data client |
| **SupabaseManager** | **14** | the single Supabase client (all persistence) |

Plus the **app-root wiring**: **~16 stores injected via `.environment`** (`matches`, `following`, `knowHer`,
`trivia`, `bracket`, `predict`, `auth`, `router`, `playoffs`, …). Any view can pull any store from the
environment.

**Honest risk map:**
- Editing **a feature's own files** → blast radius = that feature. Know Her Game cannot break Live Activities
  or the feed this way.
- Editing a **shared dependency** (`SupabaseManager`, `AuthStore`, `FollowingStore`, `Club`/`Event` models,
  `ESPNService`, `DesignSystem`, `Diagnostics`, `AppConfig`, or `RootTabView` wiring) → blast radius = **dozens
  of files across all features**, with no compiler warning about which features you touched. **This** is where a
  "changed X, broke Y" surprise comes from.
- The **app↔widget contract** (`MatchActivityAttributes`) is a specific coupling point: its shape must stay in
  sync across two targets (the additive-optional discipline used for `stoppageDisplay`).

## 5. What mitigates the risk today

- **Clean MVVM + state-enum discipline** keeps feature logic separable in practice.
- **31 unit-test files** — but **logic-level** (scoring, clinch derivation, clock, formation, migrations,
  reconcile), not integration/UI. They catch algorithm regressions, **not** a cross-feature store/UI break.
- **The `Diagnostics` spine** surfaces runtime anomalies loudly (helps catch silent breakage post-hoc).

## 6. Bottom line

The four Fan Zone games are independent of each other and of Live Activities, and feature code is disciplined.
The exposure is the classic single-target one: **all safety is by convention, none is compiler-enforced**, and
the shared-infrastructure layer (stores, models, Supabase client, design system) has a wide blast radius. The
highest-leverage "true isolation" move, *if ever wanted*, is extracting leaf features (the Fan Zone games are
the best candidates — near-zero inbound coupling) into their own Swift packages so the compiler enforces the
boundary. Noted as an option, not a recommendation to act on now.
