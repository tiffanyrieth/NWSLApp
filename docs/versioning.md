# Versioning & Distribution

_Read when bumping the version or preparing a build/release._

- **Versioning model (owner's, NOT classic semver — follow this).** A **`minor.0` (e.g. `0.4.0`) is a
  big flagship release** (like iOS 26.0) — bundles many features and spans **several TestFlight builds**
  under the *same* marketing version. **Do NOT bump the patch digit for a feature** — features stay `.0`;
  **patches (`0.4.1`…) are reserved for BUG FIXES** after the big release. A **minor bump (`0.4`→`0.5`)**
  starts the next era. Reserve **1.0.0** for the first public App Store launch. (So far: 0.1.x prototype →
  0.3.x backbone → **0.4.0 flagship**, shipping as successive builds.)
- **Xcode fields:** "Marketing Version" (`CFBundleShortVersionString`, stays `0.4.0` across the flagship's
  builds) + "Build" (`CFBundleVersion`, a monotonic int bumped per TestFlight upload). Tag releases in git;
  proxy-only changes don't bump the app version.
- **Forced-update gate (`/config`) — a manual FLOOR, not "always latest".** The app checks the proxy's
  `GET /config` at launch and walls itself off if `CFBundleVersion < minBuild`. `minBuild` is a hardcoded
  constant (`MIN_APP_BUILD` in `nwslapp-proxy/src/index.ts`); it does **not** auto-track the build number,
  and bumping the build does **not** change it. Rules when doing a build bump / release:
  - **Don't raise `minBuild` on every bump.** Setting it to the newest build force-updates *every* user on
    *every* build — the gate is for retiring broken/incompatible builds, not routine updates.
  - **Never raise it to a build that isn't live + installable yet.** If you set `minBuild = N` while build
    N is still "Processing" on TestFlight/App Store, everyone on N-1 gets the wall with nowhere to update —
    a self-inflicted outage. Raise it only **after** the target build is downloadable.
  - **It only governs builds that contain the gate (21+).** Older builds predate the mechanism and never
    call `/config`, so they can't be retroactively blocked — the gate bites a user only once they're on a
    gated build and fall behind a later `minBuild`.
  - **To force an update:** after the fixed build is live, raise `MIN_APP_BUILD` + `wrangler deploy` the
    proxy. The app side fails OPEN (an unreachable `/config` never blocks), so the endpoint being down is
    safe. See `AppGateView` / `ForceUpdateService`.
- **Distribution:** Simulator + Personal Team sideload now; Dev Program active (paid); TestFlight (OTA) for
  testers. App Store deferred until presentable.

