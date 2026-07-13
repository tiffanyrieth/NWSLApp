// swift-tools-version: 5.9
import PackageDescription

// LiveActivityContract — the app↔widget Live Activity data contract, extracted into its own
// compiler-enforced module. Both the NWSLApp app target and the NWSLLiveActivity widget extension
// link THIS one library, so ActivityKit compiles the SAME `MatchActivityAttributes` definition into
// both binaries. That replaces the old hand-maintained dual target-membership hack (which, if it
// drifted, silently broke all V2 rendering via a Codable decode mismatch — see docs/live-activity-v2.md §0).
//
// Deliberately a clean LEAF: only ActivityKit + Foundation, no app infrastructure (DesignSystem /
// Supabase / Diagnostics all stay app-side). Platform floor is .v17 — SPM can't express the app's
// real 17.2 minimum, but the project keeps enforcing 17.2 and push-to-start needs 17.2 regardless.
let package = Package(
    name: "LiveActivityContract",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "LiveActivityContract", targets: ["LiveActivityContract"]),
    ],
    targets: [
        .target(name: "LiveActivityContract"),
    ]
)
