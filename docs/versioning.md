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
- **Distribution:** Simulator + Personal Team sideload now; Dev Program active (paid); TestFlight (OTA) for
  testers. App Store deferred until presentable.

