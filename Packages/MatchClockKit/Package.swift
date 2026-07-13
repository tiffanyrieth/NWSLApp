// swift-tools-version: 5.9
import PackageDescription

// MatchClockKit — the app's live football-clock engine + its display guard, extracted into one
// compiler-enforced module so the counterintuitive live-clock invariants (monotonic freeze at
// 45:00/90:00, re-anchor only on advance/period-change, freshAtCap → defer to ESPN's string, static
// label at halftime) live in ONE tested place instead of copy-pasted across three frequently-edited
// view files. A layout edit in a view can no longer silently reintroduce a mid-match clock bug.
//
// Clean leaf: Foundation + SwiftUI only, no app infrastructure. Styling stays in the caller (the view
// APIs take a `content:` closure), so there's no DesignSystem dependency. Decoupled from the ESPN
// `Event` model via the `ClockTickSource` protocol (the app conforms Event to it). Platform floor .v17.
let package = Package(
    name: "MatchClockKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "MatchClockKit", targets: ["MatchClockKit"]),
    ],
    targets: [
        .target(name: "MatchClockKit"),
        .testTarget(name: "MatchClockKitTests", dependencies: ["MatchClockKit"]),
    ]
)
